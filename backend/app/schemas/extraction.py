"""LLM-facing schema passed to Gemini as ``response_schema``.

Kept intentionally "dumb" for maximum compatibility with Gemini's OpenAPI-subset
schema support: no defaults, no dicts, dates as ISO strings. Every field is
required-but-nullable so the model must make an explicit decision.
Strong typing and sanity checks happen afterwards in ``schemas/notification.py``.
"""

from pydantic import BaseModel, Field


class ExtractedRelaxation(BaseModel):
    category: str = Field(description="One of: SC, ST, OBC, EWS, PWBD, EXSM")
    years: int = Field(description="Upper age relaxation in years for this category")


class ExtractedVacancy(BaseModel):
    ur: int | None = Field(description="Unreserved / General / UR / GEN seats")
    sc: int | None = Field(description="Scheduled Caste seats")
    st: int | None = Field(description="Scheduled Tribe seats")
    obc: int | None = Field(description="OBC / OBC-NCL seats")
    ews: int | None = Field(description="Economically Weaker Section seats")
    total: int | None = Field(description="Total seats for the post as printed")
    pwbd: int | None = Field(description="PwBD / PH / Divyang seats (horizontal), if printed")
    ex_serviceman: int | None = Field(description="Ex-Servicemen seats (horizontal), if printed")


class ExtractedPost(BaseModel):
    post_code: str | None = Field(description="Post code / advt. post no., verbatim")
    post_name: str = Field(description="Post / discipline name in English")
    min_age: int | None = Field(description="Minimum age in years")
    max_age_ur: int | None = Field(description="Maximum age in years for UR/General")
    age_as_on_date: str | None = Field(
        description="Post-specific age cut-off date (YYYY-MM-DD); "
        "only if it differs from the notification-wide one"
    )
    eligible_degrees: list[str] = Field(
        description="One short entry per degree+branch, e.g. 'B.E./B.Tech Electronics & Communication'. "
        "Use 'Any Graduate' or 'B.E./B.Tech Any Branch' for open eligibility."
    )
    qualification_summary: str | None = Field(description="One-sentence plain-English qualification summary")
    vacancies: ExtractedVacancy
    age_relaxations: list[ExtractedRelaxation] = Field(
        description="Only relaxations specific to this post that differ from the notification-wide list"
    )


class NotificationExtraction(BaseModel):
    organization: str = Field(description="Recruiting organisation, e.g. 'Bharat Electronics Limited'")
    exam_name: str = Field(description="Recruitment / exam title")
    advertisement_no: str | None
    official_portal_url: str | None = Field(description="Online application URL printed in the notification")
    application_start_date: str | None = Field(description="YYYY-MM-DD")
    application_end_date: str | None = Field(description="Last date for online application, YYYY-MM-DD")
    application_end_time: str | None = Field(description="Closing time on the last date, 24h HH:MM")
    exam_date: str | None = Field(description="Tentative exam date, YYYY-MM-DD")
    age_as_on_date: str | None = Field(description="Date on which age is reckoned, YYYY-MM-DD")
    general_age_relaxations: list[ExtractedRelaxation]
    posts: list[ExtractedPost]
