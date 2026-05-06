#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
mkdir -p "$HOME/.local/bin"
install -m 755 just-go-home "$HOME/.local/bin/just-go-home"
echo "installed: $HOME/.local/bin/just-go-home"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "warning: $HOME/.local/bin not in PATH — add it to your shell rc";;
esac
echo "next: just-go-home init"
