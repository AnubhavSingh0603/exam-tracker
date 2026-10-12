# Exam Tracker — Backend (Phases 1, 3, 4)

Production deployment: see [DEPLOY.md](DEPLOY.md).

FastAPI + SQLAlchemy 2.0 (async) + PostgreSQL + Gemini Flash, packaged for an OCI Always-Free VM.
Two containers share one image: **api** (HTTP) and **worker** (scrapers, Gemini queue).

## Layout

```
backend/
├── app/
│   ├── main.py                     # FastAPI app, lifespan, /healthz
│   ├── core/
│   │   ├── config.py               # pydantic-settings (reads .env)
│   │   ├── security.py             # Fernet encryption for the Credential Vault
│   │   └── tokens.py               # JWT access/refresh minting + verification
│   ├── certs/extra_intermediates.pem   # CA intermediates some .gov.in servers forget to send
│   ├── db/                         # DeclarativeBase, async engine/session
│   ├── domain/enums.py             # Category, statuses, SourceKind, ItemKind… (no deps)
│   ├── domain/qualifications.py    # tiers + degree list (source of the app's copy)
│   ├── models/
│   │   ├── user.py · job.py        # profile, notifications, posts, seats
│   │   ├── application.py          # UserApplication + ExamUpdateLog (exam watcher)
│   │   ├── lifecycle.py            # ExamLifecycleTimeline (5 stages per notification)
│   │   ├── auth.py                 # User (Google identity), RefreshToken
│   │   └── source.py               # Source, DiscoveredItem (diff-engine state)
│   ├── schemas/                    # Pydantic v2
│   ├── services/
│   │   ├── eligibility.py · streams.py · feed.py   # discovery: degree/age/seat/experience match
│   │   ├── pdf_parser.py · ingestion.py            # Gemini PDF extraction
│   │   ├── exam_watcher.py         # post-application: per-exam notice watcher + pushes
│   │   ├── auth_service.py         # Google ID-token check, token rotation, reuse detection
│   │   ├── http_fetcher.py         # SSRF guard, per-host throttle, robots.txt, size caps
│   │   ├── js_renderer.py          # optional Playwright fallback
│   │   ├── scraper_service.py      # parsers, keyword engine, MD5 diff, SourceCrawler
│   │   ├── telegram_service.py     # t.me/s/<channel> reader
│   │   ├── discovery_pipeline.py   # crawl → detail pages → Gemini ingestion
│   │   └── seeds.py                # built-in sources
│   ├── workers/scheduler.py        # APScheduler worker (python -m app.workers.scheduler)
│   └── api/
│       ├── deps.py                 # get_current_user, get_principal, require_api_key
│       └── v1/{auth,jobs,users,sources}.py
├── tests/                          # 76 tests; no DB or network needed
└── Dockerfile · docker-compose.yml · .env.example · pyproject.toml
```

> The Phase 3 brief named `routers/auth.py`; it lives at `app/api/v1/auth.py` to match the existing layout.

## Run

```bash
cp .env.example .env      # fill in every change-me value (see "Google sign-in setup" below)
docker compose up -d --build
docker compose logs -f worker     # first crawl starts ~20 s after boot
```

Tests: `pip install -r requirements-dev.txt && pytest`

## Authentication

Two ways in, both accepted side by side:

| Who | How | Used for |
|---|---|---|
| App users | `Authorization: Bearer <access token>` from Google sign-in | feed, profile, sources, alerts |
| Server owner / scripts | `X-API-Key` | PDF upload, admin feed by `user_id`, legacy Phase 1/2 clients |

**Tokens.** Access tokens last 15 min. Refresh tokens last 60 days and **rotate on every use**.
Presenting an already-used refresh token revokes that whole login (stolen-token defence). A
20-second grace window covers the app legitimately refreshing twice at once.

