#!/usr/bin/env bash
# Dei in machina — Copyright (C) 2026 vonausterliz — GNU AGPL-3.0 (vedi LICENSE).
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
#   ./avvia.sh --debugllm      # apre la finestra col tracciato delle chiamate al modello
#   ./avvia.sh --tracellm      # come sopra, PIU' il dettaglio HTTP di ogni richiesta/risposta
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

# L'IMPRONTA DEI FILE CHE SCARICHIAMO.
#
# Il launcher prende un ESEGUIBILE da internet e lo lancia sulla macchina di chi gioca. Il
# canale e' HTTPS e la fonte sono le release ufficiali di Godot, ma «l'ho preso dal posto
# giusto» non e' la stessa cosa di «e' il file giusto»: un mirror aziendale, un proxy che
# intercetta, una release ripubblicata, e si esegue altro senza accorgersene.
#
# Sono le SHA-512 pubblicate da Godot in SHA512-SUMS.txt per questa versione. Se cambi
# GODOT_VER devi cambiare anche queste, e il launcher si ferma finche' non lo fai: meglio
# fermarsi che verificare contro un valore vecchio, che e' come non verificare.
SHA_LINUX="4ccdab7a48eeccbe8819a2fc1f6262f8d72065d98601bcb3743fcbd7ebd39f373758a788ee3293a05ec5b2c48538266c437404312e372225cd2df273945a2de9"
SHA_MACOS="a5c6443e193829de9a3237b57ef5e01c23839888900e241543da0dd4bac1050125e19469f0cca9a9958ac346070d98cab8e5d6aee16b181c6d06cda86bd07224"

case "$OS" in
  Linux)
    GODOT="$DIR/tools/godot/godot4"
    ASSET="Godot_v${GODOT_VER}_linux.x86_64.zip"
    INNER="Godot_v${GODOT_VER}_linux.x86_64"
    ATTESA="$SHA_LINUX"
    ;;
  Darwin)
    GODOT="$DIR/tools/godot/Godot.app/Contents/MacOS/Godot"
    ASSET="Godot_v${GODOT_VER}_macos.universal.zip"
    INNER=""  # lo zip contiene direttamente Godot.app
    ATTESA="$SHA_MACOS"
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

  # Verifica dell'impronta PRIMA di estrarre: uno zip non fidato non si apre nemmeno.
  echo "  verifico l'impronta…"
  if command -v sha512sum >/dev/null 2>&1; then
    OTTENUTA="$(sha512sum "$TMP/godot.zip" | cut -d" " -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    OTTENUTA="$(shasum -a 512 "$TMP/godot.zip" | cut -d" " -f1)"
  else
    echo "  [!] Non trovo ne' sha512sum ne' shasum: non posso verificare cosa ho scaricato."
    echo "      Installa uno dei due, oppure scarica Godot ${GODOT_VER} a mano e mettilo in"
    echo "      tools/godot/ ."
    rm -rf "$TMP"; exit 1
  fi
  if [ "$OTTENUTA" != "$ATTESA" ]; then
    echo "  [!] IMPRONTA SBAGLIATA: il file scaricato non e' quello atteso. NON lo eseguo."
    echo "      attesa:   $ATTESA"
    echo "      ottenuta: $OTTENUTA"
    echo "      Puo' voler dire che la versione e' cambiata (aggiorna SHA_LINUX/SHA_MACOS in"
    echo "      questo file, dalla SHA512-SUMS.txt della release) — oppure che il download"
    echo "      e' stato manomesso. Nel dubbio, la seconda."
    rm -rf "$TMP"; exit 1
  fi
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

# I DUE LIVELLI DI OSSERVAZIONE. Nessuno dei due e' una voce di menu: non servono a chi
# gioca — servono a chi indaga, e una finestra di traffico HTTP davanti alla narrazione e'
# rumore per tutti gli altri. Il tracciato su FILE, in user://log/, si scrive SEMPRE: la
# finestra e' solo una vetrina su quel flusso.
#
#   --debugllm   apre la finestra: l'esito di ogni chiamata (agente, latenza, token, errori).
#                E' il livello con cui si scopre QUALE chiamata e' lenta.
#   --tracellm   aggiunge il dettaglio HTTP: verbo, indirizzo, intestazioni e corpo di ogni
#                richiesta, e lo stesso di ogni risposta. E' il livello con cui si scopre
#                PERCHE'. Implica --debugllm: chiedere il dettaglio e non vederlo a schermo
#                sarebbe una trappola. Le credenziali restano oscurate anche qui.
for a in "$@"; do
  case "$a" in
    --debugllm) export DEI_DEBUG_LLM=1; shift ;;
    --tracellm) export DEI_DEBUG_LLM=1; export DEI_TRACE_LLM=1; shift ;;
  esac
done

MODE="${1:-gui}"
case "$MODE" in
  # NIENTE --audio-driver Dummy qui. C'era, con un commento che parlava del gioco testuale:
  # copiato dalla riga sotto e mai riletto. Con l'audio spento la musica della schermata
  # d'apertura non si sarebbe sentita, e non ci sarebbe stato niente da cui accorgersene —
  # solo un'apertura muta che sembra voluta.
  gui)     ollama_preflight; exec "$GODOT" --path "$DIR" ;;
  console) shift; ollama_preflight; exec "$GODOT" --headless --path "$DIR" --script res://tools/gioca.gd "$@" ;;
  # I TEST NON TOCCANO LE TUE PREFERENZE. Scrivono nel file indicato qui, usa-e-getta.
  # Senza questa riga la suite cancellava provider_nome e spegneva il gateway nel file VERO:
  # al riavvio il gioco ripiegava in silenzio sul primo provider dell'elenco, e sembrava che
  # «OpenRouter fosse lentissimo» mentre stava girando su Ollama con un 24B.
  test)
    PROVE="$(mktemp -d)"
    DEI_IMPOSTAZIONI="$PROVE/impostazioni.json" DEI_LOG="$PROVE/log" \
      "$GODOT" --headless --path "$DIR" -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
    ESITO=$?
    rm -rf "$PROVE"
    exit $ESITO
    ;;
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
