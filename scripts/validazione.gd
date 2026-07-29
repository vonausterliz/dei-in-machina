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
## resto lo intercettano il prompt dell'Interprete e il secondo parere (vaglia()).
const MARCATORI_ANACRONISMO := [
	# armi da fuoco ed esplosivi
	"pistola", "pistole", "fucile", "fucili", "mitra", "mitraglia", "mitragliatrice",
	"revolver", "sparo", "sparare", "spara", "sparano", "sparai", "sparammo", "sparato",
	"sparargli", "sparerò", "sparero", "pallottola", "pallottole", "proiettile",
	"proiettili", "bomba", "bombe", "bombardo", "granata", "granate", "esplosivo",
	"esplosivi", "dinamite", "tritolo", "missile", "missili", "razzo", "bazooka",
	"kalashnikov", "cannone", "cannoni", "artiglieria", "siluro",
	# mezzi militari e motorizzati
	"carro armato", "carri armati", "tank", "corazzata", "sottomarino", "portaerei",
	"aereo", "aerei", "aeroplano", "elicottero", "drone", "droni", "motoscafo",
	"automobile", "camion", "motore", "motori", "treno",
	# tecnologia
	"telefono", "telefonare", "telefono a", "cellulare", "smartphone", "computer",
	"internet", "wifi", "email", "radio", "televisione", "televisore", "elettricità",
	"elettricita", "batteria", "benzina", "gasolio", "fotografia", "orologio digitale",
	# sostanze e gergo moderni
	"droga", "droghe", "cocaina", "eroina", "marijuana", "spinello", "sballo",
	"raga", "bro", "videogioco", "respawn", "resetta", "gameover", "game over", "prompt",
]

var _stato: StatoPartita

func _init(stato: StatoPartita) -> void:
	_stato = stato

## Vero se il testo contiene un marcatore moderno come PAROLA INTERA (maiuscole ignorate).
static func e_anacronistico(input_testo: String) -> bool:
	var t := input_testo.to_lower()
	var re := RegEx.new()
	for m in MARCATORI_ANACRONISMO:
		re.compile("\\b" + m + "\\b")
		if re.search(t) != null:
			return true
	return false

## VAGLIO a tre livelli (dal piu' economico al piu' capace):
##  1. l'Interprete l'ha gia' detta fuori-mondo -> niente da fare;
##  2. marcatore moderno evidente -> fuori-mondo per regola (gratis, deterministico);
##  3. altrimenti SECONDO PARERE dell'LLM, una domanda secca dedicata: coglie gli
##     anacronismi che nessuna lista puo' prevedere (GPS, penicillina, ascensore...).
## In mock il livello 3 non fa nulla: i test restano deterministici.
func vaglia(envelope: Dictionary, input_testo: String) -> void:
	if envelope.get("plausibilita", "") != "in_mondo":
		return
	if e_anacronistico(input_testo):
		envelope["plausibilita"] = "anacronistico"
		return
	var classe: String = await LLMManager.verifica_plausibilita(input_testo)
	if classe != "" and classe != "in_mondo":
		envelope["plausibilita"] = classe
		envelope["tag"] = []  # regola 5 del contratto: fuori-mondo -> nessun tag

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
		# FOLLIA: un dio colpisce l'empieta reiterata. Fine.
		return {"in_mondo": false, "delta": {"ulisse.animo": -CALO_FOLLIA}, "esito": "follia", "classe": "follia"}
	if contatore >= 2:
		# SMARRIMENTO: il mondo legge il nonsenso come sbandamento, l'animo cala.
		return {"in_mondo": false, "delta": {"ulisse.animo": -CALO_SMARRIMENTO}, "esito": "continua", "classe": "smarrimento"}
	# Primo scivolone: solo richiamo, nessun danno.
	return {"in_mondo": false, "delta": {}, "esito": "continua", "classe": "richiamo"}
