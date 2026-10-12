"""Firebase Cloud Messaging via the Firebase Admin SDK (FCM HTTP v1 under the hood).

Messages are high priority with both a ``notification`` (so Android shows it even
if the app was killed) and a ``data`` payload (so the app can deep-link). They are
posted to the app's ``urgent_deadlines`` channel, which the client must create.

The Admin SDK is synchronous; calls run in a worker thread.
"""

from __future__ import annotations

import asyncio
import logging
import warnings
from dataclasses import dataclass
from datetime import timedelta
from functools import lru_cache
from pathlib import Path

from app.core.config import get_settings

log = logging.getLogger(__name__)

# How long FCM keeps trying to deliver to an offline phone. A deadline ping that
# arrives a day late is noise, so keep it short.
DEFAULT_TTL = timedelta(hours=6)
_APP_NAME = "exam-tracker"


@dataclass(frozen=True, slots=True)
class SendResult:
    ok: bool
    message_id: str | None = None
    invalid_token: bool = False  # caller should delete the token
    error: str | None = None


class FcmUnavailableError(RuntimeError):
    """Push is not configured (no service account)."""


@lru_cache
def _firebase_app():  # noqa: ANN202 - firebase_admin.App
    path = get_settings().firebase_credentials_file
    if not path or not Path(path).is_file():
        raise FcmUnavailableError("FIREBASE_CREDENTIALS_FILE is not set or missing")
    import firebase_admin
    from firebase_admin import credentials

    return firebase_admin.initialize_app(credentials.Certificate(path), name=_APP_NAME)


def fcm_enabled() -> bool:
    try:
        _firebase_app()
    except FcmUnavailableError:
        return False
    return True


def _build_message(  # noqa: ANN202
    target: str, title: str, body: str, data: dict[str, str], ttl: timedelta, target_kind: str = "token"
):
    from firebase_admin import messaging

    # firebase-admin 7.x targets app instances by Firebase Installation ID ("fid");
    # classic registration tokens still work but are deprecated.
    addressing = {"fid": target} if target_kind == "fid" else {"token": target}
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        return _message(messaging, addressing, title, body, data, ttl)


def _message(messaging, addressing, title, body, data, ttl):  # noqa: ANN001, ANN202
    return messaging.Message(
        **addressing,
        notification=messaging.Notification(title=title, body=body),
        # FCM data values must be strings.
        data={str(k): str(v) for k, v in data.items()},
        android=messaging.AndroidConfig(
            priority="high",
            ttl=ttl,
            # Same collapse key => a newer ping for the same job replaces the older one.
            collapse_key=data.get("collapse_key"),
            notification=messaging.AndroidNotification(
                channel_id=get_settings().fcm_android_channel_id,
                tag=data.get("collapse_key"),
                default_sound=True,
                # Calm, not alarming: no forced vibration pattern or flashing LED.
            ),
        ),
    )


def send_urgent_notification_sync(
    user_fcm_token: str,
    title: str,
    body: str,
    payload_data: dict[str, str] | None = None,
    *,
    ttl: timedelta = DEFAULT_TTL,
    target_kind: str = "token",
) -> SendResult:
    from firebase_admin import exceptions, messaging

    app = _firebase_app()
    message = _build_message(user_fcm_token, title[:120], body[:400], payload_data or {}, ttl, target_kind)
    try:
        message_id = messaging.send(message, app=app)
        return SendResult(ok=True, message_id=message_id)
    except (messaging.UnregisteredError, messaging.SenderIdMismatchError) as exc:
        return SendResult(ok=False, invalid_token=True, error=type(exc).__name__)
    except exceptions.InvalidArgumentError as exc:
        # Malformed token is the usual cause; treat as invalid so it gets cleaned up.
        return SendResult(ok=False, invalid_token="token" in str(exc).lower(), error=str(exc)[:300])
    except exceptions.FirebaseError as exc:  # quota, unavailable, internal: retry next run
        log.warning("FCM send failed: %s", exc)
        return SendResult(ok=False, error=str(exc)[:300])


async def send_urgent_notification(
    user_fcm_token: str,
    title: str,
    body: str,
    payload_data: dict[str, str] | None = None,
    *,
    ttl: timedelta = DEFAULT_TTL,
    target_kind: str = "token",
) -> SendResult:
    """High-priority push to one device. Never raises for per-token failures.

    ``target_kind``: "token" (FCM registration token) or "fid" (Firebase Installation ID).
    """
    return await asyncio.to_thread(
        send_urgent_notification_sync,
        user_fcm_token,
        title,
        body,
        payload_data,
        ttl=ttl,
        target_kind=target_kind,
    )
