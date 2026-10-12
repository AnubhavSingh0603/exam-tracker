"""Importing this package registers every table on Base.metadata."""

from app.models.application import ExamUpdateLog, UserApplication
from app.models.auth import RefreshToken, User
from app.models.job import JobPost, PostDetail, VacancyMatrix
from app.models.lifecycle import ExamLifecycleTimeline
from app.models.notification import DeviceToken, NotificationLog
from app.models.source import DiscoveredItem, Source
from app.models.user import UserProfile

__all__ = [
    "DeviceToken",
    "DiscoveredItem",
    "ExamLifecycleTimeline",
    "ExamUpdateLog",
    "JobPost",
    "NotificationLog",
    "PostDetail",
    "RefreshToken",
    "Source",
    "User",
    "UserApplication",
    "UserProfile",
    "VacancyMatrix",
]
