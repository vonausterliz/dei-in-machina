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
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(corpo))
	if err != OK:
		return _errore("richiesta HTTP fallita in partenza: %s" % error_string(err))

	var risultato: Array = await _http.request_completed
	# risultato = [result, response_code, headers, body]
	var result_code: int = risultato[0]
	var status: int = risultato[1]
	var body: PackedByteArray = risultato[3]

	if result_code != HTTPRequest.RESULT_SUCCESS:
		return _errore("trasporto HTTP fallito (result=%d)" % result_code)
	if status < 200 or status >= 300:
		return _errore("HTTP %d: %s" % [status, body.get_string_from_utf8().substr(0, 300)])

	var testo := body.get_string_from_utf8()
	var parsed = JSON.parse_string(testo)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _errore("risposta non-JSON dal provider")

	var contenuto := _estrai_contenuto(parsed)
	if contenuto == "":
		return _errore("nessun contenuto nella risposta del provider")

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
