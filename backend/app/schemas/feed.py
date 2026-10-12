import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.domain.enums import Category, UrgencyBand


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


class FeedItem(BaseModel):
    job_post_id: uuid.UUID
    organization: str
    exam_name: str
    portal_url: str | None
    application_deadline: datetime
    hours_remaining: int
    urgency: UrgencyBand
    next_step: str = Field(description="Single imperative sentence for the hero card")
    best_post: FeedPost  # highest reachable seats among eligible posts
    other_eligible_posts: list[FeedPost]


class FeedResponse(BaseModel):
    generated_at: datetime
    category: Category = Field(description="User's category, so clients can label quota seats")
    hero: FeedItem | None = Field(description="'One Next Step': the single most urgent action")
    up_next: list[FeedItem] = Field(description="Remaining items, capped by the Paralysis Shield")
    hidden_count: int = Field(description="Eligible open jobs deliberately not shown")
