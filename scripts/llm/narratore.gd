class_name Narratore
extends RefCounted

## Omero, l'aedo reticente. Rende in-world le conseguenze del turno SENZA nominare un dio
## (pilastro del "nascosto"). L'invariante non e' affidata solo al prompt: dopo la
## generazione un post-controllo cerca i nomi dei dei; se ne trova, ritenta una volta con
## un richiamo severo e, se serve, REDIGE il nome sostituendolo con "un dio". Cosi' la
## proprieta' vale anche quando il modello sbaglia.
## chat_fn iniettabile: Callable(messaggi, opzioni) -> {ok, content, error}.

const PROMPT_SYSTEM := "res://prompts/omero_system.txt"
const PROMPT_GUARDRAIL := "res://prompts/guardrail_anti_assistente.txt"

var _system_prompt: String = ""
var _nomi_dei: Array[String] = []

func _init(nomi_dei: Array = []) -> void:
	for n in nomi_dei:
		_nomi_dei.append(String(n))
	var template := _leggi(PROMPT_SYSTEM)
	template = template.replace("{{GUARDRAIL}}", _leggi(PROMPT_GUARDRAIL))
	_system_prompt = template

func _leggi(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("Narratore: prompt mancante: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)

func costruisci_messaggi(contesto: Dictionary) -> Array:
	var pezzi: Array[String] = []
	pezzi.append("Ulisse ha appena: %s" % contesto.get("sintesi", "qualcosa"))
	if not contesto.get("in_mondo", true):
		pezzi.append("(Nota: e' un gesto fuori dal mondo dell'Odissea; riportalo dentro con un richiamo, senza spezzare l'incanto.)")
	var segno: String = contesto.get("esito_segno", "")
	if segno != "":
		pezzi.append("La piega delle cose: %s." % segno)
	var impronta: String = contesto.get("impronta", "")
	if impronta != "":
		pezzi.append("Se vuoi lasciar intuire una presenza, usa questa impronta (MAI il nome): %s" % impronta)
	return [
		{"role": "system", "content": _system_prompt},
		{"role": "user", "content": "\n".join(pezzi)},
	]

func narra(contesto: Dictionary, chat_fn: Callable, seed: int = 0) -> String:
	var opzioni := {"temperature": 0.9}
	if seed != 0:
		opzioni["seed"] = seed
	var messaggi := costruisci_messaggi(contesto)

	var testo := await _chiedi(messaggi, chat_fn, opzioni)
	if testo != "" and not nomina_un_dio(testo):
		return testo

	# Ritenta una volta con richiamo severo.
	var messaggi2 := messaggi.duplicate(true)
	messaggi2.append({"role": "system", "content": "Hai nominato un dio: VIETATO. Riscrivi senza alcun nome divino, solo l'impronta."})
	var testo2 := await _chiedi(messaggi2, chat_fn, opzioni)
	if testo2 != "" and not nomina_un_dio(testo2):
		return testo2

	# Ultima difesa: redigi i nomi. La proprieta' vale comunque.
	var base := testo2 if testo2 != "" else testo
	return redigi(base)

func _chiedi(messaggi: Array, chat_fn: Callable, opzioni: Dictionary) -> String:
	var risposta = await chat_fn.call(messaggi, opzioni)
	if typeof(risposta) != TYPE_DICTIONARY or not risposta.get("ok", false):
		return ""
	return String(risposta.get("content", "")).strip_edges()

## Vero se il testo contiene il nome di un dio (confronto per parola, case-insensitive).
func nomina_un_dio(testo: String) -> bool:
	var t := testo.to_lower()
	for nome in _nomi_dei:
		for parola in nome.to_lower().split(" "):
			if parola.length() >= 3 and _contiene_parola(t, parola):
				return true
	return false

func redigi(testo: String) -> String:
	var out := testo
	for nome in _nomi_dei:
		for parola in nome.split(" "):
			if parola.length() >= 3:
				out = _sostituisci_parola(out, parola, "un dio")
	return out

func _contiene_parola(testo_basso: String, parola: String) -> bool:
	var re := RegEx.new()
	re.compile("(?i)\\b" + _escape(parola) + "\\b")
	return re.search(testo_basso) != null

func _sostituisci_parola(testo: String, parola: String, con: String) -> String:
	var re := RegEx.new()
	re.compile("(?i)\\b" + _escape(parola) + "\\b")
	return re.sub(testo, con, true)

func _escape(s: String) -> String:
	var speciali := ["\\", ".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|"]
	var out := s
	for c in speciali:
		out = out.replace(c, "\\" + c)
	return out
