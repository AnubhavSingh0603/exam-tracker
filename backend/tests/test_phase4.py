import json
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.services import fcm_service
from app.services.notifier import alert_matches_job, in_quiet_hours

SHA = "ab" * 32


# --- Quiet hours ------------------------------------------------------------------


@pytest.mark.parametrize(
    ("utc", "quiet"),
    # 22:00-07:00 IST == 16:30-01:30 UTC
    [
        ((16, 29), False),
        ((16, 30), True),
        ((20, 0), True),
        ((1, 29), True),
        ((1, 30), False),
        ((6, 0), False),
    ],
)
def test_quiet_hours_wrap_midnight_in_ist(utc, quiet):
    now = datetime(2026, 10, 11, utc[0], utc[1], tzinfo=UTC)
    assert in_quiet_hours(now, get_settings()) is quiet


# --- Admit-card matching ----------------------------------------------------------


@pytest.mark.parametrize(
    ("alert", "exam", "org", "match"),
    [
        (
            "SSC CGL Admit Card 2026",
            "Combined Graduate Level Examination 2026 (CGL)",
            "Staff Selection Commission",
            True,
        ),
        (
            "SSC CHSL Admit Card 2026",
            "Combined Graduate Level Examination 2026 (CGL)",
            "Staff Selection Commission",
            False,
        ),
        (
            "Railway RRB Section Controller Admit Card 2026",
            "RRB NTPC Graduate Level 2026",
            "Railway Recruitment Board",
            False,
        ),
        ("RRB NTPC Admit Card 2026 Out", "RRB NTPC Graduate Level 2026", "Railway Recruitment Board", True),
        (
            "BEL Probationary Engineer Call Letter",
            "Probationary Engineer 2026",
            "Bharat Electronics Limited",
            True,
        ),
        ("IBPS PO Admit Card", "Probationary Engineer 2026", "Bharat Electronics Limited", False),
        # The exam's acronym identifies it even when its name has no "(CHSL)".
        (
            "SSC CHSL Answer Key 2026",
            "Combined Higher Secondary Level Examination 2026",
            "Staff Selection Commission",
            True,
        ),
        # Generic words shared by two exam names don't identify either one.
        (
            "SSC Combined Graduate Level Tier-I Result",
            "Combined Higher Secondary Level Examination 2026",
            "Staff Selection Commission",
            False,
        ),
    ],
)
def test_alert_matching(alert, exam, org, match):
    assert alert_matches_job(alert, exam, org) is match


# --- FCM message construction (real Admin SDK types, no network) ----------------------


def test_fcm_message_can_target_installation_id():
    msg = fcm_service._build_message("fid-abc", "t", "b", {}, timedelta(hours=1), target_kind="fid")
    assert msg.fid == "fid-abc" and getattr(msg, "token", None) is None


def test_fcm_message_is_high_priority_on_our_channel():
    msg = fcm_service._build_message(
        "token-123",
        "⏳ SSC CGL: 18 hrs left",
        "Apply before 23:59",
        {"type": "deadline", "job_post_id": "42", "collapse_key": "deadline-42"},
        timedelta(hours=6),
    )
    assert msg.android.priority == "high"
    assert msg.android.notification.channel_id == get_settings().fcm_android_channel_id
    assert msg.android.collapse_key == "deadline-42"
    assert msg.data["job_post_id"] == "42"


def test_send_maps_unregistered_token_to_invalid(monkeypatch):
    from firebase_admin import messaging

    def boom(message, app=None):  # noqa: ARG001
        raise messaging.UnregisteredError("gone")

    monkeypatch.setattr(fcm_service, "_firebase_app", lambda: object())
    monkeypatch.setattr(messaging, "send", boom)
    result = fcm_service.send_urgent_notification_sync("t" * 30, "title", "body", {})
    assert not result.ok and result.invalid_token


def test_fcm_disabled_without_credentials(monkeypatch):
    fcm_service._firebase_app.cache_clear()
    monkeypatch.setattr(get_settings(), "firebase_credentials_file", None)
    assert fcm_service.fcm_enabled() is False
    fcm_service._firebase_app.cache_clear()


# --- Version endpoint -------------------------------------------------------------------


def _manifest(**over):
    m = {
        "version_code": 5,
        "version_name": "0.4.1",
        "min_supported_version_code": 3,
        "release_notes": "Calmer hero card",
        "apks": {
            "universal": {"url": "https://github.com/o/r/releases/download/v0.4.1/u.apk", "sha256": SHA},
            "arm64-v8a": {
                "url": "https://github.com/o/r/releases/download/v0.4.1/a.apk",
                "sha256": SHA,
                "size_bytes": 9_000_000,
            },
        },
    }
    m.update(over)
    return m


@pytest.fixture
def client(tmp_path, monkeypatch):
    from app.api.v1 import app_meta
    from app.main import app

    path = tmp_path / "latest.json"
    monkeypatch.setattr(get_settings(), "release_manifest_path", str(path))
    monkeypatch.setattr(app_meta, "_cache", None)
    return TestClient(app), path


def test_version_endpoint_picks_abi_and_flags(client):
    c, path = client
    path.write_text(json.dumps(_manifest()))
    r = c.get("/api/v1/app/version", params={"current_version_code": 2, "abi": "arm64-v8a"})
    body = r.json()
    assert r.status_code == 200 and body["abi"] == "arm64-v8a" and body["apk_url"].endswith("a.apk")
    assert body["update_available"] is True and body["mandatory"] is True  # 2 < min_supported 3

    r = c.get("/api/v1/app/version", params={"current_version_code": 5, "abi": "x86"})
    assert r.json()["abi"] == "universal" and r.json()["update_available"] is False


def test_version_endpoint_404_before_first_release_and_rejects_http(client):
    c, path = client
    assert c.get("/api/v1/app/version").status_code == 404
    bad = _manifest(apks={"universal": {"url": "http://insecure/u.apk", "sha256": SHA}})
    path.write_text(json.dumps(bad))
    assert c.get("/api/v1/app/version").status_code == 503
