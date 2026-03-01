#!/usr/bin/env bash
# test-lab-08-02.sh — Lab 08-02: External Dependencies
# Module 08: Jitsi — coturn TURN/STUN server, separate jitsi-net + turn-net
set -euo pipefail

LAB_ID="08-02"
LAB_NAME="External Dependencies"
MODULE="jitsi"
COMPOSE_FILE="docker/docker-compose.lan.yml"
PASS=0
FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting for coturn TURN server..."
timeout 30 bash -c 'until docker ps --filter name=jitsi-lan-coturn --filter status=running --format "{{.Names}}" | grep -q coturn; do sleep 2; done'
info "Waiting for Jitsi web (HTTPS :8443)..."
timeout 120 bash -c 'until curl -sk https://localhost:8443/ -o /dev/null -w "%{http_code}" | grep -E "^(200|301|302)$"; do sleep 5; done'

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

for c in jitsi-lan-coturn jitsi-lan-prosody jitsi-lan-jicofo jitsi-lan-jvb jitsi-lan-web; do
  if docker ps --filter "name=^/${c}$" --filter "status=running" --format '{{.Names}}' | grep -q "${c}"; then
    pass "Container ${c} is running"
  else
    fail "Container ${c} is not running"
  fi
done

if timeout 5 bash -c 'echo > /dev/tcp/localhost/3478' 2>/dev/null; then
  pass "TURN server: TCP port 3478 reachable"
else
  fail "TURN server: TCP port 3478 not reachable"
fi

HTTP_CODE=$(curl -sk http://localhost:8180/ -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
if echo "${HTTP_CODE}" | grep -qE '^(200|301|302)$'; then
  pass "Jitsi web HTTP :8180 → ${HTTP_CODE}"
else
  fail "Jitsi web HTTP :8180 → ${HTTP_CODE}"
fi

HTTPS_CODE=$(curl -sk https://localhost:8443/ -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
if echo "${HTTPS_CODE}" | grep -qE '^(200|301|302)$'; then
  pass "Jitsi web HTTPS :8443 → ${HTTPS_CODE}"
else
  fail "Jitsi web HTTPS :8443 → ${HTTPS_CODE}"
fi

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
info "Phase 3: Functional Tests (Lab 02 — External Dependencies)"

COTURN_LOG=$(docker logs jitsi-lan-coturn 2>&1 | tail -10 || echo "")
if echo "${COTURN_LOG}" | grep -qi "turnserver\|Coturn\|listening"; then
  pass "coturn: TURN server started and logging"
else
  warn "coturn: check logs manually"
fi

CERT_SUBJECT=$(echo | openssl s_client -connect localhost:8443 -servername localhost \
  2>/dev/null | openssl x509 -noout -subject 2>/dev/null | head -1 || echo "")
if [ -n "${CERT_SUBJECT}" ]; then
  pass "TLS cert: present (${CERT_SUBJECT})"
else
  warn "TLS cert: could not retrieve"
fi

CONFIG_JS=$(curl -sk https://localhost:8443/config.js 2>/dev/null || echo "")
if [ -n "${CONFIG_JS}" ]; then
  pass "config.js: served by Jitsi web"
else
  fail "config.js: not reachable"
fi

if echo "${CONFIG_JS}" | grep -q 'stunServers\|iceServers\|p2p'; then
  pass "config.js: STUN/ICE server config present"
else
  warn "config.js: STUN/ICE config not detected"
fi

# Key Lab 02 test: TURN config in config.js
if echo "${CONFIG_JS}" | grep -qiE 'turn|coturn|TurnCredentials'; then
  pass "config.js: TURN configuration present"
else
  warn "config.js: TURN config not found in config.js (may be injected at runtime)"
fi

if curl -sk https://localhost:8443/external_api.js | grep -q 'JitsiMeetExternalAPI\|external_api'; then
  pass "external_api.js: Jitsi Meet External API available"
else
  fail "external_api.js: not available"
fi

JVB_LOG=$(docker logs jitsi-lan-jvb 2>&1 | tail -20 || echo "")
if echo "${JVB_LOG}" | grep -qi "started\|running\|bridge"; then
  pass "JVB: started (log evidence)"
else
  warn "JVB: could not confirm start from log"
fi

# ── PHASE 4: Cleanup ──────────────────────────────────────────────────────────
info "Phase 4: Cleanup"
docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
info "Cleanup complete"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
  exit 1
fi