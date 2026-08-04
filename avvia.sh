#!/usr/bin/env bash
# Launcher portabile per Dei in machina.
# Rileva il sistema operativo e usa il Godot giusto; se manca, lo scarica (una volta)
# in tools/godot/. Stesso comando su Linux e macOS.
#
# Uso:
#   ./avvia.sh            # finestra grafica (GUI)
#   ./avvia.sh console    # gioco testuale nel terminale (headless)
#   ./avvia.sh test       # esegue i test (dev)
#   ./avvia.sh musica     # rigenera la musica della schermata d'apertura
#   ./avvia.sh installa-menu   # mette il gioco nel menu applicazioni col suo nome
#   Aggiungi "-- ollama mistral-small3.2:latest" a 'console' per i dei reali.
#
# Scelta del modello Ollama (senza toccare il config):
#   MODELLO=llama3.1:8b ./avvia.sh     # usa quel modello (preflight + gioco)
#   In gioco puoi anche cambiarlo dal menu a tendina accanto a "Ollama (dei reali)".
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

# --- Ollama: verifica/attiva server e modello prima di avviare (modalita' "dei reali") ---
# Legge il nome del modello dal profilo di Ollama (senza dipendenze extra).
# Prima stava in config/llm_config.json: Ollama era l'unico provider descritto fuori da
# config/providers/, ed e' per questo che nel gioco non lo si poteva scegliere come gli altri.
_leggi_modello() {
  grep -o '"model"[[:space:]]*:[[:space:]]*"[^"]*"' "$DIR/config/providers/1_ollama.json" 2>/dev/null \
    | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'
}

# Nota: solo ASCII e variabili tra ${...}. Il bash 3.2 di macOS, sotto 'set -u',
# ingloba un carattere multibyte attaccato a una variabile ("<<${model}>>") nel nome
# e va in errore "unbound variable". Meglio tenerlo semplice e portabile.
ollama_preflight() {
  local url="http://localhost:11434" model base
  # Scelta del modello: MODELLO=... ha precedenza sul config. Lo propago all'app via
  # DEI_MODELLO, cosi' preflight e gioco usano lo stesso. In gioco puoi cambiarlo dal menu.
  model="${MODELLO:-$(_leggi_modello)}"; [ -z "${model}" ] && model="mistral-small3.2:latest"
  export DEI_MODELLO="${model}"
  if ! command -v ollama >/dev/null 2>&1; then
    echo "[i] Ollama non installato: modalita' 'dei reali' non disponibile (si gioca coi dei simulati)."
    return 0
  fi
  # 1) server attivo? altrimenti avvialo in background e attendi che risponda.
  if ! curl -fsS "${url}/api/tags" >/dev/null 2>&1; then
    echo "Avvio Ollama in background (ollama serve)..."
    ollama serve >/dev/null 2>&1 &
    for _ in $(seq 1 30); do curl -fsS "${url}/api/tags" >/dev/null 2>&1 && break; sleep 0.5; done
  fi
  if ! curl -fsS "${url}/api/tags" >/dev/null 2>&1; then
    echo "[!] Non riesco a contattare Ollama su ${url}. Avvialo a mano con 'ollama serve'."
    return 0
  fi
  # 2) modello presente? (confronto sul nome base, tollera il tag :latest)
  base="${model%%:*}"
  if ! ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -Eq "^${base}(:|$)"; then
    echo "Scarico il modello '${model}' (una volta sola, puo' richiedere alcuni minuti)..."
    ollama pull "${model}" || echo "[!] Download fallito: scaricalo a mano con 'ollama pull ${model}'."
  fi
  # 3) pre-riscaldamento: carica il modello in RAM in background (keep_alive lungo),
  #    cosi' la prima mossa nel gioco non paga il cold-start. Non blocca l'avvio.
  echo "[..] Scaldo '${model}' in background (keep_alive 30m): la prima mossa sara' piu' pronta."
  curl -fsS "${url}/api/generate" -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model}\",\"prompt\":\"ok\",\"stream\":false,\"keep_alive\":\"30m\"}" >/dev/null 2>&1 &
  echo "[ok] Ollama pronto - modello '${model}' (attiva 'Ollama (dei reali)' nel gioco)."
}

MODE="${1:-gui}"
case "$MODE" in
  # NIENTE --audio-driver Dummy qui. C'era, con un commento che parlava del gioco testuale:
  # copiato dalla riga sotto e mai riletto. Con l'audio spento la musica della schermata
  # d'apertura non si sarebbe sentita, e non ci sarebbe stato niente da cui accorgersene —
  # solo un'apertura muta che sembra voluta.
  gui)     ollama_preflight; exec "$GODOT" --path "$DIR" ;;
  console) shift; ollama_preflight; exec "$GODOT" --headless --path "$DIR" --script res://tools/gioca.gd "$@" ;;
  test)    exec "$GODOT" --headless --path "$DIR" -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json ;;
  # Fa comparire il gioco nel menu applicazioni COL SUO NOME. Nella barra si legge
  # «godot» perche' l'eseguibile in esecuzione e' il motore, non il gioco: il file .desktop
  # dice al desktop che quelle finestre sono nostre. Spiegazione intera nel file stesso.
  installa-menu)
    DEST="$HOME/.local/share/applications"
    mkdir -p "$DEST"
    sed -e "s|AVVIA_QUI|$DIR/avvia.sh|" -e "s|ICONA_QUI|$DIR/assets/icona.png|" \
      "$DIR/distribuzione/dei-in-machina.desktop" > "$DEST/dei-in-machina.desktop"
    chmod +x "$DEST/dei-in-machina.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DEST" || true
    echo "Installato in $DEST/dei-in-machina.desktop"
    echo "La barra delle applicazioni ora dice «Dei in machina» invece di «godot»."
    echo "(Su alcuni desktop serve un logout, o 'killall plasmashell && plasmashell &'.)"
    ;;
  musica)  exec python3 "$DIR/tools/musica/genera_proemio.py" ;;
  *)       echo "Uso: ./avvia.sh [gui|console|test|musica|installa-menu]"; exit 1 ;;
esac
