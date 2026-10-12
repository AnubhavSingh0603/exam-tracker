"""JWT minting/verification (HS256). Pure: no DB access.

Access tokens are short-lived and stateless. Refresh tokens carry a ``jti``
and ``fam`` (family) that the auth service checks against PostgreSQL.
"""

from __future__ import annotations

import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Literal

import jwt

from app.core.config import get_settings

TokenType = Literal["access", "refresh"]
_ALGORITHM = "HS256"
_LEEWAY = timedelta(seconds=30)


class TokenError(Exception):
    """Invalid, expired, or wrong-type token."""


@dataclass(frozen=True, slots=True)
class TokenClaims:
    user_id: uuid.UUID
    type: TokenType
    jti: str
    expires_at: datetime
    family: str | None = None


def new_token_id() -> str:
    return secrets.token_urlsafe(24)


def _secret() -> str:
    return get_settings().jwt_secret.get_secret_value()


def create_token(
    user_id: uuid.UUID,
    type_: TokenType,
    *,
    now: datetime | None = None,
    jti: str | None = None,
    family: str | None = None,
) -> tuple[str, TokenClaims]:
    s = get_settings()
    now = now or datetime.now(UTC)
    ttl = (
        timedelta(minutes=s.access_token_ttl_minutes)
        if type_ == "access"
        else timedelta(days=s.refresh_token_ttl_days)
    )
    claims = TokenClaims(
        user_id=user_id,
        type=type_,
        jti=jti or new_token_id(),
        expires_at=now + ttl,
        family=family if type_ == "refresh" else None,
    )
    payload: dict[str, object] = {
        "iss": s.jwt_issuer,
        "sub": str(user_id),
        "typ": type_,
        "jti": claims.jti,
        "iat": int(now.timestamp()),
        "exp": int(claims.expires_at.timestamp()),
    }
    if claims.family:
        payload["fam"] = claims.family
    return jwt.encode(payload, _secret(), algorithm=_ALGORITHM), claims


def decode_token(token: str, expected: TokenType) -> TokenClaims:
    try:
        data = jwt.decode(
            token,
            _secret(),
            algorithms=[_ALGORITHM],
            issuer=get_settings().jwt_issuer,
            leeway=_LEEWAY,
            options={"require": ["exp", "iat", "sub", "jti", "typ"]},
        )
    except jwt.PyJWTError as exc:
        raise TokenError(str(exc)) from exc
    if data.get("typ") != expected:
        raise TokenError(f"expected {expected} token")
    try:
        user_id = uuid.UUID(str(data["sub"]))
    except ValueError as exc:
        raise TokenError("malformed subject") from exc
    return TokenClaims(
        user_id=user_id,
        type=expected,
        jti=str(data["jti"]),
        expires_at=datetime.fromtimestamp(int(data["exp"]), UTC),
        family=data.get("fam"),
    )
