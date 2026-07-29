class_name Cronista
extends RefCounted

## Tiene la memoria della vicenda: condensa "riassunto precedente + fatti nuovi" in un
## unico riassunto rotolante (max ~120 parole). E' la memoria passata a TUTTI gli agenti,
## a costo COSTANTE: non cresce col numero di turni, quindi non gonfia prompt e latenza.
## Aggiornato ogni N turni (non a ogni turno): una chiamata LLM ogni tanto, non sempre.
## chat_fn iniettabile: Callable(messaggi, opzioni) -> {ok, content, error}.

const PROMPT_SYSTEM := "res://prompts/cronista_system.txt"
const PROMPT_GUARDRAIL := "res://prompts/guardrail_anti_assistente.txt"
const PROMPT_MONDO := "res://prompts/mondo.txt"

var _system_prompt: String = ""

func _init() -> void:
	var t := _leggi(PROMPT_SYSTEM)
	t = t.replace("{{GUARDRAIL}}", _leggi(PROMPT_GUARDRAIL))
	t = t.replace("{{MONDO}}", _leggi(PROMPT_MONDO))
	_system_prompt = t

func system_prompt() -> String:
	return _system_prompt

func _leggi(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Cronista: prompt mancante: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)

## contesto: {precedente: String, fatti: Array[String], luogo: String}
func costruisci_messaggi(contesto: Dictionary) -> Array:
	var precedente: String = contesto.get("precedente", "")
	var fatti: Array = contesto.get("fatti", [])
	var pezzi: Array[String] = []
	pezzi.append("RIASSUNTO PRECEDENTE: %s" % (precedente if precedente != "" else "(nessuno: la vicenda comincia ora)"))
	pezzi.append("FATTI NUOVI, in ordine:\n%s" % "\n".join(fatti))
	var luogo: String = contesto.get("luogo", "")
	if luogo != "":
		pezzi.append("Ulisse ora si trova a: %s." % luogo)
	pezzi.append("Scrivi il riassunto aggiornato (max 120 parole).")
	return [
		{"role": "system", "content": _system_prompt},
		{"role": "user", "content": "\n\n".join(pezzi)},
	]

## Ritorna il riassunto aggiornato, o "" se l'LLM non risponde (si tiene il precedente).
func aggiorna(contesto: Dictionary, chat_fn: Callable, seed: int = 0) -> String:
	var opzioni := {"temperature": 0.3}  # memoria: fedeltà, non estro
	if seed != 0:
		opzioni["seed"] = seed
	var risposta = await chat_fn.call(costruisci_messaggi(contesto), opzioni)
	if typeof(risposta) != TYPE_DICTIONARY or not risposta.get("ok", false):
		return ""
	return String(risposta.get("content", "")).strip_edges()
