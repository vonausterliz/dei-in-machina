class_name LLMClient
extends Node

## Client LLM provider-agnostico sul formato chat-completions di OpenAI
## (design sez. 9). Ollama, Mistral e l'endpoint compatibile di Anthropic parlano
## tutti questa lingua: cambiare provider = cambiare config, non codice.
## E' un Node perche' HTTPRequest deve stare nell'albero della scena.
##
## chat() e' una coroutine: `await client.chat(messaggi, opzioni)`.
## Ritorna sempre un Dictionary: {ok: bool, content: String, error: String, grezzo: Dictionary}.

var base_url: String = "http://localhost:11434"
var model: String = "llama3.3:latest"
var api_key: String = ""
var timeout_sec: float = 120.0
# Path dell'endpoint (dopo base_url). Default OpenAI/Ollama/Mistral; Google usa /v1beta/openai/...
var chat_path: String = "/v1/chat/completions"
var models_path: String = "/v1/models"
## Endpoint proprietario che elenca i modelli CON la loro taglia (Ollama: /api/tags).
## Vuoto = questo provider non ne ha uno, e le taglie restano ignote.
var tags_path: String = ""
## Intestazioni HTTP in piu', dichiarate dal profilo del provider.
##
## Serve ad Anthropic, l'unico che non parla del tutto la lingua di OpenAI: il suo layer di
## compatibilita' accetta il «Authorization: Bearer» su /chat/completions, ma /models
## pretende «x-api-key» e il Bearer lo rifiuta con un 401. L'alternativa era un ramo
## «se il provider e' anthropic» qui dentro; cosi' invece resta un dato nel suo file, e il
## prossimo provider con le sue manie si aggiunge senza toccare il client.
## Il valore SEGNAPOSTO_CHIAVE viene sostituito con la chiave API vera.
var intestazioni_extra: Dictionary = {}

## Nei dati la chiave API non c'e': c'e' questo, e lo sostituisce il client.
const SEGNAPOSTO_CHIAVE := "$CHIAVE"

## Logger opzionale per il debug: se valido, riceve righe di testo con il traffico
## (cosa viene mandato / cosa viene ricevuto). La GUI lo collega alla finestra di log.
var logger: Callable = Callable()

## UN HTTPRequest PER RICHIESTA, non uno per client.
##
## C'era un nodo solo, riusato da tutti: e HTTPRequest ne serve una alla volta. Due chiamate
## sovrapposte facevano sputare a Godot un «Condition "requesting" is true» e lasciavano il
## secondo chiamante con una risposta mai arrivata. Ho provato a metterci una guardia, ed e'
## stato peggio: la collisione e' diventata un errore VISIBILE che accusava la rete —
## «Non raggiungo http://localhost:11434» con Ollama perfettamente in ascolto. Bastava aprire
## Impostazioni mentre il motore si stava accendendo.
##
## La guardia curava il sintomo. La causa e' che due domande indipendenti — «quali modelli
## hai?» e «rispondi a questo turno?» — si contendevano un tubo solo. Un nodo per richiesta,
## creato e buttato: si sovrappongono quante ne servono, e nessuna aspetta l'altra.
var _hb: Timer          # battito d'attesa: mostra nel log che la richiesta e' viva
var _t_inizio: int = 0

func _ready() -> void:
	_hb = Timer.new()
	_hb.wait_time = 8.0
	_hb.one_shot = false
	add_child(_hb)
	_hb.timeout.connect(_battito)

## Diceva «in attesa di Ollama» qualunque fosse il provider — copiato da quando ce n'era
## uno solo. E ora dice anche quanto manca al tetto: un'attesa con un termine si sopporta,
## una senza sembra un blocco.
func _battito() -> void:
	var passati := int((Time.get_ticks_msec() - _t_inizio) / 1000)
	_log("    … in attesa (%d s di %d)…" % [passati, int(timeout_sec)])

func configura(config: Dictionary, chiave: String = "") -> void:
	base_url = config.get("base_url", base_url)
	model = config.get("model", model)
	api_key = chiave
	timeout_sec = config.get("timeout_sec", timeout_sec)
	# Default OpenAI espliciti: se il profilo non li specifica, si torna a questi (così
	# passando da Google a Mistral il path non resta quello di Google).
	chat_path = config.get("chat_path", "/v1/chat/completions")
	models_path = config.get("models_path", "/v1/models")
	tags_path = config.get("tags_path", "")
	intestazioni_extra = config.get("intestazioni", {})

## Il tubo per UNA richiesta. Chi lo apre lo chiude: `_chiudi()` in ogni uscita.
func _apri() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = timeout_sec
	add_child(h)
	return h

func _chiudi(h: HTTPRequest) -> void:
	if h:
		remove_child(h)   # subito, non a fine fotogramma: e' un nodo per richiesta
		h.queue_free()

