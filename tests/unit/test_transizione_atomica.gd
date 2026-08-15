extends GutTest

## Prova il confine reale, non solo il contratto puro: Viaggio applica la tappa, il
## GameManager fotografa prima/dopo e Omero riceve una sola richiesta che contiene tutto.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(904)
	LLMManager.azzera_telemetria_omero()


func test_la_scelta_di_salpare_usa_una_sola_voce_con_il_passaggio():
	var esito: Dictionary = await GameManager.esegui_turno("Salpo e riprendo il mare.")
	assert_true(bool(esito.get("avanzato", false)))
	assert_eq(LLMManager.numero_chiamate_omero, 1)
	assert_eq(String(esito.get("transizione", "")), "")

	var quadro: Dictionary = esito.get("quadro_narrativo", {})
	assert_true(bool(QuadroNarrativo.valida(quadro)["ok"]))
	assert_eq(String(quadro["stato_prima"]["episodio"]["id"]), "troia")
	assert_eq(String(quadro["stato_dopo"]["episodio"]["id"]), "ciconi")
	assert_eq(String(quadro["passaggio"]["causa"]), "scelta")
	assert_eq(String(esito["voce"]["episodio"]), "troia")
	assert_eq(LLMManager.ultimo_contesto_omero.get("quadro_narrativo", {}), quadro)
	assert_false(LLMManager.ultimo_contesto_omero.has("registro_divino"))
	assert_true(String(esito["voce"]["narrazione_omero"]).contains("Ismaro"),
		"anche il mock deve mostrare la meta nella stessa voce, non teletrasportare")


func test_la_pressione_conserva_il_prodigio_nella_singola_chiamata():
	GameManager.stato.viaggio["turni_in_episodio"] = (
		Viaggio._pressione_da() + Viaggio._pressione_passo() * Viaggio.GRADO_SPINTA - 1)
	var esito: Dictionary = await GameManager.esegui_turno("Guardo l'orizzonte in silenzio.")
	var quadro: Dictionary = esito.get("quadro_narrativo", {})

	assert_true(bool(esito.get("avanzato", false)))
	assert_eq(String(esito.get("causa", "")), "prodigio")
	assert_eq(LLMManager.numero_chiamate_omero, 1)
	assert_eq(int(quadro["conseguenze"]["pressione"]["grado"]), Viaggio.GRADO_SPINTA)
	assert_true(bool(quadro["conseguenze"]["pressione"]["spinge"]))
	assert_eq(String(quadro["passaggio"]["causa"]), "prodigio")
	assert_has(quadro["conseguenze"]["eventi"], "gli_dei_lo_sospingono")


func test_itaca_chiude_nella_stessa_voce_senza_congedo_aggiuntivo():
	GameManager.vai_a_tappa("scheria")
	LLMManager.azzera_telemetria_omero()
	var esito: Dictionary = await GameManager.esegui_turno("Salpo verso casa.")
	var quadro: Dictionary = esito.get("quadro_narrativo", {})

	assert_eq(String(esito.get("esito", "")), "itaca")
	assert_eq(LLMManager.numero_chiamate_omero, 1)
	assert_eq(String(esito.get("congedo", "")), "")
	assert_eq(String(quadro["stato_dopo"]["episodio"]["id"]), "itaca")
	assert_eq(String(quadro["passaggio"]["a"]["id"]), "itaca")
	assert_true(String(esito["voce"]["narrazione_omero"]).contains("Itaca"))
