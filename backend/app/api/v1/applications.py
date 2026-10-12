"""Tracked applications: the exams the Phase 2 watcher follows for the signed-in user."""

import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.orm import selectinload

from app.api.deps import CurrentUser, SessionDep
from app.models import JobPost, PostDetail, UserApplication
from app.schemas.application import ApplicationOut, ApplicationStatusIn, ManualApplicationIn
from app.services.lifecycle import timeline_out

router = APIRouter(prefix="/applications", tags=["applications"])

MAX_UPDATES = 20


def _profile_id(user: CurrentUser) -> uuid.UUID:
    if user.profile_id is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Create your profile first")
    return user.profile_id


def _out(app: UserApplication) -> ApplicationOut:
    out = ApplicationOut.model_validate(app)
    return out.model_copy(
        update={
            "updates": out.updates[:MAX_UPDATES],
            "timeline": timeline_out(app.job) if app.job is not None else None,
        }
    )


@router.get("", response_model=list[ApplicationOut])
async def list_applications(user: CurrentUser, session: SessionDep) -> list[ApplicationOut]:
    """Everything the phone needs to refresh its Tracking list after a push."""
    apps = await session.scalars(
        select(UserApplication)
        .where(UserApplication.user_id == _profile_id(user))
        .options(
            selectinload(UserApplication.updates),
            selectinload(UserApplication.job).selectinload(JobPost.timeline),
        )
        .order_by(UserApplication.created_at.desc())
    )
    return [_out(a) for a in apps]


@router.post("", response_model=ApplicationOut, status_code=status.HTTP_201_CREATED)
async def add_manual_application(
    body: ManualApplicationIn, user: CurrentUser, session: SessionDep
) -> ApplicationOut:
    """Track an exam that isn't in the feed, by name and (ideally) its portal link."""
    app = UserApplication(
        user_id=_profile_id(user),
        exam_name=body.exam_name.strip(),
        organization=body.organization,
        official_portal_url=str(body.official_portal_url) if body.official_portal_url else None,
        updates=[],
        job=None,
    )
    session.add(app)
    await session.commit()
    return _out(app)


@router.put("/{post_detail_id}", status_code=status.HTTP_204_NO_CONTENT)
async def upsert_application(
    post_detail_id: uuid.UUID, body: ApplicationStatusIn, user: CurrentUser, session: SessionDep
) -> None:
    """Applied from the feed (or a manual status change on the phone). Starts the
    exam watcher; qualifications are not looked at again for this post."""
    profile_id = _profile_id(user)
    post = await session.scalar(
        select(PostDetail).where(PostDetail.id == post_detail_id).options(selectinload(PostDetail.job_post))
    )
    if post is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Unknown post")
    app = await session.scalar(
        select(UserApplication).where(
            UserApplication.user_id == profile_id, UserApplication.post_detail_id == post_detail_id
        )
    )
    if app is None:
        job = post.job_post
        session.add(
            UserApplication(
                user_id=profile_id,
                post_detail_id=post_detail_id,
                job_id=job.id,
                exam_name=job.exam_name,
                organization=job.organization,
                official_portal_url=job.portal_url,
                status=body.status,
            )
        )
    else:
        app.status = body.status
    await session.commit()


@router.delete("/{post_detail_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_application(post_detail_id: uuid.UUID, user: CurrentUser, session: SessionDep) -> None:
    """Stop tracking (by post id, as the feed's Undo does, or by application id)."""
    if user.profile_id is not None:
        await session.execute(
            delete(UserApplication).where(
                UserApplication.user_id == user.profile_id,
                (UserApplication.post_detail_id == post_detail_id) | (UserApplication.id == post_detail_id),
            )
        )
        await session.commit()
