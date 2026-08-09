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

## IL TETTO NON C'E' PIU': al suo posto la pressione (R-13).
##
## Prima quattro turni distratti bastavano a chiudere Troia — un cambio di scena a contatore
## scaduto, cioe' senza causa e senza niente da raccontare. Adesso chi indugia non viene
## spostato: viene SPINTO, e la spinta si legge prima che la scena cambi.
func test_indugiare_non_sposta_piu_da_solo():
	for i in 4:
		await GameManager.esegui_turno("Guardo l'orizzonte in silenzio.")  # tag []
	assert_eq(GameManager.stato.viaggio["corrente"], "troia",
		"quattro turni distratti hanno spostato la scena senza una causa")
	assert_eq(GameManager.viaggio.grado_pressione(), 0, "la pressione è partita troppo presto")

## …e la pressione sale per gradi, ognuno col suo evento, fino alla spinta che chiude.
func test_la_pressione_sale_per_gradi_e_alla_fine_spinge():
	var v := GameManager.viaggio
	var visti: Array[String] = []
	var esito := {}
	for i in 25:
		esito = await GameManager.esegui_turno("Guardo l'orizzonte in silenzio.")
		var ev := v.evento_pressione()
		if ev != "" and not visti.has(ev):
			visti.append(ev)
		if bool(esito.get("avanzato", false)):
			break
	assert_eq(visti, Viaggio.EVENTI_PRESSIONE,
		"i tre gradi non si sono visti tutti, o non in ordine: la spinta arriva senza preavviso")
	assert_true(bool(esito["avanzato"]), "la pressione non ha mai chiuso la tappa")
	assert_eq(GameManager.stato.viaggio["corrente"], "ciconi")

## E la spinta è un PRODIGIO, non una partenza voluta: nessuno ha scelto di salpare.
func test_la_spinta_e_un_prodigio():
	var esito := {}
	for i in 25:
		esito = await GameManager.esegui_turno("Guardo l'orizzonte in silenzio.")
		if bool(esito.get("avanzato", false)):
			break
	assert_eq(String(esito.get("causa", "")), "prodigio",
		"la tappa si è chiusa senza dire perché, o dicendo il perché sbagliato")

func test_evento_di_tappa_passato_al_risveglio():
	# Nella tappa 'scilla' l'evento 'passaggio' e' attivo: lo si vede negli eventi del turno.
	# Porto Ulisse fino a scilla avanzando con 'salpo'/'fuggo'.
	var esito := {}
	# Alternando «salpo» (rotta) e «fuggo» (fuga) si chiudono entrambi i tipi di tappa senza
	# aspettare la pressione: prima al tetto ci si arrivava per sfinimento, e il tetto non c'è più.
	for i in 60:
		esito = await GameManager.esegui_turno("salpo" if i % 2 == 0 else "fuggo")
		if GameManager.stato.viaggio["corrente"] == "scilla":
			break
	assert_eq(GameManager.stato.viaggio["corrente"], "scilla")
	var esito2 := await GameManager.esegui_turno("Osservo lo stretto.")
	assert_has(esito2["voce"]["eventi_emessi"], "passaggio")

func test_vittoria_a_itaca():
	var esito := {}
	for i in 100:
		esito = await GameManager.esegui_turno("salpo" if i % 2 == 0 else "fuggo")
		if esito["esito"] != "continua":
			break
	assert_eq(esito["esito"], "itaca")
	assert_eq(GameManager.stato.stato, "finita")
	assert_eq(GameManager.stato.esito, "itaca")
