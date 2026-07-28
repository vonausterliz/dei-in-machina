class_name StatoPartita
extends RefCounted

## Stato di partita RUNTIME (schema 0.3, vedi data/stato_partita.json).
## Le sotto-strutture non ancora manipolate da logica di gioco (diario,
## storico_olimpo, coalizioni, scavalcamenti_pendenti, relazioni) restano
## Dictionary/Array grezzi: tipizzarle oltre serve solo dalle fasi che le
## useranno davvero (deliberazione, politica divina, coalizioni).

var run_id: String = ""
var seed_partita: int = 0
var creato: String = ""
var aggiornato: String = ""
var turno: int = 0
var stato: String = "in_corso"
var esito: Variant = null
var esiti_possibili: Array[String] = []

var ulisse: Dictionary = {}
var viaggio: Dictionary = {}
var registro_divino: Dictionary = {}
var relazioni: Dictionary = {}
var scavalcamenti_pendenti: Array = []
var ammonizioni: Dictionary = {}
var diario: Array = []
var storico_olimpo: Array = []
var coalizioni: Array = []

static func nuova(pantheon: Pantheon, seed_partita: int, run_id: String = "") -> StatoPartita:
	var s := StatoPartita.new()
	s.run_id = run_id if run_id != "" else "run-%d" % Time.get_ticks_usec()
	s.seed_partita = seed_partita
	var adesso := Time.get_datetime_string_from_system(true) + "Z"
	s.creato = adesso
	s.aggiornato = adesso
	s.turno = 0
	s.stato = "in_corso"
	s.esito = null
	s.esiti_possibili = ["itaca", "morte", "prigionia_eterna", "follia", "ciurma_perduta"]
	s.ulisse = {
		"episodio_corrente": null,
		"stat": {"metis": 50, "animo": 50, "ciurma": {"vivi": 45, "iniziali": 45}},
		"hybris": 0,
		"cimeli": [],
	}
	s.viaggio = {"ordine_episodi": [], "completati": [], "corrente": null}
	s.registro_divino = {}
	for dio in pantheon.tutti():
		# I persistenti attivi sono "in gioco" fin dall'inizio (sempre in ascolto);
		# i locali entrano in gioco quando si raggiunge il loro episodio.
		var in_gioco := dio.attivo and dio.fascia == "persistente"
		s.registro_divino[dio.id] = {
			"favore": dio.favore_iniziale,
			"ira": dio.ira_iniziale,
			"umore": "",
			"risvegliato": in_gioco,
		}
	s.relazioni = {"zeus_verso": {}}
	for id in pantheon.tutti_gli_id():
		if id != "zeus":
			s.relazioni["zeus_verso"][id] = 0
	s.scavalcamenti_pendenti = []
	s.ammonizioni = {
		"contatore": 0,
		"soglia": 3,
		"turni_puliti": 0,
		"decadimento_ogni": 3,
		"ultimo_richiamo": null,
	}
	s.diario = []
	s.storico_olimpo = []
	s.coalizioni = []
	return s

static func carica(path: String) -> StatoPartita:
	# Nessun salvataggio ancora e' condizione normale, non un errore di sistema.
	if not FileAccess.file_exists(path):
		return null
	var testo := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(testo)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("StatoPartita: JSON non valido: %s" % path)
		return null
	return StatoPartita.from_dict(parsed)

static func from_dict(d: Dictionary) -> StatoPartita:
	var s := StatoPartita.new()
	var meta: Dictionary = d.get("_meta", {})
	s.run_id = meta.get("run_id", "")
	s.seed_partita = meta.get("seed", 0)
	s.creato = meta.get("creato", "")
	s.aggiornato = meta.get("aggiornato", "")
	s.turno = meta.get("turno", 0)
	s.stato = meta.get("stato", "in_corso")
	s.esito = meta.get("esito", null)
	var esiti: Array[String] = []
	for v in meta.get("esiti_possibili", []):
		esiti.append(String(v))
	s.esiti_possibili = esiti
	s.ulisse = d.get("ulisse", {})
	s.viaggio = d.get("viaggio", {})
	s.registro_divino = d.get("registro_divino", {})
	s.relazioni = d.get("relazioni", {})
	s.scavalcamenti_pendenti = d.get("scavalcamenti_pendenti", [])
	s.ammonizioni = d.get("ammonizioni", {})
	s.diario = d.get("diario", [])
	s.storico_olimpo = d.get("storico_olimpo", [])
	s.coalizioni = d.get("coalizioni", [])
	return s

func to_dict() -> Dictionary:
	return {
		"_meta": {
			"gioco": "Dei in machina",
			"versione_schema": "0.3",
			"run_id": run_id,
			"seed": seed_partita,
			"creato": creato,
			"aggiornato": aggiornato,
			"turno": turno,
			"stato": stato,
			"esito": esito,
			"esiti_possibili": esiti_possibili,
		},
		"ulisse": ulisse,
		"viaggio": viaggio,
		"registro_divino": registro_divino,
		"relazioni": relazioni,
		"scavalcamenti_pendenti": scavalcamenti_pendenti,
		"ammonizioni": ammonizioni,
		"diario": diario,
		"storico_olimpo": storico_olimpo,
		"coalizioni": coalizioni,
	}

func salva(path: String) -> bool:
	aggiornato = Time.get_datetime_string_from_system(true) + "Z"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("StatoPartita: impossibile scrivere %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true
