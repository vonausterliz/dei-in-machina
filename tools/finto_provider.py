#!/usr/bin/env python3
"""Provider finto in formato OpenRouter: serve a guardare il tracciato senza spendere token.

Risponde come risponderebbe OpenRouter con DeepSeek: usage completo (cached_tokens,
reasoning_tokens, cost), il campo `provider` con chi ha servito a monte, e una latenza
finta ma verosimile perche' nel consuntivo si veda un colpevole.
"""
import json, time, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

LENTEZZA = {"Omero": 2.0, "Poseidone": 1.2}   # secondi, per agente riconosciuto dal prompt


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        corpo = json.dumps({"data": [{"id": "deepseek/deepseek-chat-v3.1:free"},
                                     {"id": "mistralai/mistral-small-3.2-24b-instruct"}]})
        self._invia(200, corpo, {"x-ratelimit-remaining-requests": "19"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        richiesta = json.loads(self.rfile.read(n) or b"{}")
        testo = json.dumps(richiesta.get("messages", []))
        attesa = 0.05
        for chi, s in LENTEZZA.items():
            if chi.lower() in testo.lower():
                attesa = s
        time.sleep(attesa)

        # IL MODELLO CHE RAGIONA E NON PARLA. E' la risposta vera che ha bloccato una
        # partita: DeepSeek V4 Flash con un tetto di pochi token lo spende tutto a pensare
        # e restituisce `content: null` con `finish_reason: length`. Il gioco lo leggeva
        # come «il modello non risponde» e rifiutava un modello funzionante.
        tetto = richiesta.get("max_tokens")
        if tetto is not None and tetto <= 4:
            corpo = json.dumps({
                "id": "gen-finta-ragiona", "provider": "Parasail",
                "model": richiesta.get("model", "?"),
                "choices": [{"finish_reason": "length", "native_finish_reason": "length",
                             "message": {"role": "assistant", "content": None,
                                         "reasoning": "好的"}}],
                "usage": {"prompt_tokens": 5, "completion_tokens": 1, "total_tokens": 6,
                          "cost": 9.8e-07,
                          "prompt_tokens_details": {"cached_tokens": 0},
                          "completion_tokens_details": {"reasoning_tokens": 2}},
            })
            self._invia(200, corpo, {"x-ratelimit-remaining-requests": "18"})
            return

        corpo = json.dumps({
            "id": "gen-finta-0001",
            "provider": "DeepInfra",
            "model": richiesta.get("model", "?"),
            "choices": [{"finish_reason": "stop",
                         "message": {"role": "assistant", "content": '{"registro":"castigo","intensita":2,"dice":"Pagherai."}'}}],
            "usage": {
                "prompt_tokens": 2043, "completion_tokens": 96, "total_tokens": 2139,
                "prompt_tokens_details": {"cached_tokens": 1780},
                "completion_tokens_details": {"reasoning_tokens": 640},
                "cost": 0.00021,
            },
        })
        self._invia(200, corpo, {"x-ratelimit-remaining-requests": "18"})

    def _invia(self, stato, corpo, extra=None):
        b = corpo.encode()
        self.send_response(stato)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(b)


if __name__ == "__main__":
    # SERVE FINCHE' NON LO SI FERMA. Prima c'era un `time.sleep(120)`: dopo due minuti il
    # processo usciva in silenzio, e lo strumento che gli parla riportava «il provider non
    # risponde» — tre fallimenti che accusavano il codice giusto. Un banco di prova che
    # scade da solo produce diagnosi false, che e' l'esatto contrario del suo mestiere.
    s = HTTPServer(("127.0.0.1", 8899), H)
    print("finto provider su http://127.0.0.1:8899 — Ctrl-C per fermarlo", flush=True)
    try:
        s.serve_forever()
    except KeyboardInterrupt:
        print("\nfermato.")
