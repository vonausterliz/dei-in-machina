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
	# Passaggio tra tappe: una breve traversata da un luogo all'altro (per non far
	# "teletrasportare" Ulisse). Ha un formato suo, ignora i campi dell'azione.
	var passaggio: Dictionary = contesto.get("passaggio", {})
	if not passaggio.is_empty():
		return [
			{"role": "system", "content": _system_prompt},
			{"role": "user", "content": "PASSAGGIO: Ulisse lascia «%s» e per mare giunge a «%s». Rendi in 2-3 righe il distacco dalla terra che si allontana e la traversata fino alla nuova sponda: così il lettore capisce come ci è arrivato. Tono epico e asciutto. Non nominare un dio." % [passaggio.get("da", "questa terra"), passaggio.get("a", "una nuova terra")]},
		]

	var pezzi: Array[String] = []
	var scena: String = contesto.get("scena", "")
	if scena != "":
		pezzi.append("LA SCENA (attieniti a questa: luogo, chi è presente, cosa NO): %s" % scena)
	var storia: Array = contesto.get("storia", [])
	if not storia.is_empty():
		pezzi.append("LA STORIA FINORA (i fatti già accaduti, non contraddirli): %s" % " → ".join(storia))
	var ultima: String = contesto.get("ultima_narrazione", "")
	if ultima != "":
		pezzi.append("LA TUA ULTIMA VOCE (prosegui coerente, senza ripeterla): %s" % ultima)
	# Orientamento discreto: dove siamo e come sta andando (Omero li fa sentire, non li recita).
	var luogo: String = contesto.get("luogo", "")
	if luogo != "":
		var progresso: String = {"inizio": "il ritorno è ancora lontano", "mezzo": "sei a metà del cammino verso Itaca", "vicino": "Itaca non è più tanto lontana"}.get(contesto.get("progresso", ""), "")
		var morale: String = {"duro": "le ultime vicende sono state dure", "bene": "le cose sembrano volgere al meglio", "incerto": ""}.get(contesto.get("morale", ""), "")
		pezzi.append("ORIENTAMENTO (fallo SENTIRE con naturalezza, non ogni volta e mai come un elenco): siamo a «%s»; %s; %s." % [luogo, progresso, morale])
	# L'azione GREZZA di Ulisse (parole/gesto esatti) + la sintesi: Omero deve rispondere
	# proprio a QUESTO, non andare per la sua strada.
	var azione: String = contesto.get("azione", "")
	if azione != "":
		pezzi.append("ULISSE HA APPENA, con queste parole o questo gesto: «%s» (in sintesi: %s). Rendi la scena e la sua RISPOSTA CONCRETA nel mondo — cosa accade come diretta conseguenza di ciò che Ulisse ha fatto o detto (se chiede udienza, mostra la risposta; se offre qualcosa, mostra chi lo accoglie o lo rifiuta) — e solo dopo, con misura, l'impronta del divino." % [azione, contesto.get("sintesi", "qualcosa")])
	else:
		pezzi.append("Ulisse ha appena: %s" % contesto.get("sintesi", "qualcosa"))
	match contesto.get("ammonizione", ""):
		"richiamo":
			pezzi.append("(Gesto fuori dal mondo dell'Odissea: NON narrarlo come reale. Rifiutati con dolcezza e riportalo dentro la scena, senza spezzare l'incanto.)")
		"smarrimento":
			pezzi.append("(Ulisse insiste con gesti insensati: lo smarrimento lo prende, i compagni lo guardano con timore. Narra la confusione, non il gesto.)")
		"follia":
			pezzi.append("(Ulisse ha perso la ragione: l'empieta reiterata chiama la mano di un dio. E' la fine, per follia. Narra il tracollo, cupo e breve — mai un nome.)")
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
