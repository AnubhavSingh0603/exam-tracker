# Exam Tracker — Android client (Phase 2)

Flutter · Riverpod · sqflite · device_calendar · flutter_secure_storage.

## Layout

```
mobile/
├── lib/
│   ├── main.dart                          # opens SQLite, injects it into ProviderScope
│   ├── config/env.dart                    # --dart-define values (API URL, key, user id)
│   ├── theme/app_theme.dart               # palette, UrgencyColors ThemeExtension, ThemeData
│   ├── domain/
│   │   ├── urgency.dart                   # bands (72 h / 14 d), countdown + date formatting
│   │   └── next_step.dart                 # "One Next Step" selection (pure)
│   ├── models/                            # TrackedApplication, VaultEntry, Feed*
│   ├── services/
│   │   ├── database_service.dart          # SQLite schema + CRUD (offline source of truth)
│   │   ├── calendar_sync_service.dart     # CalendarContract writes + 3 reminders
│   │   ├── secret_store.dart              # Keystore-backed passwords
│   │   └── api_client.dart                # GET /api/v1/jobs/feed
│   ├── providers/providers.dart           # Riverpod wiring
│   ├── screens/dashboard_screen.dart      # hero → ≤5 new jobs → tracked list
│   ├── widgets/                           # hero, cards, pills, credential drawer, tracker sheet
│   └── utils/system_actions.dart          # clipboard (auto-clear), url_launcher
├── android/app/src/main/AndroidManifest.xml   # calendar perms, url queries, backup off
└── test/                                  # pure logic, SQLite (ffi), widget smoke tests
```

## First run

```bash
# 1. Generate the Android/Gradle scaffolding around the existing code (existing files are kept)
flutter create --platforms=android --org com.examtracker --project-name exam_tracker .
flutter pub get
flutter test

# 2. Point it at the backend (or skip for fully offline mode)
cp env/dev.example.json env/dev.json   # see TESTING.md
flutter run --flavor direct --dart-define-from-file=env/dev.json

# 3. Release builds, signing and store publishing: see RELEASING.md
```

Get `USER_ID` by creating your profile once on the backend:

```bash
curl -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"display_name":"Me","date_of_birth":"1998-06-15","category":"SC","streams":["B.Tech ECE"]}' \
  https://tracker.example.com/api/v1/users
```

## Behaviour notes

- **Offline-first.** Tracked applications, credentials and calendar refs live on the phone. The job
  feed is cached; with no network the app shows the last good feed with an "Offline" label.
- **Swipe right on a new job** → saved as *Applied* immediately (Undo in the snackbar), then the
  Application Tracker sheet opens. All fields are optional.
- **Swipe left on a tracked card** → archive (Undo available). Archived jobs stay out of the feed.
- **Credential Vault.** Reg No. / Roll No. are in SQLite; the password is in the Android Keystore
  via `flutter_secure_storage`, never in SQLite. Copied passwords are wiped from the clipboard after 45 s.
- **Calendar.** Writes a 30-min "closes" block ending at the deadline and a 3-hour exam event, each
  with reminders exactly 7 days, 2 days and 3 hours before. Re-syncing updates the same events. If you
  deleted one by hand, re-syncing recreates it.
- **Status menu (⋮)**: "Admit card is out" (optional download link), "Set exam date" (re-syncs the
  calendar automatically if it was synced), "Back to Applied".
