#!/usr/bin/env python3
# Dei in machina — Copyright (C) 2026 vonausterliz — GNU AGPL-3.0 (vedi ../LICENSE).
"""Gateway LLM: coda, throttling, cache e backoff davanti ai provider free tier.

E' un'APPLICAZIONE SEPARATA dal gioco: parla il protocollo OpenAI
(/v1/chat/completions), quindi il gioco ci punta cambiando solo base_url. Tutta la
logica dei limiti del piano gratuito vive qui: per toglierla basta ripuntare il gioco
al provider e spegnere il gateway. Nessuna dipendenza esterna: solo stdlib.

Cosa fa, in ordine, per ogni richiesta:
  1. CACHE      - se lo stesso payload e' gia' stato chiesto di recente, risponde subito
                  (nessuna chiamata, nessun consumo di quota);
  2. CODA       - una coda FIFO per provider, servita da un solo worker: le richieste non
                  partono mai in parallelo verso lo stesso provider;
  3. THROTTLING - rispetta insieme l'intervallo minimo tra richieste (es. 1/s), il tetto
                  al minuto (RPM) e quello al giorno (RPD);
  4. BACKOFF    - su 429 / 5xx ritenta con attesa esponenziale (1s, 2s, 4s...), leggendo
                  Retry-After quando c'e'.

Uso:  python3 gateway.py [--porta 8800] [--config limiti.json]
Stato: GET /stato  ->  code, quote residue, cache hit.
"""

from __future__ import annotations

import hashlib
import json
import os
import queue
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

QUI = os.path.dirname(os.path.abspath(__file__))


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


class Limitatore:
    """Throttling di un singolo provider: intervallo minimo + RPM + RPD.

    attendi() blocca finche' non e' lecito partire. Chiamato solo dal worker del
    provider, quindi non serve altro lock oltre a quello interno.
    """

    def __init__(self, cfg: dict) -> None:
        self.nome = cfg["nome"]
        self.min_intervallo = float(cfg.get("min_intervallo_s", 0))
        self.rpm = int(cfg.get("rpm", 0))          # 0 = nessun tetto al minuto
        self.rpd = int(cfg.get("rpd", 0))          # 0 = nessun tetto al giorno
        self._ultimo = 0.0
        self._minuto: deque[float] = deque()       # timestamp ultimi 60 s
        self._giorno: deque[float] = deque()       # timestamp ultime 24 h
        self._lock = threading.Lock()

    def _pota(self, ora: float) -> None:
        while self._minuto and ora - self._minuto[0] > 60:
            self._minuto.popleft()
        while self._giorno and ora - self._giorno[0] > 86400:
            self._giorno.popleft()

    def attendi(self) -> None:
        while True:
            with self._lock:
                ora = time.time()
                self._pota(ora)
                attesa = 0.0
                # 1) intervallo minimo tra due richieste (il limite di VELOCITA')
                if self.min_intervallo > 0:
                    attesa = max(attesa, self._ultimo + self.min_intervallo - ora)
                # 2) tetto al minuto: aspetto che scada la piu' vecchia della finestra
                if self.rpm and len(self._minuto) >= self.rpm:
                    attesa = max(attesa, self._minuto[0] + 60 - ora)
                # 3) tetto al giorno
                if self.rpd and len(self._giorno) >= self.rpd:
                    attesa = max(attesa, self._giorno[0] + 86400 - ora)
                if attesa <= 0:
                    self._ultimo = ora
                    self._minuto.append(ora)
                    self._giorno.append(ora)
                    return
            if attesa > 2:
                log(f"  ⏳ {self.nome}: quota, attendo {attesa:.0f}s")
            time.sleep(min(attesa, 5))

    def stato(self) -> dict:
        with self._lock:
            ora = time.time()
            self._pota(ora)
            return {
                "min_intervallo_s": self.min_intervallo,
                "rpm": self.rpm,
                "usate_ultimo_minuto": len(self._minuto),
                "rpd": self.rpd,
                "usate_oggi": len(self._giorno),
            }


