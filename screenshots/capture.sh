#!/usr/bin/env bash
# Drive the widget through every visible state and capture PNGs into ./screenshots/.
# Requires: grim, slurp, just-go-home installed.
#
# Usage:
#   screenshots/capture.sh                 # interactive: slurp prompts for the region
#   screenshots/capture.sh 32,352 600x26   # explicit "x,y WxH" (slurp format)
#
# Notes:
#  - Backs up state.json and restores on exit (even on Ctrl-C).
#  - Uses preview-mode + skip_final_notif so no real shutdown / final
#    notification fires.
set -euo pipefail
cd "$(dirname "$0")"

for bin in grim just-go-home; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

STATE="${XDG_CACHE_HOME:-$HOME/.cache}/just-go-home/state.json"
LOCK="${XDG_CACHE_HOME:-$HOME/.cache}/just-go-home/state.lock"
mkdir -p "$(dirname "$STATE")"

# Same advisory lock the python tick uses; without it, an in-flight tick's
# atomic rename can clobber our write and the widget never updates.
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
  echo "state restored."
}
trap restore EXIT INT TERM

if [[ $# -ge 1 ]]; then
  REGION="$*"
else
  command -v slurp >/dev/null || { echo "missing: slurp (or pass region as arg)" >&2; exit 1; }
  echo "select the widget region (drag with mouse)..."
  REGION=$(slurp)
fi

snap() {
  local name=$1 spec=$2 target
  # Naive ISO (no tz suffix); the widget stores naive datetimes and aborts
  # with TypeError if it has to compare a tz-aware override to datetime.now().
  if [[ "$spec" == "past" ]]; then
    target=$(date '+%Y-%m-%dT%H:%M:%S' -d "1 hour ago")
  else
    target=$(date '+%Y-%m-%dT%H:%M:%S' -d "+${spec} seconds")
  fi
  write_state "$(printf '{"target_override":"%s","preview":true,"skip_final_notif":true}' "$target")"
  sleep 1.5
  grim -g "$REGION" "widget-$name.png"
  echo "  → screenshots/widget-$name.png"
}

echo "capturing widget states (1.5s settle each)..."
snap calm     7200
snap warm     2900
snap warning  1500
snap urgent   200
snap flashing 45
snap shutdown past
echo "done. commit the PNGs when you're happy."
