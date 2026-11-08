#!/bin/zsh
# Keeps TestFlight from expiring (builds stop opening 90 days after upload).
# Run weekly by launchd (scripts/install-keepalive.sh). If the newest TestFlight build is more
# than 60 days old, uploads a maintenance rebuild (patch version). Devices with TestFlight
# "Automatic Updates" on install it by themselves — no reinstalling.
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$(dirname "$0")/.."
echo "== $(date) keep-alive check"

git pull -q --ff-only || { echo "git pull failed; skipping"; exit 0; }
LAST=$(git for-each-ref --sort=-creatordate --format='%(creatordate:unix)' 'refs/tags/v*' | head -1)
AGE_DAYS=$(( ( $(date +%s) - ${LAST:-0} ) / 86400 ))
echo "Newest TestFlight build is $AGE_DAYS days old."
if (( AGE_DAYS < 60 )); then echo "Fresh enough."; exit 0; fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes; not uploading. (Commit them, or run scripts/testflight.sh.)"; exit 1
fi
MAINTENANCE=1 scripts/testflight.sh patch
