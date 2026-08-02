extends GutTest

## LA MEMORIA DI UN DIO. Due memorie distinte, che prima non aveva nessuna delle due:
##
## 1. PRIMA della storia — la guerra di Troia e i conti gia' aperti con Ulisse. Un dio che
##    non sa cos'e' successo a Troia non e' il dio dell'Odissea: e' un dio generico.
## 2. DURANTE la storia — cio' che ha fatto LUI. La `cronaca` non basta: e' ripulita dai
##    nomi divini (finisce anche a Omero, che non deve nominarli), quindi un dio non vi
##    ritrova nemmeno le proprie opere. Serve un taccuino privato, per dio.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(555)

# --- 1. Memoria del prima ---

func test_ogni_dio_conosce_il_proprio_antefatto():
	for dio in PantheonManager.pantheon.tutti():
		assert_ne(dio.antefatto, "", "%s deve sapere da dove viene" % dio.nome)

func test_l_antefatto_del_dio_entra_nel_suo_prompt():
	var dio: Dio = PantheonManager.get_dio("poseidone")
	var agente := DioAgente.new()
	assert_string_contains(agente.system_prompt(dio), dio.antefatto,
		"cio' che il dio ricorda del prima dev'essere nel suo prompt")

## L'antefatto comune (Troia) sta nel contesto di mondo, quindi lo conoscono tutti:
## gli dei, Omero e anche i compagni, che quella guerra l'hanno combattuta.
func test_la_guerra_di_troia_e_nel_contesto_condiviso():
	var mondo := FileAccess.get_file_as_string("res://prompts/mondo.txt").to_lower()
	for parola in ["troia", "dieci anni", "cavallo"]:
		assert_string_contains(mondo, parola, "il mondo condiviso deve ricordare la guerra")

# --- 2. Memoria di cio' che ha fatto ---

func test_il_dio_ricorda_cio_che_ha_deciso():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var memoria: Array = GameManager.stato.registro_divino["poseidone"].get("memoria", [])
	assert_gt(memoria.size(), 0, "chi ha agito deve ricordarselo")
	assert_string_contains(String(memoria[0]).to_lower(), "castigo",
		"nel taccuino c'e' cosa ha voluto")

func test_chi_non_reagisce_non_scrive_nulla():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	# Atena non si desta su questa azione: il suo taccuino resta bianco.
	assert_eq(GameManager.stato.registro_divino["atena"].get("memoria", []).size(), 0,
		"non si ricorda cio' che non si e' fatto")

func test_la_memoria_dice_se_ha_prevalso_o_e_stato_scavalcato():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var riga := String(GameManager.stato.registro_divino["poseidone"]["memoria"][0]).to_lower()
	assert_true(riga.contains("prevals") or riga.contains("prevalso") or riga.contains("respint"),
		"deve ricordare anche COME e' andata, non solo cosa voleva: «%s»" % riga)

## A costo costante, come la cronaca: il taccuino non puo' crescere all'infinito o il
## prompt del dio si gonfia turno dopo turno.
func test_la_memoria_e_limitata():
	GameManager.vai_a_tappa("ciclope")
	for i in 9:
		await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var tetto: int = Bilanciamento.intero("memoria/ricordi_per_dio", 6)
	assert_lte(GameManager.stato.registro_divino["poseidone"]["memoria"].size(), tetto,
		"il taccuino tiene solo gli ultimi ricordi")

func test_il_taccuino_arriva_al_dio_nel_prompt():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var dio: Dio = PantheonManager.get_dio("poseidone")
	var contesto := GameManager._contesto_dio("poseidone", {"sintesi": "qualcosa"}, [])
	var messaggi := DioAgente.new().costruisci_messaggi(dio, contesto)
	assert_string_contains(String(messaggi[1]["content"]).to_lower(), "castigo",
		"cio' che ha fatto dev'essere sotto i suoi occhi al turno dopo")

## La memoria sopravvive a salvataggio e ripresa: un dio non dimentica perche' si e'
## chiuso il gioco.
func test_la_memoria_si_salva_e_si_rilegge():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var percorso := "user://prova_memoria.json"
	GameManager.stato.salva(percorso)
	var riletto := StatoPartita.carica(percorso)
	assert_eq(riletto.registro_divino["poseidone"]["memoria"],
		GameManager.stato.registro_divino["poseidone"]["memoria"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(percorso))
