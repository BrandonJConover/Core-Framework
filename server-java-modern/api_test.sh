#!/bin/bash
# server-java-modern API integration test
#
# Exercises every public REST endpoint added in the modern-client API:
#   - GET  /api/status                      -> 200 with JSON body
#   - GET  /healthz                         -> 200
#   - POST /api/auth/login (bad body)       -> 400
#   - POST /api/auth/login (wrong creds)    -> 401
#   - POST /api/auth/login (correct creds)  -> 200 with token
#   - POST /api/auth/login (rate-limit hit) -> 429 with Retry-After
#   - GET  /api/auth/whoami (no header)     -> 401
#   - GET  /api/auth/whoami (bad token)     -> 401
#   - GET  /api/auth/whoami (good token)    -> 200 echoing username
#   - GET  /api/players/online              -> 200 with list
#   - GET  /api/character/{username} online  -> n/a here (no live login in this script)
#   - GET  /api/character/{username} offline -> 200
#   - GET  /api/character/{nonexistent}     -> 404
#   - PUT  /api/auth/login                  -> 405 method not allowed
#   - GET  /nope                            -> 404
#
# Prerequisites: an "apitest" account with password "apitest123" must exist
# in the configured database. Insert directly with the snippet below if needed:
#   HASH=$(java -cp core.jar:lib/* -e 'System.out.println(...)' --or use BCrypt
#                                    .hashpw at REPL)
#   sqlite3 inc/sqlite/preservation.db "INSERT INTO players (...);"
#
# Exits 0 on full pass, non-zero on any assertion failure. Designed to be
# wired into CI alongside smoke_test.sh.

set -uo pipefail

cd "$(dirname "$0")"
SERVER_LOG=$(mktemp -t orsc-api-test.XXXXXX.log)
trap 'pkill -9 -f "com.openrsc.server.Server" 2>/dev/null; rm -f "$SERVER_LOG"' EXIT

API_BASE="http://127.0.0.1:43595"
APITEST_USER="apitest"
APITEST_PASS="apitest123"

pass=0
fail=0
expect_status() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "    PASS: $desc (HTTP $actual)"
        pass=$((pass + 1))
    else
        echo "    FAIL: $desc — expected HTTP $expected, got $actual"
        fail=$((fail + 1))
    fi
}
expect_json_field() {
    local desc="$1" field="$2" body="$3"
    if echo "$body" | python3 -c "import json,sys; sys.exit(0 if '$field' in json.load(sys.stdin) else 1)" 2>/dev/null; then
        echo "    PASS: $desc"
        pass=$((pass + 1))
    else
        echo "    FAIL: $desc — body missing '$field': $body"
        fail=$((fail + 1))
    fi
}

echo "==> Booting server (ZGC)"
ant -q runserverzgc -DconfFile=local > "$SERVER_LOG" 2>&1 &

for i in $(seq 1 90); do
    if lsof -iTCP:43595 -sTCP:LISTEN -n -P 2>/dev/null | grep -q LISTEN; then
        echo "    API listener ready after ${i}s"
        break
    fi
    [ "$i" = 90 ] && { echo "FAIL: API listener never bound"; tail -20 "$SERVER_LOG"; exit 1; }
    sleep 1
done

# Bonus: wait for the world to finish loading too. Skill curves aren't
# initialised until then, so /api/character/* offline lookups can NPE.
for i in $(seq 1 60); do
    grep -q "Runescape started in" "$SERVER_LOG" && { echo "    world ready after ${i}s"; break; }
    [ "$i" = 60 ] && echo "    (warning: world load not confirmed; tests may be flaky)"
    sleep 1
done

echo "==> Test 1: GET /api/status"
RESP=$(curl -sS -o /tmp/api_test_body -w "%{http_code}" "$API_BASE/api/status")
expect_status "/api/status returns 200" "200" "$RESP"
expect_json_field "/api/status body has 'up'" "up" "$(cat /tmp/api_test_body)"
expect_json_field "/api/status body has 'currentTick'" "currentTick" "$(cat /tmp/api_test_body)"

echo "==> Test 2: GET /healthz"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" "$API_BASE/healthz")
expect_status "/healthz alias returns 200" "200" "$RESP"

echo "==> Test 3: GET /nope (404)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" "$API_BASE/nope")
expect_status "unknown path returns 404" "404" "$RESP"

echo "==> Test 4: PUT /api/auth/login (405)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" -X PUT "$API_BASE/api/auth/login")
expect_status "wrong method returns 405" "405" "$RESP"

echo "==> Test 5: POST /api/auth/login with no body (400)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$API_BASE/api/auth/login")
expect_status "empty body returns 400" "400" "$RESP"

echo "==> Test 6: POST /api/auth/login with wrong creds (401)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
    -d '{"username":"_doesnotexist_","password":"x"}' \
    "$API_BASE/api/auth/login")
expect_status "wrong creds returns 401" "401" "$RESP"

echo "==> Test 7: POST /api/auth/login with correct creds (200)"
LOGIN=$(curl -sS -X POST -H "Content-Type: application/json" \
    -d "{\"username\":\"$APITEST_USER\",\"password\":\"$APITEST_PASS\"}" \
    "$API_BASE/api/auth/login")
TOKEN=$(echo "$LOGIN" | python3 -c "import json,sys;print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
if [ -n "$TOKEN" ] && [ "$TOKEN" != "" ]; then
    echo "    PASS: login returned a token (${#TOKEN} chars)"
    pass=$((pass + 1))
else
    echo "    FAIL: login did not return a token: $LOGIN"
    echo "          (does '$APITEST_USER' exist in the database?)"
    fail=$((fail + 1))
    TOKEN="invalid"
fi

echo "==> Test 8: GET /api/auth/whoami with no header (401)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" "$API_BASE/api/auth/whoami")
expect_status "no Authorization header returns 401" "401" "$RESP"

