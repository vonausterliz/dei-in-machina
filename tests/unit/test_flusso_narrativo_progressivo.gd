extends GutTest

## Accettazione indipendente del confine fra motore, Omero e GUI.
##
## Questi test non sostituiscono i test puri dei singoli componenti: attraversano i punti
## in cui i contratti possono perdersi. In particolare sorvegliano l'ordine osservabile
## dell'Olimpo, la natura effimera degli indicatori e l'uso reale del quadro autorevole
## durante un cambio di tappa.

const PATH_SALVATAGGIO := "user://test_flusso_narrativo_progressivo.json"


class FakeChat:
	var risposte: Array = []
	var chiamate := 0

	func chat(_messaggi: Array, _opzioni: Dictionary) -> Dictionary:
		var indice := mini(chiamate, risposte.size() - 1)
		chiamate += 1
		return risposte[indice]


func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(707)


func after_each():
	if FileAccess.file_exists(PATH_SALVATAGGIO):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH_SALVATAGGIO))


func _ok(testo: String) -> Dictionary:
	return {"ok": true, "content": testo, "error": ""}


func _stato(id: String, nome: String) -> Dictionary:
	return {
		"episodio": {"id": id, "nome": nome, "scena": "Ulisse e la ciurma presso il mare."},
		"ulisse": {"animo": 50, "metis": 50, "ciurma": 45},
		"viaggio": {"turni_in_episodio": 18},
	}


func _quadro_di_traversata() -> Dictionary:
	return QuadroNarrativo.crea(
		_stato("troia", "La partenza da Troia"),
		{"testo": "Sciolgo le vele.", "sintesi": "Ulisse lascia Troia.",
			"tipo": "movimento", "tag": ["rotta"]},
		{"delta": {}, "eventi": ["gli_dei_lo_sospingono"],
			"fatti": ["Le vele sono state sciolte."], "esito": "continua",
			"pressione": {"grado": 3, "spinge": true}},
		_stato("ciconi", "I Ciconi di Ismaro"),
		"a mezzogiorno",
		["Le navi raggiungono la tappa assegnata."],
		[{"id": "nave_perduta", "descrizione": "la perdita permanente di una nave",
			"marcatori": ["una nave affondo'", "perdettero una nave"]}],
		{"avvenuto": true,
			"da": {"id": "troia", "nome": "La partenza da Troia"},
			"a": {"id": "ciconi", "nome": "I Ciconi di Ismaro"},
			"causa": "prodigio"},
		QuadroNarrativo.politica_rotta_fissa(
			["troia", "ciconi", "lotofagi"],
			{"troia": "La partenza da Troia", "ciconi": "I Ciconi di Ismaro",
				"lotofagi": "La terra dei Lotofagi"}))


func test_dopo_invio_il_feedback_e_immediato_e_transitorio():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_process_frames(2)
	GameManager.vai_a_tappa("ciclope")
	GameManager.stato.eventi_accaduti.append("maledizione_di_polifemo")

	ui._input.text = "Mi vanto della mia astuzia davanti a tutti"
	ui._on_agisci()
	assert_true(ui._busy, "l'invio deve entrare subito nello stato occupato")
	assert_true(ui._pan_olimpo.ha_indicatore(),
		"prima ancora della prima risposta deve comparire un feedback visivo")
	assert_false(ui._input.editable, "durante il turno non si puo' inviare una seconda azione")

	await wait_until(func(): return not ui._busy, 5.0, "il turno mock deve concludersi")
	assert_false(ui._pan_olimpo.ha_indicatore(), "l'indicatore non deve sopravvivere al turno")
	assert_true(ui._input.editable)
	assert_false(ui._btn_agisci.disabled)


func test_il_ramo_di_esito_vuoto_ripulisce_tutta_l_attesa():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_process_frames(2)
	# Simula la race lecita in cui la partita viene chiusa prima che l'azione arrivi al core.
	GameManager.stato.stato = "finita"
	ui._input.text = "Salpo."
	await ui._on_agisci()
	assert_false(ui._busy)
	assert_false(ui._pan_olimpo.ha_indicatore())
	assert_true(ui._input.editable)
	assert_false(ui._btn_agisci.disabled)


func test_la_gui_mostra_una_sola_voce_atomica_nel_cambio_di_tappa():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_process_frames(2)
	var omero_prima: int = ui._narrazione.get_parsed_text().count("Omero:")
	ui._input.text = "Salpo e riprendo il mare."
	await ui._on_agisci()
	var prosa: String = ui._narrazione.get_parsed_text()
	assert_eq(prosa.count("Omero:"), omero_prima + 1,
		"azione e traversata devono essere una voce sola, non narrazione + transizione + intro")
	assert_true(prosa.contains("Ciconi") or prosa.contains("Ismaro"),
		"la sola voce deve rendere visibile la tappa raggiunta")


