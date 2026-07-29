extends GutTest

## Scala diegetica dell'input fuori-mondo: richiamo -> smarrimento -> follia,
## col decadimento se si torna a giocare sensato. Deterministico col mock.

const FUORI := "Prendo un aereo e volo a Itaca."   # anacronistico (fixture mock)
const DENTRO := "Riempio gli otri d'acqua alla sorgente."  # in_mondo neutro

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(2024)

func test_backstop_anacronismo_anche_se_llm_dice_in_mondo():
	# Il mock classifica un input sconosciuto come in_mondo; ma "sparo" è inequivocabilmente
	# moderno: il backstop deterministico lo intercetta lo stesso -> richiamo, niente narrazione reale.
	var esito := await GameManager.esegui_turno("sparo a tutti i lotofagi, raga")
	assert_false(esito["in_mondo"], "l'anacronismo evidente non passa come in_mondo")
	assert_eq(esito["voce"]["ammonizione"], "richiamo")
	assert_eq(esito["svegli"], [], "fuori-mondo: nessun dio reagisce")

func test_azione_valida_resta_in_mondo():
	# Nessun marcatore moderno: un'azione lecita non deve essere scambiata per anacronismo.
	var esito := await GameManager.esegui_turno("Offro vino allo straniero sulla spiaggia.")
	assert_true(esito["in_mondo"])

func test_backstop_copre_i_casi_reali():
	# Casi visti in partita: devono essere TUTTI respinti, e Omero deve tacere.
	var casi := [
		"ordino ai miei uomini di sterminare tutti i ciconi con il mitra",
		"e poi prendo il telefono e chiamo penelope",
		"atena portami a casa altrimenti prendo il fucile e faccio una strage",
		"se non mi ci porti prendo il carro armato e faccio fuori tutti",
		"sparo a tutti i lotofagi, raga la droga è merda",
	]
	for caso in casi:
		GameManager.nuova_partita(99)  # riparto pulito: mi interessa il primo scivolone
		var esito := await GameManager.esegui_turno(caso)
		assert_false(esito["in_mondo"], "deve essere respinto: %s" % caso)
		assert_eq(esito["voce"]["narrazione_omero"], "", "Omero deve tacere: %s" % caso)

func test_niente_falsi_positivi_su_italiano_legittimo():
	# Parole che assomigliano a marcatori ma sono legittime nell'Odissea.
	var leciti := [
		"osservo il moto delle onde contro lo scafo",
		"taglio una canna sulla riva per farne un giaciglio",
		"organizzo il salvataggio dei compagni caduti in mare",
	]
	for frase in leciti:
		GameManager.nuova_partita(98)
		var esito := await GameManager.esegui_turno(frase)
		assert_true(esito["in_mondo"], "non deve essere respinto: %s" % frase)

func test_primo_scivolone_solo_richiamo():
	var esito := await GameManager.esegui_turno(FUORI)
	assert_false(esito["in_mondo"])
	assert_eq(esito["esito"], "continua")
	assert_eq(esito["voce"]["ammonizione"], "richiamo")
	assert_eq(GameManager.stato.ammonizioni["contatore"], 1)
	# Nessun danno al primo scivolone.
	assert_eq(GameManager.stato.ulisse["stat"]["animo"], 50)

func test_secondo_e_smarrimento_cala_animo():
	await GameManager.esegui_turno(FUORI)
	var esito := await GameManager.esegui_turno(FUORI)
	assert_eq(esito["voce"]["ammonizione"], "smarrimento")
	assert_eq(GameManager.stato.ammonizioni["contatore"], 2)
	assert_lt(GameManager.stato.ulisse["stat"]["animo"], 50, "lo smarrimento fa calare l'animo")

func test_terzo_e_follia_game_over():
	await GameManager.esegui_turno(FUORI)
	await GameManager.esegui_turno(FUORI)
	var esito := await GameManager.esegui_turno(FUORI)
	assert_eq(esito["esito"], "follia")
	assert_eq(esito["voce"]["ammonizione"], "follia")
	assert_eq(GameManager.stato.stato, "finita")
	assert_eq(GameManager.stato.esito, "follia")

func test_decadimento_torna_sensato():
	await GameManager.esegui_turno(FUORI)  # contatore 1
	assert_eq(GameManager.stato.ammonizioni["contatore"], 1)
	# 3 turni puliti (decadimento_ogni=3) -> il contatore scende.
	await GameManager.esegui_turno(DENTRO)
	await GameManager.esegui_turno(DENTRO)
	await GameManager.esegui_turno(DENTRO)
	assert_eq(GameManager.stato.ammonizioni["contatore"], 0, "l'ammonizione decade tornando sensati")
	assert_eq(GameManager.stato.ammonizioni["turni_puliti"], 3)

func test_turno_pulito_azzera_i_turni_dopo_scivolone():
	await GameManager.esegui_turno(DENTRO)   # turni_puliti 1
	await GameManager.esegui_turno(FUORI)    # scivolone: azzera
	assert_eq(GameManager.stato.ammonizioni["turni_puliti"], 0)
