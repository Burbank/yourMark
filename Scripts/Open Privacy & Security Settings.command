#!/bin/zsh
# Opens System Settings → Privacy & Security.
# That is where “Open Anyway” appears after macOS blocks an unsigned app.
# Not an Apple “Always Trust” switch — that does not exist for unsigned apps.

open_settings() {
  open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" 2>/dev/null && return 0
  open "x-apple.systempreferences:com.apple.preference.security" 2>/dev/null && return 0
  open "x-apple.systempreferences:com.apple.Settings.PrivacySecurity" 2>/dev/null && return 0
  if [[ -d /System/Library/PreferencePanes/Security.prefPane ]]; then
    open /System/Library/PreferencePanes/Security.prefPane 2>/dev/null && return 0
  fi
  open -a "System Settings" 2>/dev/null || open -a "System Preferences"
  return 0
}

open_settings
osascript <<'APPLESCRIPT' &
try
  delay 0.8
  tell application "System Settings" to activate
end try
APPLESCRIPT
exit 0
