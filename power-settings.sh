#!/bin/zsh
# Shared by the privileged install/restore entrypoints.
STATE_DIR="/Library/Application Support/com.yuwangzhi.power-management"

capture_power_settings() {
  if [[ -f "$STATE_DIR/custom.txt" && -f "$STATE_DIR/sleep-disabled.txt" ]]; then
    return
  fi
  /usr/bin/install -d -o root -g wheel -m 700 "$STATE_DIR"
  local capture_dir
  capture_dir="$(/usr/bin/mktemp -d "$STATE_DIR/capture.XXXXXX")"
  /usr/bin/pmset -g custom > "$capture_dir/custom.txt"
  /usr/bin/pmset -g | /usr/bin/awk '$1 == "SleepDisabled" { print $2; exit }' > "$capture_dir/sleep-disabled.txt"
  if [[ "$(/bin/cat "$capture_dir/sleep-disabled.txt")" != [01] ]]; then
    print -u2 "Cannot read SleepDisabled; power settings have not been changed."
    /bin/rm -f "$capture_dir/custom.txt" "$capture_dir/sleep-disabled.txt"
    /bin/rmdir "$capture_dir"
    return 1
  fi
  /bin/chmod 600 "$capture_dir/"*.txt
  /usr/sbin/chown root:wheel "$capture_dir/"*.txt
  /bin/mv "$capture_dir/custom.txt" "$STATE_DIR/custom.txt"
  /bin/mv "$capture_dir/sleep-disabled.txt" "$STATE_DIR/sleep-disabled.txt"
  /bin/rmdir "$capture_dir"
}

restore_power_settings() {
  if [[ -f "$STATE_DIR/custom.txt" && -f "$STATE_DIR/sleep-disabled.txt" ]]; then
    local disabled power_source setting setting_value
    disabled="$(/bin/cat "$STATE_DIR/sleep-disabled.txt")"
    [[ "$disabled" == [01] ]] || { print -u2 "Invalid power-settings backup."; return 1; }
    /usr/bin/pmset -a disablesleep "$disabled"
    # Only restore numeric keys changed by this tool. Never execute backup text.
    while read -r power_source setting setting_value; do
      /usr/bin/pmset "$power_source" "$setting" "$setting_value"
    done < <(/usr/bin/awk '
      /^AC Power:/ { source = "-c"; next }
      /^Battery Power:/ { source = "-b"; next }
      /^[^[:space:]].*:$/ { source = ""; next }
      source != "" && NF == 2 && $1 ~ /^(sleep|displaysleep|disksleep|womp|tcpkeepalive|powernap|ttyskeepawake)$/ && $2 ~ /^[0-9]+$/ { print source, $1, $2 }
    ' "$STATE_DIR/custom.txt")
    /bin/rm -f "$STATE_DIR/custom.txt" "$STATE_DIR/sleep-disabled.txt"
    /bin/rmdir "$STATE_DIR" 2>/dev/null || true
    print "Restored saved power settings."
  else
    # Compatibility for legacy installs, which did not save a snapshot.
    /usr/bin/pmset -a disablesleep 0
    /usr/bin/pmset -c displaysleep 10 sleep 1 disksleep 10
    /usr/bin/pmset -b displaysleep 5 sleep 1 disksleep 10
    print "Restored legacy normal sleep defaults."
  fi
}
