class_name Compagno
extends RefCounted

## Da' voce a un compagno di ciurma. Stesso schema del DioAgente, con due differenze
## sostanziali: il compagno non e' nascosto (puo' essere nominato) e puo' essere
## interpellato direttamente da Ulisse.
##
## chat_fn iniettabile: Callable(messaggi, opzioni) -> {ok, content, error}.

const PROMPT_SYSTEM := "res://prompts/compagno_system.txt"
const PROMPT_GUARDRAIL := "res://prompts/guardrail_anti_assistente.txt"
const PROMPT_MONDO := "res://prompts/mondo.txt"

var _template: String = ""
var _guardrail: String = ""
var _mondo: String = ""
var _cache: Dictionary = {}   # id compagno -> system prompt

func _init() -> void:
	_template = _leggi(PROMPT_SYSTEM)
	_guardrail = _leggi(PROMPT_GUARDRAIL)
	_mondo = _leggi(PROMPT_MONDO)

func _leggi(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Compagno: prompt mancante: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)

func system_prompt(c: Dictionary) -> String:
	var id := String(c.get("id", ""))
	if _cache.has(id):
		return _cache[id]
	var sp := _template
	sp = sp.replace("{{GUARDRAIL}}", _guardrail)
	sp = sp.replace("{{MONDO}}", _mondo)
	sp = sp.replace("{{NOME}}", String(c.get("nome", "")))
	sp = sp.replace("{{RUOLO}}", String(c.get("ruolo", "un compagno")))
	sp = sp.replace("{{CARATTERE}}", String(c.get("carattere", "")))
	sp = sp.replace("{{VOCE}}", String(c.get("voce", "")))
	sp = sp.replace("{{ESEMPI}}", "\n".join(c.get("esempi", [])))
	_cache[id] = sp
	return sp

## contesto: {scena, cronaca, accaduto, ulisse_dice, interpellato: bool}
func costruisci_messaggi(c: Dictionary, contesto: Dictionary) -> Array:
	var pezzi: Array[String] = []
	var scena: String = contesto.get("scena", "")
	if scena != "":
		pezzi.append("Dove siete: %s" % scena)
	# La memoria del compagno: cio' che ha visto nel viaggio (la cronaca comune).
	var cronaca: String = contesto.get("cronaca", "")
	if cronaca != "":
		pezzi.append("Quello che avete passato: %s" % cronaca)
	var accaduto: String = contesto.get("accaduto", "")
	if accaduto != "":
		pezzi.append("Cosa e' appena successo: %s" % accaduto)
	var dice: String = contesto.get("ulisse_dice", "")
	if dice != "":
		if bool(contesto.get("interpellato", false)):
			pezzi.append("Ulisse si rivolge PROPRIO A TE e dice: «%s». Rispondigli." % dice)
		else:
			pezzi.append("Ulisse ha detto o fatto: «%s»." % dice)
	return [
		{"role": "system", "content": system_prompt(c)},
		{"role": "user", "content": "\n".join(pezzi)},
	]

## Una battuta del compagno. "" se il modello non produce nulla di usabile: chi non ha
## niente da dire, tace (e la chat resta pulita).
func parla(c: Dictionary, contesto: Dictionary, chat_fn: Callable, seed: int = 0) -> String:
	var opzioni := {"temperature": 0.9}
	if seed != 0:
		opzioni["seed"] = seed
	var risposta = await chat_fn.call(costruisci_messaggi(c, contesto), opzioni)
	if typeof(risposta) != TYPE_DICTIONARY or not risposta.get("ok", false):
		return ""
	var testo := String(risposta.get("content", "")).strip_edges()
	# Ripulisco le virgolette e l'eventuale "Nome:" che i modelli tendono a premettere.
	testo = testo.trim_prefix("\"").trim_suffix("\"").strip_edges()
	var etichetta := String(c.get("nome", "")) + ":"
	if testo.begins_with(etichetta):
		testo = testo.substr(etichetta.length()).strip_edges()
	return testo
