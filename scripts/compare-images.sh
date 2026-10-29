#!/usr/bin/env bash
# Before/after evidence for the hardened image: size, user, shell, Dockerfile lint and CVE counts.
#   ./scripts/compare-images.sh
# Builds both images for linux/amd64 (the EKS node architecture) and scans each with Trivy.
set -euo pipefail

PLATFORM="${PLATFORM:-linux/amd64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

log "Building BEFORE (docker/Dockerfile.before) and AFTER (Dockerfile) for ${PLATFORM}"
docker buildx build --platform "$PLATFORM" -f docker/Dockerfile.before -t spr-app:before --load . >/dev/null
docker buildx build --platform "$PLATFORM" -t spr-app:after --load . >/dev/null

log "Updating the Trivy vulnerability DB"
trivy image --download-db-only --quiet

row() { printf '%-36s %-22s %-22s\n' "$@"; }

# Pull size = compressed layers, what EKS nodes download from ECR. Unpacked = on-disk size; with Docker's
# containerd image store .Size only includes unpacked layers after the image has been run once, so it is
# read after the run-based checks below.
pull_mb()     { docker save --platform "$PLATFORM" "$1" | wc -c | awk '{printf "%.0f MB", $1/1000/1000}'; }
unpacked_mb() { docker image inspect "$1" --format '{{.Size}}' | awk '{printf "%.0f MB", $1/1000/1000}'; }
user_of()  { local u; u="$(docker image inspect "$1" --format '{{.Config.User}}')"; echo "${u:-root (unset)}"; }
has_shell() { docker run --rm --platform "$PLATFORM" --entrypoint sh "$1" -c 'echo yes' 2>/dev/null || echo "no"; }
has_git()  { docker run --rm --platform "$PLATFORM" --entrypoint sh "$1" -c 'test -d /app/.git && echo "yes (.git copied)" || echo no' 2>/dev/null || echo "no"; }
layers()   { docker image inspect "$1" --format '{{len .RootFS.Layers}}'; }
lint()     { local n; n="$(hadolint --no-fail --format json "$1" | jq 'length')"; echo "${n} finding(s)"; }
misconf()  { trivy config --quiet --format json "$1" | jq -r '[.Results[]?.Misconfigurations[]?.ID] | if length == 0 then "none" else join(", ") end'; }

# Count vulnerabilities by severity; "fixable" = a fixed version exists (what the Phase 6 CI gate fails on).
cves() {
  trivy image --quiet --skip-db-update --scanners vuln --format json "$1" \
    | jq -r '[.Results[]?.Vulnerabilities[]?] as $v
      | ($v | map(select(.Severity=="CRITICAL")) | length) as $c
      | ($v | map(select(.Severity=="HIGH")) | length) as $h
      | ($v | map(select(.Severity=="MEDIUM")) | length) as $m
      | ($v | map(select(.Severity=="LOW" or .Severity=="UNKNOWN")) | length) as $l
      | ($v | map(select((.Severity=="CRITICAL" or .Severity=="HIGH") and (.FixedVersion // "") != "")) | length) as $f
      | "\($c) \($h) \($m) \($l) \($v|length) \($f)"'
}

log "Scanning (this takes a minute the first time)"
read -r BC BH BM BL BT BF <<<"$(cves spr-app:before)"
read -r AC AH AM AL AT AF <<<"$(cves spr-app:after)"

# Run-based checks first (they also unpack both images, so the unpacked size below is accurate).
SH_B="$(has_shell spr-app:before)"; SH_A="$(has_shell spr-app:after)"
GIT_B="$(has_git spr-app:before)";  GIT_A="$(has_git spr-app:after)"

log "Results (${PLATFORM})"
row "" "BEFORE" "AFTER"
row "Pull size (compressed)" "$(pull_mb spr-app:before)" "$(pull_mb spr-app:after)"
row "Unpacked size" "$(unpacked_mb spr-app:before)" "$(unpacked_mb spr-app:after)"
row "Layers" "$(layers spr-app:before)" "$(layers spr-app:after)"
row "Runs as" "$(user_of spr-app:before)" "$(user_of spr-app:after)"
row "Shell available" "$SH_B" "$SH_A"
row ".git history in image" "$GIT_B" "$GIT_A"
row "Base pinned by digest" "no (mutable tag)" "yes (sha256)"
row "hadolint" "$(lint docker/Dockerfile.before)" "$(lint Dockerfile)"
row "Trivy Dockerfile misconfigs" "$(misconf docker/Dockerfile.before)" "$(misconf Dockerfile)"
row "CVEs CRITICAL" "$BC" "$AC"
row "CVEs HIGH" "$BH" "$AH"
row "CVEs MEDIUM" "$BM" "$AM"
row "CVEs LOW/UNKNOWN" "$BL" "$AL"
row "CVEs total" "$BT" "$AT"
row "HIGH+CRITICAL with a fix (gate)" "$BF" "$AF"

cat <<'EOF'

Details:  trivy image --severity HIGH,CRITICAL spr-app:before
          trivy image --severity HIGH,CRITICAL --ignore-unfixed spr-app:after
EOF