### Google sign-in setup (one-time, in Google Cloud Console)
1. APIs & Services → Credentials → **Create OAuth client ID → Web application**. Its client ID
   goes into `GOOGLE_CLIENT_IDS` and is the `serverClientId` the Android app passes to Credential Manager.
2. Create an **Android** OAuth client too (package name + SHA-1 of your signing key). Its ID is
   *not* put in `.env`; Google only requires it to exist.
3. `JWT_SECRET`: `python -c "import secrets; print(secrets.token_urlsafe(48))"`.

## API

| Method | Path | Auth | Notes |
|---|---|---|---|
| `POST` | `/api/v1/auth/google` | — | `{id_token}` → tokens + `needs_profile`; creates the user on first login |
| `POST` | `/api/v1/auth/refresh` | — | `{refresh_token}` → new pair (old one stops working) |
| `POST` | `/api/v1/auth/logout` | — | revokes that login's refresh tokens |
| `GET` | `/api/v1/auth/me` | Bearer | |
| `GET/PUT` | `/api/v1/users/me/profile` | Bearer | DOB, category, `qualification_tier`, `degree_title` (or `OTHERS` + `custom_qualification_text`), `experience_years`, PwBD/ESM |
| `GET` | `/api/v1/meta/qualifications` | — | tiers and degree codes for the profile picker |
| `GET` | `/api/v1/jobs/feed` | Bearer, or API key + `user_id` | `{category, hero, up_next[], hidden_count, suggested[], suggested_hidden_count}`, ≤ 5 items each |
| `POST` | `/api/v1/jobs/upload-notification` | API key | manual PDF ingestion |
| `POST` | `/api/v1/sources/custom-url` | Bearer | `{url, name?}`; fetched once now and returns a preview |
| `POST` | `/api/v1/sources/telegram` | Bearer | `{channel}`: `@name`, `name` or a t.me link |
| `GET` | `/api/v1/sources` | Bearer | seeds + yours, with last check / error |
| `DELETE` | `/api/v1/sources/{id}` | Bearer | only your own |
| `GET` | `/api/v1/sources/alerts` | Bearer | admit card / exam date / postponed / corrigendum / date-extended updates |
| `PUT/DELETE` | `/api/v1/devices` | Bearer | register/remove an FCM token (`kind`: `token` or `fid`) |
| `GET` | `/api/v1/applications` | Bearer | tracked exams with watcher status, latest notices and 5-stage timeline |
| `POST` | `/api/v1/applications` | Bearer | track an exam by name + portal link (not from the feed) |
| `PUT/DELETE` | `/api/v1/applications/{post_detail_id}` | Bearer | applied from the feed (starts the exam watcher, stops deadline pings) |
| `GET` | `/api/v1/app/version` | — | `?current_version_code=&abi=` → latest APK URL, SHA-256, `update_available`, `mandatory` |
| `POST/GET` | `/api/v1/users`, `/api/v1/users/{id}` | API key | Phase 1 admin endpoints |

## Discovery pipeline

```
every 10 min ── crawl: sources whose next_check_at is due
                 fetch → parse → MD5 of the normalised link set
                 unchanged? done.  changed? new links → classify:
                   notification PDF ─┐        aggregator detail page ─┐      alert ─→ /sources/alerts
every 10 min ── details: open detail pages, find "Download Notification" ─┘
every 15 min ── ingest: download ≤ 4 PDFs (checked to really be PDFs) → Gemini → job_posts
```

- **Per-source schedule.** After every crawl a source schedules itself 4 h ± 30 min ahead, so
  sources drift apart instead of firing together. Failures back off exponentially, capped at 24 h.
- **No first-crawl flood.** Adding a source records its existing links as a baseline and only
  ingests the newest 3 (`SEED_BACKFILL_PER_SOURCE`). SarkariResult's list alone has ~4,000 entries.
- **Gemini quota.** Only links that look like recruitment notifications are queued. Results, answer
  keys, syllabi and tentative-vacancy notices are skipped.