## Le intestazioni di autenticazione, uguali per chat ed elenco dei modelli. Erano scritte
## due volte, e con Anthropic le due copie avrebbero dovuto divergere: un posto solo.
func intestazioni() -> PackedStringArray:
	var h := PackedStringArray()
	if api_key != "":
		h.append("Authorization: Bearer %s" % api_key)
	for nome in intestazioni_extra:
		var valore := String(intestazioni_extra[nome])
		if valore == SEGNAPOSTO_CHIAVE:
			if api_key == "":
				continue   # senza chiave l'intestazione sarebbe vuota: meglio non mandarla
			valore = api_key
		h.append("%s: %s" % [nome, valore])
	return h

## messaggi: Array di {role, content}. opzioni: {temperature, seed, json_mode}.
func chat(messaggi: Array, opzioni: Dictionary = {}) -> Dictionary:
	if not is_inside_tree():
		return _errore("client non nell'albero della scena")

	var corpo := {
		"model": model,
		"messages": messaggi,
		"temperature": opzioni.get("temperature", 0.7),
		"stream": false,
	}
	# Seed deterministico per run riproducibili (design: "seed presto").
	if opzioni.has("seed"):
		corpo["seed"] = opzioni["seed"]
	# Forza output JSON quando serve (Interprete): supportato da Ollama /v1 e OpenAI.
	if opzioni.get("json_mode", false):
		corpo["response_format"] = {"type": "json_object"}

	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(intestazioni())

	var url := base_url.trim_suffix("/") + chat_path
	_log("  ⇢ POST %s · model=%s · temp=%s%s" % [url, model, corpo["temperature"], " · json" if opzioni.get("json_mode", false) else ""])
	_log("    ⇡ invio: %s" % _tronca(_ultimo_utente(messaggi), 240))
	var h := _apri()
	var err := h.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(corpo))
	if err != OK:
		_chiudi(h)
		return _fallita("richiesta HTTP fallita in partenza: %s" % error_string(err))

	_t_inizio = Time.get_ticks_msec()
	_hb.start()
	var risultato: Array = await h.request_completed
	_hb.stop()
	_chiudi(h)
	# risultato = [result, response_code, headers, body]
	var result_code: int = risultato[0]
	var status: int = risultato[1]
	var body: PackedByteArray = risultato[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		if result_code == HTTPRequest.RESULT_TIMEOUT:
			return _fallita("timeout: nessuna risposta entro %d s (modello troppo lento su questa macchina?)" % int(timeout_sec))
		return _fallita("trasporto HTTP fallito (result=%d) — Ollama non risponde?" % result_code)
	if status < 200 or status >= 300:
		return _fallita("HTTP %d: %s" % [status, body.get_string_from_utf8().substr(0, 300)])

	var testo := body.get_string_from_utf8()
	var parsed = JSON.parse_string(testo)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fallita("risposta non-JSON dal provider")

	var contenuto := _estrai_contenuto(parsed)
	if contenuto == "":
		return _fallita("nessun contenuto nella risposta del provider")

	_log("    ⇣ HTTP %d · %s" % [status, _tronca(contenuto, 320)])
	return {"ok": true, "content": contenuto, "error": "", "grezzo": parsed}

## Estrae il testo del messaggio dalla risposta chat-completions.
func _estrai_contenuto(risposta: Dictionary) -> String:
	var choices = risposta.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return ""
	var primo: Dictionary = choices[0]
	var messaggio: Dictionary = primo.get("message", {})
	return messaggio.get("content", "")

## «HTTP 401» e basta non dice niente a nessuno: non chi ha risposto, non perche'. Il corpo
## della risposta di solito lo dice in chiaro («No API key found in request»), e finora lo
## buttavamo via — chat() lo teneva, l'elenco dei modelli no. E se si sta passando dal
## Gateway, il consiglio giusto e' l'OPPOSTO di quello solito: la chiave non va messa nel
## gioco, ce l'ha lui, e va nel SUO ambiente.
func _perche(stato: int, corpo: PackedByteArray) -> String:
	var testo := corpo.get_string_from_utf8().strip_edges().replace("\n", " ")
	var fine := " — %s" % testo.substr(0, 200) if testo != "" else ""
	if stato in [401, 403]:
		var dove := "il Gateway (che le chiavi le tiene lui: mettila nel suo ambiente, non in Settings)" \
			if base_url.contains("localhost:8800") or base_url.contains("127.0.0.1:8800") \
			else "il provider"
		return "HTTP %d: chiave API rifiutata o assente. La chiede %s%s" % [stato, dove, fine]
	return "HTTP %d%s" % [stato, fine]

func _errore(msg: String) -> Dictionary:
	return {"ok": false, "content": "", "error": msg, "grezzo": {}}

## Come _errore ma logga l'errore in modo evidente (percorso di chat()).
func _fallita(msg: String) -> Dictionary:
	_log("    ⇣ [ERRORE] %s" % msg)
	return _errore(msg)

func _log(riga: String) -> void:
	if logger.is_valid():
		logger.call(riga)

func _tronca(s: String, n: int) -> String:
	var t := s.replace("\n", " ")
	return t if t.length() <= n else t.substr(0, n) + " …"

func _ultimo_utente(messaggi: Array) -> String:
	var out := ""
	for m in messaggi:
		if typeof(m) == TYPE_DICTIONARY and m.get("role", "") == "user":
			out = String(m.get("content", ""))
	return out

## Elenca i modelli disponibili sul provider (formato OpenAI /v1/models, supportato da
## Ollama). Ritorna {ok, modelli: Array[String], errore}. Serve alla verifica pre-partita.
##
## Passando dal Gateway il percorso porta «?provider=…», per dire di CHI vogliamo l'elenco.
## Un gateway avviato prima di quella modifica confronta il percorso intero e non lo
## riconosce: risponde 404 «non trovato», e l'utente si vede accusare l'indirizzo. Avevo
## scritto che sarebbe stato retrocompatibile: non lo era. Qui si riprova una volta senza la
## query — che e' esattamente il comportamento di prima, cioe' il provider predefinito.
func elenca_modelli() -> Dictionary:
	var r := await _elenca(models_path)
	if not bool(r["ok"]) and String(r["errore"]).begins_with("HTTP 404") and models_path.contains("?"):
		_log("    ↻ 404 con la query: gateway non aggiornato? riprovo senza")
		return await _elenca(models_path.get_slice("?", 0))
	return r

func _elenca(percorso: String) -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "modelli": [], "errore": "client non nell'albero della scena"}
	var url := base_url.trim_suffix("/") + percorso
	var h := _apri()
	var err := h.request(url, intestazioni(), HTTPClient.METHOD_GET)
	if err != OK:
		_chiudi(h)
		return {"ok": false, "modelli": [], "errore": "connessione fallita: %s" % error_string(err)}
	var r: Array = await h.request_completed
	_chiudi(h)
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "modelli": [], "errore": "server non raggiungibile (result=%d)" % int(r[0])}
	if int(r[1]) < 200 or int(r[1]) >= 300:
		return {"ok": false, "modelli": [], "errore": _perche(int(r[1]), r[3])}
	var body: PackedByteArray = r[3]
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var modelli: Array = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for m in parsed.get("data", []):
			if typeof(m) == TYPE_DICTIONARY and m.has("id"):
				modelli.append(String(m["id"]))
	return {"ok": true, "modelli": modelli, "errore": ""}

