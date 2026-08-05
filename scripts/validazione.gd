class_name Validazione
extends RefCounted

## VAGLIO e AMMONIZIONE: decide se una mossa appartiene al mondo dell'Odissea e, se non
## vi appartiene, con quanta durezza il mondo la respinge (design sez. 6).
##
## Scala DOLCE, perche' qui il falso positivo uccide il gioco:
##   in_mondo   -> turno pulito (+1) e decadimento graduale dell'ammonizione;
##   fuori-mondo -> contatore +1; primo scivolone = solo richiamo (nessun danno),
##                  se insisti = smarrimento (l'animo cala), alla soglia = follia (fine).
##
## Estratto da GameManager: la regola vive qui, isolata e testabile da sola.

## Entita' del crollo d'animo per smarrimento e per follia (valori-seme).
const CALO_SMARRIMENTO := 8
const CALO_FOLLIA := 100

## Parole inequivocabilmente MODERNE: se compaiono, l'azione e' fuori dal mondo anche se
## l'LLM l'ha classificata in_mondo. Lista mirata (alta precisione), non esaustiva: il


var _stato: StatoPartita

func _init(stato: StatoPartita) -> void:
	_stato = stato

## Vero se il testo contiene un marcatore moderno come PAROLA INTERA (maiuscole ignorate).
static func e_anacronistico(input_testo: String) -> bool:
	var t := input_testo.to_lower()
	var re := RegEx.new()
	for m in Lingua.marcatori_anacronismo():
		re.compile("\\b" + m + "\\b")
		if re.search(t) != null:
			return true
	return false

## VAGLIO. Decide se la mossa appartiene al mondo, e adesso decide anche nell'ALTRO verso:
## un rifiuto sbagliato si ribalta.
##
## PERCHE'. In partita vera (5 agosto 2026) l'Interprete ha respinto tre mosse cosi':
##   «sono odisseo! il più forte guerriero acheo»  -> anacronistico, tono=vanto, tag=[]
##   «distruggiamo tutta la città dei cicorni»     -> assurdo_diegetico, tono=tracotanza
## Niente di moderno in nessuna delle due; la seconda e' il sacco di Ismaro, cioe' CANONE.
## Il tono dice che il modello aveva capito: e' l'etichetta che ha sbagliato, perche'
## «insensato» e «di un'altra epoca» gli si confondono. E il rifiuto costa un'ammonizione,
## in una scala che finisce in follia: tre vanterie di fila chiudevano la partita. Il gioco
## puniva come pazzia cio' per cui esiste — la tracotanza e' il motore del poema.
##
## Due regole, e la differenza fra le due e' il tipo di verdetto che sono:
##
##  1. «anacronistico» e' OGGETTIVO — nomina cose di un'altra epoca — e c'e' un
##     riconoscitore deterministico. Senza marcatore il verdetto e' falso, e si scarta:
##     non serve chiedere a nessuno, non costa niente.
##  2. Le altre classi fuori-mondo sono GIUDIZI. Un giudizio che puo' chiudere la partita
##     vuole due pareri concordi: l'Interprete propone, il Vaglio conferma. Costa una
##     chiamata in piu' solo quando si sta per respingere — cioe' di rado, e nell'unico
##     punto in cui sbagliare si paga caro.
##
## In mock il secondo parere tace (""), quindi nessuna conferma arriva e il rifiuto cade:
## i test restano deterministici, e dalla parte giusta — «il falso positivo uccide il gioco».
func vaglia(envelope: Dictionary, input_testo: String) -> void:
	# Il marcatore deterministico vale su tutto e per primo: se c'e', non si discute.
	if e_anacronistico(input_testo):
		_respingi(envelope, "anacronistico")
		return
	var detta: String = String(envelope.get("plausibilita", ""))
	if detta == "in_mondo":
		# Secondo parere: coglie gli anacronismi che nessuna lista puo' prevedere
		# (GPS, penicillina, ascensore...).
		var classe: String = await LLMManager.verifica_plausibilita(input_testo)
		if classe != "" and classe != "in_mondo":
			_respingi(envelope, classe)
		return
	# L'INTERPRETE HA RESPINTO, e di moderno non c'e' niente.
	if detta == "anacronistico":
		envelope["plausibilita"] = "in_mondo"   # oggettivamente falso: nessun marcatore
		return
	var conferma: String = await LLMManager.verifica_plausibilita(input_testo)
	if conferma != "" and conferma != "in_mondo":
		_respingi(envelope, conferma)     # due pareri concordi: il rifiuto sta in piedi
	else:
		envelope["plausibilita"] = "in_mondo"

