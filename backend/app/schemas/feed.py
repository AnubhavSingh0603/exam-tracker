import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.domain.enums import Category, MatchKind, MatchReason, SuggestionReason, UrgencyBand
from app.schemas.lifecycle import LifecycleTimelineOut


class FeedPost(BaseModel):
    post_detail_id: uuid.UUID
    post_code: str | None
    post_name: str
    age_on_cutoff_years: int | None
    effective_max_age: int | None
    eligible_via_relaxation: bool
    category_quota_seats: int
    ur_open_seats: int
    total_reachable_seats: int
    qualification_verified: bool
    notes: list[str]
    match_kind: MatchKind
    match_reason: MatchReason | None = Field(None, description="Which qualification rule matched")
    match_reason_label: str | None = Field(None, examples=["Universal Graduate Post"])
    suggestion_reasons: list[SuggestionReason] = Field(
        default_factory=list, description="Why a SUGGESTED post isn't a direct match (badge text)"
    )


class FeedItem(BaseModel):
    job_post_id: uuid.UUID
    organization: str
    exam_name: str
    portal_url: str | None
    application_deadline: datetime
    hours_remaining: int
    urgency: UrgencyBand
    next_step: str = Field(description="Single imperative sentence for the hero card")
    match_kind: MatchKind = Field(description="DIRECT if any post is a direct match, else SUGGESTED")
    best_post: FeedPost  # highest reachable seats among posts of this match_kind
    other_eligible_posts: list[FeedPost]
    timeline: LifecycleTimelineOut | None = Field(
        None, description="Post-application milestones known so far (stored by the phone on 'Applied')"
    )


class FeedResponse(BaseModel):
    generated_at: datetime
    category: Category = Field(description="User's category, so clients can label quota seats")
    hero: FeedItem | None = Field(description="'One Next Step': the single most urgent action")
    up_next: list[FeedItem] = Field(description="Remaining items, capped by the Paralysis Shield")
    hidden_count: int = Field(description="Eligible open jobs deliberately not shown")
    suggested: list[FeedItem] = Field(
        default_factory=list,
        description="'💡 Suggested' tab: posts up to 1 year short on experience, urgency-sorted, capped",
    )
    suggested_hidden_count: int = 0
