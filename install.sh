#!/usr/bin/env bash
# Idempotent installer: safe to re-run any number of times. Prints a clear
# state line each time (installed / updated / unchanged).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

SRC="just-go-home"
BIN_DIR="$HOME/.local/bin"
DEST="$BIN_DIR/just-go-home"

if [[ ! -f "$SRC" ]]; then
  echo "error: $SRC not found in $(pwd)" >&2
  exit 1
fi

# Python 3.11+ required (script uses tomllib).
if command -v python3 >/dev/null 2>&1; then
  if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)'; then
    echo "warning: python3 < 3.11 detected — just-go-home requires 3.11+ (tomllib)" >&2
  fi
else
  echo "warning: python3 not found on PATH — just-go-home will not run until installed" >&2
fi

mkdir -p "$BIN_DIR"

if [[ -L "$DEST" || ( -e "$DEST" && ! -f "$DEST" ) ]]; then
  echo "error: $DEST exists but is not a regular file (symlink/dir?) — refusing to overwrite" >&2
  exit 1
fi

if [[ -f "$DEST" ]] && cmp -s "$SRC" "$DEST"; then
  # Ensure mode is correct even when contents match.
  chmod 755 "$DEST"
  echo "unchanged: $DEST"
else
  action="installed"
  [[ -f "$DEST" ]] && action="updated"
  install -m 755 "$SRC" "$DEST"
  echo "$action: $DEST"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "warning: $BIN_DIR not in PATH — add it to your shell rc" >&2 ;;
esac

# Skip the "next" hint if config already exists, so re-runs stay quiet.
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/just-go-home/config.toml"
if [[ ! -f "$CFG" ]]; then
  echo "next: just-go-home init"
fi