## Un rifiuto DEFINITIVO porta via i tag: fuori dal mondo non c'e' niente a cui reagire
## (regola 5 del contratto). Stava nel prompt, e un prompt e' una preghiera: se il modello
## la disattendeva, i tag di una mossa respinta restavano in giro. Ora e' codice — e vale
## anche per il ramo deterministico, che prima li lasciava passare.
##
## Il contrario e' altrettanto importante: finche' il rifiuto non e' definitivo i tag NON
## si toccano. Sono `vanto` e `tracotanza`, cioe' cio' che desta Poseidone: un verdetto
## ribaltato che restituisse un envelope svuotato sarebbe una mossa formalmente valida che
## non sveglia piu' nessuno — il guasto sopravvissuto alla correzione, e in silenzio.
func _respingi(envelope: Dictionary, classe: String) -> void:
	envelope["plausibilita"] = classe
	envelope["tag"] = []

## Ritorna {in_mondo, delta, esito, classe}.
## classe: "" (nessuna) | "richiamo" | "smarrimento" | "follia".
func valida(envelope: Dictionary, input_testo: String) -> Dictionary:
	var amm: Dictionary = _stato.ammonizioni
	# La plausibilita' e' gia' passata da vaglia(); qui si ripete il controllo
	# deterministico perche' valida() e' usata anche da sola (test, strumenti).
	var in_mondo: bool = envelope.get("plausibilita", "") == "in_mondo" and not e_anacronistico(input_testo)
	if not in_mondo and envelope.get("plausibilita", "") == "in_mondo":
		envelope["plausibilita"] = "anacronistico"

	if in_mondo:
		amm["turni_puliti"] = int(amm.get("turni_puliti", 0)) + 1
		var ogni: int = int(amm.get("decadimento_ogni", 3))
		if int(amm.get("contatore", 0)) > 0 and ogni > 0 and amm["turni_puliti"] % ogni == 0:
			amm["contatore"] = int(amm["contatore"]) - 1  # torni sensato: si dimentica
		return {"in_mondo": true, "delta": {}, "esito": "continua", "classe": ""}

	# Fuori dal mondo: sale l'ammonizione, azzero i turni puliti.
	amm["contatore"] = int(amm.get("contatore", 0)) + 1
	amm["turni_puliti"] = 0
	amm["ultimo_richiamo"] = {
		"turno": _stato.turno,
		"input": input_testo,
		"classe": envelope.get("plausibilita", ""),
	}

	var soglia: int = int(amm.get("soglia", 3))
	var contatore: int = int(amm["contatore"])
	if contatore >= soglia:
		# LA FOLLIA UCCIDE. L'esito si chiamava "follia" e la partita finiva li': ma la
		# follia e' la CAUSA, non il finale. Chi perde la ragione per l'empieta' reiterata
		# muore — ed e' cosi' che `morte`, dichiarata fra gli esiti fin dal design e mai
		# prodotta da nessuna riga di codice, diventa un finale raggiungibile.
		# La `classe` resta "follia": e' la diagnosi, e dice di cosa si e' morti.
		return {"in_mondo": false, "delta": {"ulisse.animo": -CALO_FOLLIA}, "esito": "morte", "classe": "follia"}
	if contatore >= 2:
		# SMARRIMENTO: il mondo legge il nonsenso come sbandamento, l'animo cala.
		return {"in_mondo": false, "delta": {"ulisse.animo": -CALO_SMARRIMENTO}, "esito": "continua", "classe": "smarrimento"}
	# Primo scivolone: solo richiamo, nessun danno.
	return {"in_mondo": false, "delta": {}, "esito": "continua", "classe": "richiamo"}
