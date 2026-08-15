extends GutTest

## Scenari della traversata Troia -> Ismaro. Sono test puri: nessun autoload cambia stato,
## nessuna chiamata LLM e nessuna dipendenza dalla macchina del turno.

var _validatore: ValidatoreNarrativo
var _quadro: Dictionary


func before_each():
	_validatore = ValidatoreNarrativo.new()
	_quadro = {
		"origine": "Troia",
		"destinazione": "Ismaro",
		"causa": "prodigio",
		"pressione": "gli_dei_lo_sospingono",
		"momento": "a mezzogiorno",
		"rotta": [
			{"id": "troia", "nome": "La partenza da Troia", "alias": ["Troia"]},
			{"id": "ciconi", "nome": "I Ciconi di Ismaro", "alias": ["Ismaro", "Ciconi"]},
			{"id": "lotofagi", "nome": "La terra dei Lotofagi", "alias": ["Lotofagi"]},
			{"id": "trinacia", "nome": "L'isola del Sole", "alias": ["Trinacia"]},
			{"id": "itaca", "nome": "Itaca", "alias": ["Itaca"]},
		],
		"fatti_vietati": [
			{"id": "nave_perduta", "marcatori": ["una nave affondo'", "perdettero una nave"]},
		],
	}


func _codici(testo: String, quadro: Dictionary = _quadro) -> Array:
	var out: Array = []
	for violazione in _validatore.valida(testo, quadro)["violazioni"]:
		out.append(violazione["codice"])
	return out


func test_accetta_un_arrivo_corretto_a_ismaro():
	var testo := "Troia svani' dietro le prue. A mezzogiorno le navi raggiunsero Ismaro, e le chiglie toccarono terra davanti alle mura dei Ciconi."
	var esito := _validatore.valida(testo, _quadro)
	assert_true(bool(esito["ok"]), "arrivo corretto respinto: %s" % [esito["violazioni"]])


func test_lasciare_l_origine_e_il_passaggio_corretto_non_un_secondo_tratto():
	var testo := "A mezzogiorno Ulisse lascio' Troia e raggiunse Ismaro, dove le chiglie toccarono terra."
	var esito := _validatore.valida(testo, _quadro)
	assert_true(bool(esito["ok"]), "la partenza dall origine e stata respinta: %s" % [esito["violazioni"]])


func test_respingere_lascia_ismaro():
	var codici := _codici("Da Troia giunsero a Ismaro, ma Ulisse lascia Ismaro e riprende il mare.")
	assert_has(codici, ValidatoreNarrativo.CODICE_USCITA_DESTINAZIONE)


func test_respingere_una_spiaggia_sconosciuta_e_il_secondo_approdo():
	var codici := _codici("Raggiunsero Ismaro; poi approdarono su una spiaggia sconosciuta.")
	assert_has(codici, ValidatoreNarrativo.CODICE_SECONDO_APPRODO)


func test_respingere_un_approdo_altrove_anche_senza_aggettivo_sconosciuta():
	var codici := _codici("Dopo Troia approdarono a una costa rocciosa; soltanto dopo videro Ismaro.")
	assert_has(codici, ValidatoreNarrativo.CODICE_SECONDO_APPRODO)


func test_respingere_i_lotofagi_che_sono_una_tappa_futura():
	var codici := _codici("Da Troia giunsero dai Lotofagi, e soltanto dopo videro Ismaro.")
	assert_has(codici, ValidatoreNarrativo.CODICE_TAPPA_ESTRANEA)


func test_durante_il_passaggio_puo_sognare_una_tappa_futura():
	var testo := "Da Troia le navi raggiunsero Ismaro a mezzogiorno; nel cuore Ulisse sognava Itaca."
	var esito := _validatore.valida(testo, _quadro)
	assert_true(bool(esito["ok"]), "un sogno e stato letto come arrivo: %s" % [esito])


func test_respingere_il_sole_basso_al_mezzogiorno():
	var codici := _codici("Il sole basso arrossava il mare quando apparve Ismaro.")
	assert_has(codici, ValidatoreNarrativo.CODICE_TEMPO)


func test_campione_reale_unisce_difetti_senza_bocciare_il_sogno_di_itaca():
	var testo := "Il sole basso arrossava il mare. Il terzo giorno, le coste dei Ciconi sono sparite da due notti. Apparve una spiaggia sconosciuta; Ulisse continuo a sognare Itaca."
	var codici := _codici(testo)
	assert_has(codici, ValidatoreNarrativo.CODICE_TEMPO)
	assert_has(codici, ValidatoreNarrativo.CODICE_SALTO_TEMPORALE)
	assert_has(codici, ValidatoreNarrativo.CODICE_SECONDO_APPRODO)
	assert_does_not_have(codici, ValidatoreNarrativo.CODICE_TAPPA_ESTRANEA,
		"sognare Itaca non equivale ad arrivarci")


func test_respingere_un_fatto_permanente_esplicitamente_vietato():
	var codici := _codici("Prima di Ismaro una nave affondo', e le altre proseguirono.")
	assert_has(codici, ValidatoreNarrativo.CODICE_FATTO_VIETATO)


