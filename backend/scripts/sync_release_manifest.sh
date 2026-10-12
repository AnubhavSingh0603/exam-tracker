#!/usr/bin/env bash
# Pulls latest.json from the newest GitHub Release into releases/, where the API serves
# it at GET /api/v1/app/version. Runs from cron every 30 min (bootstrap_vm.sh).
#
#   GITHUB_REPO=owner/repo scripts/sync_release_manifest.sh
#   MIRROR_APKS=1 ...   also downloads the APKs into downloads/ and points the manifest
#                       at https://$DOMAIN/downloads/…, so updates work even where
#                       GitHub is slow or blocked.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

env_get() { grep -E "^$1=" .env 2>/dev/null | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
REPO="${GITHUB_REPO:-$(env_get GITHUB_REPO)}"
DOMAIN="${DOMAIN:-$(env_get DOMAIN)}"
MIRROR="${MIRROR_APKS:-$(env_get MIRROR_APKS)}"
[[ -n "$REPO" ]] || { echo "Set GITHUB_REPO=owner/repo in .env" >&2; exit 1; }

mkdir -p releases downloads
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL --retry 3 --max-time 60 -o "$tmp" \
  "https://github.com/$REPO/releases/latest/download/latest.json"

# Validate before replacing: a broken manifest must never reach phones.
python3 - "$tmp" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))
assert isinstance(m["version_code"], int) and m["version_code"] >= 1
assert "universal" in m["apks"]
for abi, a in m["apks"].items():
    assert a["url"].startswith("https://"), abi
    assert re.fullmatch(r"[0-9a-f]{64}", a["sha256"]), abi
PY

if cmp -s "$tmp" releases/latest.json 2>/dev/null && [[ "$MIRROR" != "1" ]]; then
  exit 0  # unchanged
fi

if [[ "$MIRROR" == "1" ]]; then
  [[ -n "$DOMAIN" ]] || { echo "MIRROR_APKS=1 needs DOMAIN in .env" >&2; exit 1; }
  python3 - "$tmp" "$DOMAIN" <<'PY'
import hashlib, json, os, sys, urllib.request
path, domain = sys.argv[1], sys.argv[2]
m = json.load(open(path))
for abi, a in m["apks"].items():
    name = os.path.basename(a["url"])
    dest = os.path.join("downloads", name)
    if not os.path.exists(dest):
        urllib.request.urlretrieve(a["url"], dest + ".part")
        digest = hashlib.sha256(open(dest + ".part", "rb").read()).hexdigest()
        if digest != a["sha256"]:
            os.remove(dest + ".part")
            sys.exit(f"checksum mismatch for {name}")
        os.replace(dest + ".part", dest)
    a["url"] = f"https://{domain}/downloads/{name}"
json.dump(m, open(path, "w"), indent=2)
PY
fi

install -m 644 "$tmp" releases/latest.json
echo "$(date -u +%FT%TZ) release manifest updated: $(python3 -c 'import json;m=json.load(open("releases/latest.json"));print(m["version_name"], "(", m["version_code"], ")")')"
