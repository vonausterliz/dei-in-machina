#!/usr/bin/env python3
# Dei in machina — Copyright (C) 2026 vonausterliz — GNU AGPL-3.0 (vedi ../LICENSE).
"""Prova che il gateway mandi ogni richiesta AL PROVIDER GIUSTO, o a nessuno.

Perche' esiste. Il gateway ripiegava sul provider predefinito ogni volta che non
riconosceva quello richiesto: con Anthropic scelto nel gioco e non configurato qui, le
chiamate finivano a Mistral. Un errore di configurazione — che si vede e si aggiusta — si
trasformava in risposte di un altro modello, che non si vedono affatto. E' la classe di
guasto peggiore: la risposta sbagliata sembra giusta.

Non serve rete: due provider FINTI in ascolto su localhost registrano chi ha ricevuto cosa,
e con quali intestazioni.

    python3 prova_instradamento.py        # esce 0 se tutto regge
"""

from __future__ import annotations

import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

QUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QUI)

# NESSUN __pycache__. Importare `gateway` fa scrivere a Python un .pyc accanto al sorgente,
# e dentro un .pyc c'e' il PERCORSO ASSOLUTO del file da cui e' stato compilato — cioe' la
# home dell'utente, col suo nome. Una volta e' finito in un commit (`git add -A` dopo aver
# eseguito questa prova) ed e' stato l'unico dato personale rimasto nella cronologia. Il
# .gitignore lo copre, ma la riga giusta e' questa: non generarlo affatto.
sys.dont_write_bytecode = True

import gateway as G  # noqa: E402

# Cosa ha ricevuto ogni provider finto: [(percorso, modello, intestazioni), ...]
RICEVUTO: dict[str, list] = {}
_LOCK = threading.Lock()