func test_olimpo_procede_in_botta_e_risposta_prima_di_omero():
	GameManager.vai_a_tappa("ciclope")
	GameManager.stato.eventi_accaduti.append("maledizione_di_polifemo")
	var passi: Array = []
	var ascolta := func(fase: String, dati: Dictionary):
		passi.append({"fase": fase, "dati": dati.duplicate(true)})
	GameManager.progresso_turno.connect(ascolta)
	await GameManager.esegui_turno("Mi vanto della mia astuzia davanti a tutti")
	GameManager.progresso_turno.disconnect(ascolta)

	assert_gt(passi.size(), 4, "serve una sequenza progressiva, non il solo risultato finale")
	assert_eq(String(passi[0]["fase"]), "risvegli")
	assert_eq(String(passi[-1]["fase"]), "narrazione",
		"Omero puo' cominciare soltanto dopo che l'Olimpo ha terminato")
	for i in passi.size():
		var fase := String(passi[i]["fase"])
		var foto := String(passi[i]["dati"].get("trascrizione", ""))
		assert_false(foto.contains("sta rispondendo"),
			"gli indicatori devono restare nella GUI, non negli snapshot di Agora")
		if fase == "attesa":
			assert_lt(i + 1, passi.size(), "un'attesa non puo' restare senza risposta")
			if i + 1 < passi.size():
				assert_has(["battuta", "verdetto", "azione"], String(passi[i + 1]["fase"]),
					"il botta-risposta non puo' essere scavalcato da un'altra attesa")
		elif ["battuta", "verdetto", "azione"].has(fase):
			assert_gt(i, 0)
			if i > 0:
				assert_eq(String(passi[i - 1]["fase"]), "attesa",
					"ogni voce deve essere preceduta dall'autore che sta rispondendo")
				assert_ne(foto, String(passi[i - 1]["dati"].get("trascrizione", "")),
					"la risposta deve popolare davvero la fotografia successiva")


func test_un_indicatore_visivo_non_entra_nel_salvataggio():
	var pannello := PannelloChat.new("OLIMPO")
	add_child_autofree(pannello)
	await wait_process_frames(1)
	GameManager.agora.scrivi(Agora.CANALE_OLIMPO, "Atena", "Una voce durevole.", 1, "voce", "Α")
	pannello.imposta(GameManager.agora.trascrizione(Agora.VISTA_OLIMPO))
	pannello.mostra_indicatore("Sentinella transitoria")

	assert_true(GameManager.salva_partita(PATH_SALVATAGGIO))
	var su_disco := FileAccess.get_file_as_string(PATH_SALVATAGGIO)
	assert_false(su_disco.contains("Sentinella transitoria"))
	assert_false(su_disco.contains("sta rispondendo"))
	assert_true(su_disco.contains("Una voce durevole"),
		"la chat deve salvarsi; e' soltanto l'indicatore a essere effimero")


func test_un_turno_che_avanza_usa_un_solo_quadro_autorevole():
	var ordine := GameManager.episodi.ordine()
	var esito: Dictionary = await GameManager.esegui_turno("Salpo e riprendo il mare.")
	assert_true(bool(esito.get("avanzato", false)))
	assert_eq(String(esito.get("episodio", "")), "ciconi")
	if not esito.has("quadro_narrativo"):
		fail_test("il turno reale non consegna ancora il quadro autorevole usato da Omero")
		return

	var quadro: Dictionary = esito["quadro_narrativo"]
	var controllo := QuadroNarrativo.valida(quadro)
	assert_true(bool(controllo["ok"]), "quadro del turno non valido: %s" % [controllo["errori"]])
	var passaggio: Dictionary = quadro.get("passaggio", {})
	var da_id := String(passaggio.get("da", {}).get("id", ""))
	var a_id := String(passaggio.get("a", {}).get("id", ""))
	var indice := ordine.find(da_id)
	assert_gte(indice, 0)
	assert_lt(indice + 1, ordine.size())
	if indice >= 0 and indice + 1 < ordine.size():
		assert_eq(a_id, String(ordine[indice + 1]), "Omero non puo' saltare una tappa")
	assert_eq(String(passaggio.get("causa", "")), "scelta")
	assert_eq(String(quadro.get("stato_prima", {}).get("episodio", {}).get("id", "")), "troia")
	assert_eq(String(quadro.get("stato_dopo", {}).get("episodio", {}).get("id", "")), "ciconi")
	assert_eq(String(esito.get("transizione", "")), "",
		"il quadro deve produrre una voce atomica, non una seconda traversata di Omero")
	assert_eq(String(esito.get("voce", {}).get("episodio", "")), "troia",
		"la voce appartiene alla tappa in cui l'azione e' cominciata")
	var narrazione := String(esito.get("voce", {}).get("narrazione_omero", ""))
	assert_true(narrazione.contains("Ciconi") or narrazione.contains("Ismaro"),
		"anche il mock deve rendere visibile l'unico approdo: senza la vecchia transizione " +
		"sembra un teletrasporto")


