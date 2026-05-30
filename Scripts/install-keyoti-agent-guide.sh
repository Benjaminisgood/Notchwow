#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYOTI_ROOT="${KEYOTI_ROOT:-$HOME/keyoti}"
DESTINATION="$KEYOTI_ROOT/AGENTS.md"

mkdir -p "$KEYOTI_ROOT"

if [[ -e "$DESTINATION" && "${FORCE:-0}" != "1" ]]; then
  echo "Keeping existing $DESTINATION"
  exit 0
fi

cp "$ROOT_DIR/docs/templates/keyoti-AGENTS.md" "$DESTINATION"
echo "Installed $DESTINATION"