class Cache:
    """Cache aggressiva delle risposte: chiave = hash del payload inviato.

    Utile soprattutto quando lo stesso identico prompt viene rifatto (retry del gioco,
    rigenerazioni, sviluppo): risparmia quota e restituisce all'istante.
    """

    def __init__(self, ttl_s: int, massimo: int) -> None:
        self.ttl = ttl_s
        self.massimo = massimo
        self._d: dict[str, tuple[float, bytes]] = {}
        self._lock = threading.Lock()
        self.colpi = 0
        self.mancati = 0

    @staticmethod
    def chiave(provider: str, payload: dict) -> str:
        # La temperatura fa parte della chiave: risposte a temperature diverse restano distinte.
        grezzo = json.dumps({"p": provider, "b": payload}, sort_keys=True, ensure_ascii=False)
        return hashlib.sha256(grezzo.encode("utf-8")).hexdigest()

    def leggi(self, k: str):
        if self.ttl <= 0:
            return None
        with self._lock:
            v = self._d.get(k)
            if not v:
                self.mancati += 1
                return None
            scadenza, corpo = v
            if time.time() > scadenza:
                del self._d[k]
                self.mancati += 1
                return None
            self.colpi += 1
            return corpo

    def scrivi(self, k: str, corpo: bytes) -> None:
        if self.ttl <= 0:
            return
        with self._lock:
            if len(self._d) >= self.massimo:
                # sfratto il piu' vicino alla scadenza
                piu_vecchio = min(self._d, key=lambda x: self._d[x][0])
                del self._d[piu_vecchio]
            self._d[k] = (time.time() + self.ttl, corpo)


class Provider:
    """Un provider a monte, con la sua coda e il suo worker (uno solo: niente parallelo)."""

    def __init__(self, cfg: dict, cache: Cache, throttling: bool) -> None:
        self.cfg = cfg
        self.nome = cfg["nome"]
        self.base_url = cfg["base_url"].rstrip("/")
        self.chat_path = cfg.get("chat_path", "/v1/chat/completions")
        self.models_path = cfg.get("models_path", "/v1/models")
        self.api_key = os.environ.get(cfg.get("api_key_env", ""), "")
        self.tentativi = int(cfg.get("tentativi", 5))
        self.timeout = float(cfg.get("timeout_s", 180))
        self.limitatore = Limitatore(cfg)
        self.cache = cache
        self.throttling = throttling
        self.coda: queue.Queue = queue.Queue()
        threading.Thread(target=self._servi, daemon=True).start()

    # --- worker: serve la coda UNA richiesta alla volta (niente parallelo sul provider) ---
    def _servi(self) -> None:
        while True:
            lavoro = self.coda.get()
            try:
                if self.throttling:
                    self.limitatore.attendi()
                in_coda = time.time() - lavoro["arrivo"]
                if in_coda > 1:
                    log(f"  ⏱  {self.nome}: partita dopo {in_coda:.1f}s in coda")
                lavoro["esito"] = self._inoltra(lavoro["payload"])
            except Exception as e:  # il worker non deve mai morire
                lavoro["esito"] = (502, json.dumps({"error": {"message": f"gateway: {e}"}}).encode())
            finally:
                lavoro["pronto"].set()
                self.coda.task_done()

    def _inoltra(self, payload: dict) -> tuple[int, bytes]:
        """Chiama il provider con backoff esponenziale su 429/5xx."""
        url = self.base_url + self.chat_path
        dati = json.dumps(payload).encode("utf-8")
        intestazioni = {"Content-Type": "application/json"}
        if self.api_key:
            intestazioni["Authorization"] = f"Bearer {self.api_key}"

        attesa = 1.0
        for tentativo in range(1, self.tentativi + 1):
            req = urllib.request.Request(url, data=dati, headers=intestazioni, method="POST")
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as r:
                    return r.status, r.read()
            except urllib.error.HTTPError as e:
                corpo = e.read()
                if e.code == 429 or 500 <= e.code < 600:
                    if tentativo == self.tentativi:
                        log(f"  ✗ {self.nome}: HTTP {e.code}, tentativi esauriti")
                        return e.code, corpo
                    # Retry-After ha la precedenza sul nostro backoff
                    ra = e.headers.get("Retry-After") if e.headers else None
                    pausa = float(ra) if (ra or "").replace(".", "", 1).isdigit() else attesa
                    log(f"  ↻ {self.nome}: HTTP {e.code}, riprovo tra {pausa:.0f}s ({tentativo}/{self.tentativi})")
                    time.sleep(pausa)
                    attesa = min(attesa * 2, 60)
                    continue
                return e.code, corpo  # 4xx non recuperabile: passa com'e'
            except Exception as e:
                if tentativo == self.tentativi:
                    return 502, json.dumps({"error": {"message": str(e)}}).encode()
                time.sleep(attesa)
                attesa = min(attesa * 2, 60)
        return 502, b'{"error":{"message":"gateway: tentativi esauriti"}}'

    # --- API usata dall'handler HTTP ---
    ## Ritorna (stato, corpo, da_cache). Mette in coda e aspetta il proprio turno.
    def chat(self, payload: dict) -> tuple[int, bytes, bool]:
        k = Cache.chiave(self.nome, payload)
        colpo = self.cache.leggi(k)
        if colpo is not None:
            return 200, colpo, True
        lavoro = {"payload": payload, "esito": None, "pronto": threading.Event(), "arrivo": time.time()}
        self.coda.put(lavoro)
        lavoro["pronto"].wait()
        stato, corpo = lavoro["esito"]
        if stato == 200:
            self.cache.scrivi(k, corpo)
        return stato, corpo, False

    def modelli(self) -> tuple[int, bytes]:
        url = self.base_url + self.models_path
        intestazioni = {}
        if self.api_key:
            intestazioni["Authorization"] = f"Bearer {self.api_key}"
        try:
            req = urllib.request.Request(url, headers=intestazioni, method="GET")
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.read()
        except Exception as e:
            return 502, json.dumps({"error": {"message": str(e)}}).encode()