- **Single leader.** A Postgres advisory lock means only one worker crawls, even if two run.

### Seeds (checked against the live sites, Oct 2026)

| Source | How it's read | Live result at build time |
|---|---|---|
| SarkariResult latest jobs / admit cards | `ul.wp-block-list` → detail page "Download Notification" row | real PDFs (DSSSB, NTA UGC-NET, CSIR-NET) |
| FreeJobAlert | `table.lattbl` rows → "Download Official Notification" | real PDFs (Exim Bank, J&K Bank, NABCONS) |
| SSC | public JSON API behind the React site (no browser needed) | notice board + attachments |
| UPSC | home page "What's New" | 56 links, admit card alerts |
| IBPS | home page | 31 links, call-letter + addendum alerts |

Parsers fall back to the generic DOM parser if a site's markup changes. Expect to adjust selectors occasionally.

### Telegram
Reads the public web preview at `t.me/s/<channel>`. You get message text, time, permalink, every
link in the text, and **titles** of attached files. The preview doesn't expose file downloads, so
attachments become alerts linking to the post. Downloading files would need MTProto (Telethon +
a user session), which is deliberately not included. Private channels are rejected when added.
*`t.me` was unreachable from the development network, so the parser is tested against fixtures of
Telegram's standard preview markup, not the live site.*

## Crawling safety & etiquette

- **SSRF guard.** User-submitted URLs, redirects and Playwright sub-requests may only reach public IPs
  on ports 80/443. Localhost, private ranges, CGNAT and OCI's metadata service (169.254.169.254)
  are blocked, and every redirect hop is re-checked.
- **Politeness.** One request per host per 8 s (+ jitter), robots.txt respected, size caps, retries with
  back-off on 429/5xx.
- **Honest User-Agent.** `ExamTracker/0.3 (personal exam tracker)`. No browser impersonation.
  UPSC's firewall returns 403 for any UA containing "bot", a URL or an e-mail address, hence the plain form.
- **TLS stays verified.** Two real-world fixes keep verification on while still working:
  - Some government servers send an incomplete certificate chain (IBPS). The missing public
    intermediate is bundled in `app/certs/`.
  - Some old state-commission servers (upsssc.gov.in) need legacy renegotiation. It's allowed by
    default (`TLS_ALLOW_LEGACY_RENEGOTIATION`), and certificates are still verified.
- **Playwright** is optional (`--build-arg WITH_CHROMIUM=1` + `PLAYWRIGHT_ENABLED=true`; uses Debian's arm64/amd64 `chromium`). None of
  the seeds need it. Use it on an Ampere A1 shape, not the 1 GB micro.

## Domain decisions (Phase 1)

- **Age** = completed years on the post's `age_as_on` date. 25y 11m counts as 25.
- **Relaxation defaults**: SC/ST +5, OBC +3, EWS 0, PwBD +10 (stacks on category), Ex-SM +3 + service years.
  Notification-specific values extracted from the PDF override these per post.
- **Seat pooling**: reserved candidates reach `UR + own category`. With `STRICT_UR_MIGRATION=true`
  (default), a candidate eligible **only because of** an age relaxation can't be counted against UR
  seats (DoPT rule upheld in *Deepa E.V. v. Union of India*, 2017).
- **Extraction never silently lies**: anything suspicious lands in `review_notes` with `needs_review=true`.

## Known gaps

- **Schema migrations.** Phase 3 only *adds* tables, so `AUTO_CREATE_SCHEMA` still works on an
  existing database. Move to Alembic before the next change that alters an existing table.
- **Mobile app sign-in.** The Flutter app still authenticates with `X-API-Key` + `USER_ID`. Adding
  Google sign-in there (Credential Manager → `/auth/google`) is the next mobile task.
- **Alerts are pull-only** (`/sources/alerts`). FCM push is next.
- **Alerts aren't personalised.** They aren't matched to the jobs a user tracks yet.
