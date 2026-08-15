extends GutTest

## Il quadro e' il contratto fra regole e prosa. Questi test sorvegliano soprattutto cio'
## che un prompt da solo non puo' garantire: una sola transizione, rotta fissa, causa del
## prodigio, dati non mutati e opzioni diverse per le traversate.

class FakeChat:
	var risposte: Array = []
	var chiamate := 0
	var opzioni: Array = []
	func chat(_messaggi: Array, opts: Dictionary) -> Dictionary:
		opzioni.append(opts.duplicate(true))
		var i := mini(chiamate, risposte.size() - 1)
		chiamate += 1
		return risposte[i]

func _ok(testo: String) -> Dictionary:
	return {"ok": true, "content": testo, "error": ""}

func _stato(id: String, nome: String) -> Dictionary:
	return {
		"episodio": {"id": id, "nome": nome, "scena": "Ulisse e la ciurma presso il mare."},
		"ulisse": {"animo": 50, "metis": 50, "ciurma": 45},
		"viaggio": {"turni_in_episodio": 3},
	}

func _politica() -> Dictionary:
	return QuadroNarrativo.politica_rotta_fissa(
		["troia", "ciconi", "lotofagi"],
		{"troia": "La partenza da Troia", "ciconi": "I Ciconi di Ismaro", "lotofagi": "La terra dei Lotofagi"})

func _quadro_fermo() -> Dictionary:
	return QuadroNarrativo.crea(
		_stato("troia", "La partenza da Troia"),
		{"testo": "Osservo il mare.", "sintesi": "Ulisse osserva il mare.", "tipo": "azione", "tag": []},
		{"delta": {}, "eventi": [], "fatti": [], "esito": "continua", "pressione": {"grado": 0, "spinge": false}},
		_stato("troia", "La partenza da Troia"), "all'alba", [], [], {}, _politica())

func _quadro_passaggio(causa: String = "scelta", pressione_spinge: bool = false,
		destinazione: String = "ciconi") -> Dictionary:
	var nome_a := "I Ciconi di Ismaro" if destinazione == "ciconi" else "La terra dei Lotofagi"
	return QuadroNarrativo.crea(
		_stato("troia", "La partenza da Troia"),
		{"testo": "Sciolgo le vele.", "sintesi": "Ulisse lascia Troia.", "tipo": "movimento", "tag": ["rotta"]},
		{"delta": {"ulisse.animo": -3}, "eventi": ["gli_dei_lo_sospingono"] if pressione_spinge else [],
			"fatti": ["Le vele sono state sciolte."], "esito": "continua",
			"pressione": {"grado": 3 if pressione_spinge else 0, "spinge": pressione_spinge}},
		_stato(destinazione, nome_a), "al tramonto",
		["Le navi raggiungono la tappa assegnata."],
		[{"id": "nave_perduta", "descrizione": "la perdita permanente di una nave",
			"marcatori": ["una nave affondo'", "perdettero una nave"]}],
		{"avvenuto": true,
			"da": {"id": "troia", "nome": "La partenza da Troia"},
			"a": {"id": destinazione, "nome": nome_a}, "causa": causa},
		_politica())

func test_quadro_fermo_valido_e_passaggio_esplicitamente_assente():
	var q := _quadro_fermo()
	assert_true(QuadroNarrativo.valida(q)["ok"])
	assert_false(q["passaggio"]["avvenuto"])
	assert_eq(q["stato_prima"]["episodio"]["id"], q["stato_dopo"]["episodio"]["id"])

func test_cambiare_tappa_senza_passaggio_e_rifiutato():
	var q := _quadro_fermo()
	q["stato_dopo"] = _stato("ciconi", "I Ciconi di Ismaro")
	var v := QuadroNarrativo.valida(q)
	assert_false(v["ok"])
	assert_true(" ".join(v["errori"]).contains("passaggio.avvenuto"))

