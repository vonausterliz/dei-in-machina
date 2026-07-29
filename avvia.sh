#!/usr/bin/env bash
# Launcher portabile per Dei in machina.
# Rileva il sistema operativo e usa il Godot giusto; se manca, lo scarica (una volta)
# in tools/godot/. Stesso comando su Linux e macOS.
#
# Uso:
#   ./avvia.sh            # finestra grafica (GUI)
#   ./avvia.sh console    # gioco testuale nel terminale (headless)
#   ./avvia.sh test       # esegue i test (dev)
#   Aggiungi "-- ollama mistral-small3.2:latest" a 'console' per i dei reali.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_VER="4.7.1-stable"
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VER}"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux)
    GODOT="$DIR/tools/godot/godot4"
    ASSET="Godot_v${GODOT_VER}_linux.x86_64.zip"
    INNER="Godot_v${GODOT_VER}_linux.x86_64"
    ;;
  Darwin)
    GODOT="$DIR/tools/godot/Godot.app/Contents/MacOS/Godot"
    ASSET="Godot_v${GODOT_VER}_macos.universal.zip"
    INNER=""  # lo zip contiene direttamente Godot.app
    ;;
  *)
    echo "Sistema non supportato dal launcher: $OS. Apri il progetto col tuo Godot 4.7.x."
    exit 1
    ;;
esac

# Scarica Godot se non presente.
if [ ! -x "$GODOT" ]; then
  echo "Godot ${GODOT_VER} non trovato per $OS: lo scarico (una volta sola)…"
  mkdir -p "$DIR/tools/godot"
  TMP="$(mktemp -d)"
  echo "  scarico $ASSET …"
  curl -fL --progress-bar -o "$TMP/godot.zip" "$BASE_URL/$ASSET"
  echo "  estraggo…"
  unzip -q -o "$TMP/godot.zip" -d "$TMP"
  if [ "$OS" = "Darwin" ]; then
    rm -rf "$DIR/tools/godot/Godot.app"
    mv "$TMP/Godot.app" "$DIR/tools/godot/Godot.app"
    # Toglie la quarantena di Gatekeeper sui binari scaricati.
    xattr -dr com.apple.quarantine "$DIR/tools/godot/Godot.app" 2>/dev/null || true
  else
    mv "$TMP/$INNER" "$GODOT"
    chmod +x "$GODOT"
  fi
  rm -rf "$TMP"
  echo "  fatto: $GODOT"
fi

# Importazione: genera/aggiorna .godot, registra le classi global (class_name) e
# importa le risorse nuove (font, ecc.). L'importatore e' incrementale: e' veloce se
# non e' cambiato nulla. La prima volta (o dopo un sync con file nuovi) fa il lavoro.
if [ ! -f "$DIR/.godot/global_script_class_cache.cfg" ]; then
  echo "Prima importazione del progetto (una volta sola)…"
fi
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1 || true

MODE="${1:-gui}"
case "$MODE" in
  gui)     exec "$GODOT" --path "$DIR" --audio-driver Dummy ;;  # gioco testuale: niente audio (evita l'avviso CoreAudio su macOS)
  console) shift; exec "$GODOT" --headless --path "$DIR" --script res://tools/gioca.gd "$@" ;;
  test)    exec "$GODOT" --headless --path "$DIR" -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json ;;
  *)       echo "Uso: ./avvia.sh [gui|console|test]"; exit 1 ;;
esac
