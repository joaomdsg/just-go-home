#!/usr/bin/env bash
# Fire each notification variant the script actually uses (with the
# colored progress bar) and capture each one via grim+slurp.
#
# Usage: screenshots/capture-notifications.sh
set -euo pipefail
cd "$(dirname "$0")"

for bin in grim slurp just-go-home python3; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

JGH_PATH=$(command -v just-go-home)

fire() {
  # $1: "calm" | "urgent" | "shutdown"
  python3 - "$JGH_PATH" "$1" <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
path, kind = sys.argv[1], sys.argv[2]
loader = SourceFileLoader("jgh", path)
spec = importlib.util.spec_from_loader("jgh", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)
if kind == "calm":
    mod.fire_notification(1800, {}, None)        # 30 minutes — calm pool
elif kind == "urgent":
    mod.fire_notification(30, {}, None)          # 30 seconds — urgent pool
elif kind == "shutdown":
    mod.fire_final_notification(None)            # "TIME IS UP! / Shutting down NOW!"
else:
    sys.exit(f"unknown kind: {kind}")
PY
}

if [[ $# -ge 1 ]]; then
  REGION="$*"
else
  fire calm
  sleep 0.6
  echo "drag a region around the notification (used for all 3 captures)..."
  REGION=$(slurp)
  command -v makoctl >/dev/null && makoctl dismiss --all >/dev/null 2>&1 || true
fi

shoot() {
  local name=$1
  fire "$name"
  sleep 0.6
  grim -g "$REGION" "notification-$name.png"
  echo "  saved screenshots/notification-$name.png"
  command -v makoctl >/dev/null && makoctl dismiss --all >/dev/null 2>&1 || true
}

shoot calm
shoot urgent
shoot shutdown
echo "done."