func test_la_rotta_fissa_rifiuta_un_salto_di_tappa():
	var q := _quadro_passaggio("scelta", false, "lotofagi")
	var v := QuadroNarrativo.valida(q)
	assert_false(v["ok"])
	assert_true(" ".join(v["errori"]).contains("fuori rotta"))

func test_il_passaggio_alla_sola_tappa_successiva_e_valido():
	var q := _quadro_passaggio()
	assert_true(QuadroNarrativo.valida(q)["ok"])
	assert_eq(q["passaggio"]["da"]["id"], "troia")
	assert_eq(q["passaggio"]["a"]["id"], "ciconi")
	assert_eq(q["passaggio"]["causa"], "scelta")

func test_la_pressione_che_spinge_esige_il_prodigio():
	var scelta := QuadroNarrativo.valida(_quadro_passaggio("scelta", true))
	assert_false(scelta["ok"])
	assert_true(" ".join(scelta["errori"]).contains("solo come prodigio"))
	assert_true(QuadroNarrativo.valida(_quadro_passaggio("prodigio", true))["ok"],
		"il prodigio della pressione deve restare valido e raggiungibile")

func test_autorevole_vuol_dire_stato_non_fedelta_forzata_al_poema():
	var prompt := QuadroNarrativo.per_prompt(_quadro_fermo())
	assert_string_contains(prompt, "fonte: stato della partita")
	assert_string_contains(prompt, "NON significa fedelta' forzata al poema")
	assert_string_contains(prompt, "STATO PRIMA")
	assert_string_contains(prompt, "AZIONE DI ULISSE")
	assert_string_contains(prompt, "CONSEGUENZE DETERMINISTICHE")
	assert_string_contains(prompt, "STATO DOPO")
	assert_string_contains(prompt, "PASSAGGIO: nessuno")
	assert_string_contains(prompt, "FATTI AMMESSI")
	assert_string_contains(prompt, "FATTI VIETATI")
	assert_string_contains(prompt, "SALTO TEMPORALE: vietato")

func test_il_quadro_vieta_esplicitamente_salti_di_giorni_o_notti():
	var q := _quadro_fermo()
	assert_false(bool(q["vincoli"]["salto_temporale_ammesso"]))
	assert_false(bool(QuadroNarrativo.per_validatore(q)["salto_temporale_ammesso"]))

func test_prompt_del_passaggio_fissa_da_a_causa_e_unicita():
	var prompt := QuadroNarrativo.per_prompt(_quadro_passaggio("prodigio", true))
	assert_string_contains(prompt, "PASSAGGIO UNICO")
	assert_string_contains(prompt, "La partenza da Troia")
	assert_string_contains(prompt, "I Ciconi di Ismaro")
	assert_string_contains(prompt, "causa «prodigio»")
	assert_string_contains(prompt, "fermati nella tappa di arrivo")

func test_crea_duplica_i_dati_e_non_li_lega_al_chiamante():
	var prima := _stato("troia", "La partenza da Troia")
	var q := QuadroNarrativo.crea(prima,
		{"testo": "Guardo.", "sintesi": "Ulisse guarda."}, {}, prima, "all'alba",
		[], [], {}, _politica())
	prima["episodio"]["id"] = "manomesso"
	assert_eq(q["stato_prima"]["episodio"]["id"], "troia")

func test_adattatore_del_validatore_e_puro_e_conserva_rotta_e_fatti():
	var q := _quadro_passaggio("prodigio", true)
	var v := QuadroNarrativo.per_validatore(q)
	assert_true(v["passaggio_avvenuto"])
	assert_eq(v["origine"], "La partenza da Troia")
	assert_eq(v["destinazione"], "I Ciconi di Ismaro")
	assert_eq(v["causa"], "prodigio")
	assert_eq(v["rotta"].size(), 3)
	assert_eq(v["fatti_vietati"][0]["id"], "nave_perduta")

func test_adattatore_del_turno_fermo_ancora_origine_e_destinazione_alla_stessa_tappa():
	var v := QuadroNarrativo.per_validatore(_quadro_fermo())
	assert_false(v["passaggio_avvenuto"])
	assert_eq(v["origine"], "La partenza da Troia")
	assert_eq(v["destinazione"], v["origine"])
	assert_eq(v["causa"], "")
	assert_eq(v["rotta"].size(), 3)

