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
