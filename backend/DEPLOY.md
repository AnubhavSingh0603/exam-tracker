# Deploying on an OCI Always-Free VM

Target: Ubuntu 22.04/24.04 on **Ampere A1** (arm64, recommended: up to 4 OCPU / 24 GB free)
or the AMD micro shape (1 GB RAM: works, with the swap file the bootstrap creates).

## 0. Before you start
- A domain (or free subdomain) with an **A record → the VM's public IP**.
- OCI console → your VCN → Security List: add **ingress TCP 80 and 443** from `0.0.0.0/0`.
- Optional, for push: Firebase console → Project settings → Service accounts → *Generate new
  private key* → save as `firebase-service-account.json`.

## 1. Prepare the VM (once)
```bash
sudo mkdir -p /opt/exam-tracker && sudo chown "$USER" /opt/exam-tracker
git clone https://github.com/OWNER/REPO.git /opt/exam-tracker
cd /opt/exam-tracker/backend
sudo bash scripts/bootstrap_vm.sh     # Docker, firewall (80/443), swap, auto-updates, cron
exit                                   # log back in so the docker group applies
```

## 2. Configure
```bash
cd /opt/exam-tracker/backend
cp .env.example .env && nano .env
#   DOMAIN, LETSENCRYPT_EMAIL, GITHUB_REPO
#   API_KEY, VAULT_KEY, JWT_SECRET, POSTGRES_PASSWORD (+ same in DATABASE_URL)
#   GEMINI_API_KEY, GOOGLE_CLIENT_IDS
#   ENVIRONMENT=prod
cp ~/firebase-service-account.json secrets/ && chmod 600 secrets/*.json    # optional
```

## 3. Certificate + start everything
```bash
LETSENCRYPT_STAGING=1 ./init-letsencrypt.sh   # dry run against the staging CA first
FORCE=1 ./init-letsencrypt.sh                 # then the real certificate
curl https://$DOMAIN/healthz                   # {"status":"ok","db":true}
```

From now on the stack survives reboots and crashes on its own:
- Docker starts at boot, and every container has `restart: unless-stopped`.
- Unhealthy containers are restarted.
- Certificates renew every 12 h (certbot), and nginx reloads every 6 h to pick them up.

## Day-2 operations

| Task | Command |
|---|---|
| Status | `docker compose -f docker-compose.prod.yml ps` |
| Logs | `docker compose -f docker-compose.prod.yml logs -f --tail=100 api worker` |
| Deploy new code | `git pull && docker compose -f docker-compose.prod.yml up -d --build` |
| Backup now | `scripts/backup_db.sh` (nightly 02:17 via cron, 7 days kept in `/var/backups/exam-tracker`) |
| Restore | `scripts/restore_db.sh /var/backups/exam-tracker/exam-tracker-<stamp>.sql.gz` |
| Publish app release to the server | `scripts/sync_release_manifest.sh` (cron runs it every 30 min) |

**Back up off the VM too**, because none of these can be regenerated:
- `.env`: `VAULT_KEY` decrypts stored portal passwords, and `JWT_SECRET` signs every login.
- `secrets/`
- the Android keystore

One option is an OCI Object Storage bucket (free tier) with `rclone` syncing `/var/backups/exam-tracker`.

## What runs

| Service | Image | Notes |
|---|---|---|
| nginx | nginx:1.27-alpine | TLS, HSTS/CSP, gzip, rate limits (`/auth` 10/min, API 10/s), `/downloads/` APK mirror |
| certbot | certbot/certbot | renew loop |
| api | local build | FastAPI/uvicorn, internal port 8000 only |
| worker | local build | APScheduler: crawl, details, Gemini ingest, FCM notify, token purge |
| db | postgres:16-alpine | volume `pgdata`, no published port |

Redis/Celery are intentionally absent: nothing uses a broker, and the RAM is better spent on Postgres.
