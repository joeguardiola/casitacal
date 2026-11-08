#!/bin/zsh
# Archive CasitaCal and upload it to App Store Connect (TestFlight).
# Signing uses the team in Config/Local.xcconfig (gitignored) and the Apple ID signed in to Xcode.
# Usage: scripts/testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER=$(date +%Y%m%d%H%M)   # always increasing, no bookkeeping
ARCHIVE=build/CasitaCal.xcarchive
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
echo "Archiving build $BUILD_NUMBER…"
xcodebuild archive -scheme CasitaCal -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD_NUMBER" | grep -E "error:|\*\* ARCHIVE" || true
[[ -d "$ARCHIVE" ]] || { echo "Archive failed"; exit 1; }

echo "Uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath build/export -allowProvisioningUpdates | grep -E "error|Upload|EXPORT" || true
rm -f "$OPTIONS"
echo "Done: build $BUILD_NUMBER. It shows up in TestFlight after Apple finishes processing (~5–15 min)."