## I MODELLI CON LA LORO TAGLIA, dove il provider sa dirla.
##
## `elenca_modelli()` usa l'endpoint in formato OpenAI, che da' i soli nomi. Ollama ne ha
## anche uno suo — `/api/tags` — che aggiunge la dimensione sul disco, i parametri e la
## quantizzazione: e' cio' che serve per dire, accanto a ogni modello, se questa macchina ce
## la fa a farlo girare. Il percorso lo dichiara il profilo (`tags_path`); chi non lo
## dichiara non ha nulla di simile, e qui si risponde «non lo so» invece di indovinare.
## Ritorna {ok, modelli: [{nome, byte, parametri, quantizzazione}], errore}.
func elenca_dettagli() -> Dictionary:
	if not is_inside_tree() or tags_path == "":
		return {"ok": false, "modelli": [], "errore": "nessun elenco dettagliato per questo provider"}
	var url := base_url.trim_suffix("/") + tags_path
	var h := _apri()
	var err := h.request(url, intestazioni(), HTTPClient.METHOD_GET)
	if err != OK:
		_chiudi(h)
		return {"ok": false, "modelli": [], "errore": "connessione fallita: %s" % error_string(err)}
	var r: Array = await h.request_completed
	_chiudi(h)
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "modelli": [], "errore": "server non raggiungibile (result=%d)" % int(r[0])}
	if int(r[1]) < 200 or int(r[1]) >= 300:
		return {"ok": false, "modelli": [], "errore": _perche(int(r[1]), r[3])}
	var parsed = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	var out: Array = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for m in parsed.get("models", []):
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var det: Dictionary = m.get("details", {})
			out.append({
				"nome": String(m.get("name", "")),
				"byte": int(m.get("size", 0)),
				"parametri": String(det.get("parameter_size", "")),
				"quantizzazione": String(det.get("quantization_level", "")),
			})
	return {"ok": true, "modelli": out, "errore": ""}

## Ping leggero: verifica che il provider risponda e che il modello esista.
func disponibile() -> bool:
	if not is_inside_tree():
		return false
	var url := base_url.trim_suffix("/") + models_path
	var h := _apri()
	var err := h.request(url, intestazioni(), HTTPClient.METHOD_GET)
	if err != OK:
		_chiudi(h)
		return false
	var risultato: Array = await h.request_completed
	_chiudi(h)
	return risultato[0] == HTTPRequest.RESULT_SUCCESS and int(risultato[1]) == 200
