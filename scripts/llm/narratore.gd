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
const PROMPT_MONDO := "res://prompts/mondo.txt"

var _system_prompt: String = ""
var _nomi_dei: Array[String] = []

func _init(nomi_dei: Array = []) -> void:
	for n in nomi_dei:
		_nomi_dei.append(String(n))
	var template := _leggi(PROMPT_SYSTEM)
	template = template.replace("{{GUARDRAIL}}", _leggi(PROMPT_GUARDRAIL))
	template = template.replace("{{MONDO}}", _leggi(PROMPT_MONDO))
	_system_prompt = template

func system_prompt() -> String:
	return _system_prompt

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
			{"role": "user", "content": "PASSAGGIO: Ulisse lascia «%s» e per mare giunge a «%s».\n%s\nRendi in 2-3 righe il distacco dalla terra che si allontana e la traversata fino alla nuova sponda: così il lettore capisce come ci è arrivato, E PERCHE'. Tono epico e asciutto. Non nominare un dio." % [passaggio.get("da", "questa terra"), passaggio.get("a", "una nuova terra"), _perche(String(passaggio.get("causa", "")))]},
		]

	# Congedo: l'ultima voce, quando la partita e' finita. Non c'e' un'azione da rendere,
	# c'e' una vita da chiudere. Il `modello` serve a dare il TONO — un epitaffio, non un
	# riassunto — senza che il modello lo ricopi.
	var congedo: Dictionary = contesto.get("congedo", {})
	if not congedo.is_empty():
		return [
			{"role": "system", "content": _system_prompt},
			{"role": "user", "content": "CONGEDO. La storia di Ulisse finisce qui, a «%s», e finisce cosi': %s.\nQuesto e' accaduto finora: %s\nScrivi l'ULTIMA voce del poema: un epitaffio di 4-6 righe, in terza persona, al passato remoto, rivolto a chi ascolta. Nomina Ulisse. Ricorda da dove viene questa rovina — Troia, la guerra, cio' che dieci anni gli hanno tolto — e chiudi senza consolazione e senza morale. Non nominare un dio. Non usare elenchi.\nTIENI QUESTO TONO (non copiarlo, e' solo la misura): «%s»" % [
				congedo.get("luogo", "una terra lontana"),
				_come_finisce(String(congedo.get("esito", ""))),
				congedo.get("cronaca", "un lungo ritorno mai compiuto"),
				congedo.get("modello", ""),
			]},
		]

	var pezzi: Array[String] = []
	var scena: String = contesto.get("scena", "")
	if scena != "":
		pezzi.append("LA SCENA (attieniti a questa: luogo, chi è presente, cosa NO): %s" % scena)
	var cronaca: String = contesto.get("cronaca", "")
	if cronaca != "":
		pezzi.append("LA VICENDA FINORA (memoria: non contraddirla): %s" % cronaca)
	var storia: Array = contesto.get("storia", [])
	if not storia.is_empty():
		pezzi.append("LE ULTIME MOSSE DI ULISSE: %s" % " → ".join(storia))
	var ultima: String = contesto.get("ultima_narrazione", "")
	if ultima != "":
		pezzi.append("LA TUA ULTIMA VOCE (prosegui coerente, senza ripeterla): %s" % ultima)
	# Orientamento discreto: dove siamo e come sta andando (Omero li fa sentire, non li recita).
	var luogo: String = contesto.get("luogo", "")
	if luogo != "":
		var progresso: String = {"inizio": "il ritorno è ancora lontano", "mezzo": "sei a metà del cammino verso Itaca", "vicino": "Itaca non è più tanto lontana"}.get(contesto.get("progresso", ""), "")
		var morale: String = {"duro": "le ultime vicende sono state dure", "bene": "le cose sembrano volgere al meglio", "incerto": ""}.get(contesto.get("morale", ""), "")
		pezzi.append("ORIENTAMENTO (fallo SENTIRE con naturalezza, non ogni volta e mai come un elenco): siamo a «%s»; %s; %s." % [luogo, progresso, morale])
	# L'azione GREZZA di Ulisse (parole/gesto esatti): Omero deve rispondere proprio a QUELLO.
	var azione: String = contesto.get("azione", "")
	if azione != "":
		pezzi.append("ULISSE HA APPENA, con queste parole o questo gesto: «%s» (in sintesi: %s). Rendi la scena e la sua RISPOSTA CONCRETA nel mondo — cosa accade come diretta conseguenza di ciò che Ulisse ha fatto o detto (se chiede udienza, mostra la risposta; se offre qualcosa, mostra chi lo accoglie o lo rifiuta) — e solo dopo, con misura, l'impronta del divino." % [azione, contesto.get("sintesi", "qualcosa")])
	else:
		pezzi.append("Ulisse ha appena: %s" % contesto.get("sintesi", "qualcosa"))
	# Le parole scambiate coi compagni fra un'azione e l'altra: sono accadute anche quelle,
	# e Omero puo' raccoglierne l'eco senza doverle ripetere.
	var detto: String = contesto.get("detto_ai_compagni", "")
	if detto != "":
		pezzi.append("POCO PRIMA, AI SUOI COMPAGNI, HA DETTO: «%s» (sfondo: puoi lasciarne un'eco, non ripeterlo)." % detto)
	var momento: String = contesto.get("momento", "")
	if momento != "":
		pezzi.append("QUANDO: siamo %s. Fallo sentire con naturalezza, senza annunciarlo." % momento)
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

