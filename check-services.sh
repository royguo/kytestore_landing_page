#!/bin/bash
# Self-check for KyteStore: systemd units, ports, HTTP(S) probes.
# Usage: ./check-services.sh [--quick]
#   --quick  Skip external HTTPS check (no DNS/curl to kytestore.com).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${KYTESTORE_DOMAIN:-kytestore.com}"
QUICK=0
FAILURES=0

while [ "${1:-}" = "--quick" ]; do
    QUICK=1
    shift
done

bail() {
    echo "[FAIL] $*"
    FAILURES=$((FAILURES + 1))
}

ok() {
    echo "[ OK ] $*"
}

warn() {
    echo "[WARN] $*"
}

echo "=== KyteStore service check ($(date -Is)) ==="
echo "Domain: $DOMAIN (override with KYTESTORE_DOMAIN=...)"
echo

echo "--- systemd ---"
for u in kytestore-backend caddy; do
    if systemctl cat "$u" >/dev/null 2>&1; then
        if systemctl is-active --quiet "$u" 2>/dev/null; then
            ok "unit $u is active"
        else
            bail "unit $u is not active (try: systemctl start $u)"
        fi
        if systemctl is-enabled --quiet "$u" 2>/dev/null; then
            ok "unit $u is enabled"
        else
            warn "unit $u is not enabled (will not start on boot)"
        fi
    else
        if [ "$u" = "kytestore-backend" ]; then
            warn "unit $u not installed (optional; service.sh may use legacy Python)"
        else
            bail "unit $u not installed"
        fi
    fi
done
echo

echo "--- listeners (80 / 443 / 9080) ---"
if ss -tln 2>/dev/null | grep -qE ':80[[:space:]]'; then
    ok "something is listening on TCP 80"
else
    bail "nothing listening on TCP 80 (Caddy?)"
fi
if ss -tln 2>/dev/null | grep -qE ':443[[:space:]]'; then
    ok "something is listening on TCP 443"
else
    bail "nothing listening on TCP 443 (Caddy?)"
fi
if ss -tln 2>/dev/null | grep -qE ':9080[[:space:]]'; then
    ok "something is listening on TCP 9080"
else
    bail "nothing listening on TCP 9080 (Python backend?)"
fi
ss -tlnp 2>/dev/null | grep -E '(:80|:443|:9080)\b' || true
echo

echo "--- local probes ---"
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:9080/" 2>/dev/null || echo "err")
if [ "$code" = "200" ]; then
    ok "curl http://127.0.0.1:9080/ -> $code"
else
    bail "curl http://127.0.0.1:9080/ -> $code"
fi

code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1/" 2>/dev/null || echo "err")
if [ "$code" = "308" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
    ok "curl http://127.0.0.1/ -> $code (redirect to HTTPS is expected)"
elif [ "$code" = "200" ]; then
    warn "curl http://127.0.0.1/ -> 200 (unexpected if HTTPS redirect is on)"
else
    bail "curl http://127.0.0.1/ -> $code"
fi
echo

if [ "$QUICK" -eq 1 ]; then
    echo "--- external HTTPS (skipped: --quick) ---"
else
    echo "--- DNS / HTTPS ($DOMAIN) ---"
    if command -v getent >/dev/null 2>&1; then
        ip="$(getent hosts "$DOMAIN" | awk '{ print $1; exit }' || true)"
        if [ -n "${ip:-}" ]; then
            ok "DNS $DOMAIN -> $ip"
        else
            warn "could not resolve $DOMAIN (getent)"
        fi
    fi
    pub="$(curl -sS --max-time 3 ifconfig.me 2>/dev/null || curl -sS --max-time 3 icanhazip.com 2>/dev/null || true)"
    if [ -n "${pub:-}" ]; then
        echo "    This host public IP (reference): $pub"
    fi
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "https://$DOMAIN/" 2>/dev/null || echo "err")
    if [ "$code" = "200" ]; then
        ok "curl https://$DOMAIN/ -> $code"
    else
        bail "curl https://$DOMAIN/ -> $code (firewall/DNS/backend?)"
    fi
fi
echo

echo "--- recent log (last 3 lines) ---"
if [ -f "$SCRIPT_DIR/server.log" ]; then
    tail -3 "$SCRIPT_DIR/server.log" | sed 's/^/  /'
else
    echo "  (no $SCRIPT_DIR/server.log)"
fi
echo

if [ "$FAILURES" -eq 0 ]; then
    echo "=== Summary: all critical checks passed ==="
    exit 0
fi

echo "=== Summary: $FAILURES critical check(s) failed ==="
exit 1
