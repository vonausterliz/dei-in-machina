class_name Arbitro
extends RefCounted

## Zeus arbitro: dato l'insieme delle proposte in conflitto, emette un verdetto
## {attore, registro, intensita, dice}. L'attore deve essere uno dei dei in campo e
## il registro uno dei suoi ammessi; altrimenti si ripiega sul verdetto deterministico
## (la proposta piu' intensa). Cosi' la scelta e' viva ma sempre valida.
## chat_fn iniettabile: Callable(messaggi, opzioni) -> {ok, content, error}.

const PROMPT_SYSTEM := "res://prompts/arbitro_system.txt"
const PROMPT_GUARDRAIL := "res://prompts/guardrail_anti_assistente.txt"
const PROMPT_MONDO := "res://prompts/mondo.txt"

var _system_prompt: String = ""
var _pantheon: Pantheon = null

func _init(pantheon: Pantheon = null) -> void:
	_pantheon = pantheon
	var template := _leggi(PROMPT_SYSTEM)
	template = template.replace("{{GUARDRAIL}}", _leggi(PROMPT_GUARDRAIL))
	template = template.replace("{{MONDO}}", _leggi(PROMPT_MONDO))
	_system_prompt = template

func system_prompt() -> String:
	return _system_prompt

func _leggi(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Arbitro: prompt mancante: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)

func costruisci_messaggi(proposte: Array) -> Array:
	var righe: Array[String] = []
	for p in proposte:
		var dio: Dio = _pantheon.get_dio(p.get("dio", "")) if _pantheon else null
		var nome: String = dio.nome if dio else p.get("dio", "?")
		var registri: String = ", ".join(dio.registri) if dio else "?"
		righe.append("- %s (id: %s; registri ammessi: %s) propone %s [intensita %s]: \"%s\"" % [
			nome, p.get("dio", "?"), registri, p.get("registro", "?"),
			p.get("intensita", 1), p.get("dice", "")])
	var situazione := "Le posizioni in campo:\n%s\n\nEmetti il verdetto." % "\n".join(righe)
	return [
		{"role": "system", "content": _system_prompt},
		{"role": "user", "content": situazione},
	]

func decidi(proposte: Array, chat_fn: Callable, seed: int = 0) -> Dictionary:
	if proposte.is_empty():
		return {"attore": "", "registro": "silenzio", "intensita": 1, "dice": ""}

	var opzioni := {"temperature": 0.5, "json_mode": true}
	if seed != 0:
		opzioni["seed"] = seed
	var risposta = await chat_fn.call(costruisci_messaggi(proposte), opzioni)

	if typeof(risposta) == TYPE_DICTIONARY and risposta.get("ok", false):
		var grezzo := Contratto.estrai_json(risposta.get("content", ""))
		var v := _valida(grezzo, proposte)
		if not v.is_empty():
			return v
	# Fallback deterministico: la proposta piu' intensa.
	return _fallback(proposte)

## Verdetto valido solo se l'attore e' in campo e il registro gli e' ammesso.
func _valida(grezzo: Dictionary, proposte: Array) -> Dictionary:
	if grezzo.is_empty():
		return {}
	var attore := String(grezzo.get("attore", ""))
	var ids: Array = []
	for p in proposte:
		ids.append(p.get("dio", ""))
	if not ids.has(attore):
		return {}
	var dio: Dio = _pantheon.get_dio(attore) if _pantheon else null
	var registro := String(grezzo.get("registro", ""))
	if dio != null and registro != "silenzio" and not dio.registri.has(registro):
		return {}
	return {
		"attore": attore,
		"registro": registro,
		"intensita": clampi(int(grezzo.get("intensita", 1)), 1, 3),
		"dice": String(grezzo.get("dice", "")).strip_edges(),
	}

func _fallback(proposte: Array) -> Dictionary:
	var scelta: Dictionary = proposte[0]
	for p in proposte:
		if int(p.get("intensita", 1)) > int(scelta.get("intensita", 1)):
			scelta = p
	return {
		"attore": scelta.get("dio", ""),
		"registro": scelta.get("registro", "silenzio"),
		"intensita": int(scelta.get("intensita", 1)),
		"dice": scelta.get("dice", ""),
	}
