#!/usr/bin/env bash
# Dei in machina — Copyright (C) 2026 vonausterliz — GNU AGPL-3.0 (vedi ../LICENSE).
#
# PROVA L'ANALISI DELLE OPZIONI DI avvia.sh, senza avviare il gioco.
#
# Perche' esiste. `./avvia.sh console --debugllm` non funzionava: l'analisi usava
# `for a in "$@"; do ... shift ... done`, che scorre una COPIA degli argomenti mentre
# `shift` modifica quelli veri. I due si disallineano, lo shift si mangiava «console», e
# MODE diventava «--debugllm». Con una sola opzione funzionava per caso — ed e' l'unico
# modo in cui era stato provato.
#
# Un launcher non ha test perche' «e' solo uno script»: e questo e' il punto in cui ogni
# sessione di gioco comincia. Qui si sostituisce l'ultima riga (quella che esegue Godot)
# con un'eco, cosi' si vede cosa sarebbe stato eseguito senza eseguirlo.
#
#     ./tools/prova_avvio_sh.sh        # esce 0 se tutto regge

set -uo pipefail
QUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANCO="$(mktemp -d)"
# IL TRAP DI PULIZIA SI ESEGUE ANCHE NELLE SUBSHELL, e questo lo rendeva un distruttore.
#
# `$( ... )` crea una subshell che EREDITA i trap: ogni volta che il banco veniva eseguito
# dentro una sostituzione di comando, all'uscita della subshell scattava `rm -rf "$BANCO"`
# e la cartella spariva — a meta' della prova, con i casi successivi che chiamavano un file
# non piu' esistente. Il sintomo era uno script che si piantava senza dire niente, e la
# causa era la pulizia che si mangiava la cosa da provare.
#
# Si confronta il PID: `$$` resta quello della shell principale anche nelle subshell,
# `$BASHPID` no. Solo chi ha creato la cartella la toglie.
PRINCIPALE=$$
trap '[ "$BASHPID" = "$PRINCIPALE" ] && rm -rf "$BANCO"' EXIT

# Una copia di avvia.sh che si ferma appena ha deciso modo e variabili d'ambiente: tutto
# cio' che viene dopo (scaricare Godot, eseguirlo) qui non interessa e costerebbe minuti.
#
# `DIR` va inchiodato al progetto VERO. Lo script lo ricava da `BASH_SOURCE`, e la copia
# vive altrove: senza questo, il banco di prova non trovava `tools/godot/` e si metteva a
# SCARICARE GODOT — centoquaranta megabyte per provare come si legge un trattino. Un banco
# di prova che ricrea l'ambiente sbagliato misura l'ambiente sbagliato.
sed -e "s|^DIR=.*|DIR=\"$QUI\"|" \
    -e 's|^MODE="${1:-gui}"|MODE="${1:-gui}"\
echo "MODE=$MODE DEBUG=${DEI_DEBUG_LLM:-0} TRACE=${DEI_TRACE_LLM:-0} APP=${DEI_LOG_APP:-0}"\
exit 0|' "$QUI/avvia.sh" > "$BANCO/avvia.sh"
chmod +x "$BANCO/avvia.sh"
# …e si controlla che l'innesto sia andato a segno, invece di fidarsi. Una `sed` che non
# aggancia niente non lo dice: lo script resterebbe quello vero, e il primo caso di prova
# avvierebbe il gioco.
grep -q '^exit 0$' "$BANCO/avvia.sh" || { echo "il banco di prova non si e' innestato: avvia.sh e' cambiato?" >&2; exit 2; }

ESITI=0
FALLITI=0

# atteso: la riga che avvia.sh deve stampare. "" = ci si aspetta un fallimento (uscita != 0).
prova() {
  local atteso="$1"; shift
  local ottenuto
  ottenuto="$("$BANCO/avvia.sh" "$@" 2>/dev/null)"
  local uscita=$?
  ESITI=$((ESITI + 1))
  if [ -z "$atteso" ]; then
    if [ "$uscita" -eq 0 ]; then
      echo "  ✗ './avvia.sh $*' doveva fallire, invece: $ottenuto"; FALLITI=$((FALLITI + 1))
    else
      echo "  ✓ './avvia.sh $*' rifiutato, come dev'essere"
    fi
    return
  fi
  if [ "$ottenuto" = "$atteso" ]; then
    echo "  ✓ ./avvia.sh $*"
  else
    echo "  ✗ ./avvia.sh $*"
    echo "      atteso:   $atteso"
    echo "      ottenuto: ${ottenuto:-<niente> (uscita $uscita)}"
    FALLITI=$((FALLITI + 1))
  fi
}

echo
echo "1. I modi da soli"
prova "MODE=gui DEBUG=0 TRACE=0 APP=0"
prova "MODE=console DEBUG=0 TRACE=0 APP=0" console
prova "MODE=test DEBUG=0 TRACE=0 APP=0" test

echo
echo "2. Le opzioni da sole (il modo resta quello predefinito)"
prova "MODE=gui DEBUG=1 TRACE=0 APP=0" --debugllm
prova "MODE=gui DEBUG=1 TRACE=1 APP=0" --tracellm     # --tracellm implica --debugllm
prova "MODE=gui DEBUG=0 TRACE=0 APP=1" --logdei

echo
echo "3. Modo E opzione insieme — e' quello che non funzionava"
prova "MODE=console DEBUG=1 TRACE=0 APP=0" console --debugllm
prova "MODE=console DEBUG=1 TRACE=0 APP=0" --debugllm console   # in ordine inverso
prova "MODE=test DEBUG=0 TRACE=0 APP=1" --logdei test