class Gateway:
    def __init__(self, cfg: dict) -> None:
        self.throttling = bool(cfg.get("throttling_attivo", True))
        c = cfg.get("cache", {})
        self.cache = Cache(int(c.get("ttl_s", 3600)), int(c.get("massimo", 500)))
        self.providers: dict[str, Provider] = {}
        for p in cfg["providers"]:
            self.providers[p["nome"]] = Provider(p, self.cache, self.throttling)
        self.predefinito = cfg.get("provider_predefinito", cfg["providers"][0]["nome"])
        # Modelli che rientrano nel piano gratuito: serve solo ad AVVISARE, non blocca.
        self.gratuiti: dict = cfg.get("modelli_gratuiti", {})
        self._gia_avvisati: set = set()

    def avvisa_se_a_pagamento(self, provider: str, modello: str) -> None:
        elenco = self.gratuiti.get(provider)
        if not elenco:
            return
        base = modello.split(":")[0]
        if any(base == m or base.startswith(m) for m in elenco):
            return
        chiave = f"{provider}/{base}"
        if chiave in self._gia_avvisati:
            return
        self._gia_avvisati.add(chiave)
        log(f"  ⚠ ATTENZIONE: «{modello}» non e' tra i modelli del piano gratuito di "
            f"{provider} ({', '.join(elenco)}). Potrebbe essere a pagamento.")

    def scegli(self, modello: str) -> tuple[Provider, str]:
        """«mistral/mistral-small-latest» -> (provider mistral, «mistral-small-latest»).

        Senza prefisso si usa il provider predefinito: cosi' il gioco puo' mandare il
        nome del modello cosi' com'e'.
        """
        if "/" in modello:
            pref, resto = modello.split("/", 1)
            if pref in self.providers:
                return self.providers[pref], resto
        return self.providers[self.predefinito], modello

    def stato(self) -> dict:
        return {
            "throttling_attivo": self.throttling,
            "cache": {"colpi": self.cache.colpi, "mancati": self.cache.mancati, "ttl_s": self.cache.ttl},
            # CHI HA LA CHIAVE. Il gateway la legge dal proprio ambiente UNA VOLTA, all'avvio:
            # averla nella shell adesso non conta se il processo e' partito prima. Senza, il
            # gateway chiama il provider senza Authorization, il provider risponde 401, e dal
            # gioco sembra che sia il gioco a non avere la chiave. Esposta qui perche' il
            # gioco possa dirlo in chiaro invece di lasciarlo dedurre da un 401.
            "providers": {n: dict(p.limitatore.stato(), chiave=bool(p.api_key))
                          for n, p in self.providers.items()},
        }


