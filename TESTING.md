# Testing end-to-end on your own phone

Fastest route: **A → B → C**. You'll have the app on your phone talking to the backend on your
laptop, no Google setup needed. Do **D** when you want real sign-in, and **E** when you'd rather
install builds from GitHub than over USB.

---

## A. Push the repository to GitHub

```bash
cd exam-tracker
git init -b main
git add .
git status        # MUST NOT list backend/.env, *.jks, key.properties, mobile/env/*.json (only *.example.json)
git commit -m "Initial import"
gh repo create exam-tracker --private --source=. --push   # or create it on github.com and `git push -u origin main`
```

Keep the repo **private** until mobile sign-in is configured. Workflow artifacts and pre-releases
on a public repo can be downloaded by anyone.

On Windows, if scripts were ever checked out with CRLF line endings: `git add --renormalize .` (`.gitattributes` forces LF).

---

## B. Run the backend locally (Docker Desktop)

```bash
cd backend
cp .env.example .env
```

Fill in `.env` (generate secrets with the commands in the comments):

| Key | Local value |
|---|---|
| `ENVIRONMENT` | `dev` (enables http://localhost:8000/docs) |
| `API_KEY`, `VAULT_KEY`, `JWT_SECRET` | generated |
| `POSTGRES_PASSWORD` | anything, and **the same** inside `DATABASE_URL=postgresql+asyncpg://tracker:<pw>@db:5432/tracker` |
| `GEMINI_API_KEY` | from https://aistudio.google.com/apikey |
| `GOOGLE_CLIENT_IDS` | `[]` for now (step D fills it) |

Start it so your phone can reach it over Wi-Fi:

```bash
API_BIND=0.0.0.0 docker compose up -d --build        # bash / Git Bash
```
```powershell
$env:API_BIND="0.0.0.0"; docker compose up -d --build   # PowerShell
```

Allow the port through the Windows firewall (private networks only), then find your laptop's IP:
```powershell
New-NetFirewallRule -DisplayName "exam-tracker dev API" -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private
ipconfig    # "IPv4 Address", e.g. 192.168.1.20
```

Check:
- http://localhost:8000/healthz on the laptop should return `{"status":"ok","db":true}`.
- On the phone's browser, `http://192.168.1.20:8000/healthz` should return the same.

Give it data. The worker starts crawling about 20 s after boot (`docker compose logs -f worker`)
and ingests a few PDFs every 15 minutes. To skip the wait, upload a notification PDF:
```bash
curl -H "X-API-Key: $API_KEY" -F file=@notification.pdf http://localhost:8000/api/v1/jobs/upload-notification
```

---

## C. Run the app on your phone with `flutter run` (dev API-key mode)

One-time setup:
1. Install Flutter (stable) and Android Studio (for the SDK). `flutter doctor` should be green for Android.
2. On the phone: Settings → About → tap *Build number* 7× → Developer options → **USB debugging** on.
3. Plug in, accept the prompt; `flutter devices` should list the phone.

```bash
cd mobile
flutter create --platforms=android --org com.examtracker --project-name exam_tracker .   # first time only; keeps existing files
flutter pub get
flutter test
cp env/dev.example.json env/dev.json
```
Edit `env/dev.json`:
```json
{ "APP_ENV": "dev", "API_BASE_URL_DEV": "http://192.168.1.20:8000", "API_KEY": "<backend API_KEY>" }
```
```bash
flutter run --flavor direct --dart-define-from-file=env/dev.json
```

What you should see:
1. Android asks to allow notifications (once).
2. The **"About you"** sheet opens: date of birth, category, degrees, PwBD / ex-serviceman.
3. **Save** → the "New for you" feed fills with jobs you're eligible for (if the backend has any).
4. Swipe a job right → it moves to *Tracking*; *Sync to Calendar* writes events with 7 d / 2 d / 3 h reminders.

Tips:
- **Phone can't reach the laptop** (guest Wi-Fi, AP isolation): run `adb reverse tcp:8000 tcp:8000`
  and use `"API_BASE_URL_DEV": "http://localhost:8000"` over USB instead.
- **Emulator**: the default `http://10.0.2.2:8000` already points at your laptop.
- `API_KEY` only works in non-prod builds (`APP_ENV` ≠ `prod`), and plain `http://` only works in
  **debug** builds. Release builds are HTTPS-only by design.

---

## D. Real Google sign-in (one-time Google Cloud setup)

1. https://console.cloud.google.com → new project → **Google Auth Platform / OAuth consent screen**:
   External, publishing status *Testing*, and add your Gmail under **Test users**.
2. **Credentials → Create OAuth client ID → Web application.** Copy the client ID:
   - backend `.env`: `GOOGLE_CLIENT_IDS=["<web-client-id>"]`, then `docker compose up -d`
   - app `env/*.json`: `"GOOGLE_SERVER_CLIENT_ID": "<web-client-id>"`, and **remove `API_KEY`**
     (dev key mode takes priority).
3. **Create OAuth client ID → Android**, once per signing key that builds the app:
   - package name `com.examtracker.exam_tracker`
   - SHA-1 of the signing key. For your local debug key:
     ```bash
     keytool -list -v -alias androiddebugkey -storepass android -keypass android -keystore ~/.android/debug.keystore
     ```
     (Windows: `%USERPROFILE%\.android\debug.keystore`). Repeat for the CI debug key (E) and the release key.
4. `flutter run --flavor direct --dart-define-from-file=env/dev.json` → **Sign in** (top-right) → pick your account → the profile sheet opens.

If sign-in fails with a configuration or "developer" error, the Android client's SHA-1 doesn't
match the key that signed the build you're running.

---

## E. Install a test APK built by GitHub Actions (no USB, no keystore)

1. Create a **stable** debug key once, so builds can update each other and Google sign-in can work:
   ```bash
   keytool -genkeypair -v -keystore ci-debug.keystore -storepass android -keypass android \
     -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
   base64 -w0 ci-debug.keystore      # macOS: base64 -i ci-debug.keystore
   ```
   - GitHub → Settings → Secrets and variables → Actions → **Secrets**: `DEBUG_KEYSTORE_BASE64` = that output.
   - Add its SHA-1 as another Android OAuth client (D3).
2. **Variables**:
   - `APP_API_BASE_URL_STAGING`: a backend the phone can reach. That's your OCI VM
     (`https://…`, see `backend/DEPLOY.md`), or `http://<LAN_IP>:8000` if the phone is on your Wi-Fi.
   - `GOOGLE_SERVER_CLIENT_ID`
3. Actions → **Android test build** → *Run workflow* → tick **pre-release**.
4. On the phone, open the repo's Releases page → *Test build #N* → download the `.apk` → allow
   your browser to "Install unknown apps" → install.
   - Private repo: download the artifact on a computer instead (Actions → run → Artifacts),
     unzip it, and copy the APK over or `adb install` it.
   - **Samsung One UI 6+**: turn off *Settings → Security and privacy → Auto Blocker* to sideload.

Each push to `main` that touches `mobile/` also produces a test APK artifact automatically.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `CLEARTEXT communication … not permitted` | It's a release/profile build, or the URL is `http://`. Use a debug build for LAN testing, or HTTPS. |
| "App not installed" when updating a test build | It was signed with a different key. Uninstall first, or set `DEBUG_KEYSTORE_BASE64`. |
| Sign-in: configuration / developer error | Android OAuth client missing for this package + SHA-1 (D3). |
| Sign-in works, then `401` from the API | Backend `GOOGLE_CLIENT_IDS` doesn't contain the *Web* client ID the app uses. |
| Feed says nothing new | The backend has no open jobs for your profile yet: upload a PDF (B) or wait for the worker. |
| `docker compose` can't connect to Postgres | `POSTGRES_PASSWORD` and the password inside `DATABASE_URL` differ. |
