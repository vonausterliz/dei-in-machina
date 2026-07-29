class_name Suggeritore
extends RefCounted

## Genera 3 spunti d'azione contestuali per il giocatore, sulla scena corrente (ultima
## voce di Omero + episodio). Sono appigli, non ordini: il 4o percorso resta la scrittura
## libera. NON deve nominare un dio (invariante player-facing): il prompt lo vieta e il
## LLMManager ridige eventuali nomi riusando il controllo di Omero.
## chat_fn iniettabile: Callable(messaggi, opzioni) -> {ok, content, error}.

const PROMPT_SYSTEM := "res://prompts/suggeritore_system.txt"
const PROMPT_GUARDRAIL := "res://prompts/guardrail_anti_assistente.txt"

var _system_prompt: String = ""

func _init() -> void:
	var t := _leggi(PROMPT_SYSTEM)
	t = t.replace("{{GUARDRAIL}}", _leggi(PROMPT_GUARDRAIL))
	_system_prompt = t

func system_prompt() -> String:
	return _system_prompt

func _leggi(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Suggeritore: prompt mancante: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)

func costruisci_messaggi(contesto: Dictionary) -> Array:
	var testo := "LA SCENA (attieniti a questa: luogo, chi è presente, cosa NON esiste qui): %s\n\nDove: %s.\nUltima voce del poeta: %s" % [
		contesto.get("scena", "il mare aperto"),
		contesto.get("episodio", "il mare aperto"),
		contesto.get("narrazione", "(l'inizio del viaggio)"),
	]
	return [
		{"role": "system", "content": _system_prompt},
		{"role": "user", "content": testo},
	]

## Ritorna un Array di {testo: String, rischio: bool}, al piu' 3. Vuoto se l'output
## e' inservibile (il LLMManager rimpiazza con spunti generici: sempre 3 in UI).
func suggerisci(contesto: Dictionary, chat_fn: Callable, seed: int = 0) -> Array:
	var opzioni := {"temperature": 0.8, "json_mode": true}
	if seed != 0:
		opzioni["seed"] = seed
	var risposta = await chat_fn.call(costruisci_messaggi(contesto), opzioni)
	if typeof(risposta) != TYPE_DICTIONARY or not risposta.get("ok", false):
		return []
	var grezzo := Contratto.estrai_json(risposta.get("content", ""))
	if grezzo.is_empty():
		return []
	var lista: Variant = grezzo.get("spunti", [])
	if typeof(lista) != TYPE_ARRAY:
		return []
	var out: Array = []
	for v in lista:
		var testo := ""
		var rischio := false
		if typeof(v) == TYPE_DICTIONARY:
			testo = String(v.get("testo", "")).strip_edges()
			rischio = bool(v.get("rischio", false))
		elif typeof(v) == TYPE_STRING:
			testo = String(v).strip_edges()
		if testo != "":
			out.append({"testo": testo, "rischio": rischio})
		if out.size() >= 3:
			break
	return out
