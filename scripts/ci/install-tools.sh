#!/usr/bin/env bash
# Install pinned CLI tools for CI, verified against SHA-256 hashes hardcoded HERE (linux/amd64).
#   scripts/ci/install-tools.sh trivy helm kubeconform hadolint
#
# Why hardcoded hashes instead of the release's own checksums file: in March 2026 attackers force-pushed the
# trivy-action / setup-trivy tags AND published malicious Trivy binaries. Whoever controls a release can also
# publish a matching checksums file; a hash pinned in this repo (reviewed in a PR) can't be changed that way.
# Each hash below was cross-checked on 2026-10-29 against the project's published checksums (or GitHub's
# asset digest) and matches the version used locally.
# To upgrade: download the new asset, verify it, update VERSION and SHA256 together in one reviewed PR.
set -euo pipefail

BIN_DIR="${RUNNER_TEMP:-/tmp}/bin"
mkdir -p "$BIN_DIR"
WORK="$(mktemp -d)"

fetch() {  # usage: fetch <url> <sha256> <output-file>
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum --check --strict -
}

for tool in "$@"; do
  case "$tool" in
    trivy)
      v=0.76.1; sha=c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0
      fetch "https://github.com/aquasecurity/trivy/releases/download/v${v}/trivy_${v}_Linux-64bit.tar.gz" "$sha" "$WORK/trivy.tgz"
      tar -xzf "$WORK/trivy.tgz" -C "$BIN_DIR" trivy ;;
    helm)
      v=4.2.2; sha=9adafecab4d406853bba163a70e9f104f47dbbf65ce24b7653bae7e36150bcb6
      fetch "https://get.helm.sh/helm-v${v}-linux-amd64.tar.gz" "$sha" "$WORK/helm.tgz"
      tar -xzf "$WORK/helm.tgz" -C "$WORK" && install -m 0755 "$WORK/linux-amd64/helm" "$BIN_DIR/helm" ;;
    kubeconform)
      v=0.8.0; sha=9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883
      fetch "https://github.com/yannh/kubeconform/releases/download/v${v}/kubeconform-linux-amd64.tar.gz" "$sha" "$WORK/kc.tgz"
      tar -xzf "$WORK/kc.tgz" -C "$BIN_DIR" kubeconform ;;
    hadolint)
      v=2.15.1; sha=c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507
      fetch "https://github.com/hadolint/hadolint/releases/download/v${v}/hadolint-linux-x86_64" "$sha" "$WORK/hadolint"
      install -m 0755 "$WORK/hadolint" "$BIN_DIR/hadolint" ;;
    *) echo "unknown tool: $tool" >&2; exit 1 ;;
  esac
  echo "installed $tool"
done

# Make the tools available to later steps in the same job.
if [[ -n "${GITHUB_PATH:-}" ]]; then echo "$BIN_DIR" >> "$GITHUB_PATH"; fi
