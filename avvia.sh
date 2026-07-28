#!/usr/bin/env bash
# Avvia Dei in machina con la GUI (solo Linux: usa il Godot incluso in tools/godot).
# Sul Mac usa il tuo Godot 4.7.x per macOS (vedi COME_GIOCARE.md).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="$DIR/tools/godot/godot4"

if [ ! -x "$GODOT" ]; then
  echo "Godot non trovato in $GODOT (questo binario e' per Linux x86_64)."
  echo "Sul Mac apri il progetto col tuo Godot 4.7.x. Vedi COME_GIOCARE.md."
  exit 1
fi

case "${1:-gui}" in
  gui)     exec "$GODOT" --path "$DIR" ;;                                        # finestra grafica
  console) exec "$GODOT" --headless --path "$DIR" --script res://tools/gioca.gd "${@:2}" ;;  # console testuale
  test)    exec "$GODOT" --headless --path "$DIR" -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json ;;
  *)       echo "Uso: ./avvia.sh [gui|console|test]"; exit 1 ;;
esac
