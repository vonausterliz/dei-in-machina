extends GutTest

## Scala diegetica dell'input fuori-mondo: richiamo -> smarrimento -> follia,
## col decadimento se si torna a giocare sensato. Deterministico col mock.

const FUORI := "Prendo un aereo e volo a Itaca."   # anacronistico (fixture mock)
const DENTRO := "Riempio gli otri d'acqua alla sorgente."  # in_mondo neutro

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(2024)

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
