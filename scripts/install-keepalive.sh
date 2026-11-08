#!/bin/zsh
# Installs a weekly launchd job (Mondays 4:00 AM; runs on next wake if the Mac was asleep) that
# runs scripts/keepalive.sh. Uninstall: launchctl bootout gui/$UID/com.guardiola.casitacal.keepalive
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LABEL=com.guardiola.casitacal.keepalive
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/CasitaCal-keepalive.log"
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>$REPO/scripts/keepalive.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
PLIST
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
echo "Installed $LABEL (weekly). Log: $LOG"
