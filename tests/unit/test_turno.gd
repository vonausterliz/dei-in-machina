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

func test_vanto_scatena_castigo_e_abbassa_animo():
	var animo0: int = GameManager.stato.ulisse["stat"]["animo"]
	var ira0: int = GameManager.stato.registro_divino["poseidone"]["ira"]
	var esito := await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	# Poseidone reagisce con castigo (il suo primo registro nel mock).
	assert_eq(esito["voce"]["verdetto"]["attore"], "poseidone")
	assert_eq(esito["voce"]["verdetto"]["registro"], "castigo")
	# Il delta ha abbassato l'animo e alzato l'ira di Poseidone.
	assert_lt(GameManager.stato.ulisse["stat"]["animo"], animo0)
	assert_gt(GameManager.stato.registro_divino["poseidone"]["ira"], ira0)
	# La hybris e' salita (vanto + tracotanza).
	assert_gt(GameManager.stato.ulisse["hybris"], 0)
	# Diario: ando' male.
	assert_eq(GameManager.stato.diario[-1]["esito"], "ill")
	# FSM completa con reazione.
	for fase in ["DELIBERAZIONE", "ARBITRATO", "APPLICAZIONE"]:
		assert_has(esito["fsm_path"], fase)

func test_astuzia_scatena_aiuto_di_atena():
	var esito := await GameManager.esegui_turno("Dico al gigante che il mio nome e' Nessuno.")
	assert_eq(esito["voce"]["verdetto"]["attore"], "atena")
	assert_eq(esito["voce"]["verdetto"]["registro"], "aiuto")
	assert_eq(GameManager.stato.diario[-1]["esito"], "fair")

func test_esito_ciurma_perduta_termina_partita():
	# Forzo la ciurma a 0: il prossimo controllo d'esito deve dichiarare la sconfitta.
	GameManager.stato.ulisse["stat"]["ciurma"]["vivi"] = 0
	var esito := await GameManager.esegui_turno("Riempio gli otri d'acqua alla sorgente.")
	assert_eq(esito["esito"], "ciurma_perduta")
	assert_eq(GameManager.stato.stato, "finita")
	assert_eq(GameManager.stato.esito, "ciurma_perduta")

func test_turno_senza_dei_niente_reazione():
	var esito := await GameManager.esegui_turno("Riempio gli otri d'acqua alla sorgente.")
	assert_eq(esito["svegli"], [])
	assert_true(esito["voce"]["deliberazione"].is_empty())
	assert_does_not_have(esito["fsm_path"], "ARBITRATO")

func test_preghiera_allusiva_sveglia_zeus():
	# "il capo dell'olimpo" -> zeus via risoluzione deterministica. Il mock restituisce
	# tipo preghiera, tag [], dio_invocato null: l'unico modo in cui Zeus si sveglia
	# e' la risoluzione dell'epiteto. Prova che l'allusione funziona end-to-end.
	var esito := await GameManager.esegui_turno("Mi rivolgo al capo dell'olimpo e lo supplico.")
	assert_eq(esito["voce"]["envelope"]["dio_invocato"], "zeus")
	assert_eq(esito["svegli"], ["zeus"])

func test_menzione_non_invocativa_non_sveglia():
	# Stessa allusione ma senza intento di preghiera (tipo azione, tag []): il gating
	# impedisce la risoluzione, nessun dio si sveglia per una menzione di passaggio.
	var esito := await GameManager.esegui_turno("Riempio gli otri d'acqua alla sorgente.")
	assert_eq(esito["voce"]["envelope"].get("dio_invocato"), null)
	assert_eq(esito["svegli"], [])

func test_registro_persistenti_in_gioco_da_subito():
	# Re-eval Fase 0: i persistenti attivi nascono "risvegliato:true".
	var reg: Dictionary = GameManager.stato.registro_divino
	assert_true(reg["atena"]["risvegliato"])
	assert_true(reg["poseidone"]["risvegliato"])
	assert_true(reg["zeus"]["risvegliato"])
	assert_false(reg["circe"]["risvegliato"], "un locale non e' in gioco all'inizio")
