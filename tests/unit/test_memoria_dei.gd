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
	assert_eq(String(memoria[0]["registro"]), "castigo", "nel taccuino c'e' cosa ha voluto")
	assert_string_contains(String(memoria[0]["luogo"]).to_lower(), "ciclope", "e dove")

func test_chi_non_reagisce_non_scrive_nulla():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	# Atena non si desta su questa azione: il suo taccuino resta bianco.
	assert_eq(GameManager.stato.registro_divino["atena"].get("memoria", []).size(), 0,
		"non si ricorda cio' che non si e' fatto")

func test_la_memoria_dice_se_ha_prevalso_o_e_stato_scavalcato():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var esito := String(GameManager.stato.registro_divino["poseidone"]["memoria"][0]["esito"])
	assert_true(["prevalso", "respinto", "nascosto", "nulla"].has(esito),
		"deve ricordare anche COME e' andata, non solo cosa voleva: «%s»" % esito)

# --- Il taccuino non perde niente: i ricordi vecchi si condensano, non si buttano ---

## Il tetto vale sui ricordi PER ESTESO. Oltre quello non si cancella: si riassume.
## Un dio che dimentica non e' una potenza millenaria, e' un pesce rosso.
func test_oltre_il_tetto_i_ricordi_si_riassumono_invece_di_sparire():
	GameManager.vai_a_tappa("ciclope")
	var tetto: int = Bilanciamento.intero("memoria/ricordi_per_dio", 5)
	var giri := tetto + 4
	for i in giri:
		await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var reg: Dictionary = GameManager.stato.registro_divino["poseidone"]
	assert_eq(reg["memoria"].size(), tetto, "per esteso restano gli ultimi %d" % tetto)
	var vecchia: Dictionary = reg["memoria_vecchia"]
	assert_eq(int(vecchia["quanti"]), giri - tetto, "i piu' vecchi sono condensati, non persi")
	assert_eq(int(vecchia["quanti"]) + reg["memoria"].size(), giri, "il conto torna: non si perde nulla")

func test_il_riassunto_conta_cosa_ha_voluto_e_come_e_andata():
	GameManager.vai_a_tappa("ciclope")
	for i in 9:
		await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var vecchia: Dictionary = GameManager.stato.registro_divino["poseidone"]["memoria_vecchia"]
	assert_gt(int(vecchia["registri"].get("castigo", 0)), 0, "sa quante volte ha voluto castigo")
	assert_gte(int(vecchia["dal_turno"]), 1)
	assert_lte(int(vecchia["dal_turno"]), int(vecchia["al_turno"]), "l'arco di turni ha senso")
	assert_false(GameManager.riassunto_memoria("poseidone").is_empty(),
		"il riassunto dev'essere leggibile, non solo contato")

func test_il_riassunto_arriva_al_dio_insieme_ai_ricordi_recenti():
	GameManager.vai_a_tappa("ciclope")
	for i in 9:
		await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var contesto := GameManager._contesto_dio("poseidone", {"sintesi": "alza le vele"}, [])
	var testo := String(DioAgente.new().costruisci_messaggi(
		PantheonManager.get_dio("poseidone"), contesto)[1]["content"])
	assert_string_contains(testo, GameManager.riassunto_memoria("poseidone"),
		"quello che ha fatto prima dev'essere sotto i suoi occhi")
	assert_string_contains(testo, "castigo", "e anche i ricordi recenti per esteso")

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
##
## Il confronto e' sulle forme LEGGIBILI, non sui dizionari grezzi, e non per comodita':
## il JSON non ha il tipo intero, quindi al ritorno un 1 e' un 1.0. I valori sono gli
## stessi e il codice li legge con int(), ma confrontare le strutture farebbe fallire il
## test per un dettaglio di serializzazione invece che per una perdita di memoria — che e'
## la cosa che qui vogliamo davvero sorvegliare.
func test_la_memoria_si_salva_e_si_rilegge():
	GameManager.vai_a_tappa("ciclope")
	for i in 8:
		await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var prima_recenti := GameManager.ricordi_recenti("poseidone")
	var prima_riassunto := GameManager.riassunto_memoria("poseidone")
	assert_false(prima_riassunto.is_empty(), "con 8 turni c'e' gia' del condensato")

	var percorso := "user://prova_memoria.json"
	GameManager.stato.salva(percorso)
	GameManager.stato = StatoPartita.carica(percorso)   # come riaprire la partita

	assert_eq(GameManager.ricordi_recenti("poseidone"), prima_recenti, "i recenti tornano uguali")
	assert_eq(GameManager.riassunto_memoria("poseidone"), prima_riassunto, "e il condensato pure")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(percorso))
