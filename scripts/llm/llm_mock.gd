class_name LLMMock
extends RefCounted

## Implementazione finta di LLMManager: nessuna rete, output predefiniti e
## deterministici. Permette di far girare l'intera macchina del turno senza
## token, latenza o modelli attivi (mandato di auto-verifica, CLAUDE.md).

const _FIXTURES_INTERPRETE := {
	"nessuno": {
		"plausibilita": "in_mondo", "tipo": "parola", "tag": ["astuzia", "inganno"],
		"dio_invocato": null, "bersaglio": "polifemo", "tono": "astuto", "intensita": 2,
		"sintesi": "Ulisse si presenta come 'Nessuno' al ciclope.",
	},
	"sono io, odisseo": {
		"plausibilita": "in_mondo", "tipo": "parola", "tag": ["vanto", "tracotanza"],
		"dio_invocato": null, "bersaglio": "polifemo", "tono": "sfida", "intensita": 2,
		"sintesi": "Ulisse grida il proprio nome al ciclope accecato.",
	},
	"prendo un aereo": {
		"plausibilita": "anacronistico", "tipo": "azione", "tag": [],
		"dio_invocato": null, "bersaglio": null, "tono": "neutro", "intensita": 1,
		"sintesi": "Richiesta priva di senso nel mondo del gioco.",
	},
	# Preghiera con riferimento ALLUSIVO: tag vuoto e dio_invocato null di proposito,
	# cosi' l'eventuale risveglio deriva solo dalla risoluzione dell'epiteto (GameManager).
	"capo dell'olimpo": {
		"plausibilita": "in_mondo", "tipo": "preghiera", "tag": [],
		"dio_invocato": null, "bersaglio": null, "tono": "umile", "intensita": 2,
		"sintesi": "Ulisse invoca il signore dell'Olimpo.",
	},
	# Astuzia + tracotanza insieme: sveglia Atena (astuzia) E Poseidone (tracotanza),
	# che propongono registri opposti -> CONFLITTO, per collaudare la deliberazione.
	"vanto della mia astuzia": {
		"plausibilita": "in_mondo", "tipo": "parola", "tag": ["astuzia", "tracotanza"],
		"dio_invocato": null, "bersaglio": null, "tono": "sfida", "intensita": 2,
		"sintesi": "Ulisse si vanta della propria astuzia sfidando le potenze.",
	},
	# Azioni di PROGRESSO (fanno avanzare la tappa): fuga e rotta.
	"fugg": {
		"plausibilita": "in_mondo", "tipo": "azione", "tag": ["fuga"],
		"dio_invocato": null, "bersaglio": null, "tono": "risoluto", "intensita": 2,
		"sintesi": "Ulisse fugge, lasciandosi il pericolo alle spalle.",
	},
	"scapp": {
		"plausibilita": "in_mondo", "tipo": "azione", "tag": ["fuga"],
		"dio_invocato": null, "bersaglio": null, "tono": "risoluto", "intensita": 2,
		"sintesi": "Ulisse scappa via.",
	},
	"salp": {
		"plausibilita": "in_mondo", "tipo": "movimento", "tag": ["rotta"],
		"dio_invocato": null, "bersaglio": null, "tono": "deciso", "intensita": 1,
		"sintesi": "Ulisse salpa e riprende il mare.",
	},
	"riprendo il mare": {
		"plausibilita": "in_mondo", "tipo": "movimento", "tag": ["rotta"],
		"dio_invocato": null, "bersaglio": null, "tono": "deciso", "intensita": 1,
		"sintesi": "Ulisse riprende la rotta verso casa.",
	},
}

const _ENVELOPE_DEFAULT := {
	"plausibilita": "in_mondo", "tipo": "azione", "tag": [],
	"dio_invocato": null, "bersaglio": null, "tono": "neutro", "intensita": 1,
	"sintesi": "",
}

func interpreta(testo_libero: String) -> Dictionary:
	var chiave := testo_libero.to_lower()
	for frammento in _FIXTURES_INTERPRETE.keys():
		if chiave.find(frammento) != -1:
			return (_FIXTURES_INTERPRETE[frammento] as Dictionary).duplicate(true)
	var esito: Dictionary = _ENVELOPE_DEFAULT.duplicate(true)
	esito["sintesi"] = "Ulisse: \"%s\"" % testo_libero
	return esito

## contesto atteso: {"favore": int, "ira": int, "umore": String}
func proposta_dio(dio: Dio, _contesto: Dictionary) -> Dictionary:
	var registro: String = dio.registri[0] if dio.registri.size() > 0 else "silenzio"
	var battuta: String = dio.esempi_voce[0] if dio.esempi_voce.size() > 0 else "..."
	return {
		"dio": dio.id,
		"registro": registro,
		"dice": battuta,
		"intensita": 1,
	}

## Verdetto dell'Arbitro (Zeus): deterministico nel mock — vince la proposta piu'
## intensa (a parita', l'ordine di arrivo). Ritorna {attore, registro, intensita, dice}.
func verdetto_arbitro(proposte: Array, _contesto: Dictionary = {}) -> Dictionary:
	if proposte.is_empty():
		return {"attore": "", "registro": "silenzio", "intensita": 1, "dice": ""}
	var scelta: Dictionary = proposte[0]
	for p in proposte:
		if int(p.get("intensita", 1)) > int(scelta.get("intensita", 1)):
			scelta = p
	return {
		"attore": scelta.get("dio", ""),
		"registro": scelta.get("registro", "silenzio"),
		"intensita": int(scelta.get("intensita", 1)),
		"dice": "Ho udito. Decido io.",
	}

## contesto atteso: {"sintesi": String, ...}. Non nomina MAI un dio (invariante di design).
func narrazione_omero(contesto: Dictionary) -> String:
	var sintesi: String = contesto.get("sintesi", "qualcosa accade")
	return "Un dio - e non diro' quale - osservo' %s. Le conseguenze si vedranno." % sintesi