## Come finisce, detto a Omero in una riga. Non e' il nome tecnico dell'esito: quello e'
## un'etichetta buona per la traccia, non per un poema.
func _come_finisce(esito: String) -> String:
	match esito:
		"morte":
			return "la ragione lo abbandona e Ulisse muore lontano da casa, distrutto da cio' che si era portato dentro dalla guerra"
		"prigionia_eterna":
			return "Ulisse resta per sempre sull'isola dove il tempo non passa, e a poco a poco smette di volere il ritorno"
		"ciurma_perduta":
			return "Ulisse sopravvive a tutti i suoi, e il ritorno non ha piu' nessuno a cui portarlo"
		_:
			return "il ritorno non si compie"

## NOTA: i turni FUORI-MONDO non arrivano qui. Il GameManager non chiama affatto Omero
## quando l'azione è impossibile (anacronismo/nonsenso): al giocatore va solo il richiamo,
## mostrato dalla UI. Chiedere al modello di "non narrare" non funzionava: narrava lo stesso.
## Il separatore che CHIEDIAMO a Omero (vedi il prompt). Non lo cerchiamo alla lettera:
## un modello lo storpia. Visto sul campo con Mistral Small: "---\nSPUNTI---", e perfino
## l'etichetta ORIENTAMENTO del contesto rimbalzata come titolo. Col confronto esatto
## niente combaciava e l'impalcatura finiva dentro il racconto, sotto gli occhi di chi
## gioca. Qui il riconoscimento e' tollerante e la prosa viene comunque ripulita: chi
## gioca legge una storia, mai i ponteggi.
const SEP_SPUNTI := "---SPUNTI---"

## Righe che valgono come stacco fra il racconto e gli spunti: "SPUNTI" o "ORIENTAMENTO"
## comunque vestiti di trattini, oppure una riga di soli trattini.
const RE_INTESTAZIONE := "(?im)^[ \\t]*-*[ \\t]*(SPUNTI|ORIENTAMENTO)[ \\t]*:?[ \\t]*-*[ \\t]*$"
const RE_SOLO_TRATTINI := "^[ \\t]*[-_—=]{3,}[ \\t]*$"
## Un'etichetta interna sfuggita nel testo: tutta maiuscola, senza minuscole, sulla sua riga.
const RE_ETICHETTA := "^[ \\t]*[A-ZÀÈÉÌÒÙ][A-ZÀÈÉÌÒÙ '\\t]{3,}[ \\t]*:?[ \\t]*$"
## Marcatori con cui il modello apre uno spunto. Li combina anche fra loro ("- ! Getta…").
##
## NIENTE LINEETTE (– —): in italiano aprono il DIALOGO, non un elenco. Averle messe qui
## faceva scambiare ogni battuta di Omero per uno spunto — tagliata dal racconto e messa
## su un bottone. Con una scena molto dialogata (che il prompt gli chiede espressamente)
## il racconto si svuotava.
const MARCATORI := ["-", "!", "•", "*"]

