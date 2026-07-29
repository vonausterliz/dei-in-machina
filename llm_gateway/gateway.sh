#!/usr/bin/env bash
# Avvia/ferma il Gateway LLM (coda + throttling + cache + backoff per i piani gratuiti).
# Applicazione SEPARATA dal gioco: nessuna dipendenza, solo python3.
#
#   ./gateway.sh start    avvia in background (log in gateway.log)
#   ./gateway.sh fg       avvia in primo piano (per vedere il log dal vivo)
#   ./gateway.sh stop     ferma
#   ./gateway.sh stato    quote residue e cache
#   ./gateway.sh libero   avvia SENZA throttling (piano a pagamento)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTA="${PORTA:-8800}"
PID="${DIR}/gateway.pid"
LOG="${DIR}/gateway.log"

case "${1:-start}" in
  start|libero)
    if [ -f "${PID}" ] && kill -0 "$(cat "${PID}")" 2>/dev/null; then
      echo "[i] Gateway gia' attivo (pid $(cat "${PID}")) su http://localhost:${PORTA}"; exit 0
    fi
    EXTRA=""; [ "${1:-}" = "libero" ] && EXTRA="--senza-throttling"
    # shellcheck disable=SC2086
    nohup python3 "${DIR}/gateway.py" --porta "${PORTA}" ${EXTRA} >"${LOG}" 2>&1 &
    echo $! > "${PID}"
    sleep 1
    if kill -0 "$(cat "${PID}")" 2>/dev/null; then
      echo "[ok] Gateway avviato su http://localhost:${PORTA} (log: ${LOG})"
      head -6 "${LOG}" 2>/dev/null || true
    else
      echo "[!] Avvio fallito. Log:"; cat "${LOG}"; exit 1
    fi
    ;;
  fg)
    exec python3 "${DIR}/gateway.py" --porta "${PORTA}"
    ;;
  stop)
    if [ -f "${PID}" ]; then
      kill "$(cat "${PID}")" 2>/dev/null || true
      rm -f "${PID}"
      echo "[ok] Gateway fermato."
    else
      echo "[i] Non risulta attivo."
    fi
    ;;
  stato)
    curl -fsS "http://localhost:${PORTA}/stato" || echo "[!] Gateway non raggiungibile sulla porta ${PORTA}."
    echo
    ;;
  *)
    echo "Uso: ./gateway.sh [start|fg|stop|stato|libero]"; exit 1
    ;;
esac
