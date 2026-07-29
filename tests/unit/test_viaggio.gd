extends GutTest

## Il viaggio a tappe: accensione dei locali, avanzamento (per azione o per tetto turni),
## vittoria a Itaca. Deterministico col mock.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(555)

func test_inizio_nella_prima_tappa():
	# Il viaggio segue l'Odissea: si parte dalla partenza da Troia (il proemio).
	assert_eq(GameManager.stato.viaggio["corrente"], "troia")
	assert_eq(GameManager.stato.ulisse["episodio_corrente"], "troia")

func test_ogni_tappa_ha_scena_e_mappa():
	# Grounding + cartina: ogni episodio deve avere una scena e coordinate valide.
	for id in GameManager.episodi.ordine():
		var ep := GameManager.episodi.get_episodio(id)
		assert_ne(ep.scena, "", "%s deve avere una scena (grounding)" % id)
		assert_between(ep.mappa.x, 0.0, 1.0, "%s: x mappa normalizzata" % id)
		assert_between(ep.mappa.y, 0.0, 1.0, "%s: y mappa normalizzata" % id)

func test_scena_corrente_non_vuota():
	assert_ne(GameManager.scena_corrente(), "", "la scena corrente alimenta Omero e il Suggeritore")

func test_locale_di_tappa_acceso_e_eleggibile():
	# Nel Ciclope il suo locale (Polifemo) deve essere in gioco ed eleggibile.
	GameManager.vai_a_tappa("ciclope")
	assert_true(PantheonManager.get_dio("polifemo").attivo)
	assert_true(GameManager.stato.registro_divino["polifemo"]["risvegliato"])
	assert_has(PantheonManager.eleggibili("ciclope"), "polifemo")
	# Un locale di un'altra tappa resta spento.
	assert_false(PantheonManager.get_dio("circe").attivo)

func test_avanza_su_azione_di_progresso():
	# Nel Ciclope si avanza fuggendo (tag fuga) verso Eolo.
	GameManager.vai_a_tappa("ciclope")
	var esito := await GameManager.esegui_turno("fuggo dall'antro")  # tag fuga
	assert_true(esito["avanzato"])
	assert_eq(esito["episodio"], "eolo")
	assert_eq(GameManager.stato.viaggio["corrente"], "eolo")
	assert_has(GameManager.stato.viaggio["completati"], "ciclope")
	# Entrando a Eolo si accende il suo locale.
	assert_true(PantheonManager.get_dio("eolo").attivo)

func test_avanza_per_tetto_turni():
	# Senza azione di progresso, la tappa si chiude al tetto (troia: 4) -> Ciconi.
	var esito := {}
	for i in 4:
		esito = await GameManager.esegui_turno("Guardo l'orizzonte in silenzio.")  # tag []
	assert_true(esito["avanzato"], "al tetto turni si avanza comunque")
	assert_eq(GameManager.stato.viaggio["corrente"], "ciconi")

func test_evento_di_tappa_passato_al_risveglio():
	# Nella tappa 'scilla' l'evento 'passaggio' e' attivo: lo si vede negli eventi del turno.
	# Porto Ulisse fino a scilla avanzando con 'salpo'/'fuggo'.
	var esito := {}
	for i in 40:
		esito = await GameManager.esegui_turno("salpo")
		if GameManager.stato.viaggio["corrente"] == "scilla":
			break
	assert_eq(GameManager.stato.viaggio["corrente"], "scilla")
	var esito2 := await GameManager.esegui_turno("Osservo lo stretto.")
	assert_has(esito2["voce"]["eventi_emessi"], "passaggio")

func test_vittoria_a_itaca():
	var esito := {}
	for i in 100:
		esito = await GameManager.esegui_turno("salpo")  # rotta: avanza; i due 'fuga' cadono al tetto
		if esito["esito"] != "continua":
			break
	assert_eq(esito["esito"], "itaca")
	assert_eq(GameManager.stato.stato, "finita")
	assert_eq(GameManager.stato.esito, "itaca")
