#!/bin/zsh
set -eu

BASE_DIR="${0:A:h}"
LABEL="com.yuwangzhi.codex-power-keepawake"
TOGGLE_SCRIPT="$BASE_DIR/toggle-keepawake.sh"

sleep_disabled="$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ {print $2; exit}')"
power_source="$(/usr/bin/pmset -g batt | /usr/bin/awk -F"'" '/Now drawing from/ {print $2; exit}')"
sleep_value="$(/usr/bin/pmset -g | /usr/bin/awk '/^[[:space:]]*sleep[[:space:]]/ {print $2; exit}')"
display_sleep_value="$(/usr/bin/pmset -g | /usr/bin/awk '/^[[:space:]]*displaysleep[[:space:]]/ {print $2; exit}')"
disk_sleep_value="$(/usr/bin/pmset -g | /usr/bin/awk '/^[[:space:]]*disksleep[[:space:]]/ {print $2; exit}')"

if /bin/launchctl print "system/$LABEL" >/tmp/codex-power-launchd-status.$$ 2>&1; then
  daemon_status="已安装，并且每 15 秒自动重刷"
  daemon_loaded="yes"
else
  daemon_status="未安装或未加载"
  daemon_loaded="no"
fi
/bin/rm -f /tmp/codex-power-launchd-status.$$

if [[ "$sleep_disabled" == "1" && "$daemon_loaded" == "yes" ]]; then
  current_summary="当前状态：防睡眠已开启"
  current_detail="含义：合盖/息屏后，Mac 会尽量保持系统运行；只要网络不断，VS Code SSH / Codex 连接应继续保持。"
  next_summary="如果点击「切换状态」：会关闭防睡眠，恢复普通 MacBook 睡眠策略。"
  demo="示例：现在合盖还能继续远程；切换后再合盖，Mac 可能进入睡眠，SSH/VS Code 可能断开。"
else
  current_summary="当前状态：防睡眠未完整开启"
  current_detail="含义：Mac 仍可能在合盖、拔电源或空闲后进入睡眠；SSH/VS Code 连接有断开的风险。"
  next_summary="如果点击「切换状态」：会开启防睡眠，并安装 15 秒自动重刷。"
  demo="示例：切换后再合盖或拔电源，只要 Wi-Fi/Tailscale 网络不断，SSH/VS Code 会尽量保持连接。"
fi

message="$current_summary

$current_detail

当前电源来源：$power_source
SleepDisabled：$sleep_disabled
sleep / displaysleep / disksleep：$sleep_value / $display_sleep_value / $disk_sleep_value
后台守护进程：$daemon_status

$next_summary

$demo"

if [[ "${CODEX_POWER_STATUS_NO_DIALOG:-0}" == "1" ]]; then
  printf '%s\n' "$message"
  exit 0
fi

escape_applescript_string() {
  printf '%s' "$1" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

message_escaped="$(escape_applescript_string "$message")"

button="$(
/usr/bin/osascript <<OSA
set dialogMessage to "$message_escaped"
set dialogResult to display dialog dialogMessage buttons {"我知道了", "切换状态"} default button "我知道了" with title "电源与 SSH 保持状态"
return button returned of dialogResult
OSA
)"

if [[ "$button" == "切换状态" ]]; then
  "$TOGGLE_SCRIPT"
fi
