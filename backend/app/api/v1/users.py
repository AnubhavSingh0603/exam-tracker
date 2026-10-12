import uuid

from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import CurrentUser, SessionDep, require_api_key
from app.models import UserProfile
from app.schemas.user import UserProfileCreate, UserProfileOut

router = APIRouter(prefix="/users", tags=["users"])


# --- Signed-in user (declared before /{user_id} so "me" isn't parsed as a UUID) ---


@router.get("/me/profile", response_model=UserProfileOut)
async def get_my_profile(user: CurrentUser) -> UserProfile:
    if user.profile is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Profile not created yet")
    return user.profile


@router.put("/me/profile", response_model=UserProfileOut)
async def upsert_my_profile(body: UserProfileCreate, user: CurrentUser, session: SessionDep) -> UserProfile:
    """Create or replace the eligibility profile (DOB, category, streams…)."""
    profile = user.profile
    if profile is None:
        profile = UserProfile(**body.model_dump())
        session.add(profile)
        await session.flush()
        user.profile_id = profile.id
    else:
        for field, value in body.model_dump().items():
            setattr(profile, field, value)
    await session.commit()
    await session.refresh(profile)
    return profile


# --- Admin (X-API-Key): Phase 1 endpoints, unchanged behaviour ---


@router.post(
    "",
    response_model=UserProfileOut,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_api_key)],
)
async def create_user(body: UserProfileCreate, session: SessionDep) -> UserProfile:
    user = UserProfile(**body.model_dump())
    session.add(user)
    await session.commit()
    return user


@router.get("/{user_id}", response_model=UserProfileOut, dependencies=[Depends(require_api_key)])
async def get_user(user_id: uuid.UUID, session: SessionDep) -> UserProfile:
    user = await session.get(UserProfile, user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")
    return user
