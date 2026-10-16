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
    """Post-application progress, advanced by the exam watcher (never backwards)."""

    DISCOVERED = "discovered"  # legacy: seen but not applied; never watched
    APPLIED = "applied"
    ADMIT_CARD_LIVE = "admit_card_live"
    EXAM_SCHEDULED = "exam_scheduled"
    ANSWER_KEY_LIVE = "answer_key_live"
    RESULT_DECLARED = "result_declared"

    @property
    def rank(self) -> int:
        return list(ApplicationStatus).index(self)


class ExamMilestone(StrEnum):
    """What a notice found by the exam watcher announces."""

    ADMIT_CARD = "admit_card"  # admit card / hall ticket / call letter
    EXAM_SCHEDULE = "exam_schedule"  # exam date, schedule, city intimation slip
    POSTPONED = "postponed"  # rescheduled / postponed / cancelled
    ANSWER_KEY = "answer_key"  # answer key, response sheet, objections
    RESULT = "result"  # result, merit list, cut-off, scorecard


class UpdateSource(StrEnum):
    OFFICIAL = "official"  # the exam's own portal / notice board
    AGGREGATOR = "aggregator"  # seen by the general crawl (SarkariResult etc.)


class MatchKind(StrEnum):
    """How a post relates to the profile; drives the client's feed split."""

    DIRECT = "direct"  # qualification, age and experience all met
    SUGGESTED = "suggested"  # close enough to be worth a look; see SuggestionReason


class SuggestionReason(StrEnum):
    EXPERIENCE_GAP = "experience_gap"  # needs at most 1 year more experience than you have


class MatchReason(StrEnum):
    """Why the qualification matched; shown as a small tag on the card."""

    DIRECT_DEGREE = "direct_degree"  # "Direct Degree Match": your degree is listed
    UNIVERSAL_GRADUATE = "universal_graduate"  # "Universal Graduate Post": any graduate
    UNIVERSAL_POST_GRADUATE = "universal_post_graduate"  # any post-graduate
    SCHOOL_LEVEL = "school_level"  # 10th/12th post, covered by your higher qualification
    CUSTOM_QUALIFICATION = "custom_qualification"  # "Others" text found in the eligibility text


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
    WORDPRESS_POSTS = "wordpress_posts"  # a WordPress site's /wp-json/wp/v2/posts (one category)


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
