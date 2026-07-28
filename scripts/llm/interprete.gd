class_name Interprete
extends RefCounted

## Prima chiamata LLM di ogni turno: testo libero di Ulisse -> envelope JSON validato
## (docs/contratto_interprete.md). Non narra e non parla: classifica.
##
## Il system prompt vive in file esterni (prompts/), col guardrail anti-assistente
## incluso (CLAUDE.md). Vocabolario e validazione vengono da Contratto: una lingua sola.
##
## Testabile senza rete: interpreta() riceve una `chat_fn` iniettabile
## Callable(messaggi: Array, opzioni: Dictionary) -> {ok, content, error}
## (coroutine o sincrona). A runtime e' LLMClient.chat; nei test e' un finto.

const PROMPT_SYSTEM := "res://prompts/interprete_system.txt"
const PROMPT_GUARDRAIL := "res://prompts/guardrail_anti_assistente.txt"

var _system_prompt: String = ""
var id_dei_validi: Array = []

func _init(id_dei: Array = []) -> void:
	id_dei_validi = id_dei
	_system_prompt = _costruisci_system_prompt()

func system_prompt() -> String:
	return _system_prompt

func _costruisci_system_prompt() -> String:
	var template := _leggi(PROMPT_SYSTEM)
	var guardrail := _leggi(PROMPT_GUARDRAIL)
	template = template.replace("{{GUARDRAIL}}", guardrail)
	template = template.replace("{{VOCABOLARIO_TAG}}", Contratto.vocabolario_per_prompt())
	return template

func _leggi(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Interprete: prompt mancante: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)

func costruisci_messaggi(testo_libero: String) -> Array:
	return [
		{"role": "system", "content": _system_prompt},
		{"role": "user", "content": testo_libero},
	]

## API pulita per la macchina del turno: ritorna sempre un envelope valido
## (eventualmente quello di fallback). `await` perche' chat_fn puo' essere async.
func interpreta(testo_libero: String, chat_fn: Callable, seed: int = 0) -> Dictionary:
	var traccia := await interpreta_tracciato(testo_libero, chat_fn, seed)
	return traccia["envelope"]

## Come interpreta(), ma ritorna anche la traccia per l'osservabilita' (scenario runner):
## {envelope, valido, fallback_usato, tentativi: [{content, errori}]}
func interpreta_tracciato(testo_libero: String, chat_fn: Callable, seed: int = 0) -> Dictionary:
	var opzioni := {"temperature": 0.2, "json_mode": true}
	if seed != 0:
		opzioni["seed"] = seed

	var tentativi: Array = []

	# Tentativo 1
	var messaggi := costruisci_messaggi(testo_libero)
	var esito1 := await _tenta(testo_libero, messaggi, chat_fn, opzioni)
	tentativi.append(esito1["log"])
	if esito1["ok"]:
		return {"envelope": esito1["envelope"], "valido": true, "fallback_usato": false, "tentativi": tentativi}

	# Tentativo 2: reminder piu' severo (JSON difensivo: il malformato capitera')
	var messaggi2 := messaggi.duplicate(true)
	messaggi2.append({
		"role": "system",
		"content": "Output precedente non valido. Rispondi SOLO con l'oggetto JSON dell'envelope, senza testo attorno.",
	})
	var esito2 := await _tenta(testo_libero, messaggi2, chat_fn, opzioni)
	tentativi.append(esito2["log"])
	if esito2["ok"]:
		return {"envelope": esito2["envelope"], "valido": true, "fallback_usato": false, "tentativi": tentativi}

	# Fallback inerte: un parse fallito non deve svegliare nessun dio.
	var fallback := Contratto.envelope_fallback("Ulisse: \"%s\"" % testo_libero)
	return {"envelope": fallback, "valido": false, "fallback_usato": true, "tentativi": tentativi}

## Ritorna {ok: bool, envelope: Dictionary, log: {content, errori}}
func _tenta(testo_libero: String, messaggi: Array, chat_fn: Callable, opzioni: Dictionary) -> Dictionary:
	var risposta = await chat_fn.call(messaggi, opzioni)
	if typeof(risposta) != TYPE_DICTIONARY or not risposta.get("ok", false):
		var err: String = risposta.get("error", "risposta non valida") if typeof(risposta) == TYPE_DICTIONARY else "risposta non valida"
		return {"ok": false, "envelope": {}, "log": {"content": "", "errori": [err]}}

	var content: String = risposta.get("content", "")
	var grezzo := Contratto.estrai_json(content)
	if grezzo.is_empty():
		return {"ok": false, "envelope": {}, "log": {"content": content, "errori": ["JSON non estraibile dalla risposta"]}}

	var envelope := Contratto.normalizza(grezzo)
	if String(envelope.get("sintesi", "")).strip_edges() == "":
		envelope["sintesi"] = "Ulisse: \"%s\"" % testo_libero

	var verdetto := Contratto.valida_envelope(envelope, id_dei_validi)
	if not verdetto["ok"]:
		return {"ok": false, "envelope": {}, "log": {"content": content, "errori": verdetto["errori"]}}

	return {"ok": true, "envelope": envelope, "log": {"content": content, "errori": []}}
