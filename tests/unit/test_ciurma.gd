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

## Scrivere NELLA chat della ciurma significa gia' rivolgersi ai propri uomini: il canale
## e' il destinatario. Non serve chiamare qualcuno per nome perche' Ulisse si veda parlare.
func test_cio_che_ulisse_scrive_nella_chat_si_vede_sempre():
	await GameManager.esegui_turno("Coraggio, teniamo la rotta.", [], true)
	var autori: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"].map(
		func(m): return m["autore"])
	assert_has(autori, "Ulisse", "cio' che scrive nella chat della ciurma deve comparire")

## Un gesto compiuto nel gioco, invece, non e' una frase detta agli uomini: non va messo
## in bocca a Ulisse nella chat (li' commenta la ciurma, semmai).
func test_un_gesto_nel_gioco_non_diventa_una_battuta_di_ulisse():
	await GameManager.esegui_turno("Sguaino la spada e avanzo nell'antro.")
	var autori: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"].map(
		func(m): return m["autore"])
	assert_does_not_have(autori, "Ulisse", "un'azione non e' una battuta rivolta ai compagni")

func test_chi_muore_tace():
	# Antifo muore nel Ciclope: chiusa la tappa, la sua voce sparisce.
	assert_true(GameManager.ciurma.nomi_vivi().has("Antifo"))
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("fuggo dall'antro")   # tag fuga: chiude la tappa
	assert_false(GameManager.ciurma.nomi_vivi().has("Antifo"), "Antifo non parla piu'")
	assert_string_contains(GameManager.agora.trascrizione(Agora.VISTA_CIURMA), "non risponde")

func test_destinatari_riconosciuti_con_chiocciola():
	assert_eq(GameManager.ciurma.risolvi_destinatario("@euriloco"), "euriloco")
	assert_eq(GameManager.ciurma.risolvi_destinatario("Perimede"), "perimede")
	assert_eq(GameManager.ciurma.risolvi_destinatario("Zeus"), "", "non e' un compagno")
