#!/usr/bin/env bash
# One-time VM preparation for Ubuntu 22.04/24.04 on OCI (Ampere A1 arm64 or AMD x86_64).
# Idempotent: safe to re-run.
#
#   sudo APP_DIR=/opt/exam-tracker/backend scripts/bootstrap_vm.sh
#
# Does: Docker Engine + Compose plugin, opens 80/443 in the host firewall, a swap file
# on small shapes, unattended security upgrades, and the cron jobs (backup + release sync).
# Docker's own service is enabled at boot, and every container has
# `restart: unless-stopped`, so the stack comes back on its own after a reboot.
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
APP_DIR="${APP_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DEPLOY_USER="${SUDO_USER:-ubuntu}"

echo "==> Base packages"
apt-get update -y
apt-get install -y ca-certificates curl gnupg cron unattended-upgrades iptables-persistent python3

echo "==> Docker Engine (official apt repository)"
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
usermod -aG docker "$DEPLOY_USER"

echo "==> Host firewall: OCI's Ubuntu images REJECT everything but SSH by default"
for port in 80 443; do
  if ! iptables -C INPUT -p tcp --dport "$port" -m state --state NEW -j ACCEPT 2>/dev/null; then
    # Insert before OCI's catch-all REJECT rule.
    iptables -I INPUT 5 -p tcp --dport "$port" -m state --state NEW -j ACCEPT
  fi
done
netfilter-persistent save
echo "    Also add ingress rules for TCP 80 and 443 to the subnet's Security List in the OCI console."

echo "==> Swap (helps the 1 GB AMD micro shape during docker builds)"
mem_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
if (( mem_mb < 4096 )) && ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Unattended security upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Directories"
install -d -m 700 -o "$DEPLOY_USER" /var/backups/exam-tracker
install -d -m 700 -o "$DEPLOY_USER" "$APP_DIR/secrets"
install -d -m 755 -o "$DEPLOY_USER" "$APP_DIR/releases" "$APP_DIR/downloads"
touch /var/log/exam-tracker-backup.log /var/log/exam-tracker-release.log
chown "$DEPLOY_USER" /var/log/exam-tracker-backup.log /var/log/exam-tracker-release.log
chmod +x "$APP_DIR"/init-letsencrypt.sh "$APP_DIR"/scripts/*.sh

echo "==> Cron jobs for $DEPLOY_USER"
cron_file="/etc/cron.d/exam-tracker"
cat > "$cron_file" <<CRON
# Managed by bootstrap_vm.sh
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
17 2 * * *  $DEPLOY_USER  $APP_DIR/scripts/backup_db.sh >> /var/log/exam-tracker-backup.log 2>&1
*/30 * * * * $DEPLOY_USER $APP_DIR/scripts/sync_release_manifest.sh >> /var/log/exam-tracker-release.log 2>&1
CRON
chmod 644 "$cron_file"

cat <<DONE

Bootstrap complete. Next steps (as $DEPLOY_USER, after logging out and back in for the docker group):
  cd $APP_DIR
  cp .env.example .env && nano .env        # DOMAIN, LETSENCRYPT_EMAIL, secrets…
  cp ~/firebase-service-account.json secrets/ && chmod 600 secrets/*.json   # optional (push)
  ./init-letsencrypt.sh                    # certificate + full stack
DONE
