#!/usr/bin/env bash
# test-lab-08-05.sh -- Lab 05: Jitsi Advanced Integration
# Tests: Traefik routing, Keycloak JWT realm+client, JWKS endpoint, TURN server, web UI
#
# Usage: bash tests/labs/test-lab-08-05.sh [--no-cleanup]
set -euo pipefail

COMPOSE_FILE="docker/docker-compose.integration.yml"
KC_PORT=8107
WEB_PORT=8150
TRAEFIK_PORT=8180
TRAEFIK_DASH=8109
CLEANUP=true
[[ "${1:-}" == "--no-cleanup" ]] && CLEANUP=false

PASS=0; FAIL=0
pass() { echo "[PASS] $1"; ((PASS++)); }
fail() { echo "[FAIL] $1"; ((FAIL++)); }
section() { echo ""; echo "=== $1 ==="; }
cleanup() { $CLEANUP && docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true; }
trap cleanup EXIT

section "Lab 08-05: Jitsi Advanced Integration"
echo "Compose file: $COMPOSE_FILE"

section "1. Start Containers"
docker compose -f "$COMPOSE_FILE" up -d
echo "Waiting for services to initialize..."
sleep 30

section "2. Keycloak Health"
for i in $(seq 1 24); do
  if curl -sf "http://localhost:${KC_PORT}/health/ready" | grep -q "UP"; then
    pass "Keycloak health/ready UP"
    break
  fi
  [[ $i -eq 24 ]] && fail "Keycloak did not become healthy" && exit 1
  sleep 10
done

section "3. Traefik Health"
for i in $(seq 1 12); do
  if curl -sf "http://localhost:${TRAEFIK_DASH}/api/rawdata" >/dev/null 2>&1; then
    pass "Traefik dashboard /api/rawdata responds"
    break
  fi
  [[ $i -eq 12 ]] && fail "Traefik dashboard did not become available"
  sleep 5
done

# Traefik HTTP entrypoint
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${TRAEFIK_PORT}/" 2>/dev/null || echo "000")
[[ "$HTTP" =~ ^(200|301|404)$ ]] \
  && pass "Traefik HTTP entrypoint responds (HTTP $HTTP)" \
  || fail "Traefik HTTP entrypoint unreachable (HTTP $HTTP)"

section "4. Keycloak Realm + Client (jitsi)"
KC_TOKEN=$(curl -sf "http://localhost:${KC_PORT}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli&grant_type=password&username=admin&password=Lab05Admin!" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[[ -n "$KC_TOKEN" ]] && pass "Keycloak admin token obtained" || { fail "Keycloak admin token failed"; exit 1; }

HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "http://localhost:${KC_PORT}/admin/realms" \
  -H "Authorization: Bearer $KC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"realm":"it-stack","enabled":true}')
[[ "$HTTP" =~ ^(201|409)$ ]] && pass "Realm it-stack created (HTTP $HTTP)" || fail "Realm creation failed (HTTP $HTTP)"

CLIENT_PAYLOAD='{"clientId":"jitsi","enabled":true,"protocol":"openid-connect","publicClient":false,"redirectUris":["http://localhost:'"${WEB_PORT}"'/*"],"secret":"JitsiSSO05!"}'
HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "http://localhost:${KC_PORT}/admin/realms/it-stack/clients" \
  -H "Authorization: Bearer $KC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CLIENT_PAYLOAD")
[[ "$HTTP" =~ ^(201|409)$ ]] && pass "OIDC client jitsi created (HTTP $HTTP)" || fail "Client creation failed (HTTP $HTTP)"

section "5. Keycloak JWKS Endpoint"
if curl -sf "http://localhost:${KC_PORT}/realms/it-stack/protocol/openid-connect/certs" \
   | grep -q '"keys"'; then
  pass "Keycloak JWKS endpoint returns keys"
else
  fail "Keycloak JWKS endpoint unavailable or malformed"
fi

section "6. Jitsi Web Health"
for i in $(seq 1 12); do
  if curl -sf "http://localhost:${WEB_PORT}/" | grep -q -i "jitsi\|html"; then
    pass "Jitsi Web UI accessible (port $WEB_PORT)"
    break
  fi
  [[ $i -eq 12 ]] && fail "Jitsi Web did not become accessible"
  sleep 15
done

section "7. Prosody JWT Environment"
PROSODY_ENV=$(docker inspect jitsi-int-prosody --format '{{range .Config.Env}}{{.}} {{end}}')

echo "$PROSODY_ENV" | grep -q "JWT_ASAP_KEYSERVER=http://jitsi-int-keycloak:8080" \
  && pass "JWT_ASAP_KEYSERVER points to Keycloak JWKS" \
  || fail "JWT_ASAP_KEYSERVER not configured"

echo "$PROSODY_ENV" | grep -q "JWT_ACCEPTED_ISSUERS=keycloak,localhost" \
  && pass "JWT_ACCEPTED_ISSUERS=keycloak,localhost" \
  || fail "JWT_ACCEPTED_ISSUERS missing"

echo "$PROSODY_ENV" | grep -q "AUTH_TYPE=jwt" \
  && pass "AUTH_TYPE=jwt in prosody env" \
  || fail "AUTH_TYPE missing in prosody"

section "8. Web Container Integration Environment"
WEB_ENV=$(docker inspect jitsi-int-web --format '{{range .Config.Env}}{{.}} {{end}}')

echo "$WEB_ENV" | grep -q "TOKEN_AUTH_URL=http://jitsi-int-keycloak:8080" \
  && pass "TOKEN_AUTH_URL points to Keycloak" \
  || fail "TOKEN_AUTH_URL not configured"

echo "$WEB_ENV" | grep -q "TURN_HOST=jitsi-int-coturn" \
  && pass "TURN_HOST=jitsi-int-coturn" \
  || fail "TURN_HOST not configured"

section "9. Traefik Route for Jitsi"
ROUTES=$(curl -sf "http://localhost:${TRAEFIK_DASH}/api/http/routers" 2>/dev/null || echo "{}")
echo "$ROUTES" | grep -q "jitsi-int" \
  && pass "Traefik router jitsi-int registered" \
  || fail "Traefik router jitsi-int not found"

section "Summary"
echo "Passed: $PASS | Failed: $FAIL"
[[ $FAIL -eq 0 ]] && echo "Lab 08-05 PASSED" || { echo "Lab 08-05 FAILED"; exit 1; }