class Finto(BaseHTTPRequestHandler):
    nome = "?"

    def log_message(self, *_a):
        pass

    def _registra(self, modello: str) -> None:
        with _LOCK:
            RICEVUTO.setdefault(self.nome, []).append(
                (self.path, modello, {k.lower(): v for k, v in self.headers.items()}))

    def do_POST(self):
        corpo = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        self._registra(str(corpo.get("model", "")))
        r = json.dumps({"choices": [{"message": {"content": self.nome}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(r)))
        self.end_headers()
        self.wfile.write(r)

    def do_GET(self):
        self._registra("")
        r = json.dumps({"data": [{"id": f"modello-di-{self.nome}"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(r)))
        self.end_headers()
        self.wfile.write(r)


def alza_finto(nome: str, porta: int) -> None:
    classe = type(f"Finto_{nome}", (Finto,), {"nome": nome})
    s = ThreadingHTTPServer(("127.0.0.1", porta), classe)
    threading.Thread(target=s.serve_forever, daemon=True).start()


# --- la scena: due provider finti e un gateway davanti a loro ---

PORTA_MISTRAL, PORTA_ANTHROPIC, PORTA_GATEWAY = 8871, 8872, 8873

CONFIG = {
    "throttling_attivo": False,   # qui si misura l'instradamento, non i tempi
    "provider_predefinito": "mistral",
    "cache": {"ttl_s": 0, "massimo": 10},
    "providers": [
        {"nome": "mistral", "base_url": f"http://127.0.0.1:{PORTA_MISTRAL}",
         "chat_path": "/chat", "models_path": "/models", "api_key_env": "PROVA_KEY_MISTRAL"},
        {"nome": "anthropic", "base_url": f"http://127.0.0.1:{PORTA_ANTHROPIC}",
         "chat_path": "/chat", "models_path": "/models", "api_key_env": "PROVA_KEY_ANTHROPIC",
         "intestazioni": {"x-api-key": "$CHIAVE", "anthropic-version": "2023-06-01"}},
    ],
}

ESITI: list[tuple[bool, str]] = []


def verifica(condizione: bool, cosa: str) -> None:
    ESITI.append((bool(condizione), cosa))
    print(("  ✓ " if condizione else "  ✗ ") + cosa)


def chiedi(percorso: str, corpo: dict | None = None) -> tuple[int, dict]:
    url = f"http://127.0.0.1:{PORTA_GATEWAY}{percorso}"
    dati = json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(
        url, data=dati, method="POST" if dati else "GET",
        headers={"Content-Type": "application/json"} if dati else {})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def chi_ha_ricevuto(nome: str) -> list:
    with _LOCK:
        return list(RICEVUTO.get(nome, []))


def main() -> int:
    os.environ["PROVA_KEY_MISTRAL"] = "chiave-mistral"
    os.environ["PROVA_KEY_ANTHROPIC"] = "chiave-anthropic"

    alza_finto("mistral", PORTA_MISTRAL)
    alza_finto("anthropic", PORTA_ANTHROPIC)
    G.Handler.gateway = G.Gateway(CONFIG)
    srv = ThreadingHTTPServer(("127.0.0.1", PORTA_GATEWAY), G.Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    time.sleep(0.3)

    print("\n1. Anthropic passa dal gateway quando glielo si chiede")
    stato, _ = chiedi("/v1/chat/completions?provider=anthropic",
                      {"model": "anthropic/claude-sonnet-5"})
    ric = chi_ha_ricevuto("anthropic")
    verifica(stato == 200, f"la chiamata riesce (HTTP {stato})")
    verifica(len(ric) == 1, "e' arrivata ad Anthropic")
    verifica(not chi_ha_ricevuto("mistral"), "e NON a Mistral")
    if ric:
        _, modello, teste = ric[0]
        verifica(modello == "claude-sonnet-5",
                 f"il prefisso d'instradamento e' stato tolto (model={modello!r})")
        verifica(teste.get("x-api-key") == "chiave-anthropic",
                 "l'intestazione «x-api-key» c'e' (il Bearer da solo darebbe 401 su /models)")
        verifica(teste.get("anthropic-version") == "2023-06-01",
                 "l'intestazione «anthropic-version» c'e'")
        verifica(teste.get("authorization") == "Bearer chiave-anthropic",
                 "e il Bearer resta, per il layer di compatibilita' OpenAI")

    print("\n2. L'elenco dei modelli e' quello di Anthropic, non del predefinito")
    stato, corpo = chiedi("/v1/models?provider=anthropic")
    verifica(stato == 200 and corpo["data"][0]["id"] == "modello-di-anthropic",
             f"elenco da Anthropic (ricevuto: {corpo!r})")

    print("\n3. Il difetto storico: un provider sconosciuto NON diventa Mistral")
    prima = len(chi_ha_ricevuto("mistral"))
    stato, corpo = chiedi("/v1/chat/completions?provider=cohere", {"model": "command-r"})
    verifica(stato == 400, f"risponde con un errore esplicito (HTTP {stato})")
    verifica(len(chi_ha_ricevuto("mistral")) == prima,
             "e nessuno ha risposto al posto suo")
    verifica("cohere" in json.dumps(corpo) and "limiti.json" in json.dumps(corpo),
             "l'errore dice chi mancava e dove aggiungerlo")

    print("\n4. Stessa regola per l'elenco dei modelli")
    stato, corpo = chiedi("/v1/models?provider=cohere")
    verifica(stato == 400, f"niente elenco di un altro provider (HTTP {stato})")

    print("\n5. Il prefisso continua a funzionare per chi non manda la query")
    # Si conta la DIFFERENZA, non il totale: nello stesso registro finiscono anche le GET
    # dell'elenco modelli, e un totale atteso «2» diventerebbe rosso appena si aggiunge un
    # controllo piu' su. Un test che si rompe riordinando i controlli misura se stesso.
    prima = len(chi_ha_ricevuto("anthropic"))
    stato, _ = chiedi("/v1/chat/completions", {"model": "anthropic/claude-opus-5"})
    verifica(stato == 200 and len(chi_ha_ricevuto("anthropic")) == prima + 1,
             "«anthropic/…» instrada ad Anthropic anche senza ?provider=")

    print("\n6. Un nome nudo va al predefinito, come prima")
    prima = len(chi_ha_ricevuto("mistral"))
    stato, _ = chiedi("/v1/chat/completions", {"model": "mistral-small-latest"})
    verifica(stato == 200 and len(chi_ha_ricevuto("mistral")) == prima + 1,
             "nessuna barra, nessuna query: provider predefinito")

    print("\n7. Un prefisso sconosciuto non si confonde con un nome di modello")
    stato, _ = chiedi("/v1/chat/completions", {"model": "mistralai/mistral-small:free"})
    verifica(stato == 400,
             "«mistralai/…» senza provider e' un errore, non un invito a scegliere per conto altrui")

    print("\n8. Il caso spinoso: un modello il cui NOME contiene una barra (OpenRouter)")
    # Qui il prefisso d'instradamento e il nome del modello si somigliano, ed e' il motivo
    # per cui la query string e' l'autorita': «openrouter/mistralai/…» va spezzato una volta
    # sola, e «mistralai/…» deve restare intero.
    prima = len(chi_ha_ricevuto("anthropic"))
    stato, _ = chiedi("/v1/chat/completions?provider=anthropic",
                      {"model": "anthropic/pippo/pluto"})
    ric = chi_ha_ricevuto("anthropic")
    verifica(stato == 200 and len(ric) == prima + 1, "instradato col provider dichiarato")
    verifica(ric and ric[-1][1] == "pippo/pluto",
             f"tolto solo il prefisso, il resto del nome resta intero (model={ric[-1][1]!r})")

    print("\n9. La cache non conserva una risposta inservibile")
    # Un `200` dice che il provider ha fatto il suo lavoro, non che la risposta serva. Una
    # troncata o senza contenuto messa in cache torna identica per un'ora a ogni ritentativo,
    # senza toccare la rete: un modello sano sembra guasto in modo riproducibile, e non se ne
    # esce. Successo davvero — la stessa `gen-1785930448-...` per trentacinque secondi.
    casi = [
        ("normale",             {"finish_reason": "stop",   "message": {"content": "ciao"}},                       True),
        ("troncata",            {"finish_reason": "length", "message": {"content": "ci"}},                         False),
        ("contenuto nullo",     {"finish_reason": "stop",   "message": {"content": None}},                         False),
        ("solo ragionamento",   {"finish_reason": "length", "message": {"content": None, "reasoning": "…"}},        False),
    ]
    for nome, scelta, atteso in casi:
        corpo = json.dumps({"choices": [scelta]}).encode()
        verifica(G._vale_la_pena_ricordarla(corpo) is atteso,
                 f"«{nome}» {'si conserva' if atteso else 'NON si conserva'}")
    verifica(G._vale_la_pena_ricordarla(b'{"choices":[]}') is False,
             "una risposta senza scelte non si conserva")
    verifica(G._vale_la_pena_ricordarla(b"non e' json") is False,
             "un corpo illeggibile non si conserva (nel dubbio si richiede)")

    falliti = [c for ok, c in ESITI if not ok]
    print(f"\n{len(ESITI) - len(falliti)}/{len(ESITI)} controlli passati.")
    if falliti:
        print("FALLITI:")
        for c in falliti:
            print("  ·", c)
        return 1
    print("L'instradamento regge.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
