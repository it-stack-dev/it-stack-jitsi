#!/usr/bin/env bash
# test-lab-08-06.sh — Jitsi Lab 06: Production Deployment
# Module 08 | Lab 06 | Tests: resource limits, restart=always, volumes, JWT, metrics
set -euo pipefail

COMPOSE_FILE="$(dirname "$0")/../docker/docker-compose.production.yml"
CLEANUP=true
for arg in "$@"; do [[ "$arg" == "--no-cleanup" ]] && CLEANUP=false; done

KC_PORT=8207
WEB_PORT=8250
TRAEFIK_PORT=8280
TRAEFIK_DASH=8209
KC_ADMIN_PASS="Prod06Admin!"

PASS=0; FAIL=0
pass() { echo "[PASS] $1"; ((PASS++)) || true; }
fail() { echo "[FAIL] $1"; ((FAIL++)) || true; }
section() { echo ""; echo "=== $1 ==="; }

cleanup() {
  if [[ "$CLEANUP" == "true" ]]; then
    echo "Cleaning up..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
  fi
}
trap cleanup EXIT

section "Starting Lab 06 Production Deployment"
docker compose -f "$COMPOSE_FILE" up -d
echo "Waiting for services to initialize..."

section "Health Checks"
for i in $(seq 1 60); do
  status=$(docker inspect jitsi-prod-keycloak --format '{{.State.Health.Status}}' 2>/dev/null || echo "waiting")
  [[ "$status" == "healthy" ]] && break; sleep 5
done
[[ "$(docker inspect jitsi-prod-keycloak --format '{{.State.Health.Status}}')" == "healthy" ]] && pass "Keycloak healthy" || fail "Keycloak not healthy"

for i in $(seq 1 60); do
  status=$(docker inspect jitsi-prod-prosody --format '{{.State.Health.Status}}' 2>/dev/null || echo "waiting")
  [[ "$status" == "healthy" ]] && break; sleep 5
done
[[ "$(docker inspect jitsi-prod-prosody --format '{{.State.Health.Status}}')" == "healthy" ]] && pass "Prosody healthy" || fail "Prosody not healthy"

for i in $(seq 1 60); do
  status=$(docker inspect jitsi-prod-web --format '{{.State.Health.Status}}' 2>/dev/null || echo "waiting")
  [[ "$status" == "healthy" ]] && break; sleep 5
done
[[ "$(docker inspect jitsi-prod-web --format '{{.State.Health.Status}}')" == "healthy" ]] && pass "Jitsi web healthy" || fail "Jitsi web not healthy"

section "Production Configuration Checks"
# Restart policy
for ctr in jitsi-prod-keycloak jitsi-prod-web jitsi-prod-jvb jitsi-prod-prosody; do
  rp=$(docker inspect "$ctr" --format '{{.HostConfig.RestartPolicy.Name}}')
  [[ "$rp" == "always" ]] && pass "$ctr restart=always" || fail "$ctr restart policy is '$rp'"
done

# Resource limits
for ctr in jitsi-prod-keycloak jitsi-prod-web jitsi-prod-jvb; do
  mem=$(docker inspect "$ctr" --format '{{.HostConfig.Memory}}')
  [[ "$mem" -gt 0 ]] && pass "$ctr memory limit set ($mem bytes)" || fail "$ctr memory limit not set"
done

# Named volumes
for vol in jitsi-prod-prosody jitsi-prod-jicofo jitsi-prod-jvb jitsi-prod-web; do
  docker volume ls | grep -q "$vol" && pass "Volume $vol exists" || fail "Volume $vol missing"
done

section "Traefik Dashboard"
curl -sf "http://localhost:${TRAEFIK_DASH}/api/rawdata" | grep -q "routers" && pass "Traefik API returning router data" || fail "Traefik dashboard not responding"

section "Keycloak API & Metrics"
TOKEN=$(curl -sf -X POST "http://localhost:${KC_PORT}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli&grant_type=password&username=admin&password=${KC_ADMIN_PASS}" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
[[ -n "$TOKEN" ]] && pass "Keycloak admin token obtained" || fail "Keycloak admin token failed"

REALM_EXISTS=$(curl -sf -H "Authorization: Bearer $TOKEN" "http://localhost:${KC_PORT}/admin/realms" | grep -o '"realm":"it-stack"' | wc -l || echo 0)
if [[ "$REALM_EXISTS" -gt 0 ]]; then
  pass "Realm it-stack exists"
else
  curl -sf -X POST "http://localhost:${KC_PORT}/admin/realms" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"realm":"it-stack","enabled":true,"displayName":"IT-Stack Production"}'
  pass "Realm it-stack created"
fi

CLIENT_EXISTS=$(curl -sf -H "Authorization: Bearer $TOKEN" "http://localhost:${KC_PORT}/admin/realms/it-stack/clients?clientId=jitsi-client" | grep -o '"clientId":"jitsi-client"' | wc -l || echo 0)
if [[ "$CLIENT_EXISTS" -gt 0 ]]; then
  pass "OIDC client jitsi-client exists"
else
  curl -sf -X POST "http://localhost:${KC_PORT}/admin/realms/it-stack/clients" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"clientId":"jitsi-client","enabled":true,"protocol":"openid-connect","publicClient":true,"redirectUris":["http://localhost:'"${WEB_PORT}"'/*"]}'
  pass "OIDC client jitsi-client created"
fi

curl -sf "http://localhost:${KC_PORT}/metrics" | grep -q "keycloak" && pass "Keycloak /metrics endpoint returns data" || fail "Keycloak /metrics not responding"

section "Jitsi JWT Environment"
jwt_secret=$(docker inspect jitsi-prod-web --format '{{range .Config.Env}}{{println .}}{{end}}' | grep JWT_APP_SECRET | cut -d= -f2)
[[ "$jwt_secret" == "JitsiProd06!" ]] && pass "JWT_APP_SECRET set correctly" || fail "JWT_APP_SECRET not set (got: $jwt_secret)"

section "Jitsi Web UI"
curl -sf "http://localhost:${WEB_PORT}/" | grep -qi "jitsi" && pass "Jitsi web UI responding" || fail "Jitsi web UI not reachable"

section "Log Rotation Configuration"
log_driver=$(docker inspect jitsi-prod-web --format '{{.HostConfig.LogConfig.Type}}')
[[ "$log_driver" == "json-file" ]] && pass "Log driver is json-file" || fail "Log driver is '$log_driver'"

echo ""
echo "================================================"
echo "Lab 06 Results: ${PASS} passed, ${FAIL} failed"
echo "================================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1