#!/usr/bin/env bash
# OFFLINE verification of helm/jkr-server. Never contacts a cluster.
#   * helm lint --strict + helm template for int and prod
#   * the guard rails MUST reject bad input (and for the right reason)
#   * int and prod can share one node: no host port is used by both
#   * strict schema validation of the rendered manifests (kubeconform)
# Used by CI (ci.yml) and locally:  bash scripts/helm-verify.sh      (Windows: scripts\helm-verify.ps1)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

CHART=helm/jkr-server
OUT=helm-rendered
KUBECONFORM_IMAGE="ghcr.io/yannh/kubeconform:v0.6.7"
K8S_SCHEMA_VERSION="1.30.0" # schema set used for validation; not the cluster version
fail=0
pass() { printf '  PASS  %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

rm -rf "$OUT"; mkdir -p "$OUT"
COMMON=(--set image.repository=123456789012.dkr.ecr.us-east-1.amazonaws.com/jkr-server
        --set image.tag=0123456789ab --set-string relayHost=relay.example.com)

echo "== $(helm version --short) =="
for env in int prod; do
  echo "== lint + render: $env =="
  if helm lint "$CHART" -f "$CHART/values-$env.yaml" "${COMMON[@]}" --strict >"$OUT/lint-$env.log" 2>&1; then
    pass "helm lint --strict ($env)"
  else cat "$OUT/lint-$env.log"; bad "helm lint --strict ($env)"; fi
  if helm template jkr-server "$CHART" -n "jkr-$env" -f "$CHART/values-$env.yaml" "${COMMON[@]}" >"$OUT/$env.yaml" 2>"$OUT/template-$env.err"; then
    pass "helm template ($env)"
  else cat "$OUT/template-$env.err"; bad "helm template ($env)"; fi
done

echo "== guard rails: each of these MUST be rejected =="
# must_fail <name> <expected-message-regex> <helm args...>
must_fail() {
  local name="$1" expect="$2" out rc
  shift 2
  out="$(helm template jkr-server "$CHART" -f "$CHART/values-prod.yaml" "$@" 2>&1)"; rc=$?
  out="$(printf '%s' "$out" | tr '\n' ' ' | tr -s ' ')" # collapse wrapping so phrases match
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -Eq "$expect"; then pass "$name  (rejected: $expect)"
  elif [ "$rc" -ne 0 ]; then bad "$name was rejected, but not for the expected reason: ${out:0:300}"
  else bad "$name was ACCEPTED but must be rejected"; fi
}
IMG=(--set image.repository=r/x --set image.tag=t)
must_fail "missing relayHost"            'relayHost is required'            "${IMG[@]}"
must_fail "missing image.tag"            'image.tag is required'            --set image.repository=r/x --set-string relayHost=a.b
must_fail "missing image.repository"     'image.repository is required'     --set image.tag=t --set-string relayHost=a.b
must_fail "shell metachars in relayHost" '[Dd]oes not match pattern'           "${IMG[@]}" --set-string 'relayHost=a.b";rm -rf /;"'
must_fail "relayHost with a port"        '[Dd]oes not match pattern'           "${IMG[@]}" --set-string relayHost=a.b:21117
must_fail "relayHost with a scheme"      '[Dd]oes not match pattern'           "${IMG[@]}" --set-string relayHost=https://a.b
must_fail "port collision relay=rendezvous+2" 'port collision'              "${IMG[@]}" --set-string relayHost=a.b --set ports.relay=21118
must_fail "port collision relay=rendezvous-1" 'port collision'              "${IMG[@]}" --set-string relayHost=a.b --set ports.relay=21115
must_fail "port out of range"            'minimum|greater than or equal'    "${IMG[@]}" --set-string relayHost=a.b --set ports.rendezvous=80

echo "== rendered deployment content =="
grep -q 'getent ahosts' "$OUT/prod.yaml" && pass "hbbs fails fast on an unresolvable RELAY_HOST (getent guard present)" || bad "getent guard missing from the rendered hbbs command"
grep -q 'type: Recreate' "$OUT/prod.yaml" && pass "strategy is Recreate (single pod, host ports, RWO volume)" || bad "strategy is not Recreate"
grep -q 'hostNetwork: true' "$OUT/prod.yaml" && pass "hostNetwork enabled" || bad "hostNetwork not enabled"
grep -q 'helm.sh/resource-policy.*keep' "$OUT/prod.yaml" && pass "prod PVC is protected by helm.sh/resource-policy: keep" || bad "prod PVC is NOT protected from helm uninstall"
! grep -q 'helm.sh/resource-policy' "$OUT/int.yaml" && pass "int PVC is disposable (no keep policy)" || bad "int PVC unexpectedly has a keep policy"
grep -q 'storageClassName: "ebs-gp3-database"' "$OUT/prod.yaml" && pass "prod uses the Retain storage class" || bad "prod does not use ebs-gp3-database"

echo "== int and prod share ONE node (hostNetwork): no host port may be used by both =="
ports_of() { grep -o 'containerPort: [0-9]*' "$1" | awk '{print $2}' | sort -un; }
pi="$(ports_of "$OUT/int.yaml")"; pp="$(ports_of "$OUT/prod.yaml")"
echo "  int : $(echo $pi)"; echo "  prod: $(echo $pp)"
shared="$(comm -12 <(echo "$pi") <(echo "$pp"))"
if [ -z "$shared" ] && [ "$(echo "$pi" | wc -l)" -eq 5 ] && [ "$(echo "$pp" | wc -l)" -eq 5 ]; then
  pass "int and prod use 5 distinct ports each, none shared"
else bad "int/prod share ports or the count is not 5 each: shared=[$(echo $shared)]"; fi

echo "== kubeconform (strict, Kubernetes $K8S_SCHEMA_VERSION schemas) =="
# Git-Bash on Windows needs a Windows-style path for the docker bind mount.
HOST_OUT="$(cd "$OUT" && { pwd -W 2>/dev/null || pwd; })"
if command -v kubeconform >/dev/null 2>&1; then
  kubeconform -strict -summary -kubernetes-version "$K8S_SCHEMA_VERSION" "$OUT/int.yaml" "$OUT/prod.yaml"
else
  docker run --rm -v "$HOST_OUT:/work:ro" "$KUBECONFORM_IMAGE" -strict -summary -kubernetes-version "$K8S_SCHEMA_VERSION" /work/int.yaml /work/prod.yaml
fi
[ $? -eq 0 ] && pass "kubeconform" || bad "kubeconform"

echo
if [ "$fail" -eq 0 ]; then echo "ALL HELM CHECKS PASSED"; else echo "$fail CHECK(S) FAILED"; fi
exit "$fail"
