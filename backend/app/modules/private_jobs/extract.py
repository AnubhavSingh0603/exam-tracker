"""Reading a posting: is it in India, how much experience it really asks for, which
skills it names. Pure functions, unit-tested with real posting text."""

from __future__ import annotations

import html
import re

from bs4 import BeautifulSoup

_INDIA = re.compile(
    r"\bindia\b|bengaluru|bangalore|hyderabad|\bpune\b|mumbai|new delhi|\bdelhi\b|gurugram|gurgaon|noida"
    r"|chennai|kolkata|ahmedabad|jaipur|kochi|coimbatore|chandigarh|indore|trivandrum|thiruvananthapuram"
    r"|mysuru|mysore|bhubaneswar|lucknow|nagpur|vadodara|surat|visakhapatnam",
    re.I,
)


def in_india(*locations: str | None) -> bool:
    return any(loc and _INDIA.search(loc) for loc in locations)


def html_to_text(raw: str | None) -> str:
    """Greenhouse sends escaped HTML (&lt;div&gt;); Lever and Ashby plain HTML."""
    if not raw:
        return ""
    text = BeautifulSoup(html.unescape(raw), "lxml").get_text(" ")
    return re.sub(r"\s+", " ", text).strip()


def summary(text: str, limit: int = 280) -> str:
    if len(text) <= limit:
        return text
    cut = text[:limit].rsplit(" ", 1)[0]
    return cut + "…"


# --- Experience ----------------------------------------------------------------

_YEARS = r"(?:years?|yrs?)"
_RANGE = re.compile(rf"(\d{{1,2}})\s*\+?\s*(?:-|–|to)\s*(\d{{1,2}})\s*\+?\s*{_YEARS}", re.I)
_PLUS = re.compile(rf"(\d{{1,2}})\s*\+\s*{_YEARS}", re.I)
_MIN = re.compile(rf"(?:minimum|min\.?|at least|atleast)\s*(?:of\s*)?(\d{{1,2}})\s*\+?\s*{_YEARS}", re.I)
_OF_EXP = re.compile(rf"(\d{{1,2}})\s*{_YEARS}\s*(?:of\s+)?(?:[\w/&-]+\s+){{0,4}}experience", re.I)
_FRESHER = re.compile(
    r"\bfreshers?\b|\bnew grad\w*|\bcampus hir\w*|\b0\s*(?:-|–|to)\s*1\s*(?:years?|yrs?)\b", re.I
)

# What the title says when the text gives no years.
_TITLE_LEVELS = [
    (re.compile(r"\b(?:intern|internship|trainee|apprentice|graduate|fresher|new grad)\b", re.I), 0),
    (re.compile(r"\b(?:vp|vice president|head of|director)\b", re.I), 10),
    (re.compile(r"\b(?:principal|staff|distinguished)\b", re.I), 8),
    (re.compile(r"\b(?:lead|manager|architect)\b", re.I), 5),
    (re.compile(r"\b(?:senior|sr\.?)\b", re.I), 4),
    (re.compile(r"\bintermediate\b", re.I), 2),
    (re.compile(r"\b(?:junior|jr\.?|associate)\b", re.I), 0),
]


def experience(title: str, text: str) -> tuple[int | None, int | None, str | None]:
    """(min years, max years, where it came from: 'text' | 'title' | None).

    The text wins over labels: an "Entry level" posting that says "2+ years" asks for 2.
    With several figures ("8+ years overall, 3+ years of Kubernetes"), the largest
    minimum is the real bar.
    """
    mins: list[int] = []
    maxes: list[int] = []
    ranges: list[tuple[int, int]] = []
    for m in _RANGE.finditer(text):
        lo, hi = int(m.group(1)), int(m.group(2))
        if lo <= hi <= 30:
            mins.append(lo)
            maxes.append(hi)
            ranges.append(m.span())
    # The "5" of "3-5 years of experience" is the range's top, not a second minimum.
    for rx in (_PLUS, _MIN, _OF_EXP):
        mins += [
            int(m.group(1))
            for m in rx.finditer(text)
            if int(m.group(1)) <= 30 and not any(a <= m.start(1) < b for a, b in ranges)
        ]
    if mins:
        lo = max(mins)
        hi = max(maxes) if maxes and max(maxes) >= lo else None
        return lo, hi, "text"
    if _FRESHER.search(text) or _FRESHER.search(title):
        return 0, 1, "text"
    for rx, years in _TITLE_LEVELS:
        if rx.search(title):
            return years, None, "title"
    return None, None, None


# --- Skills --------------------------------------------------------------------

