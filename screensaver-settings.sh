#!/bin/zsh
set -eu

# Screen saver preferences belong to the logged-in user, not the root daemon.
# Keep the same entrypoint usable from the App, sudo and the background service.
SCREENSAVER_UID="$(/usr/bin/id -u)"
if [[ "$SCREENSAVER_UID" == 0 ]]; then
  SCREENSAVER_UID="$(/usr/bin/stat -f %u /dev/console)"
  if [[ "$SCREENSAVER_UID" -lt 500 ]]; then
    [[ "${1:-}" != read ]] || print unavailable
    exit 0 # No desktop user yet; the daemon retries after login.
  fi
fi

user_defaults() {
  if [[ "$(/usr/bin/id -u)" == 0 ]]; then
    /bin/launchctl asuser "$SCREENSAVER_UID" /usr/bin/sudo -H -u "#$SCREENSAVER_UID" /usr/bin/defaults "$@"
  else
    /usr/bin/defaults "$@"
  fi
}

read_idle_time() {
  local idle_seconds
  if idle_seconds="$(user_defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null)"; then
    print -r -- "$idle_seconds"
  elif idle_seconds="$(user_defaults read com.apple.screensaver idleTime 2>/dev/null)"; then
    print -r -- "$idle_seconds"
  else
    print 1200 # macOS's default when no explicit preference exists.
  fi
}

if [[ "${1:-}" == read ]]; then
  read_idle_time
  exit 0
fi

SCREENSAVER_SECONDS="${1:-}"
if [[ "$SCREENSAVER_SECONDS" != <-> ]] || (( SCREENSAVER_SECONDS > 86400 )); then
  print -u2 'Usage: screensaver-settings.sh <seconds: 0..86400 | read>'
  exit 2
fi

if [[ "$(read_idle_time)" != "$SCREENSAVER_SECONDS" ]]; then
  user_defaults -currentHost write com.apple.screensaver idleTime -int "$SCREENSAVER_SECONDS"
fi
if [[ "$(read_idle_time)" != "$SCREENSAVER_SECONDS" ]]; then
  print -u2 'Could not verify the desktop user screen saver setting.'
  exit 1
fi
