#!/usr/bin/env bash
# Nightly PostgreSQL backup: pg_dump inside the db container -> gzip -> host directory,
# keeping 7 days of rolling snapshots.
#
# cron (installed by scripts/bootstrap_vm.sh):
#   17 2 * * *  /opt/exam-tracker/backend/scripts/backup_db.sh >> /var/log/exam-tracker-backup.log 2>&1
#
# Env overrides: BACKUP_DIR (default /var/backups/exam-tracker), RETENTION_DAYS (default 7)
# Restore: scripts/restore_db.sh <file.sql.gz>
#
# Note: this protects the database only. Also keep an off-VM copy of .env (VAULT_KEY,
# JWT_SECRET), secrets/ and the Android release keystore; none of them can be recreated.
set -Eeuo pipefail
umask 077

cd "$(dirname "$0")/.."
BACKUP_DIR="${BACKUP_DIR:-/var/backups/exam-tracker}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
COMPOSE=(docker compose -f docker-compose.prod.yml)

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
trap 'log "ERROR: backup failed (line $LINENO)"; rm -f "${tmp:-}"' ERR

mkdir -p "$BACKUP_DIR"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$BACKUP_DIR/exam-tracker-$stamp.sql.gz"
tmp="$BACKUP_DIR/.in-progress-$stamp.sql.gz"

log "Dumping database -> $out"
# Credentials come from the container's own environment; nothing secret on the command line.
# --clean --if-exists makes the dump restorable over an existing database.
"${COMPOSE[@]}" exec -T db sh -c \
  'pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --no-owner --no-privileges --clean --if-exists' \
  | gzip -9 > "$tmp"

gzip -t "$tmp"  # verify the archive is readable
size="$(stat -c %s "$tmp")"
if (( size < 1024 )); then
  log "ERROR: dump is suspiciously small (${size} bytes); keeping previous backups untouched"
  rm -f "$tmp"
  exit 1
fi
mv "$tmp" "$out"
log "Wrote $(du -h "$out" | cut -f1)"

# Prune only after a successful dump. -mtime +N means "more than N full days old",
# so +(RETENTION_DAYS-1) keeps today's file plus the previous RETENTION_DAYS-1 days.
pruned="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'exam-tracker-*.sql.gz' \
            -mtime +"$((RETENTION_DAYS - 1))" -print -delete | wc -l)"
find "$BACKUP_DIR" -maxdepth 1 -type f -name '.in-progress-*' -mmin +120 -delete
log "Pruned $pruned old backup(s); $(find "$BACKUP_DIR" -maxdepth 1 -name 'exam-tracker-*.sql.gz' | wc -l) kept"
