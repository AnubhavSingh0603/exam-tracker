"""5-stage post-application lifecycle: the API view of a job's timeline.

Stages: Application window -> Admit card -> Exam -> Answer key -> Result.
The exam watcher (services/exam_watcher.py) fills the timeline as it finds
notices; which stage a user is in is decided on the phone.
"""

from __future__ import annotations

from app.models import JobPost
from app.schemas.lifecycle import LifecycleTimelineOut


def timeline_out(job: JobPost) -> LifecycleTimelineOut:
    """Requires ``job.timeline`` to be loaded (selectinload) in async code."""
    t = job.timeline
    base = (
        LifecycleTimelineOut.model_validate(t) if t is not None else LifecycleTimelineOut(job_post_id=job.id)
    )
    return base.model_copy(
        update={
            "application_start": job.application_start,
            "application_end": job.application_deadline,
            "exam_start": base.exam_start or job.exam_date,
        }
    )

