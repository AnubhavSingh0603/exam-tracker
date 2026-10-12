#!/usr/bin/env bash
# Restore a backup made by backup_db.sh. Stops api/worker during the restore.
#   scripts/restore_db.sh /var/backups/exam-tracker/exam-tracker-20261011T021700Z.sql.gz
set -Eeuo pipefail
cd "$(dirname "$0")/.."
COMPOSE=(docker compose -f docker-compose.prod.yml)

file="${1:-}"
[[ -f "$file" ]] || { echo "Usage: $0 <backup.sql.gz>" >&2; exit 1; }
gzip -t "$file"

read -r -p "This REPLACES the current database with $(basename "$file"). Type 'restore' to continue: " answer
[[ "$answer" == "restore" ]] || { echo "Aborted."; exit 1; }

"${COMPOSE[@]}" stop api worker
gunzip -c "$file" | "${COMPOSE[@]}" exec -T db sh -c \
  'psql --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --set ON_ERROR_STOP=1 --quiet'
"${COMPOSE[@]}" start api worker
echo "Restored $(basename "$file")."