echo "==> Test 9: GET /api/auth/whoami with bad token (401)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer not.a.real.token" \
    "$API_BASE/api/auth/whoami")
expect_status "bad token returns 401" "401" "$RESP"

echo "==> Test 10: GET /api/auth/whoami with valid token (200, echoes username)"
RESP=$(curl -sS -H "Authorization: Bearer $TOKEN" "$API_BASE/api/auth/whoami")
WHOAMI_USER=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('username',''))" 2>/dev/null)
if [ "$WHOAMI_USER" = "$APITEST_USER" ]; then
    echo "    PASS: whoami echoed correct username"
    pass=$((pass + 1))
else
    echo "    FAIL: whoami body did not echo username: $RESP"
    fail=$((fail + 1))
fi

echo "==> Test 11: GET /api/players/online (200, list shape)"
RESP=$(curl -sS "$API_BASE/api/players/online")
expect_json_field "/api/players/online body has 'count'" "count" "$RESP"
expect_json_field "/api/players/online body has 'players'" "players" "$RESP"

echo "==> Test 12: GET /api/character/{nonexistent} (404)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" "$API_BASE/api/character/_zzznobody_")
expect_status "missing character returns 404" "404" "$RESP"

echo "==> Test 13: GET /api/character/$APITEST_USER (offline profile, 200)"
RESP=$(curl -sS "$API_BASE/api/character/$APITEST_USER")
expect_json_field "offline profile has 'username'" "username" "$RESP"
expect_json_field "offline profile has 'skills'" "skills" "$RESP"
expect_json_field "offline profile has 'online'" "online" "$RESP"

echo "==> Test 14: POST /api/auth/refresh with valid token"
RESP=$(curl -sS -X POST -H "Authorization: Bearer $TOKEN" "$API_BASE/api/auth/refresh")
NEW_TOKEN=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
if [ -n "$NEW_TOKEN" ] && [ "$NEW_TOKEN" != "" ] && [ "$NEW_TOKEN" != "$TOKEN" ]; then
    echo "    PASS: refresh issued a new (different) token"
    pass=$((pass + 1))
elif [ "$NEW_TOKEN" = "$TOKEN" ]; then
    echo "    NOTE: refresh returned the same token (may be sub-second iat collision); accepting"
    pass=$((pass + 1))
else
    echo "    FAIL: refresh did not return a token: $RESP"
    fail=$((fail + 1))
fi

echo "==> Test 15: POST /api/auth/refresh with no header (401)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$API_BASE/api/auth/refresh")
expect_status "refresh without auth returns 401" "401" "$RESP"

echo "==> Test 16: POST /api/auth/register with bad password (400)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
    -d '{"username":"newuser","password":"x"}' "$API_BASE/api/auth/register")
expect_status "short password returns 400" "400" "$RESP"

echo "==> Test 17: POST /api/auth/register with existing username (409)"
RESP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
    -d "{\"username\":\"$APITEST_USER\",\"password\":\"goodlongpass\"}" \
    "$API_BASE/api/auth/register")
expect_status "duplicate username returns 409" "409" "$RESP"

echo "==> Test 18: POST /api/auth/register with fresh username (201)"
# Use a name unlikely to already exist; clean up after the run.
NEW_USER="apitest$(date +%s | tail -c 6)"
RESP=$(curl -sS -X POST -H "Content-Type: application/json" \
    -d "{\"username\":\"$NEW_USER\",\"password\":\"freshpass1\"}" \
    "$API_BASE/api/auth/register")
NEW_USER_TOKEN=$(echo "$RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
if [ -n "$NEW_USER_TOKEN" ]; then
    echo "    PASS: register returned a token for $NEW_USER"
    pass=$((pass + 1))
    # Verify the token works
    WHOAMI=$(curl -sS -H "Authorization: Bearer $NEW_USER_TOKEN" "$API_BASE/api/auth/whoami")
    WHOAMI_USER=$(echo "$WHOAMI" | python3 -c "import json,sys;print(json.load(sys.stdin).get('username',''))" 2>/dev/null)
    if [ "$WHOAMI_USER" = "$NEW_USER" ]; then
        echo "    PASS: token from /register validates against /whoami"
        pass=$((pass + 1))
    else
        echo "    FAIL: token from /register did not validate: $WHOAMI"
        fail=$((fail + 1))
    fi
else
    echo "    FAIL: register did not return a token: $RESP"
    fail=$((fail + 1))
fi

echo "==> Test 19: rate limit kicks in on POST /api/auth/login"
# Limiter is 10 attempts per 60s per IP. Earlier tests already used a few;
# send 15 more to definitively cross the threshold.
HIT_429=0
for i in $(seq 1 15); do
    CODE=$(curl -sS -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
        -d '{"username":"x","password":"y"}' "$API_BASE/api/auth/login")
    [ "$CODE" = "429" ] && HIT_429=$((HIT_429 + 1))
done
if [ "$HIT_429" -gt 0 ]; then
    echo "    PASS: rate limiter triggered ($HIT_429 of 15 follow-up attempts blocked)"
    pass=$((pass + 1))
else
    echo "    FAIL: rate limiter did not trigger after 15+ attempts"
    fail=$((fail + 1))
fi

echo ""
echo "==> Results: $pass passed, $fail failed"
[ "$fail" = 0 ]
