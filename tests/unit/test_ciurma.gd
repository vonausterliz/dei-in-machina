extends GutTest

## La ciurma: compagni con voce propria, interpellabili da Ulisse, che TACCIONO se muoiono.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(77)

func test_roster_caricato_dal_file():
	assert_gte(GameManager.ciurma.compagni.size(), 6, "i compagni vengono da data/ciurma.json")
	assert_eq(GameManager.ciurma.get_compagno("euriloco")["nome"], "Euriloco")

func test_un_compagno_commenta_ogni_turno():
	await GameManager.esegui_turno("Sciolgo le vele.")
	var c: Dictionary = GameManager.agora.canali[Agora.CANALE_CIURMA]
	assert_gt(c["messaggi"].size(), 0, "qualcuno commenta")

func test_ulisse_puo_rivolgersi_a_uno_per_nome():
	await GameManager.esegui_turno("Euriloco, prepara i remi.")
	var messaggi: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"]
	var autori: Array = messaggi.map(func(m): return m["autore"])
	assert_has(autori, "Ulisse", "quando parla ai suoi, Ulisse compare in chat")
	assert_has(autori, "Euriloco", "risponde chi e' stato chiamato")

func test_chi_muore_tace():
	# Antifo muore nel Ciclope: chiusa la tappa, la sua voce sparisce.
	assert_true(GameManager.ciurma.nomi_vivi().has("Antifo"))
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("fuggo dall'antro")   # tag fuga: chiude la tappa
	assert_false(GameManager.ciurma.nomi_vivi().has("Antifo"), "Antifo non parla piu'")
	assert_string_contains(GameManager.agora.trascrizione(), "non risponde")

func test_destinatari_riconosciuti_con_chiocciola():
	assert_eq(GameManager.ciurma.risolvi_destinatario("@euriloco"), "euriloco")
	assert_eq(GameManager.ciurma.risolvi_destinatario("Perimede"), "perimede")
	assert_eq(GameManager.ciurma.risolvi_destinatario("Zeus"), "", "non e' un compagno")
