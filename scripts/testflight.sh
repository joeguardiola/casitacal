#!/bin/zsh
# Version, archive and upload CasitaCal to App Store Connect (TestFlight), then tag the release.
#
# Semantic versioning (MAJOR.MINOR.PATCH; 0.x = still in development):
#   scripts/testflight.sh          # PATCH, bug fixes only   (0.2.0 -> 0.2.1); uses the current version if never released
#   scripts/testflight.sh minor    # MINOR, new features      (0.2.1 -> 0.3.0)
#   scripts/testflight.sh major    # MAJOR, breaking/1.0      (0.9.2 -> 1.0.0)
#
# Signing uses the team in Config/Local.xcconfig (gitignored) and the Apple ID signed in to Xcode.
# Add a "## <version>" section to CHANGELOG.md before running (the script warns if it's missing).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first — each upload is tagged in git."; exit 1
fi

CURRENT=$(sed -nE 's/^ *MARKETING_VERSION: "([0-9.]+)".*/\1/p' project.yml)
IFS=. read -r MAJ MIN PAT <<< "$CURRENT"
case "${1:-patch}" in
  major) VERSION="$((MAJ + 1)).0.0" ;;
  minor) VERSION="$MAJ.$((MIN + 1)).0" ;;
  patch) if git rev-parse -q --verify "refs/tags/v$CURRENT" >/dev/null; then VERSION="$MAJ.$MIN.$((PAT + 1))"; else VERSION="$CURRENT"; fi ;;
  *) echo "Usage: $0 [patch|minor|major]"; exit 1 ;;
esac
BUILD_NUMBER=$(date +%Y%m%d%H%M)   # always increasing, no bookkeeping

if ! grep -q "^## $VERSION" CHANGELOG.md; then
  if [[ -n "${MAINTENANCE:-}" ]]; then
    # Keep-alive upload: note it in the changelog (included in the release commit).
    perl -0pi -e "s/\n## /\n## $VERSION\n- Maintenance rebuild so TestFlight never expires (no changes)\n\n## /" CHANGELOG.md
  else
    echo "⚠️  CHANGELOG.md has no '## $VERSION' section yet."
  fi
fi
sed -i '' -E "s/^( *MARKETING_VERSION: )\"[0-9.]+\"/\1\"$VERSION\"/" project.yml

ARCHIVE=build/CasitaCal.xcarchive
rm -rf "$ARCHIVE"
OPTIONS=$(mktemp -t exportoptions).plist
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST

xcodegen generate >/dev/null
echo "Archiving $VERSION ($BUILD_NUMBER)…"
xcodebuild archive -scheme CasitaCal -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD_NUMBER" | grep -E "error:|\*\* ARCHIVE" || true
if [[ ! -d "$ARCHIVE" ]]; then git checkout -- project.yml CHANGELOG.md; echo "Archive failed"; exit 1; fi

echo "Uploading to App Store Connect…"
LOG=$(mktemp)
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath build/export -allowProvisioningUpdates > "$LOG" 2>&1 || true
rm -f "$OPTIONS"
grep -vE "Progress [0-9]+%" "$LOG" | grep -E "error|Upload|EXPORT" || true
if ! grep -q "EXPORT SUCCEEDED" "$LOG"; then git checkout -- project.yml CHANGELOG.md; echo "Upload failed (see $LOG)"; exit 1; fi

git add project.yml CHANGELOG.md
git commit -q -m "Release $VERSION (build $BUILD_NUMBER) to TestFlight"
git tag -a "v$VERSION" -m "CasitaCal $VERSION (build $BUILD_NUMBER) — TestFlight"
git push -q --follow-tags
echo "Done: $VERSION ($BUILD_NUMBER) uploaded, tagged v$VERSION and pushed. In TestFlight after processing (~5–15 min)."
