#!/usr/bin/env sh
# Mac/Linux: run Polox with a Godot 4.7.2 binary.
# Set GODOT=/path/to/godot, or have `godot` on your PATH.
cd "$(dirname "$0")" || exit 1
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
exec "$GODOT" --path .