echo
echo "4. Piu' opzioni insieme"
prova "MODE=gui DEBUG=1 TRACE=1 APP=1" --tracellm --logdei
prova "MODE=console DEBUG=1 TRACE=1 APP=1" console --tracellm --logdei

echo
echo "5. Il trattino singolo si perdona"
prova "MODE=gui DEBUG=1 TRACE=1 APP=0" -tracellm
prova "MODE=gui DEBUG=0 TRACE=0 APP=1" -logdei

echo
echo "6. Un'opzione sconosciuta si rifiuta, invece di diventare un modo"
prova "" --pippo
prova "" -x

echo
echo "7. E un modo sconosciuto si rifiuta dicendo che e' un MODO"
# Questo si prova sullo script VERO: il banco si ferma prima del `case` che sceglie il modo,
# quindi li' un modo sbagliato passerebbe sempre. Provarlo sul banco vorrebbe dire misurare
# il banco. Sullo script vero costa niente — si ferma subito, senza avviare Godot.
ESITI=$((ESITI + 1))
uscita_vera=0
messaggio="$("$QUI/avvia.sh" modo-inesistente 2>&1)" || uscita_vera=$?
if [ "$uscita_vera" -ne 0 ] && printf '%s' "$messaggio" | grep -q "Modo sconosciuto"; then
  echo "  ✓ './avvia.sh modo-inesistente' rifiutato, e dice che il problema e' il modo"
else
  echo "  ✗ './avvia.sh modo-inesistente': uscita $uscita_vera — $messaggio"
  FALLITI=$((FALLITI + 1))
fi

echo
echo "8. L'aiuto esiste, e nomina le opzioni che prima non nominava"
for atteso in "--debugllm" "--tracellm" "--logdei" "console --debugllm"; do
  ESITI=$((ESITI + 1))
  if "$QUI/avvia.sh" --help 2>&1 | grep -q -- "$atteso"; then
    echo "  ✓ l'aiuto parla di «$atteso»"
  else
    echo "  ✗ l'aiuto NON nomina «$atteso»"; FALLITI=$((FALLITI + 1))
  fi
done

echo
echo "9. Ollama si scalda solo se si giochera' con Ollama"
# Le due funzioni si estraggono da avvia.sh e si eseguono con un HOME finto: cosi' si prova
# il codice VERO, non una sua copia riscritta qui — che e' il modo classico di avere un test
# verde su una funzione rotta.
#
# `ollama_preflight` si puo' chiamare per intero solo nel caso in cui deve FERMARSI: se
# proseguisse cercherebbe il server locale davvero. Il caso opposto si prova sulla lettura.
estratte="$(sed -n '/^_provider_scelto() {/,/^}/p;/^ollama_preflight() {/,/^}/p' "$QUI/avvia.sh")"
CASA="$BANCO/casa"
mkdir -p "$CASA/.local/share/godot/app_userdata/Dei in machina"
CONFIG="$CASA/.local/share/godot/app_userdata/Dei in machina/impostazioni.json"

legge() {  # legge <contenuto-del-file-o-vuoto> -> stampa il provider letto
  if [ -z "$1" ]; then rm -f "$CONFIG"; else printf '%s' "$1" > "$CONFIG"; fi
  HOME="$CASA" XDG_DATA_HOME="$CASA/.local/share" \
    bash -c "$estratte"$'\n_provider_scelto' 2>/dev/null
}

controlla() {  # controlla <descrizione> <atteso> <ottenuto>
  ESITI=$((ESITI + 1))
  if [ "$3" = "$2" ]; then
    echo "  ✓ $1"
  else
    echo "  ✗ $1"; echo "      atteso:   $2"; echo "      ottenuto: $3"; FALLITI=$((FALLITI + 1))
  fi
}

controlla "legge «OpenRouter» dalle preferenze" "OpenRouter" \
  "$(legge '{"provider_nome": "OpenRouter", "modello": "x"}')"
controlla "legge «Ollama locale» dalle preferenze" "Ollama locale" \
  "$(legge '{"provider_nome":"Ollama locale"}')"
controlla "senza file di preferenze non dice niente (e allora si scalda)" "" "$(legge '')"

# E il cancello vero: col provider remoto scelto, il preflight si ferma e lo dice.
#
# Col guinzaglio. Sabotando il cancello (`if false; then`) per verificare che questo controllo
# lo veda, il preflight ha fatto cio' che fa sempre quando prosegue — cercare il server locale,
# provare ad avviarlo — e la prova si e' PIANTATA invece di fallire. Un test che, quando la
# cosa provata si rompe, si blocca senza dire niente non e' un test.
printf '%s' '{"provider_nome": "OpenRouter"}' > "$CONFIG"
GUINZAGLIO=(); command -v timeout >/dev/null 2>&1 && GUINZAGLIO=(timeout 15)
uscita_pf=0
detto="$(HOME="$CASA" XDG_DATA_HOME="$CASA/.local/share" \
  "${GUINZAGLIO[@]}" bash -c "$estratte"$'\nollama_preflight' </dev/null 2>&1)" || uscita_pf=$?
ESITI=$((ESITI + 1))
if [ "$uscita_pf" -eq 0 ] && printf '%s' "$detto" | grep -q "Non scaldo Ollama"; then
  echo "  ✓ col provider remoto scelto, il preflight si ferma e lo dice"
else
  echo "  ✗ col provider remoto scelto il preflight NON si e' fermato: $detto"
  FALLITI=$((FALLITI + 1))
fi

echo
if [ "$FALLITI" -eq 0 ]; then
  echo "$ESITI/$ESITI controlli passati. Il launcher regge."
  exit 0
fi
echo "$((ESITI - FALLITI))/$ESITI passati, $FALLITI FALLITI."
exit 1
