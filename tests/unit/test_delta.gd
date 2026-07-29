extends GutTest

var _p: Pantheon

func before_each():
	_p = Pantheon.carica("res://data/pantheon.json")

func _stato() -> StatoPartita:
	return StatoPartita.nuova(_p, 999)

# --- delta da azione ---

func test_da_azione_hybris_su_tracotanza():
	var d := Delta.da_azione({"tag": ["vanto", "tracotanza"], "intensita": 2})
	assert_eq(d.get("ulisse.hybris"), 8)  # 2 tag hybris * 2 * intensita(2)

func test_da_azione_metis_su_astuzia():
	var d := Delta.da_azione({"tag": ["astuzia"], "intensita": 2})
	assert_eq(d.get("ulisse.metis"), 2)

func test_da_azione_neutra_vuota():
	assert_true(Delta.da_azione({"tag": [], "intensita": 1}).is_empty())

# --- delta da reazione ---

func test_castigo_abbassa_animo_e_alza_ira():
	var d := Delta.da_reazione("poseidone", "castigo", 2)
	assert_eq(d.get("ulisse.animo"), -4)
	assert_eq(d.get("poseidone.ira"), 4)

func test_aiuto_alza_animo_e_favore():
	var d := Delta.da_reazione("atena", "aiuto", 1)
	assert_eq(d.get("ulisse.animo"), 2)
	assert_eq(d.get("atena.favore"), 1)

func test_silenzio_nessun_effetto():
	assert_true(Delta.da_reazione("zeus", "silenzio", 3).is_empty())

# --- unione e applicazione ---

func test_unisci_somma_additiva():
	var a := {"ulisse.animo": 2, "atena.favore": 1}
	var b := {"ulisse.animo": -5}
	var u := Delta.unisci(a, b)
	assert_eq(u.get("ulisse.animo"), -3)
	assert_eq(u.get("atena.favore"), 1)

func test_applica_muta_stato():
	var s := _stato()
	var animo0: int = s.ulisse["stat"]["animo"]
	Delta.applica(s, {"ulisse.animo": -10, "poseidone.ira": 5, "ulisse.hybris": 3})
	assert_eq(s.ulisse["stat"]["animo"], animo0 - 10)
	assert_eq(s.ulisse["hybris"], 3)
	assert_eq(s.registro_divino["poseidone"]["ira"], _p.get_dio("poseidone").ira_iniziale + 5)

func test_applica_clamp_massimo():
	var s := _stato()
	s.ulisse["stat"]["animo"] = 98
	Delta.applica(s, {"ulisse.animo": 10})
	assert_eq(s.ulisse["stat"]["animo"], 100, "l'animo non supera 100")

func test_applica_clamp_ciurma_non_negativa():
	var s := _stato()
	s.ulisse["stat"]["ciurma"]["vivi"] = 3
	Delta.applica(s, {"ulisse.ciurma.vivi": -10})
	assert_eq(s.ulisse["stat"]["ciurma"]["vivi"], 0)

# --- marcatore diario ---

func test_marcatore_ill_fair_neutro():
	assert_eq(Delta.marcatore_diario({"ulisse.animo": -2}), "ill")
	assert_eq(Delta.marcatore_diario({"ulisse.ciurma.vivi": -1}), "ill")
	assert_eq(Delta.marcatore_diario({"ulisse.animo": 3}), "fair")
	assert_eq(Delta.marcatore_diario({"ulisse.metis": 1}), "neutro")

# --- Difetti corretti nel box "La tua condizione" ---

func test_castigo_forte_costa_uomini():
	# Prima nessun delta toccava la ciurma: restava 45/45 per tutta la partita e
	# l'esito "ciurma_perduta" era irraggiungibile.
	var forte := Delta.da_reazione("poseidone", "castigo", 3)
	assert_eq(forte.get("ulisse.ciurma.vivi", 0), -2, "l'ira piena si porta via dei compagni")
	var medio := Delta.da_reazione("poseidone", "castigo", 2)
	assert_eq(medio.get("ulisse.ciurma.vivi", 0), -1)
	var lieve := Delta.da_reazione("poseidone", "castigo", 1)
	assert_false(lieve.has("ulisse.ciurma.vivi"), "un castigo lieve non uccide nessuno")

func test_umilta_fa_scendere_la_tracotanza():
	# Prima la hybris poteva solo salire: fondo di scala inevitabile.
	var d := Delta.da_azione({"tag": ["preghiera"], "intensita": 2})
	assert_eq(d.get("ulisse.hybris", 0), -2, "la reverenza sgonfia la tracotanza")

func test_vanto_e_preghiera_insieme_non_si_annullano():
	# Se ti vanti mentre preghi, la tracotanza sale: l'umilta' non ripaga.
	var d := Delta.da_azione({"tag": ["vanto", "preghiera"], "intensita": 1})
	assert_gt(d.get("ulisse.hybris", 0), 0)
