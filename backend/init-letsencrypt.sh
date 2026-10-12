#!/usr/bin/env bash
# One-time TLS bootstrap for docker-compose.prod.yml.
#
# Chicken-and-egg: nginx won't start without a certificate, and Let's Encrypt needs
# nginx running to answer the HTTP-01 challenge. So we:
#   1. create a throw-away self-signed cert,  2. start the stack,
#   3. delete it and request the real one via webroot,  4. reload nginx.
# Afterwards the certbot container renews automatically.
#
# Usage:  ./init-letsencrypt.sh            (reads DOMAIN, LETSENCRYPT_EMAIL from .env)
#         LETSENCRYPT_STAGING=1 ./init-letsencrypt.sh   # test run, avoids rate limits
#         FORCE=1 ./init-letsencrypt.sh                 # replace an existing certificate
set -Eeuo pipefail
cd "$(dirname "$0")"

COMPOSE=(docker compose -f docker-compose.prod.yml)

env_get() {  # read KEY from .env without sourcing it (values may contain spaces/parens)
  grep -E "^$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

DOMAIN="${DOMAIN:-$(env_get DOMAIN)}"
EMAIL="${LETSENCRYPT_EMAIL:-$(env_get LETSENCRYPT_EMAIL)}"
STAGING="${LETSENCRYPT_STAGING:-$(env_get LETSENCRYPT_STAGING)}"
STAGING="${STAGING:-0}"
FORCE="${FORCE:-0}"
DATA=./certbot

[[ -n "$DOMAIN" ]] || { echo "DOMAIN is not set in .env" >&2; exit 1; }
[[ -n "$EMAIL" ]] || { echo "LETSENCRYPT_EMAIL is not set in .env (needed for expiry notices)" >&2; exit 1; }
[[ -f .env ]] || { echo "Missing .env (copy .env.example)" >&2; exit 1; }

if [[ -d "$DATA/conf/live/$DOMAIN" && "$FORCE" != "1" ]]; then
  echo "Certificate for $DOMAIN already exists. Starting the stack (FORCE=1 to replace)."
  "${COMPOSE[@]}" up -d
  exit 0
fi

# Sanity check: DNS must point at this machine or the challenge will fail.
public_ip="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
resolved="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)"
if [[ -n "$public_ip" && -n "$resolved" && "$public_ip" != "$resolved" ]]; then
  echo "WARNING: $DOMAIN resolves to $resolved but this VM's public IP is $public_ip." >&2
  echo "         Fix the DNS A record first, or the challenge will fail." >&2
fi

mkdir -p "$DATA/conf/live/$DOMAIN" "$DATA/www" releases downloads secrets

echo "==> Creating temporary self-signed certificate"
"${COMPOSE[@]}" run --rm --no-deps --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout /etc/letsencrypt/live/$DOMAIN/privkey.pem \
    -out /etc/letsencrypt/live/$DOMAIN/fullchain.pem \
    -subj /CN=localhost" certbot

echo "==> Building and starting the stack"
"${COMPOSE[@]}" up -d --build

echo "==> Removing temporary certificate"
"${COMPOSE[@]}" run --rm --no-deps --entrypoint "\
  rm -rf /etc/letsencrypt/live/$DOMAIN /etc/letsencrypt/archive/$DOMAIN \
         /etc/letsencrypt/renewal/$DOMAIN.conf" certbot

echo "==> Requesting Let's Encrypt certificate for $DOMAIN"
extra_args=()
[[ "$STAGING" == "1" ]] && extra_args+=(--staging)
[[ "$FORCE" == "1" ]] && extra_args+=(--force-renewal)
"${COMPOSE[@]}" run --rm --no-deps --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email \
    --key-type ecdsa --non-interactive ${extra_args[*]:-}" certbot

echo "==> Reloading nginx"
"${COMPOSE[@]}" exec nginx nginx -s reload

echo "Done: https://$DOMAIN/healthz"
