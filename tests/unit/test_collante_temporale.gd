extends GutTest

## IL COLLANTE TEMPORALE fra le tre viste.
##
## Tolte le etichette «— turno N —» (giustamente: una conversazione non e' un tabellone),
## le chat sono rimaste senza scansione: leggevi le reazioni degli dèi senza sapere a COSA
## reagivano, e le tre finestre non erano piu' allineate su niente.
##
## Il collante non e' un numero, sono due cose che appartengono alla storia:
##  - l'AZIONE di Ulisse, come intestazione del gruppo di battute che ne segue;
##  - il MOMENTO DEL GIORNO, che avanza a ogni turno e compare solo quando cambia.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(404)

func test_il_momento_del_giorno_avanza_a_ogni_turno():
	var primo := GameManager.momento_corrente()
	await GameManager.esegui_turno("Sciolgo le vele.")
	assert_ne(GameManager.momento_corrente(), primo, "il tempo passa")

func test_il_momento_gira_e_torna():
	var quanti: int = Lingua.momenti_del_giorno().size()
	assert_gt(quanti, 2, "servono piu' momenti per fare un giorno")
	var primo := GameManager.momento_corrente()
	for i in quanti:
		await GameManager.esegui_turno("Piego ai remi.")
	assert_eq(GameManager.momento_corrente(), primo, "dopo un giro si ricomincia")

## Le tre viste devono agganciarsi allo STESSO evento.
func test_le_chat_riportano_l_azione_di_ulisse():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var olimpo := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	assert_string_contains(olimpo, "Odisseo", "si legge a cosa stanno reagendo")

func test_l_intestazione_porta_anche_il_momento():
	await GameManager.esegui_turno("Sciolgo le vele.")
	var intestazione: Dictionary = GameManager.agora.intestazioni.get(GameManager.stato.turno, {})
	assert_false(String(intestazione.get("azione", "")).is_empty())
	assert_false(String(intestazione.get("momento", "")).is_empty())

## L'intestazione compare UNA volta per turno, non a ogni battuta.
func test_l_intestazione_non_si_ripete():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var t := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	assert_eq(t.count("Odisseo, che t'ho accecato"), 1, "una sola intestazione per turno")

## Il momento arriva anche a Omero: serve alla prosa («il sole gia' calava»), non solo
## come decorazione nelle chat.
func test_omero_sa_che_ora_e():
	var ctx := GameManager._contesto_omero({}, "x", [], {}, {}, "")
	assert_true(ctx.has("momento"))
	assert_false(String(ctx["momento"]).is_empty())

## Anche la narrazione principale porta lo stesso marcatore: e' li' che il collante serve
## davvero, perche' e' la vista che si guarda sempre.
func test_la_narrazione_principale_scandisce_il_tempo():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._input.text = "Sciolgo le vele."
	await ui._on_agisci()
	assert_string_contains(ui._narrazione.get_parsed_text(), "≈",
		"il marcatore del momento compare anche nel racconto")

## Ma non a ogni riga: sarebbe un orologio, non un respiro.
func test_il_marcatore_non_si_ripete_se_il_momento_non_cambia():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._ultimo_momento = GameManager.momento_corrente()   # gia' mostrato
	var prima: int = ui._narrazione.get_parsed_text().count("≈")
	ui._input.text = "Piego ai remi."
	await ui._on_agisci()
	assert_lte(ui._narrazione.get_parsed_text().count("≈"), prima + 2,
		"al piu' il cambio successivo, non uno per riga")
