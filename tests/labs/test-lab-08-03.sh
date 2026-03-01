#!/usr/bin/env bash
# test-lab-08-03.sh — Lab 08-03: Jitsi Advanced Features
# Tests: JWT auth config, coturn, resource limits, HTTPS
set -euo pipefail
COMPOSE_FILE="docker/docker-compose.advanced.yml"
PASS=0; FAIL=0
pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
section() { echo; echo "=== $1 ==="; }

section "Container health"
for c in jitsi-adv-coturn jitsi-adv-prosody jitsi-adv-jicofo jitsi-adv-jvb jitsi-adv-web; do
  if docker inspect --format '{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
    pass "Container $c is running"
  else
    fail "Container $c is not running"
  fi
done

section "TURN server port"
if timeout 5 bash -c 'echo > /dev/tcp/localhost/3478' 2>/dev/null; then
  pass "TURN server :3478 reachable"
else
  fail "TURN server :3478 not reachable"
fi

section "Jitsi HTTPS endpoint"
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://localhost:8443/ 2>/dev/null) || HTTP_CODE="000"
if echo "$HTTP_CODE" | grep -qE "^(200|301|302)"; then
  pass "Jitsi HTTPS :8443 returned $HTTP_CODE"
else
  fail "Jitsi HTTPS :8443 returned $HTTP_CODE"
fi

section "External API JS"
EXTAPI=$(curl -skf https://localhost:8443/external_api.js 2>/dev/null | head -1) || EXTAPI=""
if [ -n "$EXTAPI" ]; then
  pass "external_api.js served"
else
  fail "external_api.js not available"
fi

section "JWT auth in web container env"
WEB_ENV=$(docker inspect jitsi-adv-web --format '{{json .Config.Env}}' 2>/dev/null) || WEB_ENV="[]"
if echo "$WEB_ENV" | grep -q '"ENABLE_AUTH=1"'; then
  pass "ENABLE_AUTH=1 set in jitsi-adv-web"
else
  fail "ENABLE_AUTH=1 not found in jitsi-adv-web env"
fi
if echo "$WEB_ENV" | grep -q '"AUTH_TYPE=jwt"'; then
  pass "AUTH_TYPE=jwt set in jitsi-adv-web"
else
  fail "AUTH_TYPE=jwt not found in jitsi-adv-web env"
fi
if echo "$WEB_ENV" | grep -q '"APP_ID=jitsi"'; then
  pass "APP_ID=jitsi set in jitsi-adv-web"
else
  fail "APP_ID=jitsi not found in jitsi-adv-web env"
fi
if echo "$WEB_ENV" | grep -q '"APP_SECRET=JitsiJWT03!"'; then
  pass "APP_SECRET=JitsiJWT03! set in jitsi-adv-web"
else
  fail "APP_SECRET not found in jitsi-adv-web env"
fi

section "JWT auth in prosody container env"
PROSODY_ENV=$(docker inspect jitsi-adv-prosody --format '{{json .Config.Env}}' 2>/dev/null) || PROSODY_ENV="[]"
if echo "$PROSODY_ENV" | grep -q '"AUTH_TYPE=jwt"'; then
  pass "AUTH_TYPE=jwt set in jitsi-adv-prosody"
else
  fail "AUTH_TYPE=jwt not found in jitsi-adv-prosody env"
fi
if echo "$PROSODY_ENV" | grep -q '"ENABLE_GUESTS=1"'; then
  pass "ENABLE_GUESTS=1 set in jitsi-adv-prosody"
else
  fail "ENABLE_GUESTS=1 not found in jitsi-adv-prosody env"
fi

section "Resource limits check"
WEB_MEM=$(docker inspect jitsi-adv-web --format '{{.HostConfig.Memory}}' 2>/dev/null) || WEB_MEM="0"
if [ "$WEB_MEM" = "536870912" ]; then
  pass "jitsi-adv-web memory limit = 512M (536870912 bytes)"
else
  fail "jitsi-adv-web memory limit: expected 536870912, got $WEB_MEM"
fi
JVB_MEM=$(docker inspect jitsi-adv-jvb --format '{{.HostConfig.Memory}}' 2>/dev/null) || JVB_MEM="0"
if [ "$JVB_MEM" = "536870912" ]; then
  pass "jitsi-adv-jvb memory limit = 512M (536870912 bytes)"
else
  fail "jitsi-adv-jvb memory limit: expected 536870912, got $JVB_MEM"
fi

section "JVB log check"
JVB_LOGS=$(docker logs jitsi-adv-jvb 2>&1 | tail -20) || JVB_LOGS=""
if echo "$JVB_LOGS" | grep -qi "error\|JVB registration failed"; then
  fail "JVB logs show error: $(echo "$JVB_LOGS" | grep -i error | head -2)"
else
  pass "JVB logs show no critical errors"
fi

section "TURN credentials in web config"
if echo "$WEB_ENV" | grep -q "TURN_CREDENTIALS"; then
  pass "TURN_CREDENTIALS configured in web container"
else
  fail "TURN_CREDENTIALS not found in web container env"
fi

echo
echo "====================================="
echo "  Jitsi Lab 08-03 Results"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "====================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1