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

## Logger opzionale per il debug: se valido, riceve righe di testo con il traffico
## (cosa viene mandato / cosa viene ricevuto). La GUI lo collega alla finestra di log.
var logger: Callable = Callable()

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = timeout_sec
	add_child(_http)

func configura(config: Dictionary, chiave: String = "") -> void:
	base_url = config.get("base_url", base_url)
	model = config.get("model", model)
	api_key = chiave
	timeout_sec = config.get("timeout_sec", timeout_sec)
	if _http:
		_http.timeout = timeout_sec

## messaggi: Array di {role, content}. opzioni: {temperature, seed, json_mode}.
func chat(messaggi: Array, opzioni: Dictionary = {}) -> Dictionary:
	if _http == null:
		return _errore("HTTPRequest non pronto (client non nell'albero)")

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
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)

	var url := "%s/v1/chat/completions" % base_url.trim_suffix("/")
	_log("  ⇢ POST %s · model=%s · temp=%s%s" % [url, model, corpo["temperature"], " · json" if opzioni.get("json_mode", false) else ""])
	_log("    ⇡ invio: %s" % _tronca(_ultimo_utente(messaggi), 240))
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(corpo))
	if err != OK:
		return _fallita("richiesta HTTP fallita in partenza: %s" % error_string(err))

	var risultato: Array = await _http.request_completed
	# risultato = [result, response_code, headers, body]
	var result_code: int = risultato[0]
	var status: int = risultato[1]
	var body: PackedByteArray = risultato[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
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
	if _http == null:
		return {"ok": false, "modelli": [], "errore": "client non pronto"}
	var url := "%s/v1/models" % base_url.trim_suffix("/")
	var headers := PackedStringArray()
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		return {"ok": false, "modelli": [], "errore": "connessione fallita: %s" % error_string(err)}
	var r: Array = await _http.request_completed
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

## Ping leggero: verifica che il provider risponda e che il modello esista.
func disponibile() -> bool:
	if _http == null:
		return false
	var url := "%s/v1/models" % base_url.trim_suffix("/")
	var headers := PackedStringArray()
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)  # richiesto dalle API cloud (Mistral)
	var err := _http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		return false
	var risultato: Array = await _http.request_completed
	return risultato[0] == HTTPRequest.RESULT_SUCCESS and int(risultato[1]) == 200