func test_la_pressione_resta_un_prodigio_nel_quadro_del_turno():
	# Con i valori di bilanciamento correnti il turno 19 e' quello successivo all'intero
	# grado 3: si e' gia' letto «gli dei lo sospingono», ora la spinta puo' avvenire.
	GameManager.stato.viaggio["turni_in_episodio"] = 18
	var esito: Dictionary = await GameManager.esegui_turno("Guardo l'orizzonte in silenzio.")
	assert_true(bool(esito.get("avanzato", false)))
	assert_eq(String(esito.get("causa", "")), "prodigio")
	if not esito.has("quadro_narrativo"):
		fail_test("la spinta reale non e' ancora rappresentata in un quadro autorevole")
		return

	var quadro: Dictionary = esito["quadro_narrativo"]
	var pressione: Dictionary = quadro.get("conseguenze", {}).get("pressione", {})
	var passaggio: Dictionary = quadro.get("passaggio", {})
	assert_eq(int(pressione.get("grado", 0)), Viaggio.GRADO_SPINTA)
	assert_true(bool(pressione.get("spinge", false)))
	assert_has(quadro.get("conseguenze", {}).get("eventi", []), "gli_dei_lo_sospingono")
	assert_eq(String(passaggio.get("causa", "")), "prodigio")
	assert_eq(String(passaggio.get("da", {}).get("id", "")), "troia")
	assert_eq(String(passaggio.get("a", {}).get("id", "")), "ciconi")
	assert_true(bool(QuadroNarrativo.valida(quadro)["ok"]))


func test_due_uscite_incoerenti_cadono_sulla_traversata_sicura():
	var quadro := _quadro_di_traversata()
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("Al tramonto giunsero a Ismaro, poi lasciarono Ismaro, videro i Lotofagi e approdarono su una costa sconosciuta."),
		_ok("Il sole basso li vide ripartire da Ismaro verso una seconda isola, oltre la terra dei Lotofagi."),
	]
	var testo := await Narratore.new([]).narra(QuadroNarrativo.come_contesto_omero(quadro), fake.chat)
	var per_guardia := QuadroNarrativo.per_validatore(quadro)
	var controllo := ValidatoreNarrativo.new().valida(testo, per_guardia)
	assert_eq(fake.chiamate, 2, "Omero deve avere un solo tentativo di correzione")
	assert_true(bool(controllo["ok"]), "il ripiego ha violato il quadro: %s" % [controllo["violazioni"]])
	assert_false(testo.contains("Lotofagi"))
	assert_false(testo.to_lower().contains("tramonto"))
	assert_true(testo.contains("Troia"))
	assert_true(testo.contains("Ismaro"))


func test_negare_un_fatto_vietato_non_forza_un_retry():
	var quadro := _quadro_di_traversata()
	var corretto := "Nessuna nave affondo': tutte raggiunsero Ismaro a mezzogiorno."
	var fake := FakeChat.new()
	fake.risposte = [_ok(corretto), _ok("Da Troia raggiunsero Ismaro a mezzogiorno.")]
	var testo := await Narratore.new([]).narra(QuadroNarrativo.come_contesto_omero(quadro), fake.chat)
	assert_eq(fake.chiamate, 1,
		"una negazione esplicita e coerente non e' un fatto inventato e non deve consumare un retry")
	assert_eq(testo, corretto)