## Quanto puo' essere lunga una riga per passare da spunto: il prompt ne chiede di brevi
## ("max ~12 parole"). Una riga lunga e' prosa, e nel dubbio la prosa vince — perdere due
## suggerimenti si rimedia con quelli generici, perdere il racconto no.
const SPUNTO_MAX_CARATTERI := 110

## Narrazione E spunti in UNA chiamata sola.
##
## Prima erano due: Omero narrava, poi il Suggeritore rileggeva la stessa scena per
## proporre tre azioni. Sotto il free tier di Mistral ogni chiamata e' ~1 secondo di
## pavimento imposto dal limitatore, quindi la seconda si sentiva tutta — e per giunta
## arrivava DOPO che il testo era gia' a schermo. Gli spunti nascono comunque dalla
## narrazione: chiederli a chi l'ha appena scritta e' anche piu' coerente.
##
## La prosa resta libera (niente JSON, che peggiora la scrittura): il modello chiude con
## una riga separatrice e tre righe secche. Se non lo fa, spunti vuoti e il chiamante
## ripiega su quelli generici — la narrazione non si perde mai.
func narra_e_suggerisci(contesto: Dictionary, chat_fn: Callable, seed: int = 0) -> Dictionary:
	return _separa(await narra(contesto, chat_fn, seed, false))

## Divide l'uscita grezza in racconto e spunti.
##
## Cerca la prima riga di stacco che abbia sotto almeno DUE righe-spunto: la doppia
## condizione e' cio' che rende sicuro accettare separatori improvvisati (un "---" a meta'
## racconto non taglia niente se non e' seguito da un elenco). Se nessuno stacco combacia,
## guarda se il testo finisce comunque con una coda di righe-spunto.
func _separa(grezzo: String) -> Dictionary:
	var righe := grezzo.split("\n")
	for i in righe.size():
		if _e_stacco(righe[i]) and _leggi_spunti(righe.slice(i + 1)).size() >= 2:
			return {"narrazione": _prosa(righe.slice(0, i)), "spunti": _leggi_spunti(righe.slice(i + 1))}
	var da := _inizio_coda_spunti(righe)
	if da >= 0:
		return {"narrazione": _prosa(righe.slice(0, da)), "spunti": _leggi_spunti(righe.slice(da))}
	return {"narrazione": _prosa(righe), "spunti": []}

func _e_stacco(riga: String) -> bool:
	return _combacia(RE_INTESTAZIONE, riga) or _combacia(RE_SOLO_TRATTINI, riga)

## Il racconto: le righe ripulite dall'impalcatura (barre di separazione, etichette
## interne rimaste in maiuscolo). Il prompt le vieta gia', ma il prompt e' una preghiera:
## questa e' la garanzia.
func _prosa(righe: Array) -> String:
	var out: Array[String] = []
	for riga in righe:
		var r := String(riga)
		if _combacia(RE_SOLO_TRATTINI, r) or _combacia(RE_ETICHETTA, r):
			continue
		out.append(r)
	return "\n".join(out).strip_edges()

## Dove comincia l'elenco finale di spunti, se il modello l'ha scritto SENZA intestazione.
## -1 se in fondo non c'e' un elenco.
##
## Riconoscimento severo — TRE righe brevi, quante il prompt ne chiede — perche' qui non
## c'e' nessuna intestazione a fare da conferma: si sta indovinando su della prosa. Se
## sbaglia, mangia il finale del racconto. Meglio non riconoscere degli spunti (ci sono
## quelli generici di riserva) che amputare cio' che il giocatore deve leggere.
func _inizio_coda_spunti(righe: Array) -> int:
	var i := righe.size() - 1
	while i >= 0 and String(righe[i]).strip_edges() == "":
		i -= 1
	var ultimo := i
	while i >= 0 and _e_spunto(String(righe[i])):
		i -= 1
	return i + 1 if ultimo - i == 3 else -1

