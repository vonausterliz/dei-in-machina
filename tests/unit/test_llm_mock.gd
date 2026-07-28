extends GutTest

var _mock: LLMMock
var _pantheon: Pantheon

func before_each():
	_mock = LLMMock.new()
	_pantheon = Pantheon.carica("res://data/pantheon.json")

func test_interpreta_e_deterministico():
	var e1 := _mock.interpreta("Sono io, Odisseo, che t'ho accecato!")
	var e2 := _mock.interpreta("Sono io, Odisseo, che t'ho accecato!")
	assert_eq(e1, e2, "stesso input deve produrre lo stesso envelope: coerenza del tagging")
	assert_has(e1["tag"], "vanto")
	assert_has(e1["tag"], "tracotanza")

func test_interpreta_input_ignoto_ha_tag_vuoti():
	var e := _mock.interpreta("Raccolgo dell'acqua dal pozzo.")
	assert_eq(e["tag"], [])
	assert_eq(e["plausibilita"], "in_mondo")

func test_interpreta_input_anacronistico():
	var e := _mock.interpreta("Prendo un aereo per tornare a casa.")
	assert_eq(e["plausibilita"], "anacronistico")
	assert_eq(e["tag"], [], "parsimonia sui tag quando plausibilita != in_mondo")

func test_proposta_dio_usa_dati_del_pantheon():
	var atena := _pantheon.get_dio("atena")
	var proposta := _mock.proposta_dio(atena, {})
	assert_eq(proposta["dio"], "atena")
	assert_has(atena.registri, proposta["registro"])
	assert_has(atena.esempi_voce, proposta["dice"])

func test_verdetto_arbitro_senza_proposte_e_silenzio():
	var v := _mock.verdetto_arbitro([])
	assert_eq(v["registro"], "silenzio")

func test_narrazione_omero_non_nomina_mai_un_dio():
	# Invariante di design (CLAUDE.md, sez. "Due invarianti"): la narrazione
	# rivolta al giocatore non nomina MAI un dio. Va verificata come test, non
	# solo affidata al prompt.
	var contesti := [
		{"sintesi": "Ulisse grida il proprio nome al ciclope."},
		{"sintesi": "Ulisse offre vino allo straniero."},
		{"sintesi": "La nave scivola tra le onde."},
	]
	for contesto in contesti:
		var narrazione: String = _mock.narrazione_omero(contesto)
		var narrazione_bassa := narrazione.to_lower()
		for dio in _pantheon.tutti():
			assert_eq(
				narrazione_bassa.find(dio.nome.to_lower()), -1,
				"la narrazione non deve mai nominare '%s': \"%s\"" % [dio.nome, narrazione]
			)
