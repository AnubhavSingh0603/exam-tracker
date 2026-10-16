# Private jobs workspace (optional feature)

Corporate jobs from employers' own job boards (`private_jobs.json`, written by
`backend/app/modules/private_jobs`), a private profile (skills, experience, cities,
resume), LinkedIn-export import, and a private application tracker
(Applied → Screening → Interview → Offer).

**Isolated:** nothing in the Govt app imports this folder except
`lib/main.dart` (which shell to show). Its data lives apart too: its own
encrypted profile key, its own `private_jobs.db`, its own cache file.

Switches:
- Users: Settings › Jobs › "Private jobs (beta)", off by default.
- Builds: `--dart-define=ENABLE_PRIVATE_JOBS=false` strips it from a build.
- Pipeline: repository variable `ENABLE_PRIVATE_JOBS=false` stops the data step.

**To remove it entirely:** delete this folder, the `PrivateShell` line in
`lib/main.dart`, the "Private jobs" step in `.github/workflows/data-pipeline.yml`
and `backend/app/modules/private_jobs/`. The Govt app keeps working as before.

Not in the Drive backup yet (only the Govt data is backed up).