func test_adattatore_e_validatore_accettano_la_sola_traversata_fissata():
	var q := _quadro_passaggio("prodigio", true)
	var guardia := ValidatoreNarrativo.new()
	var v := guardia.valida(
		"Lasciata Troia, una forza li sospinse fino ai Ciconi di Ismaro.",
		QuadroNarrativo.per_validatore(q))
	assert_true(v["ok"], "il quadro e il validatore devono parlare lo stesso contratto: %s" % v)

func test_traversata_sicura_conserva_rotta_causa_pressione_e_prodigio():
	var q := _quadro_passaggio("prodigio", true)
	var per_guardia := QuadroNarrativo.per_validatore(q)
	var guardia := ValidatoreNarrativo.new()
	var invalido := guardia.valida(
		"Dopo Ismaro ripartirono e approdarono alla terra dei Lotofagi.", per_guardia)
	assert_false(invalido["ok"])
	var sicura := TraversataSicura.scegli("testo da scartare", per_guardia, invalido, guardia)
	assert_true(sicura["fallback"])
	assert_eq(sicura["causa"], "prodigio")
	assert_true(sicura["validazione"]["ok"])
	assert_false(String(sicura["testo"]).to_lower().contains("lotofagi"))

func test_mock_accetta_il_contesto_nuovo_senza_perdere_la_sintesi():
	var contesto := QuadroNarrativo.come_contesto_omero(_quadro_fermo())
	var mock := LLMMock.new()
	var a := mock.narrazione_omero(contesto)
	var b := mock.narrazione_omero(contesto)
	assert_eq(a, b, "il mock resta deterministico")
	assert_string_contains(a, "Ulisse osserva il mare")

func test_il_prompt_atomico_conserva_la_continuita_senza_far_ne_una_seconda_fonte():
	var contesto := QuadroNarrativo.come_contesto_omero(_quadro_passaggio())
	contesto["cronaca"] = "La guerra e il primo tratto di mare sono alle spalle."
	contesto["storia"] = ["Ulisse raccolse i suoi", "ordino' di sciogliere le vele"]
	contesto["ultima_narrazione"] = "Il fumo di Troia velava ancora l'orizzonte."
	contesto["detto_ai_compagni"] = "Ai remi, amici: torniamo a casa."
	contesto["luogo"] = "I Ciconi di Ismaro"
	contesto["progresso"] = "inizio"
	contesto["morale"] = "incerto"
	var messaggi := Narratore.new([]).costruisci_messaggi(contesto)
	var prompt := String(messaggi[1]["content"])
	assert_string_contains(prompt, "CONTINUITA' DEL RACCONTO")
	assert_string_contains(prompt, String(contesto["cronaca"]))
	assert_string_contains(prompt, String(contesto["ultima_narrazione"]))
	assert_string_contains(prompt, String(contesto["detto_ai_compagni"]))
	assert_string_contains(prompt, "se contrasta col quadro, vale il quadro")

func test_le_temperature_sono_distinte_senza_degradare_la_prosa_ordinaria():
	var n := Narratore.new([])
	var normale: float = n.opzioni_per({"sintesi": "x"})["temperature"]
	var traversata: float = n.opzioni_per({"passaggio": {"da": "A", "a": "B"}})["temperature"]
	var atomica: float = n.opzioni_per(QuadroNarrativo.come_contesto_omero(_quadro_passaggio()))["temperature"]
	assert_eq(normale, Narratore.TEMPERATURA_NARRAZIONE)
	assert_lt(traversata, normale)
	assert_lt(atomica, normale)
	assert_gt(atomica, traversata, "azione + transizione conserva piu' respiro della sola traversata")