func test_il_messaggio_atomico_conserva_la_continuita_oltre_al_quadro():
	GameManager.stato.cronaca = "CRONACA SENTINELLA: il ritorno ha gia avuto un prezzo."
	GameManager._ultima_narrazione = "ULTIMA SENTINELLA: le vele erano ancora serrate."
	GameManager.stato.parole_ai_compagni.append(
		"PAROLE SENTINELLA: nessuno sciolga la formazione.")
	LLMManager.azzera_telemetria_omero()
	await GameManager.esegui_turno("Sciolgo le vele.")

	assert_eq(LLMManager.numero_chiamate_omero, 1,
		"il turno atomico deve inviare un solo contesto a Omero")
	var ctx: Dictionary = LLMManager.ultimo_contesto_omero
	assert_true(ctx.has("quadro_narrativo"),
		"il contesto realmente consegnato deve portare il quadro autorevole")
	var messaggi := Narratore.new([]).costruisci_messaggi(ctx)
	assert_eq(messaggi.size(), 2)
	if messaggi.size() < 2:
		return
	var consegna := String(messaggi[1].get("content", ""))
	assert_string_contains(consegna, "Sciolgo le vele.", "il quadro deve portare le parole esatte di Ulisse")
	assert_string_contains(consegna, "CRONACA SENTINELLA")
	assert_string_contains(consegna, "ULTIMA SENTINELLA")
	assert_string_contains(consegna, "PAROLE SENTINELLA")


func test_senza_indugio_non_nasconde_un_uscita_dalla_destinazione():
	var per_guardia := QuadroNarrativo.per_validatore(_quadro_di_traversata())
	var testo := "A mezzogiorno raggiunsero Ismaro e, senza indugio, lasciarono Ismaro a remi."
	var controllo := ValidatoreNarrativo.new().valida(testo, per_guardia)
	var codici: Array = []
	for violazione in controllo.get("violazioni", []):
		codici.append(String(violazione.get("codice", "")))
	assert_has(codici, ValidatoreNarrativo.CODICE_USCITA_DESTINAZIONE,
		"«senza indugio» modifica il modo della partenza: non la nega")


func test_due_movimenti_inventati_in_un_turno_fermo_cadono_sul_ripiego():
	var fermo := _stato("troia", "La partenza da Troia")
	var quadro := QuadroNarrativo.crea(
		fermo,
		{"testo": "Osservo il mare.", "sintesi": "Ulisse osserva il mare.",
			"tipo": "azione", "tag": []},
		{"delta": {}, "eventi": [], "fatti": [], "esito": "continua",
			"pressione": {"grado": 0, "spinge": false}},
		fermo, "alba", [], [], {},
		QuadroNarrativo.politica_rotta_fissa(
			["troia", "ciconi", "lotofagi"],
			{"troia": "La partenza da Troia", "ciconi": "I Ciconi di Ismaro",
				"lotofagi": "La terra dei Lotofagi"}))
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("Alzate le vele, Ulisse e i compagni salparono da Troia verso il mare aperto."),
		_ok("Infine approdarono a Ismaro; gia si scorgeva la terra dei Lotofagi."),
	]

	var testo := await Narratore.new([]).narra(
		QuadroNarrativo.come_contesto_omero(quadro), fake.chat)
	var per_guardia := QuadroNarrativo.per_validatore(quadro)
	var controllo := ValidatoreNarrativo.new().valida(testo, per_guardia)
	assert_false(bool(per_guardia.get("passaggio_avvenuto", true)))
	assert_eq(fake.chiamate, 2,
		"anche una partenza senza tappa extra deve consumare il retry del turno fermo")
	assert_true(bool(controllo["ok"]), "il ripiego fermo non e valido: %s" % controllo)
	assert_false(testo.to_lower().contains("ismaro"))
	assert_false(testo.to_lower().contains("lotofagi"))
	var basso := testo.to_lower()
	assert_true(basso.contains("osserva il mare") or basso.contains("resto"),
		"il ripiego deve conservare lazione lecita o dichiarare esplicitamente la permanenza")


func test_sognare_itaca_non_e_una_tappa_extra_durante_un_passaggio_reale():
	var quadro := _quadro_di_traversata()
	quadro["politica"]["ordine_tappe"].append("itaca")
	quadro["politica"]["nomi_tappe"]["itaca"] = "Itaca"
	var corretto := ("Da Troia le navi raggiunsero Ismaro a mezzogiorno; " +
		"nel cuore Ulisse sognava Itaca.")
	var fake := FakeChat.new()
	fake.risposte = [_ok(corretto), _ok("Da Troia raggiunsero Ismaro a mezzogiorno.")]

	var testo := await Narratore.new([]).narra(
		QuadroNarrativo.come_contesto_omero(quadro), fake.chat)
	var controllo := ValidatoreNarrativo.new().valida(
		testo, QuadroNarrativo.per_validatore(quadro))
	assert_eq(fake.chiamate, 1,
		"una meta soltanto sognata non deve consumare il retry durante la traversata")
	assert_eq(testo, corretto)
	assert_true(bool(controllo["ok"]),
		"Itaca sognata non e un secondo approdo: %s" % controllo)
