#!/usr/bin/env bash
# test-lab-08-04.sh — Lab 08-04: Jitsi SSO Integration
# Tests: Keycloak running, JWT token authority config, JWKS endpoint, Jitsi JWT auth
set -euo pipefail
COMPOSE_FILE="docker/docker-compose.sso.yml"
KC_PORT="8086"
PASS=0; FAIL=0
pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
section() { echo; echo "=== $1 ==="; }

section "Container health"
for c in jitsi-sso-keycloak jitsi-sso-coturn jitsi-sso-prosody jitsi-sso-jicofo jitsi-sso-jvb jitsi-sso-web; do
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

section "Keycloak health"
KC_HEALTH=$(curl -sf "http://localhost:${KC_PORT}/health/ready" 2>/dev/null) || KC_HEALTH=""
if echo "$KC_HEALTH" | grep -q "UP"; then
  pass "Keycloak health/ready = UP"
else
  fail "Keycloak health/ready not UP"
fi

section "Keycloak admin API + realm"
KC_TOKEN=$(curl -sf -X POST \
  "http://localhost:${KC_PORT}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli&username=admin&password=Lab04Admin!&grant_type=password" 2>/dev/null \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4) || KC_TOKEN=""
if [ -n "$KC_TOKEN" ]; then
  pass "Keycloak admin token obtained"
else
  fail "Keycloak admin login failed"
fi

if [ -n "$KC_TOKEN" ]; then
  curl -sf -X POST "http://localhost:${KC_PORT}/admin/realms" \
    -H "Authorization: Bearer $KC_TOKEN" -H "Content-Type: application/json" \
    -d '{"realm":"it-stack","enabled":true}' 2>/dev/null || true
  curl -sf -X POST "http://localhost:${KC_PORT}/admin/realms/it-stack/clients" \
    -H "Authorization: Bearer $KC_TOKEN" -H "Content-Type: application/json" \
    -d '{"clientId":"jitsi","enabled":true,"publicClient":false,"secret":"JitsiSSO04!","redirectUris":["https://localhost:8443/*"],"standardFlowEnabled":true}' \
    2>/dev/null || true
  CLIENTS=$(curl -sf "http://localhost:${KC_PORT}/admin/realms/it-stack/clients?clientId=jitsi" \
    -H "Authorization: Bearer $KC_TOKEN" 2>/dev/null) || CLIENTS=""
  if echo "$CLIENTS" | grep -q '"clientId":"jitsi"'; then
    pass "Keycloak OIDC client 'jitsi' configured"
  else
    fail "Keycloak OIDC client 'jitsi' not found"
  fi
else
  fail "Skipping client check (no admin token)"
fi

section "Keycloak JWKS endpoint (JWT token authority)"
JWKS=$(curl -sf "http://localhost:${KC_PORT}/realms/it-stack/protocol/openid-connect/certs" 2>/dev/null) || JWKS=""
if echo "$JWKS" | grep -q '"keys"'; then
  pass "Keycloak JWKS endpoint reachable (JWT authority)"
else
  fail "Keycloak JWKS endpoint not reachable"
fi

section "Jitsi prosody JWT config"
PROSODY_ENV=$(docker inspect jitsi-sso-prosody --format '{{json .Config.Env}}' 2>/dev/null) || PROSODY_ENV="[]"
if echo "$PROSODY_ENV" | grep -q '"AUTH_TYPE=jwt"'; then
  pass "AUTH_TYPE=jwt in prosody"
else
  fail "AUTH_TYPE=jwt not found in prosody env"
fi
if echo "$PROSODY_ENV" | grep -q "JWT_ASAP_KEYSERVER"; then
  pass "JWT_ASAP_KEYSERVER configured (Keycloak JWKS)"
else
  fail "JWT_ASAP_KEYSERVER not found in prosody env"
fi
if echo "$PROSODY_ENV" | grep -q '"JWT_ACCEPTED_ISSUERS=keycloak,localhost"'; then
  pass "JWT_ACCEPTED_ISSUERS includes keycloak"
else
  fail "JWT_ACCEPTED_ISSUERS not configured properly"
fi

section "Jitsi web JWT config"
WEB_ENV=$(docker inspect jitsi-sso-web --format '{{json .Config.Env}}' 2>/dev/null) || WEB_ENV="[]"
if echo "$WEB_ENV" | grep -q '"ENABLE_AUTH=1"'; then
  pass "ENABLE_AUTH=1 in jitsi-sso-web"
else
  fail "ENABLE_AUTH=1 not found in web env"
fi
if echo "$WEB_ENV" | grep -q "TOKEN_AUTH_URL"; then
  pass "TOKEN_AUTH_URL (Keycloak OIDC) configured in web"
else
  fail "TOKEN_AUTH_URL not configured in web env"
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

section "Keycloak OIDC discovery endpoint"
KC_OIDC=$(curl -sf "http://localhost:${KC_PORT}/realms/it-stack/.well-known/openid-configuration" 2>/dev/null) || KC_OIDC=""
if echo "$KC_OIDC" | grep -q '"jwks_uri"'; then
  pass "Keycloak OIDC discovery has jwks_uri"
else
  fail "Keycloak OIDC discovery failed"
fi

echo
echo "====================================="
echo "  Jitsi Lab 08-04 Results"
echo "  PASS: $PASS  FAIL: $FAIL"
echo "====================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1