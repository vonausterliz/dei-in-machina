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
	# Dopo il turno la narrazione e' cresciuta e le stat sono aggiornate.
	assert_string_contains(ui._narrazione.get_parsed_text().to_lower(), "un dio")
	assert_string_contains(ui._stats.text, "animo")
