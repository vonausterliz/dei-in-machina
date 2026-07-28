extends GutTest

var _pantheon: Pantheon

func before_each():
	_pantheon = Pantheon.carica("res://data/pantheon.json")

func test_nuova_partita_inizializza_registro_da_pantheon():
	var s := StatoPartita.nuova(_pantheon, 42)
	assert_eq(s.seed_partita, 42)
	assert_eq(s.turno, 0)
	assert_true(s.registro_divino.has("poseidone"))
	assert_eq(s.registro_divino["poseidone"]["ira"], _pantheon.get_dio("poseidone").ira_iniziale)
	assert_true(s.relazioni["zeus_verso"].has("poseidone"))
	assert_false(s.relazioni["zeus_verso"].has("zeus"), "zeus non cova ira verso se stesso")

func test_round_trip_salva_e_carica():
	var s := StatoPartita.nuova(_pantheon, 7)
	s.turno = 3
	s.diario.append({"turno": 3, "voce": "prova", "esito": "fair"})
	var path := "user://_test_stato_partita.json"
	assert_true(s.salva(path))

	var ricaricato := StatoPartita.carica(path)
	assert_not_null(ricaricato)
	assert_eq(ricaricato.turno, 3)
	assert_eq(ricaricato.seed_partita, 7)
	assert_eq(ricaricato.diario.size(), 1)

	var dir := DirAccess.open("user://")
	if dir:
		dir.remove("_test_stato_partita.json")

func test_carica_esempio_fornito():
	var s := StatoPartita.carica("res://data/stato_partita.json")
	assert_not_null(s)
	assert_eq(s.turno, 12)
	assert_eq(s.run_id, "run-7f3a9c")
	assert_true(s.registro_divino.has("atena"))
	assert_eq(s.storico_olimpo.size(), 1)

func test_carica_file_mancante_restituisce_null():
	assert_null(StatoPartita.carica("res://data/non_esiste.json"))
