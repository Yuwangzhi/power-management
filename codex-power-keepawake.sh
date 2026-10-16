#!/bin/zsh
set -eu

# Keep this Mac awake for Codex remote-control work.
# This intentionally affects both AC and battery power.

/usr/bin/pmset -a disablesleep 1

# AC power: keep display, system, and disk awake.
/usr/bin/pmset -c displaysleep 0 sleep 0 disksleep 0 womp 1 tcpkeepalive 1 powernap 1 ttyskeepawake 1

# Battery power: keep display, system, and disk awake as well.
# This is useful for remote Codex continuity, but it can drain battery and increase heat.
/usr/bin/pmset -b displaysleep 0 sleep 0 disksleep 0 tcpkeepalive 1 powernap 1 ttyskeepawake 1
