#!/usr/bin/env bash
# Smoke-test a jkr-server image exactly the way the Helm chart runs it:
# non-root, read-only root filesystem, tmpfs /tmp, all capabilities dropped, one volume at
# /data, `-k _`. Publishes NO host ports, so it cannot collide with anything on the machine.
#
# Used by CI (deploy-int.yml) BEFORE the image is pushed to ECR, so a broken image never
# gets an immutable tag. Also runnable locally (Linux/macOS/Git-Bash):
#     scripts/smoke-test-server-image.sh [IMAGE]            default IMAGE=jkr-server:dev
# Windows Git-Bash only:  MSYS_NO_PATHCONV=1 scripts/smoke-test-server-image.sh
#
# EXPECT_PATCHED=0 skips the "no phone-home" assertion (for images built with
# --build-arg DISABLE_UPDATE_CHECK=0).
set -uo pipefail

IMAGE="${1:-jkr-server:dev}"
EXPECT_PATCHED="${EXPECT_PATCHED:-1}"
RUN="jkr-smoke-$$"
fail=0

pass() { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else bad "$name"; fi; }
section() { printf '\n== %s ==\n' "$1"; }

cleanup() {
  docker rm -f "$RUN-hbbs" "$RUN-hbbr" "$RUN-hbbs-b" "$RUN-hbbr-b" "$RUN-hbbs-c" >/dev/null 2>&1 || true
  docker volume rm -f "$RUN-a" "$RUN-b" "$RUN-c" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Same security posture as helm/jkr-server/templates/deployment.yaml
HARDEN=(--read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges --user 10001:10001)

# wait_log <container> <ERE> <timeout-seconds>
wait_log() {
  local c="$1" re="$2" t="$3" i
  for ((i = 0; i < t; i++)); do
    docker logs "$c" 2>&1 | grep -Eq "$re" && return 0
    [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ] || return 1
    sleep 1
  done
  return 1
}
running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
pubkey()  { docker run --rm -v "$1:/data" --entrypoint cat "$IMAGE" /data/id_ed25519.pub 2>/dev/null | tr -d '\r\n'; }

# The commands below mirror helm/jkr-server/templates/deployment.yaml. KEEP THEM IN SYNC:
# this test is only meaningful if it runs what the chart runs.
#
# hbbs_cmd <rendezvous-port> <relay-port>
hbbs_cmd() {
  cat <<EOF
set -eu
getent ahosts "\${RELAY_HOST}" >/dev/null || { echo "FATAL: RELAY_HOST '\${RELAY_HOST}' does not resolve from inside this pod; refusing to start with the relay disabled" >&2; exit 1; }
exec hbbs -p $1 -r "\${RELAY_HOST}:$2" -k _
EOF
}

# start_pair <vol> <suffix> <rendezvous-port> <relay-port> <relay-host>
start_pair() {
  local vol="$1" sfx="$2" r="$3" rl="$4" host="$5"
  docker run -d --name "$RUN-hbbs$sfx" "${HARDEN[@]}" -v "$vol:/data" -e "RELAY_HOST=$host" \
    "$IMAGE" /bin/sh -c "$(hbbs_cmd "$r" "$rl")" >/dev/null
  docker run -d --name "$RUN-hbbr$sfx" "${HARDEN[@]}" -v "$vol:/data" \
    "$IMAGE" /bin/sh -c "set -eu; until [ -s /data/id_ed25519 ]; do sleep 1; done; exec hbbr -p $rl -k _" >/dev/null
}

# A relay host that must resolve for hbbs to keep it (IP literal => no DNS needed here).
RELAY_OK="127.0.0.1"

printf 'Image under test: %s\n' "$IMAGE"
docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "image not found: $IMAGE"; exit 2; }

section "1. image: platform, user"
check "linux/amd64 (matches the node)" test "$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$IMAGE")" = "linux/amd64"
check "runs as uid 10001" test "$(docker run --rm --entrypoint id "$IMAGE" -u | tr -d '\r\n')" = "10001"

section "2. shared libraries resolve"
for b in hbbs hbbr rustdesk-utils; do
  out="$(docker run --rm --entrypoint sh "$IMAGE" -c "ldd /usr/local/bin/$b 2>&1" || true)"
  if printf '%s' "$out" | grep -q 'not found'; then bad "$b has missing libraries"; else pass "$b: no missing libraries"; fi
done

section "3. privacy: no phone-home in hbbs"
# Control first, so a grep that silently can't read the binary can't fake a pass.
check "control: grep can read the binary (finds 'Listening on tcp')" \
  docker run --rm --entrypoint sh "$IMAGE" -c "grep -q 'Listening on tcp' /usr/local/bin/hbbs"
if [ "$EXPECT_PATCHED" = "1" ]; then
  check "hbbs contains no api.rustdesk.com" \
    docker run --rm --entrypoint sh "$IMAGE" -c "! grep -q 'api.rustdesk.com' /usr/local/bin/hbbs"
