extends GutTest

## La GUI (scenes/Main.tscn) si istanzia e gioca un turno senza errori (headless).
## Non testa il rendering (serve un display), ma la costruzione e il wiring col motore.

func test_scena_si_istanzia_e_apre():
	LLMManager.mock_mode = true
	var scena: PackedScene = load("res://scenes/Main.tscn")
	assert_not_null(scena, "Main.tscn deve caricarsi")
	var ui = scena.instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	# La UI ha avviato una partita e mostrato l'intro della prima tappa.
	assert_not_null(GameManager.stato)
	assert_string_contains(ui._narrazione.get_parsed_text(), "Omero")

func test_gui_gioca_un_turno():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._input.text = "Sono io, Odisseo, che t'ho accecato!"
	await ui._on_agisci()
	# Dopo il turno la narrazione e' cresciuta e le stat (barre + valori) esistono.
	assert_string_contains(ui._narrazione.get_parsed_text().to_lower(), "un dio")
	assert_true(ui._stat_vals.has("animo"))
	assert_ne(ui._stat_vals["animo"].text, "—", "il valore dell'animo e' stato popolato")

## Regressione: la finestra della ciurma era dichiarata, aveva il pulsante, la voce di
## menu e le funzioni di aggiornamento — ma non veniva MAI creata. I test headless non se
## ne accorgevano perche' nessuno guardava le finestre di servizio. Ora le guardano.
func test_le_tre_finestre_di_servizio_esistono():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	for nome in ["_fin_log", "_fin_olimpo", "_fin_ciurma"]:
		assert_not_null(ui.get(nome), "%s deve essere costruita, non solo dichiarata" % nome)

func test_la_finestra_della_ciurma_e_interattiva_e_collegata():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_true(ui._fin_ciurma.interattiva, "dalla ciurma Ulisse deve poter scrivere")
	assert_not_null(ui._fin_ciurma.campo, "la barra d'invio dev'essere costruita")
	assert_true(ui._fin_ciurma.inviato.is_connected(ui._on_ciurma_invio),
		"cio' che Ulisse scrive ai compagni deve arrivare al gioco")

## Aprire una vista non deve mai fallire: erano chiamate su un riferimento nullo.
func test_le_viste_si_aprono_senza_errori():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	for f in [ui._on_toggle_ciurma, ui._on_toggle_olimpo, ui._on_toggle_log]:
		f.call(true)
		f.call(false)
	pass_test("le tre viste si aprono e si chiudono")

## La Vista Olimpo e' una CHAT: niente traccia tecnica, niente voci della ciurma.
func test_la_vista_olimpo_resta_una_chat():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._input.text = "Sono io, Odisseo, che t'ho accecato!"
	await ui._on_agisci()
	ui._on_toggle_olimpo(true)
	var t: String = ui._fin_olimpo.testo.get_parsed_text()
	assert_false(t.contains("Envelope:"), "la traccia tecnica appartiene al Log LLM")
	assert_false(t.contains("# Ciurma"), "la ciurma ha la sua finestra")

## Il bottone per provare il modello dev'essere costruito e collegato: e' l'unico modo
## per sapere se una configurazione funziona SENZA cominciare una partita.
func test_settings_ha_il_bottone_prova_collegato():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	var f = ui._fin_impostazioni
	assert_not_null(f._btn_prova, "il bottone dev'essere costruito, non solo dichiarato")
	assert_true(f._btn_prova.pressed.is_connected(f._prova_modello), "e collegato")

## La prova deve guardare il profilo SCELTO, non quello che sta girando: si configura
## Gemini mentre il gioco e' ancora sul simulato, e provare "l'attivo" proverebbe Ollama.
func test_la_prova_guarda_il_profilo_scelto_non_quello_attivo():
	LLMManager.provider_esterno = false          # com'e' all'avvio
	var quanti: int = LLMManager.profili_esterni.size()
	if quanti == 0:
		pending("nessun profilo esterno"); return
	LLMManager.provider_esterno_idx = quanti - 1
	var cfg := LLMManager.config_del_profilo()
	assert_eq(String(cfg["model"]), String(LLMManager.profili_esterni[quanti - 1]["model"]))
	assert_ne(String(cfg["base_url"]), String(LLMManager.config.get("base_url", "")),
		"non deve cadere sul profilo locale")

## L'avviso del motore simulato dev'essere nell'INTESTAZIONE e in rosso: quando stava in
## fondo alla pagina, in colore tenue, si sono giocati quattro turni credendo di parlare
## con gli dèi veri. Un avviso che non si vede non e' un avviso.
func test_l_avviso_del_motore_simulato_si_vede():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_string_contains(ui._lbl_motore.text.to_lower(), "simulato")
	assert_eq(ui._lbl_motore.get_theme_color("font_color"), ui.C_OXBLOOD, "in rosso")
	# Nell'intestazione, cioe' fra i primi nodi della pagina — non in fondo.
	var testata: Control = ui._lbl_motore.get_parent()
	assert_lt(testata.get_index(), 3, "dev'essere in cima, non sotto la piega")

# --- Il simulato non e' uno stato in cui si possa GIOCARE ---

## Il mock resta (ci girano i test e la console headless), ma con una finestra aperta non
## dev'essere una partita: si sono giocati quattro turni con dèi finti credendo fossero
## veri. Meglio un gioco che si ferma e spiega, di uno che finge.
func test_col_simulato_e_una_finestra_aperta_il_gioco_si_ferma():
	assert_true(Main.blocca_simulato(true, true), "motore finto + schermo = non si gioca")

func test_senza_schermo_il_simulato_resta_permesso():
	assert_false(Main.blocca_simulato(true, false), "headless: test e console devono girare")

func test_col_motore_vero_non_si_blocca_nulla():
	assert_false(Main.blocca_simulato(false, true))
	assert_false(Main.blocca_simulato(false, false))

## Guardia effettiva: in headless (dove girano i test) non deve MAI scattare, altrimenti
## si bloccherebbero da soli.
func test_la_guardia_non_scatta_nei_test():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_false(ui._simulato_blocca(), "i test girano sul mock: non devono autobloccarsi")

## Salvare e riprendere dall'interfaccia. Il codice per farlo esisteva da sempre in
## GameManager e non era collegato a niente: una partita dura ~76 turni, e perderla
## chiudendo la finestra e' una perdita vera.
func test_la_partita_si_salva_e_si_riprende_dalla_gui():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	GameManager.vai_a_tappa("ciclope")
	ui._input.text = "Sono io, Odisseo, che t'ho accecato!"
	await ui._on_agisci()
	var turno: int = GameManager.stato.turno

	ui._on_menu_partita(Main.VOCE_SALVA)
	assert_string_contains(ui._narrazione.get_parsed_text(), "salvata")

	GameManager.nuova_partita(1)          # si perde tutto…
	await ui._on_menu_partita(Main.VOCE_CARICA)   # …e si riprende
	assert_eq(GameManager.stato.turno, turno, "si riparte da dove si era")
	assert_string_contains(ui._narrazione.get_parsed_text(), "ripresa")
	# Il diario non si appende: si RIDISEGNA per intero, o riprendere darebbe pagine bianche.
	assert_eq(ui._diario_box.get_child_count(), GameManager.stato.diario.size())
