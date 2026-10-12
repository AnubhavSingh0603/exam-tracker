"""Domain enums. Deliberately free of SQLAlchemy/FastAPI imports so pure
services (eligibility, stream matching) stay importable in isolation."""

from enum import StrEnum


class Category(StrEnum):
    UR = "UR"
    SC = "SC"
    ST = "ST"
    OBC = "OBC"
    EWS = "EWS"


class ApplicationStatus(StrEnum):
    DISCOVERED = "discovered"
    APPLIED = "applied"
    ADMIT_CARD_LIVE = "admit_card_live"
    EXAM_SCHEDULED = "exam_scheduled"


class UrgencyBand(StrEnum):
    """Maps 1:1 to the client's dark-pastel palette.

    SAFE        > 14 days   -> muted sage      (#7DA87B)
    APPROACHING 3–14 days   -> soft ochre      (#E5C07B)
    CRITICAL    < 72 hours  -> dusty rose      (#D9777F)
    INFO        no deadline -> periwinkle      (#61AFEF)
    """

    SAFE = "safe"
    APPROACHING = "approaching"
    CRITICAL = "critical"
    INFO = "info"


class SourceKind(StrEnum):
    SEED = "seed"  # built-in, shared by everyone
    CUSTOM_URL = "custom_url"  # user-submitted career page
    TELEGRAM = "telegram"  # user-submitted public channel


class ParserKey(StrEnum):
    GENERIC = "generic"
    SARKARI_RESULT = "sarkari_result"
    FREE_JOB_ALERT = "free_job_alert"
    SSC_API = "ssc_api"
    TELEGRAM = "telegram"


class ItemKind(StrEnum):
    NOTIFICATION_PDF = "notification_pdf"  # goes to the Gemini ingester
    DETAIL_PAGE = "detail_page"  # aggregator page we must open to find the PDF
    ALERT = "alert"  # admit card / exam date / postponed / corrigendum update
    OTHER = "other"  # seen, kept only for de-duplication


class ItemStatus(StrEnum):
    PENDING = "pending"
    DONE = "done"
    BASELINE = "baseline"  # present on a source's first crawl; not back-filled
    SKIPPED = "skipped"
    FAILED = "failed"


# Keys used in PostDetail.age_relaxation_overrides (in addition to Category values).
RELAXATION_KEY_PWBD = "PWBD"
RELAXATION_KEY_EXSM = "EXSM"
