#!/usr/bin/env bash
# Avvia/ferma il Gateway LLM (coda + throttling + cache + backoff per i piani gratuiti).
# Applicazione SEPARATA dal gioco: nessuna dipendenza, solo python3.
#
#   ./gateway.sh start     avvia in background (log in gateway.log)
#   ./gateway.sh restart   ferma e riavvia
#   ./gateway.sh fg        avvia in primo piano (per vedere il log dal vivo)
#   ./gateway.sh stop      ferma
#   ./gateway.sh stato     quote residue e cache
#   ./gateway.sh libero    avvia SENZA throttling (per un piano a pagamento).
#                          «libero» = senza freni, NON «libera la porta».
#
# LA DOMANDA GIUSTA E' «QUALCUNO ASCOLTA SULLA PORTA?», non «c'e' un pidfile?».
# Prima si guardava solo il pidfile, e le due cose divergono piu' spesso di quanto sembri:
# il gateway avviato con `fg`, o da un'altra copia del progetto, o — il caso vero — il
# pidfile portato via da `sync-mac.sh`, che rsync-a con --delete e non lo escludeva. Da quel
# momento `stop` rispondeva «Non risulta attivo» mentre il processo continuava a tenersi la
# 8800, e `start` falliva per sempre con un traceback di Python. Un comando che dice «non
# attivo» di una cosa attiva e' peggio di uno che non risponde.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTA="${PORTA:-8800}"
PID="${DIR}/gateway.pid"
LOG="${DIR}/gateway.log"

## Il pid di chi ascolta sulla porta, o niente. Tre strumenti perche' nessuno c'e' ovunque:
## lsof su macOS, ss sulle distribuzioni recenti, fuser sulle altre.
chi_ascolta() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti "tcp:${PORTA}" -sTCP:LISTEN 2>/dev/null || true
  elif command -v ss >/dev/null 2>&1; then
    ss -ltnpH 2>/dev/null | awk -v p=":${PORTA}\$" '$4 ~ p' \
      | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true
  elif command -v fuser >/dev/null 2>&1; then
    fuser -n tcp "${PORTA}" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' || true
  fi
}

## E' il NOSTRO gateway? Si guarda la riga di comando: sulla 8800 potrebbe esserci altro, e
## ammazzare il processo di qualcun altro perche' occupa una porta e' un modo per fare danni.
e_nostro() {
  ps -p "$1" -o args= 2>/dev/null | grep -q "gateway.py"
}

ferma_pid() {
  kill "$1" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 0.3
  done
  kill -9 "$1" 2>/dev/null || true
}

## Ferma tutto cio' che e' nostro sulla porta. Ritorna 1 se resta occupata da altri.
ferma() {
  fermati=0
  estranei=""
  if [ -f "${PID}" ]; then
    if kill -0 "$(cat "${PID}")" 2>/dev/null; then
      ferma_pid "$(cat "${PID}")"
      fermati=$((fermati + 1))
    fi
    rm -f "${PID}"
  fi
  for p in $(chi_ascolta); do
    if e_nostro "${p}"; then
      ferma_pid "${p}"
      fermati=$((fermati + 1))
    else
      estranei="${estranei} ${p}"
    fi
  done
  if [ -n "${estranei}" ]; then
    echo "[!] La porta ${PORTA} e' occupata da un processo che NON e' il gateway:${estranei}"
    for p in ${estranei}; do ps -p "${p}" -o pid=,comm= 2>/dev/null || true; done
    echo "    Non lo tocco. Fermalo tu, oppure usa un'altra porta: PORTA=8801 ./gateway.sh start"
    return 1
  fi
  if [ "${fermati}" -gt 0 ]; then
    echo "[ok] Gateway fermato (${fermati} processo/i)."
  else
    echo "[i] Non era attivo, e nessuno occupa la porta ${PORTA}."
  fi
  return 0
}

avvia() {
  extra="${1:-}"
  occupanti="$(chi_ascolta)"
  if [ -n "${occupanti}" ]; then
    for p in ${occupanti}; do
      if e_nostro "${p}"; then
        echo "[i] Gateway gia' attivo (pid ${p}) su http://localhost:${PORTA}"
        echo "    Per riavviarlo: ./gateway.sh restart"
        return 0
      fi
    done
    echo "[!] La porta ${PORTA} e' gia' occupata, ma non dal gateway:"
    for p in ${occupanti}; do ps -p "${p}" -o pid=,comm= 2>/dev/null || true; done
    echo "    Fermalo tu, oppure: PORTA=8801 ./gateway.sh start"
    return 1
  fi
  # shellcheck disable=SC2086
  nohup python3 "${DIR}/gateway.py" --porta "${PORTA}" ${extra} >"${LOG}" 2>&1 &
  echo $! > "${PID}"
  sleep 1
  if kill -0 "$(cat "${PID}")" 2>/dev/null; then
    echo "[ok] Gateway avviato su http://localhost:${PORTA} (log: ${LOG})"
    head -8 "${LOG}" 2>/dev/null || true
    # Un gateway senza chiavi si avvia benissimo e poi rigira 401 a ogni richiesta: meglio
    # dirlo ORA che scoprirlo dal gioco, dove sembra un problema del gioco.
    if grep -q "CHIAVE MANCANTE" "${LOG}" 2>/dev/null; then
      echo "[!] Attenzione: qualche provider e' senza chiave (vedi sopra). Le chiavi le tiene"
      echo "    il GATEWAY, non il gioco: esportale PRIMA di avviarlo, per esempio"
      echo "      export MISTRAL_API_KEY=...  &&  ./gateway.sh restart"
    fi
  else
    echo "[!] Avvio fallito. Log:"
    cat "${LOG}"
    return 1
  fi
}

case "${1:-start}" in
  start)   avvia "" ;;
  libero)  avvia "--senza-throttling" ;;
  restart) ferma; avvia "" ;;
  fg)      exec python3 "${DIR}/gateway.py" --porta "${PORTA}" ;;
  stop)    ferma ;;
  stato)
    curl -fsS "http://localhost:${PORTA}/stato" || echo "[!] Gateway non raggiungibile sulla porta ${PORTA}."
    echo
    ;;
  *)
    echo "Uso: ./gateway.sh [start|restart|stop|stato|fg|libero]"
    echo "  libero = avvia senza throttling (piano a pagamento), non «libera la porta»."
    exit 1
    ;;
esac
