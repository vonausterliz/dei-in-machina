extends GutTest

func test_carica_pantheon_da_file():
	var p := Pantheon.carica("res://data/pantheon.json")
	assert_gt(p.numero_dei(), 0, "il pantheon deve contenere degli dei")
	assert_true(p.ha("zeus"))
	assert_true(p.ha("poseidone"))
	assert_true(p.ha("atena"))

func test_dio_atena_campi_base():
	var p := Pantheon.carica("res://data/pantheon.json")
	var atena := p.get_dio("atena")
	assert_not_null(atena)
	assert_eq(atena.nome, "Atena")
	assert_eq(atena.fascia, "persistente")
	assert_true(atena.attivo)
	assert_has(atena.trigger_azione, "astuzia")

func test_dei_attivi_solo_persistenti_allo_stadio_1():
	var p := Pantheon.carica("res://data/pantheon.json")
	for dio in p.dei_attivi():
		assert_eq(dio.fascia, "persistente", "allo stadio 1 solo i persistenti hanno attivo:true")

func test_id_sconosciuto_restituisce_null():
	var p := Pantheon.carica("res://data/pantheon.json")
	assert_null(p.get_dio("afrodite"))