else
  echo "  SKIP  phone-home assertion (EXPECT_PATCHED=0)"
fi

section "4. standard ports (prod block 21115-21119), read-only fs, non-root, -k _"
docker volume create "$RUN-a" >/dev/null
start_pair "$RUN-a" "" 21116 21117 "$RELAY_OK"
check "hbbs started (log: Start)"        wait_log "$RUN-hbbs" 'INFO .*Start$' 40
logs="$(docker logs "$RUN-hbbs" 2>&1)"
check "hbbs listens tcp/udp 21116"       grep -Eq 'Listening on tcp/udp [^ ]*:21116' <<<"$logs"
check "hbbs listens tcp 21115 (NAT test)" grep -Eq 'Listening on tcp [^ ]*:21115' <<<"$logs"
check "hbbs listens websocket 21118"     grep -Eq 'Listening on websocket [^ ]*:21118' <<<"$logs"
check "hbbs advertises the relay ($RELAY_OK:21117) to clients" grep -Fq "relay-servers=[\"$RELAY_OK:21117\"]" <<<"$logs"
check "hbbs generated a key"             grep -q 'Key: ' <<<"$logs"
check "hbbs still running"               running "$RUN-hbbs"
mode="$(docker run --rm -v "$RUN-a:/data" --entrypoint stat "$IMAGE" -c '%a %u' /data/id_ed25519 2>/dev/null | tr -d '\r\n')"
check "private key is mode 600, owner 10001 (got '$mode')" test "$mode" = "600 10001"
check "hbbr started and listens on 21117" wait_log "$RUN-hbbr" 'Listening on tcp :21117' 40
check "hbbr listens websocket 21119"     bash -c "docker logs $RUN-hbbr 2>&1 | grep -q 'Listening on websocket :21119'"
check "hbbr still running"               running "$RUN-hbbr"
key1="$(pubkey "$RUN-a")"
check "public key present" test -n "$key1"
printf '        public key: %s\n' "$key1"

section "5. persistence: restart keeps the SAME key"
docker restart "$RUN-hbbs" >/dev/null
check "hbbs restarted and loaded the key from disk" wait_log "$RUN-hbbs" 'Private key comes from' 40
check "public key unchanged after restart" test "$(pubkey "$RUN-a")" = "$key1"

section "6. shifted block (int: 22115-22119) - must work next to prod on one node"
docker volume create "$RUN-b" >/dev/null
start_pair "$RUN-b" "-b" 22116 22117 "$RELAY_OK"
check "int hbbs started" wait_log "$RUN-hbbs-b" 'INFO .*Start$' 40
logsb="$(docker logs "$RUN-hbbs-b" 2>&1)"
check "int hbbs listens tcp/udp 22116"   grep -Eq 'Listening on tcp/udp [^ ]*:22116' <<<"$logsb"
check "int hbbs listens tcp 22115 (NAT)" grep -Eq 'Listening on tcp [^ ]*:22115' <<<"$logsb"
check "int hbbs listens websocket 22118" grep -Eq 'Listening on websocket [^ ]*:22118' <<<"$logsb"
check "int hbbs advertises the relay ($RELAY_OK:22117)" grep -Fq "relay-servers=[\"$RELAY_OK:22117\"]" <<<"$logsb"
check "int hbbr listens 22117"           wait_log "$RUN-hbbr-b" 'Listening on tcp :22117' 40
check "int hbbr listens websocket 22119" bash -c "docker logs $RUN-hbbr-b 2>&1 | grep -q 'Listening on websocket :22119'"
check "int key differs from prod key (independent volumes)" test "$(pubkey "$RUN-b")" != "$key1"

section "7. a wrong RELAY_HOST must fail fast, not run with the relay silently disabled"
# Evidence for why this guard exists: hbbs drops an unresolvable -r host and carries on.
docker volume create "$RUN-c" >/dev/null
docker run -d --name "$RUN-hbbs-c" "${HARDEN[@]}" -v "$RUN-c:/data" -e "RELAY_HOST=does-not-resolve.invalid" \
  "$IMAGE" /bin/sh -c "$(hbbs_cmd 21116 21117)" >/dev/null
rc="$(timeout 40 docker wait "$RUN-hbbs-c" 2>/dev/null | tr -d '\r\n')"
check "container exited with status 1 (got '${rc:-timeout}')" test "${rc:-}" = "1"
check "log explains why (FATAL: RELAY_HOST ... does not resolve)" bash -c "docker logs $RUN-hbbs-c 2>&1 | grep -q 'FATAL: RELAY_HOST'"
check "hbbs never started listening" bash -c "! docker logs $RUN-hbbs-c 2>&1 | grep -q 'Listening on'"
docker volume rm -f "$RUN-c" >/dev/null 2>&1 || true
docker rm -f "$RUN-hbbs-c" >/dev/null 2>&1 || true

printf '\n'
if [ "$fail" -eq 0 ]; then echo "ALL SMOKE TESTS PASSED"; else echo "$fail CHECK(S) FAILED"; fi
exit "$fail"
