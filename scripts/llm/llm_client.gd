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

## UNA RICHIESTA ALLA VOLTA. C'e' un solo HTTPRequest, e chiamarne due in parallelo fa
## sputare a Godot un «Condition "requesting" is true» che non dice niente a nessuno e
## lascia il chiamante con una risposta mai arrivata. Non e' un caso di scuola: appena
## Impostazioni ha cominciato a chiedere le taglie dei modelli all'apertura, si e'
## sovrapposta alle verifiche gia' in volo. Meglio un errore in chiaro e subito.
var _in_corso := false

var _http: HTTPRequest
var _hb: Timer          # battito d'attesa: mostra nel log che la richiesta e' viva
var _t_inizio: int = 0

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = timeout_sec
	add_child(_http)
	_hb = Timer.new()
	_hb.wait_time = 8.0
	_hb.one_shot = false
	add_child(_hb)
	_hb.timeout.connect(_battito)

func _battito() -> void:
	_log("    … in attesa di Ollama (%d s)…" % int((Time.get_ticks_msec() - _t_inizio) / 1000))

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
	if _http:
		_http.timeout = timeout_sec

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
	if _http == null:
		return _errore("HTTPRequest non pronto (client non nell'albero)")
	if _in_corso:
		return _errore("c'e' gia' una richiesta in volo su questo client")

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
	_in_corso = true
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(corpo))
	if err != OK:
		_in_corso = false
		return _fallita("richiesta HTTP fallita in partenza: %s" % error_string(err))

	_t_inizio = Time.get_ticks_msec()
	_hb.start()
	var risultato: Array = await _http.request_completed
	_hb.stop()
	_in_corso = false
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
func elenca_modelli() -> Dictionary:
	if _in_corso:
		return {"ok": false, "modelli": [], "errore": "c'e' gia' una richiesta in volo su questo client"}
	if _http == null:
		return {"ok": false, "modelli": [], "errore": "client non pronto"}
	var url := base_url.trim_suffix("/") + models_path
	_in_corso = true
	var err := _http.request(url, intestazioni(), HTTPClient.METHOD_GET)
	if err != OK:
		_in_corso = false
		return {"ok": false, "modelli": [], "errore": "connessione fallita: %s" % error_string(err)}
	var r: Array = await _http.request_completed
	_in_corso = false
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "modelli": [], "errore": "server non raggiungibile (result=%d)" % int(r[0])}
	if int(r[1]) < 200 or int(r[1]) >= 300:
		return {"ok": false, "modelli": [], "errore": "HTTP %d" % int(r[1])}
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
	if _in_corso:
		return {"ok": false, "modelli": [], "errore": "c'e' gia' una richiesta in volo su questo client"}
	if _http == null or tags_path == "":
		return {"ok": false, "modelli": [], "errore": "nessun elenco dettagliato per questo provider"}
	var url := base_url.trim_suffix("/") + tags_path
	_in_corso = true
	var err := _http.request(url, intestazioni(), HTTPClient.METHOD_GET)
	if err != OK:
		_in_corso = false
		return {"ok": false, "modelli": [], "errore": "connessione fallita: %s" % error_string(err)}
	var r: Array = await _http.request_completed
	_in_corso = false
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "modelli": [], "errore": "server non raggiungibile (result=%d)" % int(r[0])}
	if int(r[1]) < 200 or int(r[1]) >= 300:
		return {"ok": false, "modelli": [], "errore": "HTTP %d" % int(r[1])}
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
	if _http == null:
		return false
	var url := base_url.trim_suffix("/") + models_path
	var err := _http.request(url, intestazioni(), HTTPClient.METHOD_GET)
	if err != OK:
		return false
	var risultato: Array = await _http.request_completed
	return risultato[0] == HTTPRequest.RESULT_SUCCESS and int(risultato[1]) == 200