class Handler(BaseHTTPRequestHandler):
    gateway: Gateway = None  # iniettato all'avvio

    def log_message(self, *_a):  # silenzio: logghiamo noi
        pass

    def _rispondi(self, stato: int, corpo: bytes, tipo: str = "application/json") -> None:
        self.send_response(stato)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def do_GET(self):
        if self.path.rstrip("/") in ("/stato", "/v1/stato"):
            self._rispondi(200, json.dumps(self.gateway.stato(), indent=2, ensure_ascii=False).encode())
            return
        percorso, _, query = self.path.partition("?")
        if percorso.rstrip("/").endswith("/models"):
            # QUALE provider. Prima si rispondeva SEMPRE col predefinito, qualunque cosa
            # avesse scelto il gioco: con Mistral (che e' il predefinito) andava bene per
            # caso, con Google si ottenevano i modelli di Mistral etichettati come suoi —
            # la risposta di un altro, che e' il difetto peggiore perche' sembra giusta.
            # Il gioco lo dice in query string; senza, si ripiega sul predefinito come prima.
            voluto = urllib.parse.parse_qs(query).get("provider", [""])[0]
            nome = voluto if voluto in self.gateway.providers else self.gateway.predefinito
            if voluto and voluto not in self.gateway.providers:
                log(f"  ⚠ elenco modelli chiesto per «{voluto}», che non conosco: "
                    f"rispondo con {nome}. Aggiungilo a limiti.json.")
            stato, corpo = self.gateway.providers[nome].modelli()
            self._rispondi(stato, corpo)
            return
        self._rispondi(404, b'{"error":{"message":"non trovato"}}')

    def do_POST(self):
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self._rispondi(404, b'{"error":{"message":"non trovato"}}')
            return
        lunghezza = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(lunghezza) or b"{}")
        except json.JSONDecodeError:
            self._rispondi(400, b'{"error":{"message":"JSON non valido"}}')
            return

        provider, modello = self.gateway.scegli(str(payload.get("model", "")))
        self.gateway.avvisa_se_a_pagamento(provider.nome, modello)
        payload["model"] = modello
        t0 = time.time()
        stato, corpo, da_cache = provider.chat(payload)
        etichetta = "cache" if da_cache else f"{time.time() - t0:.1f}s"
        log(f"{provider.nome}/{modello} -> HTTP {stato} ({etichetta})")
        self._rispondi(stato, corpo)


def carica_config(percorso: str) -> dict:
    with open(percorso, encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    porta = 8800
    percorso_cfg = os.path.join(QUI, "limiti.json")
    argomenti = sys.argv[1:]
    for i, a in enumerate(argomenti):
        if a in ("--porta", "-p") and i + 1 < len(argomenti):
            porta = int(argomenti[i + 1])
        elif a in ("--config", "-c") and i + 1 < len(argomenti):
            percorso_cfg = argomenti[i + 1]
        elif a in ("--senza-throttling",):
            os.environ["GATEWAY_SENZA_THROTTLING"] = "1"

    cfg = carica_config(percorso_cfg)
    if os.environ.get("GATEWAY_SENZA_THROTTLING") == "1":
        cfg["throttling_attivo"] = False

    Handler.gateway = Gateway(cfg)
    stato = "ATTIVO" if Handler.gateway.throttling else "DISATTIVATO"
    log(f"Gateway LLM su http://localhost:{porta}  ·  throttling {stato}")
    for nome, p in Handler.gateway.providers.items():
        chiave = "chiave OK" if p.api_key else "CHIAVE MANCANTE"
        log(f"  · {nome}: {p.base_url} ({chiave}) "
            f"min {p.limitatore.min_intervallo}s, {p.limitatore.rpm}/min, {p.limitatore.rpd}/giorno")
    log("  Punta il gioco a questo indirizzo. Stato: curl localhost:%d/stato" % porta)
    try:
        ThreadingHTTPServer(("127.0.0.1", porta), Handler).serve_forever()
    except KeyboardInterrupt:
        log("Gateway fermato.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
