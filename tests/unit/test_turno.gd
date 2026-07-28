extends GutTest

## Integrazione della macchina del turno (GameManager.esegui_turno) col mock.
## Deterministico: LLMManager in mock, seed fisso. Verifica transizioni FSM,
## risveglio instradato, registrazioni e l'invariante "Omero non nomina dei".

var _pantheon: Pantheon

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(12345)
	_pantheon = Pantheon.carica("res://data/pantheon.json")

func test_turno_in_mondo_sveglia_e_registra():
	var esito := await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	assert_true(esito["in_mondo"])
	assert_eq(esito["svegli"], ["poseidone"])
	assert_eq(esito["esito"], "continua")
	# La FSM ha attraversato il RISVEGLIO.
	assert_has(esito["fsm_path"], "RISVEGLIO")
	assert_eq(esito["fsm_path"][0], "INTERPRETAZIONE")
	assert_eq(esito["fsm_path"][-1], "AVANZAMENTO")
	# Registrazioni.
	assert_eq(GameManager.stato.turno, 1)
	assert_eq(GameManager.stato.storico_olimpo.size(), 1)
	assert_eq(GameManager.stato.diario.size(), 1)

func test_turno_fuori_mondo_salta_risveglio():
	var esito := await GameManager.esegui_turno("Prendo un aereo e volo a Itaca.")
	assert_false(esito["in_mondo"])
	assert_eq(esito["svegli"], [])
	assert_does_not_have(esito["fsm_path"], "RISVEGLIO", "fuori-mondo non risveglia dei")
	# Comunque narrato e registrato (Omero fa da richiamo diegetico).
	assert_ne(esito["voce"]["narrazione_omero"], "")
	assert_eq(GameManager.stato.storico_olimpo.size(), 1)

func test_turni_multipli_avanzano_il_contatore():
	await GameManager.esegui_turno("Dico al gigante che il mio nome e' Nessuno.")
	await GameManager.esegui_turno("Riempio gli otri d'acqua alla sorgente.")
	assert_eq(GameManager.stato.turno, 2)
	assert_eq(GameManager.stato.storico_olimpo.size(), 2)

func test_astuzia_sveglia_atena_nel_turno():
	var esito := await GameManager.esegui_turno("Dico al gigante che il mio nome e' Nessuno.")
	assert_eq(esito["svegli"], ["atena"])

func test_invariante_omero_non_nomina_dei():
	# Pilastro del "nascosto" (CLAUDE.md): la narrazione player-facing non nomina MAI un dio.
	var frasi := [
		"Sono io, Odisseo, che t'ho accecato!",
		"Dico al gigante che il mio nome e' Nessuno.",
		"Riempio gli otri d'acqua alla sorgente.",
	]
	for frase in frasi:
		var esito := await GameManager.esegui_turno(frase)
		var narrazione: String = esito["voce"]["narrazione_omero"]
		var bassa := narrazione.to_lower()
		for dio in _pantheon.tutti():
			assert_eq(bassa.find(dio.nome.to_lower()), -1,
				"narrazione nomina '%s': \"%s\"" % [dio.nome, narrazione])

func test_registro_persistenti_in_gioco_da_subito():
	# Re-eval Fase 0: i persistenti attivi nascono "risvegliato:true".
	var reg: Dictionary = GameManager.stato.registro_divino
	assert_true(reg["atena"]["risvegliato"])
	assert_true(reg["poseidone"]["risvegliato"])
	assert_true(reg["zeus"]["risvegliato"])
	assert_false(reg["circe"]["risvegliato"], "un locale non e' in gioco all'inizio")
