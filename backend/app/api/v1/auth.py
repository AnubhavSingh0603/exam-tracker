from typing import Annotated

from fastapi import APIRouter, Header, HTTPException, status

from app.api.deps import CurrentUser, SessionDep
from app.schemas.auth import GoogleLoginIn, RefreshIn, TokenOut, UserOut
from app.services import auth_service
from app.services.auth_service import AuthError, TokenPair

router = APIRouter(prefix="/auth", tags=["auth"])

UserAgent = Annotated[str | None, Header()]


def _token_out(pair: TokenPair, user, *, is_new: bool = False) -> TokenOut:  # noqa: ANN001
    return TokenOut(
        access_token=pair.access_token,
        access_expires_at=pair.access_expires_at,
        refresh_token=pair.refresh_token,
        refresh_expires_at=pair.refresh_expires_at,
        user=UserOut.model_validate(user),
        is_new_user=is_new,
        needs_profile=user.profile_id is None,
    )


@router.post("/google", response_model=TokenOut)
async def login_with_google(
    body: GoogleLoginIn, session: SessionDep, user_agent: UserAgent = None
) -> TokenOut:
    """Exchange a Google ID token for our access + refresh tokens. Creates the user on first login."""
    try:
        identity = await auth_service.verify_google_id_token(body.id_token)
        user, created = await auth_service.upsert_google_user(session, identity)
    except AuthError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, str(exc)) from exc
    pair = await auth_service.start_session(session, user, user_agent=user_agent)
    return _token_out(pair, user, is_new=created)


@router.post("/refresh", response_model=TokenOut)
async def refresh(body: RefreshIn, session: SessionDep, user_agent: UserAgent = None) -> TokenOut:
    """Rotate: the old refresh token stops working; keep the new one."""
    try:
        user, pair = await auth_service.rotate_refresh_token(
            session, body.refresh_token, user_agent=user_agent
        )
    except AuthError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, str(exc)) from exc
    return _token_out(pair, user)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshIn, session: SessionDep) -> None:
    await auth_service.logout(session, body.refresh_token)


@router.get("/me", response_model=UserOut)
async def me(user: CurrentUser) -> UserOut:
    return UserOut.model_validate(user)