# --- Falsi positivi noti: immagini, parole generiche e negazioni non sono eventi. ---

func test_le_ombre_verso_occidente_non_cambiano_la_rotta():
	var testo := "A mezzogiorno le ombre delle prue correvano verso occidente; la rotta fra Troia e Ismaro non muto'."
	assert_true(bool(_validatore.valida(testo, _quadro)["ok"]),
		"un'immagine di direzione non e' una deviazione o una partenza")


func test_il_sole_normale_non_anticipa_l_isola_del_sole():
	var testo := "Il sole alto di mezzogiorno batteva sulle prue mentre Ismaro cresceva davanti a loro."
	assert_true(bool(_validatore.valida(testo, _quadro)["ok"]),
		"la parola generica «sole» non deve valere come nome di Trinacia")


func test_una_partenza_negata_non_e_un_uscita_dalla_destinazione():
	var testo := "Giunti a Ismaro, non lasciarono Ismaro: tirarono le navi sulla sabbia."
	assert_true(bool(_validatore.valida(testo, _quadro)["ok"]))


func test_senza_indugio_non_nega_la_partenza_da_ismaro():
	var testo := "A mezzogiorno raggiunsero Ismaro e, senza indugio, lasciarono Ismaro a remi."
	var codici := _codici(testo)
	assert_has(codici, ValidatoreNarrativo.CODICE_USCITA_DESTINAZIONE)


func test_senza_lasciare_nega_davvero_la_partenza_da_ismaro():
	var testo := "Giunti a Ismaro, posarono i remi senza lasciare Ismaro."
	assert_true(bool(_validatore.valida(testo, _quadro)["ok"]))


func test_un_approdo_ignoto_negato_non_e_un_secondo_approdo():
	var testo := "Da Troia non approdarono su alcuna spiaggia sconosciuta: raggiunsero soltanto Ismaro."
	assert_true(bool(_validatore.valida(testo, _quadro)["ok"]))


func test_un_fatto_vietato_negato_non_viene_affermato():
	var testo := "Nessuna nave affondo': tutte raggiunsero Ismaro a mezzogiorno."
	assert_true(bool(_validatore.valida(testo, _quadro)["ok"]))


func test_i_confini_di_parola_non_scambiano_un_frammento_per_un_nome():
	var testo := "Il loto non apparve; soltanto lotofagico sarebbe un frammento, non il nome dei Lotofagi."
	# Tolgo il nome vero dalla frase di controllo: resta soltanto il frammento lungo.
	testo = testo.replace("il nome dei Lotofagi", "il nome di quella gente")
	assert_true(bool(_validatore.valida(testo, _quadro)["ok"]))


# --- Composizione e fallback preparano l'integrazione senza toccare Narratore/GameManager. ---

func test_l_esito_si_compone_con_il_guardrail_divino_senza_duplicarlo():
	var narrativo := _validatore.valida("Da Troia raggiunsero Ismaro a mezzogiorno.", _quadro)
	var divino := ValidatoreNarrativo.esito_esterno(false, "nome_divino", "nome olimpio")
	var totale := ValidatoreNarrativo.componi([narrativo, divino])
	assert_false(bool(totale["ok"]))
	assert_eq(totale["violazioni"].size(), 1)
	assert_eq(totale["violazioni"][0]["codice"], "nome_divino")


func test_la_composizione_rispetta_anche_un_no_senza_dettagli():
	var totale := ValidatoreNarrativo.componi([{"ok": false, "violazioni": []}])
	assert_false(bool(totale["ok"]))


func test_il_fallback_e_deterministico_valido_e_conserva_rotta_pressione_prodigio():
	var invalido := _validatore.valida("Lascia Ismaro e cerca i Lotofagi.", _quadro)
	var a := TraversataSicura.scegli("Lascia Ismaro e cerca i Lotofagi.", _quadro, invalido, _validatore)
	var b := TraversataSicura.scegli("altro testo invalido", _quadro, invalido, _validatore)
	assert_true(bool(a["fallback"]))
	assert_eq(a["testo"], b["testo"], "stesso quadro: stesso fallback")
	assert_true(String(a["testo"]).contains("Troia"))
	assert_true(String(a["testo"]).contains("Ismaro"))
	assert_false(String(a["testo"]).contains("Lotofagi"))
	assert_eq(a["rotta_fissa"], ["Troia", "Ismaro"])
	assert_eq(a["pressione"], "gli_dei_lo_sospingono")
	assert_eq(a["causa"], "prodigio")
	assert_true(String(a["testo"]).contains("forza piu' grande"), "il prodigio deve restare leggibile")
	assert_true(bool(a["validazione"]["ok"]), "fallback non valido: %s" % [a["validazione"]])


func test_un_testo_valido_non_viene_sostituito_dal_fallback():
	var testo := "Da Troia raggiunsero Ismaro a mezzogiorno."
	var esito := _validatore.valida(testo, _quadro)
	var scelto := TraversataSicura.scegli(testo, _quadro, esito, _validatore)
	assert_false(bool(scelto["fallback"]))
	assert_eq(scelto["testo"], testo)


