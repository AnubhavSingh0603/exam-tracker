# JobSummit

**One clear next step. Less to keep in mind.** A calm, ADHD-friendly Android app for
Indian government and PSU jobs and exams.

**Download:** [latest release](https://github.com/AnubhavSingh0603/exam-tracker/releases/latest)
(most phones: the `arm64-v8a` file) · [home page](https://anubhavsingh0603.github.io/exam-tracker/) ·
[privacy policy](https://anubhavsingh0603.github.io/exam-tracker/privacy.html)

| Folder | What | Status |
|---|---|---|
| [`backend/`](backend/README.md) | FastAPI + PostgreSQL + Gemini PDF extraction, Docker on OCI | Phases 1, 3, 4 |
| [`mobile/`](mobile/README.md) | Flutter Android client, offline-first, calendar sync, self-updater | Phases 2 + 4 |

**Test on your phone:** [`TESTING.md`](TESTING.md) · **Deploy:** [`backend/DEPLOY.md`](backend/DEPLOY.md) · **Release the app:** [`mobile/RELEASING.md`](mobile/RELEASING.md)

**Phase 3 (backend)** added:
- Google sign-in with rotating refresh tokens
- A worker that crawls SarkariResult, FreeJobAlert, SSC, UPSC and IBPS every ~4 h
- User-added career pages and public Telegram channels
- Automatic hand-off of newly found notification PDFs to the Gemini extractor

**Phase 4** added:
- Production Docker stack: nginx with Let's Encrypt, healthchecks, nightly backups with 7 days kept
- FCM push engine
- `/api/v1/app/version`
- An in-app self-updater for GitHub builds
- Signed `direct`/`store` build flavours and a tag-triggered GitHub Actions release

## Known gaps

- **Push needs the app side.** The server sends FCM pushes; the app still needs `firebase_messaging`
  plus your Firebase `google-services.json`, and must register its token at `PUT /api/v1/devices`.
  Application status already syncs to `PUT /api/v1/applications/{id}` when signed in.
- **No migrations yet.** Move the database to Alembic before the next change to an existing table.
