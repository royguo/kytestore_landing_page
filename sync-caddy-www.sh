#!/bin/bash
# Optional: only if Caddy uses file_server to /var/www/kytestore. With reverse_proxy
# + Python (service.sh start), edits under SCRIPT_DIR are served live; this script is unused.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="/var/www/kytestore"
mkdir -p "$DST/assets"
cp -a "$SRC/index.html" "$DST/"
cp -a "$SRC/assets/"* "$DST/assets/"
chown -R caddy:caddy "$DST"