# --- Salti temporali: solo durate esplicite non decise dal quadro. ---

func test_respingere_salti_temporali_espliciti_non_decisi():
	for testo in [
		"A mezzogiorno, il terzo giorno, videro Ismaro.",
		"Due notti dopo erano ancora in mare.",
		"Da due notti i compagni attendevano.",
	]:
		var codici := _codici(testo)
		assert_has(codici, ValidatoreNarrativo.CODICE_SALTO_TEMPORALE, testo)


func test_metafore_temporali_non_sono_un_salto_di_stato():
	var testo := "Il mare pareva vecchio di mille notti, ma Ismaro era davanti alle prue a mezzogiorno."
	var esito := _validatore.valida(testo, _quadro)
	assert_true(bool(esito["ok"]), "metafora temporale respinta: %s" % [esito])


func test_un_salto_temporale_esplicitamente_ammesso_passa():
	var q := _quadro.duplicate(true)
	q["salto_temporale_ammesso"] = true
	var esito := _validatore.valida("Due notti dopo videro Ismaro.", q)
	assert_true(bool(esito["ok"]), "salto autorizzato respinto: %s" % [esito])


# --- Turno fermo: nessun passaggio deciso dal quadro. ---

func _quadro_fermo() -> Dictionary:
	var q := _quadro.duplicate(true)
	q["passaggio_avvenuto"] = false
	q["origine"] = "Ismaro"
	q["destinazione"] = "Ismaro"
	q["causa"] = ""
	return q


func test_turno_fermo_respingere_una_partenza_senza_altra_tappa():
	var codici := _codici("Ulisse e i compagni salparono da Ismaro verso il largo.", _quadro_fermo())
	assert_has(codici, ValidatoreNarrativo.CODICE_MOVIMENTO_IMPREVISTO)


func test_turno_fermo_respingere_salpo_con_accento_normalizzato():
	var codici := _codici("Ulisse salpo da Ismaro verso il mare aperto.", _quadro_fermo())
	assert_has(codici, ValidatoreNarrativo.CODICE_MOVIMENTO_IMPREVISTO)


func test_turno_fermo_respingere_un_approdo_alla_tappa_corrente():
	var codici := _codici("Ulisse approdo a Ismaro e tiro le navi sulla sabbia.", _quadro_fermo())
	assert_has(codici, ValidatoreNarrativo.CODICE_MOVIMENTO_IMPREVISTO)


func test_turno_fermo_respingere_un_arrivo_a_una_tappa_futura():
	var codici := _codici("Ulisse e i compagni giunsero a Itaca.", _quadro_fermo())
	assert_has(codici, ValidatoreNarrativo.CODICE_TAPPA_ESTRANEA)


func test_turno_fermo_respingere_una_presenza_in_tappa_futura():
	var codici := _codici("Ulisse e i compagni erano gia a Itaca.", _quadro_fermo())
	assert_has(codici, ValidatoreNarrativo.CODICE_TAPPA_ESTRANEA)


func test_turno_fermo_puo_sognare_ricordare_e_desiderare_altre_tappe():
	var q := _quadro_fermo()
	for testo in [
		"Si corico sognando Itaca.",
		"Ricordo Troia e il fuoco sulle mura.",
		"Disse ai compagni: dobbiamo tornare a Itaca.",
	]:
		var esito := _validatore.valida(testo, q)
		assert_true(bool(esito["ok"]), "menzione lecita respinta: %s -> %s" % [testo, esito])


func test_turno_fermo_preserva_negazioni_e_immagini_di_direzione():
	var q := _quadro_fermo()
	for testo in [
		"Non salparono da Ismaro.",
		"Restarono sulla riva senza lasciare Ismaro.",
		"Non giunsero a Itaca.",
		"Non erano a Itaca.",
		"Le ombre delle prue correvano verso occidente.",
	]:
		var esito := _validatore.valida(testo, q)
		assert_true(bool(esito["ok"]), "falso positivo nel turno fermo: %s -> %s" % [testo, esito])


func test_turno_fermo_l_approdo_come_nome_non_e_un_nuovo_movimento():
	var esito := _validatore.valida("L approdo di Ismaro era quieto.", _quadro_fermo())
	assert_true(bool(esito["ok"]), "il nome approdo e stato letto come verbo: %s" % [esito])


func test_fallback_del_turno_fermo_non_inventa_una_traversata():
	var q := _quadro_fermo()
	var invalido := _validatore.valida("Salparono da Ismaro.", q)
	var scelto := TraversataSicura.scegli("Salparono da Ismaro.", q, invalido, _validatore)
	assert_true(bool(scelto["fallback"]))
	assert_false(bool(scelto["passaggio_avvenuto"]))
	assert_eq(scelto["rotta_fissa"], ["Ismaro"])
	assert_true(bool(scelto["validazione"]["ok"]), "fallback fermo non valido: %s" % [scelto])
