import uuid
from datetime import UTC, date, datetime

from app.models import ExamLifecycleTimeline, JobPost
from app.services.lifecycle import timeline_out


def _job(**kw) -> JobPost:
    base = dict(
        id=uuid.uuid4(),
        organization="Staff Selection Commission",
        exam_name="Combined Graduate Level Examination 2026",
        application_start=datetime(2026, 9, 1, tzinfo=UTC),
        application_deadline=datetime(2026, 10, 1, 12, tzinfo=UTC),
        exam_date=date(2026, 12, 10),
    )
    base.update(kw)
    return JobPost(**base)


def test_timeline_without_row_still_has_application_and_exam_dates():
    job = _job()
    job.timeline = None
    t = timeline_out(job)
    assert t.application_end == job.application_deadline
    assert t.exam_start == date(2026, 12, 10)
    assert t.admit_card_url is None


def test_timeline_row_wins_over_job_exam_date():
    job = _job()
    job.timeline = ExamLifecycleTimeline(job_post_id=job.id, exam_start=date(2026, 12, 12), cutoff_marks={})
    assert timeline_out(job).exam_start == date(2026, 12, 12)
