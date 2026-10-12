"""Request dependencies: DB session and the two ways to authenticate.

* Bearer access token (Google sign-in)   -> a real ``User``
* ``X-API-Key`` (server owner / scripts)   -> admin, no user

Phase 1/2 clients that only send X-API-Key keep working unchanged.
"""

import secrets
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, HTTPException, Security, status
from fastapi.security import APIKeyHeader, HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.tokens import TokenError, decode_token
from app.db.session import get_session
from app.models import User

SessionDep = Annotated[AsyncSession, Depends(get_session)]

_api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)
_bearer = HTTPBearer(auto_error=False)

_UNAUTHORIZED = HTTPException(
    status.HTTP_401_UNAUTHORIZED, "Not authenticated", headers={"WWW-Authenticate": "Bearer"}
)


def _api_key_ok(key: str | None) -> bool:
    expected = get_settings().api_key.get_secret_value()
    return bool(key) and secrets.compare_digest(key.encode(), expected.encode())  # type: ignore[union-attr]


async def require_api_key(key: Annotated[str | None, Security(_api_key_header)]) -> None:
    if not _api_key_ok(key):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or missing API key")


async def _user_from_bearer(session: AsyncSession, creds: HTTPAuthorizationCredentials | None) -> User | None:
    if creds is None or creds.scheme.lower() != "bearer":
        return None
    try:
        claims = decode_token(creds.credentials, "access")
    except TokenError:
        raise _UNAUTHORIZED from None
    user = await session.get(User, claims.user_id)
    if user is None or not user.is_active:
        raise _UNAUTHORIZED
    return user


async def get_current_user(
    session: SessionDep,
    creds: Annotated[HTTPAuthorizationCredentials | None, Security(_bearer)],
) -> User:
    user = await _user_from_bearer(session, creds)
    if user is None:
        raise _UNAUTHORIZED
    return user


@dataclass(frozen=True, slots=True)
class Principal:
    user: User | None
    is_admin: bool


async def get_principal(
    session: SessionDep,
    creds: Annotated[HTTPAuthorizationCredentials | None, Security(_bearer)],
    key: Annotated[str | None, Security(_api_key_header)],
) -> Principal:
    if creds is not None:
        user = await _user_from_bearer(session, creds)
        return Principal(user=user, is_admin=False)
    if _api_key_ok(key):
        return Principal(user=None, is_admin=True)
    raise _UNAUTHORIZED


CurrentUser = Annotated[User, Depends(get_current_user)]
PrincipalDep = Annotated[Principal, Depends(get_principal)]
