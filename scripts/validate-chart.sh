#!/usr/bin/env bash
# Lint, render, schema-validate and scan the Helm chart; then prove the values guardrails reject bad input.
#   ./scripts/validate-chart.sh
# Used locally and by CI (Phase 6). Needs: helm, kubeconform, checkov.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/app"
NAMESPACE=spr-app
K8S_VERSION="${K8S_VERSION:-1.36.0}"
OUT="${OUT:-$ROOT/target/chart}"
# A syntactically valid placeholder: the real digest is written by release.yml.
TEST_DIGEST="sha256:$(printf '0%.0s' {1..64})"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
mkdir -p "$OUT"

log "helm lint --strict"
helm lint "$CHART" --strict --namespace "$NAMESPACE" --set image.digest="$TEST_DIGEST"

log "helm template -> $OUT/rendered.yaml"
helm template spr-app "$CHART" --namespace "$NAMESPACE" --set image.digest="$TEST_DIGEST" > "$OUT/rendered.yaml"
grep -E '^kind:' "$OUT/rendered.yaml" | sort | uniq -c

log "kubeconform (Kubernetes $K8S_VERSION, strict; ExternalSecret CRD schema from the CRDs catalog)"
kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$OUT/rendered.yaml"

# CI runs Checkov in its own job (with SARIF upload) and sets SKIP_CHECKOV=1 here.
if [[ "${SKIP_CHECKOV:-0}" != "1" ]]; then
  log "Checkov on the rendered manifests"
  checkov -f "$OUT/rendered.yaml" --framework kubernetes --compact --quiet
fi

log "Guardrails: values.schema.json must reject unsafe values"
expect_reject() {  # usage: expect_reject <description> <helm --set args...>
  local desc=$1; shift
  if helm template spr-app "$CHART" --namespace "$NAMESPACE" "$@" >/dev/null 2>&1; then
    echo "FAIL  accepted: $desc"; return 1
  fi
  echo "OK    rejected: $desc"
}
expect_reject "no digest (first deploy before any release)"
expect_reject "a tag instead of a digest"      --set image.digest=latest
expect_reject "a public registry"              --set image.digest="$TEST_DIGEST" --set image.repository=docker.io/library/nginx
expect_reject "a single replica"               --set image.digest="$TEST_DIGEST" --set replicaCount=1
expect_reject "running as root (UID 0)"        --set image.digest="$TEST_DIGEST" --set podSecurity.uid=0
expect_reject "pods open to the internet"      --set image.digest="$TEST_DIGEST" --set networkPolicy.ingressCidr=0.0.0.0/0
expect_reject "a secret in plain env values"   --set image.digest="$TEST_DIGEST" --set env.API_TOKEN=hunter2

log "All chart checks passed"