# Skill -> what postings call it. Matched as whole words in the title and text.
SKILLS: dict[str, list[str]] = {
    "python": ["python"],
    "java": ["java(?!script)"],
    "javascript": ["javascript", "js"],
    "typescript": ["typescript"],
    "react": ["react(?:\\.?js)?", "react native"],
    "angular": ["angular(?:js)?"],
    "vue": ["vue(?:\\.?js)?"],
    "node": ["node(?:\\.?js)?"],
    "golang": ["golang", "go lang"],
    "rust": ["rust"],
    "c++": ["c\\+\\+", "cpp"],
    "c#": ["c#", "\\.net", "dotnet"],
    "kotlin": ["kotlin"],
    "swift": ["swift"],
    "flutter": ["flutter"],
    "android": ["android"],
    "ios": ["ios"],
    "sql": ["sql", "mysql", "postgres(?:ql)?", "oracle db"],
    "mongodb": ["mongo(?:db)?"],
    "redis": ["redis"],
    "kafka": ["kafka"],
    "spark": ["spark", "pyspark"],
    "airflow": ["airflow"],
    "snowflake": ["snowflake"],
    "aws": ["aws", "amazon web services"],
    "gcp": ["gcp", "google cloud"],
    "azure": ["azure"],
    "docker": ["docker", "containers?"],
    "kubernetes": ["kubernetes", "k8s"],
    "terraform": ["terraform"],
    "linux": ["linux", "unix"],
    "ci/cd": ["ci/cd", "jenkins", "github actions"],
    "graphql": ["graphql"],
    "microservices": ["microservices?"],
    "django": ["django"],
    "spring": ["spring(?: boot)?"],
    "machine learning": ["machine learning", "ml", "deep learning"],
    "pytorch": ["pytorch"],
    "tensorflow": ["tensorflow"],
    "llm": ["llms?", "large language models?", "generative ai", "genai"],
    "nlp": ["nlp", "natural language processing"],
    "data science": ["data science", "data scientist"],
    "data analysis": ["data analysis", "data analyst", "analytics"],
    "excel": ["excel", "spreadsheets?"],
    "power bi": ["power ?bi"],
    "tableau": ["tableau"],
    "figma": ["figma"],
    "ui/ux": ["ui/ux", "ux", "user experience", "product design"],
    "product management": ["product manag\\w*", "product owner"],
    "sales": ["sales", "business development"],
    "marketing": ["marketing", "growth"],
    "seo": ["seo"],
    "content writing": ["content writ\\w*", "copywrit\\w*"],
    "customer support": ["customer support", "customer success", "customer service"],
    "finance": ["finance", "financial planning", "fp&a"],
    "accounting": [
        "accounting",
        "accounts payable",
        "accounts receivable",
        "chartered accountant",
        "\\bca\\b",
    ],
    "audit": ["audit\\w*"],
    "hr": ["human resources", "\\bhr\\b", "talent acquisition", "recruit\\w*"],
    "legal": ["legal", "compliance", "counsel"],
    "operations": ["operations"],
    "security": ["security", "infosec", "cybersecurity"],
    "qa": ["qa", "quality assurance", "test automation", "selenium"],
    "devops": ["devops", "sre", "site reliability"],
    "salesforce": ["salesforce"],
    "sap": ["sap"],
}
_SKILL_RE = {
    skill: re.compile(r"(?<![\w+#.])(?:" + "|".join(aliases) + r")(?![\w+#])", re.I)
    for skill, aliases in SKILLS.items()
}


# Job functions: every posting's "About us" and equal-opportunity text mentions
# marketing, HR or security, so these count only in the title and team.
FUNCTIONS = {
    "data analysis",
    "ui/ux",
    "product management",
    "sales",
    "marketing",
    "seo",
    "content writing",
    "customer support",
    "finance",
    "accounting",
    "audit",
    "hr",
    "legal",
    "operations",
    "security",
    "qa",
}


def skills(title: str, text: str, team: str | None = None) -> list[str]:
    heading = f"{title} {team or ''}"
    whole = f"{heading} {text}"
    return [skill for skill, rx in _SKILL_RE.items() if rx.search(heading if skill in FUNCTIONS else whole)]


# --- Employment type -------------------------------------------------------------


def employment_type(*raw: str | None) -> str:
    joined = " ".join(r for r in raw if r).lower().replace("-", "").replace("_", "").replace(" ", "")
    if "intern" in joined:
        return "internship"
    if "contract" in joined or "temporary" in joined or "temp" == joined:
        return "contract"
    if "parttime" in joined:
        return "part_time"
    return "full_time"
