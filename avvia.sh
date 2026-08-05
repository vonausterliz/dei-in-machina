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
#   ./avvia.sh --logdei        # apre la finestra col diario dell'applicazione (eventi ed errori)
#   Aggiungi "-- ollama mistral-small3.2:latest" a 'console' per i dei reali.
#
# Scelta del modello Ollama (senza toccare il config):
#   MODELLO=llama3.1:8b ./avvia.sh     # usa quel modello (preflight + gioco)
#   In gioco puoi anche cambiarlo dal menu a tendina accanto a "Ollama (dei reali)".
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## L'AIUTO E LE OPZIONI, PRIMA DI QUALUNQUE LAVORO.
##
## Stavano in fondo, dopo l'importazione del progetto: `./avvia.sh --help` impiegava
## QUATTRO SECONDI E MEZZO — due passate di `godot --import` — per stampare venti righe di
## testo. E un'opzione scritta male le pagava tutte prima di essere rifiutata.
##
## Chi chiede aiuto o sbaglia a scrivere dev'essere servito subito: qui non serve Godot, non
## serve il progetto, non serve niente. Le uniche righe che devono precedere sono quelle che
## dicono DOVE siamo.
mostra_uso() {
  cat <<'AIUTO'
Uso: ./avvia.sh [modo] [opzioni]

Modi:
  gui              la finestra di gioco (predefinito, si puo' omettere)
  console          il gioco nel terminale, senza finestra
  test             esegue i test
  musica           rigenera la musica della schermata d'apertura
  installa-menu    mette il gioco nel menu applicazioni col suo nome

Opzioni (si possono combinare con qualunque modo):
  --debugllm       finestra col tracciato delle chiamate al modello: per ogni chiamata
                   agente, latenza, token, errori. Serve a scoprire QUALE e' lenta.
  --tracellm       come sopra, piu' il dettaglio HTTP di ogni richiesta e risposta —
                   verbo, indirizzo, intestazioni, corpo. Serve a scoprire PERCHE'.
                   Implica --debugllm. Le credenziali restano oscurate.
  --logdei         finestra col diario dell'applicazione: cosa fa il gioco e cosa gli
                   va storto (avvio, preferenze, partita, motore, audio, guai).

I tracciati si scrivono SEMPRE su file, in user://log/, anche senza queste opzioni:
le finestre sono solo una vetrina su quel flusso.

Esempi:
  ./avvia.sh --tracellm
  ./avvia.sh console --debugllm
  MODELLO=llama3.1:8b ./avvia.sh
AIUTO
}

# LE OPZIONI SI TOLGONO DI MEZZO PRIMA, e i modi restano.
#
# Qui c'era `for a in "$@"; do ... shift ... done`, che e' rotto in un modo silenzioso: il
# ciclo scorre una COPIA degli argomenti mentre `shift` modifica quelli veri, e i due si
# disallineano. Con una sola opzione funzionava per caso; `./avvia.sh console --debugllm`
# no — lo shift si mangiava «console», MODE diventava «--debugllm», e il launcher rispondeva
# col messaggio d'uso come se non si fosse capito niente. Non si poteva combinare un modo
# con un'opzione, e nessuno l'aveva mai provato.
#
# Le grafie si accettano tutte, singolo trattino compreso: e' un launcher, non un compilatore,
# e far fallire un avvio per un trattino e' una scortesia gratuita.
ARGOMENTI=()
while [ $# -gt 0 ]; do
  case "$1" in
    --debugllm|-debugllm)              export DEI_DEBUG_LLM=1 ;;
    --tracellm|-tracellm)              export DEI_DEBUG_LLM=1; export DEI_TRACE_LLM=1 ;;
    --logdei|-logdei|--logDei|-logDei|--logDEI) export DEI_LOG_APP=1 ;;
    -h|--help|-help|aiuto)             mostra_uso; exit 0 ;;
    --) shift; ARGOMENTI+=("$@"); break ;;   # tutto il resto va al gioco, non a noi
    -*)
      # Un'opzione che non conosciamo NON diventa un modo. Prima ci diventava, e il
      # messaggio d'errore parlava dei modi: si cercava il refuso nel posto sbagliato.
      echo "Opzione sconosciuta: $1" >&2
      echo >&2
      mostra_uso >&2
      exit 1 ;;
    *) ARGOMENTI+=("$1") ;;
  esac
  shift
done
set -- "${ARGOMENTI[@]+"${ARGOMENTI[@]}"}"
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
# IL PROVIDER SCELTO L'ULTIMA VOLTA, letto dalle preferenze dell'utente.
#
# Serve a una domanda sola: vale la pena scaldare Ollama? Le preferenze stanno sotto la
# cartella dati dell'utente, che cambia con il sistema. Se non si riesce a leggerle si
# ritorna vuoto, e chi chiama si comporta come prima — nel dubbio si scalda.
_provider_scelto() {
  local base
  case "$(uname -s)" in
    Darwin) base="$HOME/Library/Application Support/Godot/app_userdata" ;;
    *)      base="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata" ;;
  esac
  grep -o '"provider_nome"[[:space:]]*:[[:space:]]*"[^"]*"' \
    "$base/Dei in machina/impostazioni.json" 2>/dev/null \
    | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'
}

ollama_preflight() {
  local url="http://localhost:11434" model base scelto
  # SI SCALDA OLLAMA SOLO SE SI GIOCHERA' CON OLLAMA.
  #
  # Girava sempre: con OpenRouter selezionato, il launcher avviava il server locale e
  # caricava in RAM un modello da 24 miliardi di parametri che nessuno avrebbe interrogato —
  # e lo annunciava pure, due righe di «[ok] Ollama pronto» in cima a una partita che sarebbe
  # andata tutta in rete. Rumore che somiglia a un'informazione, e qualche gigabyte di RAM.
  #
  # Se le preferenze non si leggono (primo avvio, percorso inatteso) si scalda comunque: il
  # caso in cui non si sa e' quello in cui conviene fare la cosa di prima.
  scelto="$(_provider_scelto)"
  if [ -n "${scelto}" ] && [ "${scelto}" != "Ollama locale" ]; then
    echo "[i] Provider scelto: ${scelto}. Non scaldo Ollama (serve solo se giochi in locale)."
    return 0
  fi
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
# --logdei apre invece la finestra del DIARIO DELL'APPLICAZIONE: cosa fa il gioco e cosa gli
# va storto — l'avvio, le preferenze rilette, la partita caricata, il motore, l'audio, i guai.
# E' un log separato da quello del modello perche' risponde a una domanda diversa, e cercare
# «perche' non ho la musica» in mezzo a settemila righe di prompt e' peggio che non cercarla.
# Anche questo si scrive SEMPRE su file, in user://log/app-*.log.

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
  *)       echo "Modo sconosciuto: $MODE" >&2; echo >&2; mostra_uso >&2; exit 1 ;;
esac