func test_un_quadro_invalido_non_chiama_il_modello():
	var q := _quadro_passaggio("scelta", false, "lotofagi")
	var fake := FakeChat.new()
	fake.risposte = [_ok("Non dovrebbe essere letta.")]
	var testo := await Narratore.new([]).narra(QuadroNarrativo.come_contesto_omero(q), fake.chat)
	assert_eq(testo, "")
	assert_eq(fake.chiamate, 0)

func test_un_fatto_vietato_reiterato_cade_sul_ripiego_autorevole():
	var q := _quadro_passaggio()
	var fake := FakeChat.new()
	fake.risposte = [_ok("Nel viaggio una nave affondo'."), _ok("Una nave affondo' prima dell'approdo.")]
	var testo := await Narratore.new([]).narra(QuadroNarrativo.come_contesto_omero(q), fake.chat)
	assert_eq(fake.chiamate, 2)
	assert_false(testo.to_lower().contains("una nave affondo"))
	assert_string_contains(testo, "I Ciconi di Ismaro")

func test_senza_indugio_non_nega_un_fatto_vietato_ma_nessuna_si():
	var q := _quadro_passaggio()
	assert_false(QuadroNarrativo.violazioni_testuali(
		q, "Senza indugio, una nave affondo' prima dell'approdo.").is_empty())
	assert_true(QuadroNarrativo.violazioni_testuali(
		q, "Nessuna nave affondo': tutte raggiunsero Ismaro.").is_empty())

func test_una_tappa_extra_reiterata_cade_sulla_traversata_sicura():
	var q := _quadro_passaggio("prodigio", true)
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("Da Troia giunsero a Ismaro, poi ripartirono verso i Lotofagi."),
		_ok("Toccato Ismaro, salparono ancora e raggiunsero i Lotofagi."),
	]
	var testo := await Narratore.new([]).narra(QuadroNarrativo.come_contesto_omero(q), fake.chat)
	assert_eq(fake.chiamate, 2)
	assert_false(testo.to_lower().contains("lotofagi"))
	assert_string_contains(testo, "I Ciconi di Ismaro")
	assert_true(ValidatoreNarrativo.new().valida(
		testo, QuadroNarrativo.per_validatore(q))["ok"], "anche l'ultima difesa deve validarsi")

func test_due_partenze_inventate_in_un_turno_fermo_cadono_su_un_ripiego_fermo():
	var q := _quadro_fermo()
	q["azione"]["testo"] = "Salpo verso Ismaro."
	q["azione"]["sintesi"] = "Ulisse salpa e raggiunge Ismaro."
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("Ulisse salpo' da Troia e approdo' a Ismaro."),
		_ok("Lasciata Troia, le navi raggiunsero la terra dei Lotofagi."),
	]
	var testo := await Narratore.new([]).narra(QuadroNarrativo.come_contesto_omero(q), fake.chat)
	assert_eq(fake.chiamate, 2)
	assert_false(testo.to_lower().contains("ismaro"))
	assert_false(testo.to_lower().contains("lotofagi"))
	assert_false(testo.to_lower().contains("salpa"), "il ripiego non deve ripetere la sintesi incoerente")
	assert_false(testo.to_lower().contains("approd"))
	assert_string_contains(testo, "rimase dov'era")
	var controllo := ValidatoreNarrativo.new().valida(testo, QuadroNarrativo.per_validatore(q))
	assert_true(bool(controllo["ok"]), "il ripiego deve restare nella scena: %s" % controllo)

func test_due_salti_temporali_inventati_cadono_sul_ripiego_dello_stesso_momento():
	var q := _quadro_fermo()
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("Il terzo giorno Ulisse guardo' ancora il mare."),
		_ok("Due notti dopo, la stessa alba lo trovo' sulla riva."),
	]
	var testo := await Narratore.new([]).narra(QuadroNarrativo.come_contesto_omero(q), fake.chat)
	assert_eq(fake.chiamate, 2)
	assert_false(testo.to_lower().contains("terzo giorno"))
	assert_false(testo.to_lower().contains("due notti"))
	assert_string_contains(testo, "Ulisse osserva il mare")
