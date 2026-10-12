"""Google sign-in + our own access/refresh tokens.

Flow
----
1. The app signs in with Google (Android Credential Manager) and gets an ID token
   whose ``aud`` is our Web client ID.
2. ``POST /auth/google`` verifies it against Google's JWKS, upserts the User,
   and returns a 15-min access token + a 60-day refresh token.
3. ``POST /auth/refresh`` rotates the refresh token. Re-using an already-rotated
   token revokes the whole login family (stolen-token defence).
"""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from functools import lru_cache

import jwt
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.tokens import TokenError, create_token, decode_token, new_token_id
from app.models import RefreshToken, User

GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = frozenset({"https://accounts.google.com", "accounts.google.com"})
# Two near-simultaneous refreshes (app resume + background sync) are normal, not theft.
REUSE_GRACE = timedelta(seconds=20)


class AuthError(Exception):
    """Authentication failed; message is safe to show to clients."""


@dataclass(frozen=True, slots=True)
class GoogleIdentity:
    sub: str
    email: str
    email_verified: bool
    name: str | None
    picture: str | None


@dataclass(frozen=True, slots=True)
class TokenPair:
    access_token: str
    access_expires_at: datetime
    refresh_token: str
    refresh_expires_at: datetime


@lru_cache
def _jwks_client() -> jwt.PyJWKClient:
    # Caches Google's signing keys in-process (they rotate ~weekly).
    return jwt.PyJWKClient(GOOGLE_JWKS_URL, cache_keys=True, lifespan=6 * 3600)


def verify_google_id_token_sync(id_token: str) -> GoogleIdentity:
    audiences = get_settings().google_client_ids
    if not audiences:
        raise AuthError("Google sign-in is not configured on this server")
    try:
        key = _jwks_client().get_signing_key_from_jwt(id_token)
        claims = jwt.decode(
            id_token,
            key.key,
            algorithms=["RS256"],
            audience=audiences,
            leeway=30,
            options={"require": ["exp", "iat", "iss", "aud", "sub"]},
        )
    except jwt.PyJWTError as exc:
        raise AuthError("Invalid Google ID token") from exc
    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise AuthError("Invalid Google ID token issuer")
    email = claims.get("email")
    if not email:
        raise AuthError("Google account has no email")
    return GoogleIdentity(
        sub=str(claims["sub"]),
        email=str(email),
        email_verified=bool(claims.get("email_verified", False)),
        name=claims.get("name"),
        picture=claims.get("picture"),
    )


async def verify_google_id_token(id_token: str) -> GoogleIdentity:
    # JWKS fetch on cache miss is blocking network I/O.
    return await asyncio.to_thread(verify_google_id_token_sync, id_token)


async def upsert_google_user(session: AsyncSession, ident: GoogleIdentity) -> tuple[User, bool]:
    now = datetime.now(UTC)
    user = await session.scalar(select(User).where(User.google_sub == ident.sub))
    created = user is None
    if user is None:
        user = User(google_sub=ident.sub, email=ident.email, last_login_at=now)
        session.add(user)
    if not user.is_active:
        raise AuthError("Account disabled")
    user.email = ident.email
    user.email_verified = ident.email_verified
    user.name = ident.name
    user.picture_url = ident.picture
    user.last_login_at = now
    await session.flush()
    return user, created


async def _issue(
    session: AsyncSession, user_id: uuid.UUID, *, family: str, user_agent: str | None
) -> tuple[TokenPair, str]:
    access, a_claims = create_token(user_id, "access")
    refresh, r_claims = create_token(user_id, "refresh", family=family)
    session.add(
        RefreshToken(
            jti=r_claims.jti,
            user_id=user_id,
            family_id=family,
            expires_at=r_claims.expires_at,
            user_agent=(user_agent or "")[:300] or None,
        )
    )
    pair = TokenPair(access, a_claims.expires_at, refresh, r_claims.expires_at)
    return pair, r_claims.jti


async def start_session(session: AsyncSession, user: User, *, user_agent: str | None) -> TokenPair:
    pair, _ = await _issue(session, user.id, family=new_token_id(), user_agent=user_agent)
    await session.commit()
    return pair


async def revoke_family(session: AsyncSession, family: str) -> None:
    await session.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )


async def rotate_refresh_token(
    session: AsyncSession, refresh_token: str, *, user_agent: str | None
) -> tuple[User, TokenPair]:
    try:
        claims = decode_token(refresh_token, "refresh")
    except TokenError as exc:
        raise AuthError("Invalid refresh token") from exc

    now = datetime.now(UTC)
    row = await session.scalar(select(RefreshToken).where(RefreshToken.jti == claims.jti).with_for_update())
    if row is None or row.user_id != claims.user_id:
        raise AuthError("Invalid refresh token")
    if row.expires_at <= now:
        raise AuthError("Refresh token expired")
    if row.revoked_at is not None:
        within_grace = row.replaced_by is not None and now - row.revoked_at <= REUSE_GRACE
        if not within_grace:
            await revoke_family(session, row.family_id)
            await session.commit()
            raise AuthError("Refresh token reuse detected; please sign in again")

    user = await session.get(User, row.user_id)
    if user is None or not user.is_active:
        raise AuthError("Account disabled")

    pair, new_jti = await _issue(session, user.id, family=row.family_id, user_agent=user_agent)
    if row.revoked_at is None:
        row.revoked_at = now
        row.replaced_by = new_jti
    await session.commit()
    return user, pair


async def logout(session: AsyncSession, refresh_token: str) -> None:
    """Revokes the whole login family. Silently ignores invalid tokens."""
    try:
        claims = decode_token(refresh_token, "refresh")
    except TokenError:
        return
    if claims.family:
        await revoke_family(session, claims.family)
        await session.commit()


async def purge_expired_tokens(session: AsyncSession) -> int:
    result = await session.execute(
        delete(RefreshToken).where(RefreshToken.expires_at < datetime.now(UTC) - timedelta(days=1))
    )
    await session.commit()
    return result.rowcount or 0
