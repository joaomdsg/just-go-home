#!/usr/bin/env bash
# Capture every widget state into a single PNG per state, with the matching
# mako notification visible in the same frame for the states that have one
# (calm, urgent, shutdown). Pick one slurp region that covers both the bar
# slot and the notification slot — every PNG comes from that region, so they
# all share dimensions and the notification "appears" in the joint states.
#
# Requires: grim, slurp, python3, just-go-home on $PATH, a running waybar
# with the widget, and a running mako (or any notify-send daemon) to render
# the notifications. Hyprland or another wlroots compositor.
#
# Usage:
#   screenshots/capture.sh                      # slurp prompts for the region
#   REGION="32,40 1100x420" screenshots/capture.sh   # explicit (slurp "x,y WxH")
#
# Implementation notes:
#  - Writes state.json under the same state.lock flock the widget's tick
#    uses, via tempfile + atomic mv. A bare `>` redirect races with tick's
#    atomic rename and the widget never sees the override.
#  - Emits naive ISO timestamps. The widget stores naive datetimes; a
#    tz-aware override raises TypeError in get_target and the widget silently
#    falls into the error path.
#  - Sets preview=true + skip_final_notif=true so no real shutdown fires and
#    no final notification sneaks through during the past-target capture.
#    Notifications are fired explicitly via the imported python module.
#  - Backs up state.json and restores it on exit (even on Ctrl-C).
set -euo pipefail
cd "$(dirname "$0")"

for bin in grim just-go-home python3; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

JGH_PATH=$(command -v just-go-home)
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/just-go-home/state.json"
LOCK="${XDG_CACHE_HOME:-$HOME/.cache}/just-go-home/state.lock"
mkdir -p "$(dirname "$STATE")"

exec 9>"$LOCK"
write_state() {
  local payload=$1 tmp
  flock -x 9
  tmp=$(mktemp -p "$(dirname "$STATE")" .state.cap.XXXXXX)
  printf '%s\n' "$payload" > "$tmp"
  mv "$tmp" "$STATE"
  flock -u 9
}

backup=$(mktemp)
if [[ -f "$STATE" ]]; then cp "$STATE" "$backup"; else echo '{}' > "$backup"; fi
restore() {
  if [[ -f "$backup" ]]; then
    write_state "$(cat "$backup")" 2>/dev/null || cp "$backup" "$STATE" 2>/dev/null || rm -f "$STATE"
  fi
  rm -f "$backup"
  command -v makoctl >/dev/null && makoctl dismiss --all >/dev/null 2>&1 || true
  echo "state restored."
}
trap restore EXIT INT TERM

fire_notif() {
  python3 - "$JGH_PATH" "$1" <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
path, kind = sys.argv[1], sys.argv[2]
loader = SourceFileLoader("jgh", path)
spec = importlib.util.spec_from_loader("jgh", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
if kind == "1h":
    mod.fire_notification(3600, {}, None)        # 1 hour — calm pool
elif kind == "30min":
    mod.fire_notification(1800, {}, None)        # 30 minutes — calm pool
elif kind == "15min":
    mod.fire_notification(900, {}, None)         # 15 minutes — calm pool
elif kind == "5min":
    mod.fire_notification(300, {}, None)         # 5 minutes — urgent pool
elif kind == "30s":
    mod.fire_notification(30, {}, None)          # 30 seconds — urgent pool
elif kind == "shutdown":
    mod.fire_final_notification(None)            # "Shutting down NOW!"
else:
    sys.exit(f"unknown kind: {kind}")
PY
}

REGION=${REGION:-}
if [[ -z "$REGION" ]]; then
  command -v slurp >/dev/null || { echo "missing: slurp (or set REGION)" >&2; exit 1; }
  # Fire a sample notification so the user can include it in the region drag.
  fire_notif 30min
  sleep 0.6
  echo "select a region covering BOTH the widget and the notification slot..."
  REGION=$(slurp)
  command -v makoctl >/dev/null && makoctl dismiss --all >/dev/null 2>&1 || true
fi

set_target() {
  local spec=$1 target
  if [[ "$spec" == "past" ]]; then
    target=$(date '+%Y-%m-%dT%H:%M:%S' -d "1 hour ago")
  else
    target=$(date '+%Y-%m-%dT%H:%M:%S' -d "+${spec} seconds")
  fi
  write_state "$(printf '{"target_override":"%s","preview":true,"skip_final_notif":true}' "$target")"
}

# $1 = state name, $2 = target spec, $3 = notif kind ("" for widget-only)
snap() {
  local name=$1 spec=$2 notif=${3:-}
  set_target "$spec"
  sleep 1.0   # let widget repaint
  if [[ -n "$notif" ]]; then
    fire_notif "$notif"
    sleep 0.6 # let mako render
  fi
  grim -g "$REGION" "state-$name.png"
  echo "  → screenshots/state-$name.png"
  command -v makoctl >/dev/null && makoctl dismiss --all >/dev/null 2>&1 || true
}

echo "capturing states..."
snap calm     7200
snap warm     3590 1h
snap warning  890  15min
snap urgent   290  5min
snap flashing 30   30s
snap shutdown past shutdown
echo "done. commit the PNGs when you're happy."
