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

# Nelle intestazioni extra di un provider, questo valore viene sostituito con la chiave API
# vera. E' la stessa convenzione dei profili del gioco (config/providers/*.json): i due file
# si leggono allo stesso modo, e chi aggiunge un provider non impara due grammatiche.
SEGNAPOSTO_CHIAVE = "$CHIAVE"


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


class ProviderIgnoto(Exception):
    """Ci e' stato chiesto un provider che non conosciamo.

    NON si ripiega su un altro. Prima si ripiegava sul predefinito, ed e' il difetto
    peggiore possibile qui: con Anthropic selezionato e non configurato, le chiamate
    finivano a Mistral. La risposta di un altro sembra giusta, e non c'e' niente
    nell'interfaccia che possa smentirla.
    """

    def __init__(self, voluto: str, noti) -> None:
        super().__init__(voluto)
        self.voluto = voluto
        self.noti = sorted(noti)

    def messaggio(self) -> str:
        return (f"provider «{self.voluto}» non configurato nel gateway. "
                f"Conosco: {', '.join(self.noti)}. "
                f"Aggiungilo a limiti.json, oppure togli la spunta «Gateway» nel gioco "
                f"per andare diretto al provider.")


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


def _vale_la_pena_ricordarla(corpo: bytes) -> bool:
    """Una risposta `200` inservibile non va messa in cache.

    Il `200` dice che il PROVIDER ha fatto il suo lavoro, non che la risposta serva a
    qualcosa. Una troncata a meta' (`finish_reason: length`) o senza contenuto lo e' —
    e metterla in cache e' peggio che non averla: per un'ora ogni ritentativo riceve la
    stessa risposta rotta senza toccare la rete, e chi la riceve non ha modo di uscirne.

    Successo davvero: chiamando la stessa richiesta quattro volte in trentacinque secondi,
    tornava sempre `gen-1785930448-...` — la stessa generazione vuota, in 260 ms invece che
    in 5117, con l'ora che diceva 13:47:33 anche alle 13:48:04. Sembrava un modello guasto
    in modo perfettamente riproducibile, ed era una cache che difendeva un errore.

    Nel dubbio si NON-cachea: costa una chiamata, e una chiamata in piu' e' un danno
    reversibile mentre un errore congelato per un'ora non lo e'.
    """
    try:
        d = json.loads(corpo)
    except (ValueError, TypeError):
        return False   # se non si riesce nemmeno a leggerla, non la si conserva
    scelte = d.get("choices")
    if not isinstance(scelte, list) or not scelte:
        return False
    prima = scelte[0] if isinstance(scelte[0], dict) else {}
    if prima.get("finish_reason") == "length":
        return False   # troncata: rigiocarla vuol dire rigiocare il troncamento
    msg = prima.get("message")
    contenuto = msg.get("content") if isinstance(msg, dict) else None
    return bool(contenuto)


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
        # Intestazioni che appartengono a QUESTO provider. Anthropic non parla del tutto la
        # lingua di OpenAI: il suo /models pretende «x-api-key» e rifiuta il Bearer con un
        # 401, e ogni chiamata vuole «anthropic-version». Invece di un ramo «se e' Anthropic»
        # dentro il codice, il provider dichiara cosa gli serve: resta un dato.
        self.intestazioni_extra: dict = cfg.get("intestazioni", {})
        # Falso = questo provider non ha un piano gratuito: si paga sempre. Serve a dirlo
        # all'avvio, non a impedirlo.
        self.gratuito = bool(cfg.get("gratuito", True))
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

    ## Le intestazioni di autenticazione, UGUALI per chat ed elenco dei modelli. Erano
    ## scritte due volte, e con Anthropic le due copie avrebbero dovuto divergere: un posto
    ## solo. (Stessa correzione gia' fatta nel client del gioco, per la stessa ragione.)
    def _intestazioni(self) -> dict:
        h: dict[str, str] = {}
        if self.api_key:
            h["Authorization"] = f"Bearer {self.api_key}"
        for nome, valore in self.intestazioni_extra.items():
            v = str(valore)
            if v == SEGNAPOSTO_CHIAVE:
                if not self.api_key:
                    continue   # senza chiave l'intestazione sarebbe vuota: meglio non mandarla
                v = self.api_key
            h[nome] = v
        return h

    def _inoltra(self, payload: dict) -> tuple[int, bytes]:
        """Chiama il provider con backoff esponenziale su 429/5xx."""
        url = self.base_url + self.chat_path
        dati = json.dumps(payload).encode("utf-8")
        intestazioni = {"Content-Type": "application/json", **self._intestazioni()}

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
        if stato == 200 and _vale_la_pena_ricordarla(corpo):
            self.cache.scrivi(k, corpo)
        return stato, corpo, False

    def modelli(self) -> tuple[int, bytes]:
        url = self.base_url + self.models_path
        intestazioni = self._intestazioni()
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

    def scegli(self, modello: str, voluto: str = "") -> tuple[Provider, str]:
        """Decide A CHI va la richiesta. Non indovina mai, e non ripiega mai su un altro.

        Tre strade, in ordine di autorevolezza:

        1. `voluto` — il provider detto ESPLICITAMENTE dal client (query string
           `?provider=`). Comanda su tutto. Se non lo conosciamo: ProviderIgnoto.
        2. Il PREFISSO del modello: «mistral/mistral-small-latest». Se c'e' una barra e
           il pezzo davanti non e' un provider che conosciamo, e' ProviderIgnoto — non e'
           un invito a mandarlo altrove. Chi ha un nome di modello che contiene davvero
           una barra (OpenRouter: «mistralai/…») deve dire il provider, davanti o in
           query: «openrouter/mistralai/…».
        3. Nessun prefisso e nessuna barra: il provider predefinito, come sempre.

        LA REGOLA E' NATA DA UN DANNO. Con Anthropic scelto nel gioco e non configurato
        qui, «anthropic/claude-sonnet-5» finiva a Mistral: il ripiego trasformava una
        configurazione mancante — che si vede e si aggiusta — in risposte di un altro
        modello, che non si vedono affatto.
        """
        if voluto:
            if voluto not in self.providers:
                raise ProviderIgnoto(voluto, self.providers)
            pref = voluto + "/"
            return self.providers[voluto], modello[len(pref):] if modello.startswith(pref) else modello
        if "/" in modello:
            pref, resto = modello.split("/", 1)
            if pref not in self.providers:
                raise ProviderIgnoto(pref, self.providers)
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
            if voluto and voluto not in self.gateway.providers:
                # Prima si rispondeva col predefinito. Un elenco di modelli SBAGLIATO e' la
                # peggiore delle risposte: chi lo legge sceglie da quell'elenco.
                e = ProviderIgnoto(voluto, self.gateway.providers)
                log(f"  ✗ elenco modelli per «{voluto}»: {e.messaggio()}")
                self._rispondi(400, json.dumps({"error": {"message": e.messaggio()}}).encode())
                return
            nome = voluto or self.gateway.predefinito
            stato, corpo = self.gateway.providers[nome].modelli()
            self._rispondi(stato, corpo)
            return
        self._rispondi(404, b'{"error":{"message":"non trovato"}}')

    def do_POST(self):
        percorso, _, query = self.path.partition("?")
        if not percorso.rstrip("/").endswith("/chat/completions"):
            self._rispondi(404, b'{"error":{"message":"non trovato"}}')
            return
        lunghezza = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(lunghezza) or b"{}")
        except json.JSONDecodeError:
            self._rispondi(400, b'{"error":{"message":"JSON non valido"}}')
            return

        # Il provider si dice in query string, come per /models: e' l'unica cosa che non si
        # puo' confondere con un nome di modello che contiene una barra. Il prefisso resta
        # come ripiego per i client che non la mandano.
        voluto = urllib.parse.parse_qs(query).get("provider", [""])[0]
        try:
            provider, modello = self.gateway.scegli(str(payload.get("model", "")), voluto)
        except ProviderIgnoto as e:
            log(f"  ✗ {e.messaggio()}")
            self._rispondi(400, json.dumps({"error": {"message": e.messaggio()}}).encode())
            return
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
        # «Nessun piano gratuito» va detto all'avvio, non scoperto in fattura: questo gateway
        # nasce per stare dentro i tier gratuiti, e davanti a un provider che non ne ha uno
        # fa solo da coda.
        paga = "" if p.gratuito else "  ⚠ SEMPRE A PAGAMENTO (nessun piano gratuito)"
        log(f"  · {nome}: {p.base_url} ({chiave}) "
            f"min {p.limitatore.min_intervallo}s, {p.limitatore.rpm}/min, {p.limitatore.rpd}/giorno"
            f"{paga}")
    log("  Punta il gioco a questo indirizzo. Stato: curl localhost:%d/stato" % porta)
    try:
        ThreadingHTTPServer(("127.0.0.1", porta), Handler).serve_forever()
    except KeyboardInterrupt:
        log("Gateway fermato.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