func _e_spunto(riga: String) -> bool:
	var r := riga.strip_edges()
	if r == "" or not MARCATORI.has(r.substr(0, 1)):
		return false
	return r.length() <= SPUNTO_MAX_CARATTERI

func _leggi_spunti(righe: Array) -> Array:
	var out: Array = []
	for riga in righe:
		var r := String(riga).strip_edges()
		if not _e_spunto(r):
			continue  # non e' uno spunto: coda di prosa, intestazione o commento
		# Il modello combina i marcatori ("- ! Getta il pesce…"): li sbuccio tutti, e se
		# fra questi c'e' un "!" lo spunto e' di quelli rischiosi.
		var rischio := false
		while r != "" and MARCATORI.has(r.substr(0, 1)):
			rischio = rischio or r.begins_with("!")
			r = r.substr(1).strip_edges()
		if r != "":
			out.append({"testo": r, "rischio": rischio})
		if out.size() >= 3:
			break
	return out

func _combacia(schema: String, testo: String) -> bool:
	var re := RegEx.new()
	re.compile(schema)
	return re.search(testo) != null

## `taglia_spunti`: vero per chi vuole solo la prosa (i passaggi fra le tappe, la console).
## Il modello potrebbe aggiungere il blocco anche quando non serve: qui lo si taglia via,
## cosi' non finisce mai a schermo come se fosse narrazione.
func narra(contesto: Dictionary, chat_fn: Callable, seed: int = 0, taglia_spunti: bool = true) -> String:
	var opzioni := {"temperature": 0.9}
	if seed != 0:
		opzioni["seed"] = seed
	var messaggi := costruisci_messaggi(contesto)

	var testo := await _chiedi(messaggi, chat_fn, opzioni)
	if testo != "" and not nomina_un_dio(testo):
		return _senza_spunti(testo) if taglia_spunti else testo

	# Ritenta una volta con richiamo severo.
	var messaggi2 := messaggi.duplicate(true)
	messaggi2.append({"role": "system", "content": "Hai nominato un dio: VIETATO. Riscrivi senza alcun nome divino, solo l'impronta."})
	var testo2 := await _chiedi(messaggi2, chat_fn, opzioni)
	if testo2 != "" and not nomina_un_dio(testo2):
		return _senza_spunti(testo2) if taglia_spunti else testo2

	# Ultima difesa: redigi i nomi. La proprieta' vale comunque.
	var base := testo2 if testo2 != "" else testo
	var pulito := redigi(base)
	return _senza_spunti(pulito) if taglia_spunti else pulito

func _senza_spunti(testo: String) -> String:
	return String(_separa(testo)["narrazione"])

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

## LA CAUSA DEL PASSAGGIO, detta a Omero a parole (R-12).
##
## Prima riceveva solo «da» e «a», e con due nomi si puo' scrivere una cosa sola: il mare che
## si allarga. La stessa prosa per una fuga e per un commiato — ed e' cosi' che si finisce a
## «combattere coi Ciconi e al turno dopo trovarsi dai Lotofagi». Non era il narratore a
## sbagliare: non aveva l'informazione, quindi non poteva darla.
##
## Le tre cause sono un elenco chiuso (`Viaggio.CAUSE`). Qui si traducono in un'istruzione,
## non in una frase fatta: il testo lo scrive lui, ma sa cosa deve rendere.
static func _perche(causa: String) -> String:
	match causa:
		"scelta":
			return "MOTIVO: la partenza è una SUA decisione. Che si veda l'atto di chi scioglie gli ormeggi perché ha finito qui, non un allontanarsi passivo."
		"cacciato":
			return "MOTIVO: se ne va SOTTO SPINTA — inseguito, respinto, non piu' tollerato. Che si senta chi lo caccia, anche senza nominarlo, e che la partenza abbia il sapore di una perdita."
		"prodigio":
			return "MOTIVO: non e' stata una sua scelta ne' una cacciata: qualcosa di piu' grande lo ha spostato — vento, corrente, sonno, smarrimento. Che il lettore capisca di aver assistito a un prodigio, senza che nessuno lo spieghi."
		_:
			return ""
