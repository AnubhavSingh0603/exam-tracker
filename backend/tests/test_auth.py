import time
import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.core.tokens import TokenError, create_token, decode_token
from app.services import auth_service
from app.services.auth_service import AuthError, verify_google_id_token_sync

CLIENT_ID = "test-client.apps.googleusercontent.com"


def test_access_token_roundtrip():
    uid = uuid.uuid4()
    token, claims = create_token(uid, "access")
    decoded = decode_token(token, "access")
    assert decoded.user_id == uid and decoded.jti == claims.jti and decoded.family is None


def test_refresh_token_carries_family_and_rejects_wrong_type():
    token, claims = create_token(uuid.uuid4(), "refresh", family="fam-1")
    assert decode_token(token, "refresh").family == "fam-1"
    with pytest.raises(TokenError):
        decode_token(token, "access")  # a refresh token can't be used as an access token


def test_expired_and_tampered_tokens_rejected():
    old, _ = create_token(uuid.uuid4(), "access", now=datetime.now(UTC) - timedelta(hours=2))
    with pytest.raises(TokenError):
        decode_token(old, "access")
    good, _ = create_token(uuid.uuid4(), "access")
    with pytest.raises(TokenError):
        decode_token(good[:-4] + "AAAA", "access")


# --- Google ID token verification (JWKS mocked with a local RSA key) -----------------

_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class _FakeJwks:
    def get_signing_key_from_jwt(self, token):  # noqa: ARG002
        return jwt.PyJWK.from_dict(
            {**jwt.algorithms.RSAAlgorithm.to_jwk(_KEY.public_key(), as_dict=True), "alg": "RS256"}
        )


@pytest.fixture(autouse=True)
def fake_google_keys(monkeypatch):
    monkeypatch.setattr(auth_service, "_jwks_client", lambda: _FakeJwks())


def google_token(**overrides) -> str:
    now = int(time.time())
    claims = {
        "iss": "https://accounts.google.com",
        "aud": CLIENT_ID,
        "sub": "1234567890",
        "email": "aspirant@example.com",
        "email_verified": True,
        "name": "Aspirant",
        "iat": now,
        "exp": now + 3600,
    }
    claims.update(overrides)
    return jwt.encode(claims, _KEY, algorithm="RS256")


def test_google_token_accepted():
    ident = verify_google_id_token_sync(google_token())
    assert ident.sub == "1234567890" and ident.email_verified


@pytest.mark.parametrize(
    "bad",
    [{"aud": "someone-elses-client"}, {"iss": "https://evil.example"}, {"exp": int(time.time()) - 3600}],
)
def test_google_token_rejected(bad):
    with pytest.raises(AuthError):
        verify_google_id_token_sync(google_token(**bad))
