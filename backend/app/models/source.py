from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, TimestampMixin, UUIDPkMixin, pg_enum
from app.domain.enums import ItemKind, ItemStatus, ParserKey, SourceKind


class Source(UUIDPkMixin, TimestampMixin, Base):
    """Something we poll: a seed portal, a user's career page, or a Telegram channel."""

    __tablename__ = "sources"
    __table_args__ = (UniqueConstraint("kind", "url", name="kind_url"),)

    kind: Mapped[SourceKind] = mapped_column(pg_enum(SourceKind, "source_kind"))
    parser: Mapped[ParserKey] = mapped_column(pg_enum(ParserKey, "parser_key"))
    name: Mapped[str] = mapped_column(String(200))
    url: Mapped[str] = mapped_column(String(1000))
    owner_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    enabled: Mapped[bool] = mapped_column(default=True)
    render_js: Mapped[bool] = mapped_column(default=False)

    # --- Diff engine state ----------------------------------------------------
    content_hash: Mapped[str | None] = mapped_column(String(32))  # MD5 of normalised content
    cursor: Mapped[str | None] = mapped_column(String(200))  # e.g. last Telegram post id
    last_checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_changed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    next_check_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)
    last_error: Mapped[str | None] = mapped_column(Text)
    consecutive_failures: Mapped[int] = mapped_column(Integer, default=0)

    items: Mapped[list[DiscoveredItem]] = relationship(back_populates="source", passive_deletes=True)


class DiscoveredItem(UUIDPkMixin, TimestampMixin, Base):
    """A link (PDF, detail page or alert) seen on a source. Unique per source+URL,
    which is what makes a re-crawl cheap: only unseen URLs are 'new'."""

    __tablename__ = "discovered_items"
    __table_args__ = (UniqueConstraint("source_id", "url", name="source_url"),)

    source_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("sources.id", ondelete="CASCADE"), index=True)
    url: Mapped[str] = mapped_column(String(2000))
    title: Mapped[str] = mapped_column(String(500))
    kind: Mapped[ItemKind] = mapped_column(pg_enum(ItemKind, "item_kind"))
    status: Mapped[ItemStatus] = mapped_column(pg_enum(ItemStatus, "item_status"), index=True)
    keywords: Mapped[list[str]] = mapped_column(ARRAY(String(40)), default=list)
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    error: Mapped[str | None] = mapped_column(Text)
    job_post_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("job_posts.id", ondelete="SET NULL"))

    source: Mapped[Source] = relationship(back_populates="items")
