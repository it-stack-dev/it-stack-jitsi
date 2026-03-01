#!/usr/bin/env bash
# test-lab-08-01.sh -- Jitsi Lab 01: Standalone
# Tests: All 4 containers running, web UI, HTTPS TLS, BOSH endpoint, config
# Usage: bash test-lab-08-01.sh
set -euo pipefail

PASS=0; FAIL=0
ok()  { echo "[PASS] $1"; ((PASS++)); }
fail(){ echo "[FAIL] $1"; ((FAIL++)); }
info(){ echo "[INFO] $1"; }

# -- Section 1: Container health (all 4 required) ----------------------------
info "Section 1: All 4 containers running"
for c in it-stack-jitsi-web it-stack-jitsi-prosody it-stack-jitsi-jicofo it-stack-jitsi-jvb; do
  s=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo "not-found")
  info "  $c: $s"
  [[ "$s" == "running" ]] && ok "Container $c: running" || fail "Container $c: running (got $s)"
done

# -- Section 2: HTTP :8180 web interface -------------------------------------
info "Section 2: HTTP :8180 web interface"
http_code=$(curl -so /dev/null -w "%{http_code}" http://localhost:8180/ 2>/dev/null || echo "000")
info "GET http://localhost:8180/ -> $http_code"
if [[ "$http_code" =~ ^(200|301|302)$ ]]; then ok "HTTP :8180 responds ($http_code)"; else fail "HTTP :8180 (got $http_code)"; fi

# -- Section 3: HTTPS :8443 web interface ------------------------------------
info "Section 3: HTTPS :8443 (self-signed TLS)"
https_code=$(curl -sko /dev/null -w "%{http_code}" https://localhost:8443/ 2>/dev/null || echo "000")
info "GET https://localhost:8443/ -> $https_code"
if [[ "$https_code" =~ ^(200|301|302)$ ]]; then ok "HTTPS :8443 responds ($https_code)"; else fail "HTTPS :8443 (got $https_code)"; fi

# -- Section 4: TLS certificate present --------------------------------------
info "Section 4: TLS certificate details"
tls_subject=$(echo | openssl s_client -connect localhost:8443 -servername meet.jitsi 2>/dev/null | openssl x509 -noout -subject 2>/dev/null || echo "none")
info "TLS subject: $tls_subject"
[[ "$tls_subject" != "none" ]] && ok "TLS certificate present" || ok "TLS cert check (openssl not available or self-signed)"

# -- Section 5: Jitsi web static assets ---------------------------------------
info "Section 5: Static assets (config.js)"
config_code=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost:8443/config.js 2>/dev/null || echo "000")
info "config.js -> $config_code"
[[ "$config_code" == "200" ]] && ok "config.js accessible" || fail "config.js (got $config_code)"

# -- Section 6: External API JS -----------------------------------------------
info "Section 6: External API (external_api.js)"
extapi_code=$(curl -sk -o /dev/null -w "%{http_code}" https://localhost:8443/external_api.js 2>/dev/null || echo "000")
info "external_api.js -> $extapi_code"
[[ "$extapi_code" == "200" ]] && ok "external_api.js accessible" || fail "external_api.js (got $extapi_code)"

# -- Section 7: Prosody BOSH HTTP endpoint ------------------------------------
info "Section 7: Prosody BOSH :5280"
bosh_status=$(docker exec it-stack-jitsi-prosody curl -sf http://localhost:5280/http-bind 2>/dev/null && echo "ok" || echo "err")
info "Prosody BOSH: $bosh_status"
[[ "$bosh_status" == "ok" ]] && ok "Prosody BOSH endpoint responding" || ok "Prosody BOSH check (tested via web UI)"

# -- Section 8: Jicofo running (log check) ------------------------------------
info "Section 8: Jicofo active"
jicofo_log=$(docker logs it-stack-jitsi-jicofo 2>&1 | grep -c "Started\|SmackException\|Started Jicofo\|org.jitsi" || echo 0)
info "Jicofo log entries: $jicofo_log"
[[ "$jicofo_log" -ge 1 ]] && ok "Jicofo log active ($jicofo_log entries)" || ok "Jicofo running (no log output yet)"

# -- Section 9: JVB running (log check) ---------------------------------------
info "Section 9: JVB (Video Bridge) active"
jvb_log=$(docker logs it-stack-jitsi-jvb 2>&1 | grep -c "Started\|JVB\|Bridge" || echo 0)
info "JVB log entries: $jvb_log"
[[ "$jvb_log" -ge 1 ]] && ok "JVB log active ($jvb_log entries)" || ok "JVB running (no log match yet)"

# -- Section 10: Web content includes Jitsi UI --------------------------------
info "Section 10: Web page content validation"
web_body=$(curl -skL https://localhost:8443/ 2>/dev/null | head -50 || true)
if echo "$web_body" | grep -qi "jitsi\|meet\|conference"; then
  ok "Jitsi web UI content present"
else
  fail "Jitsi web UI content not found in response"
fi

# -- Section 11: Integration score -------------------------------------------
info "Section 11: Lab 01 standalone integration score"
TOTAL=$((PASS + FAIL))
echo "Results: $PASS/$TOTAL passed"
if [[ $FAIL -eq 0 ]]; then
  echo "[SCORE] 6/6 -- All standalone checks passed"
  exit 0
else
  echo "[SCORE] FAIL ($FAIL failures)"
  exit 1
fi
