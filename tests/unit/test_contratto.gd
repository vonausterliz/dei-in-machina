extends GutTest

func _envelope_valido() -> Dictionary:
	return {
		"plausibilita": "in_mondo", "tipo": "parola", "tag": ["vanto", "tracotanza"],
		"dio_invocato": null, "bersaglio": "polifemo", "tono": "sfida", "intensita": 2,
		"sintesi": "prova",
	}

func test_envelope_valido_passa():
	var esito := Contratto.valida_envelope(_envelope_valido())
	assert_true(esito["ok"], str(esito["errori"]))

func test_tag_fuori_vocabolario_fallisce():
	var e := _envelope_valido()
	e["tag"] = ["vanto", "inesistente"]
	var esito := Contratto.valida_envelope(e)
	assert_false(esito["ok"])

func test_plausibilita_non_valida_fallisce():
	var e := _envelope_valido()
	e["plausibilita"] = "boh"
	assert_false(Contratto.valida_envelope(e)["ok"])

func test_intensita_fuori_range_fallisce():
	var e := _envelope_valido()
	e["intensita"] = 5
	assert_false(Contratto.valida_envelope(e)["ok"])

func test_regola_5_non_in_mondo_con_tag_fallisce():
	var e := _envelope_valido()
	e["plausibilita"] = "anacronistico"
	e["tag"] = ["vanto"]
	assert_false(Contratto.valida_envelope(e)["ok"], "plausibilita != in_mondo con tag deve fallire")

func test_dio_invocato_sconosciuto_fallisce_se_lista_fornita():
	var e := _envelope_valido()
	e["dio_invocato"] = "afrodite"
	var esito := Contratto.valida_envelope(e, ["atena", "zeus", "poseidone"])
	assert_false(esito["ok"])

func test_dio_invocato_valido_passa():
	var e := _envelope_valido()
	e["dio_invocato"] = "atena"
	assert_true(Contratto.valida_envelope(e, ["atena", "zeus"])["ok"])

func test_fallback_e_sempre_valido():
	assert_true(Contratto.valida_envelope(Contratto.envelope_fallback("x"))["ok"])

# --- parsing JSON difensivo ---

func test_estrai_json_pulito():
	var d := Contratto.estrai_json('{"a": 1, "b": "due"}')
	assert_eq(int(d.get("a")), 1)
	assert_eq(d.get("b"), "due")

func test_estrai_json_con_fence_markdown():
	var testo := "Ecco l'envelope:\n```json\n{\"plausibilita\": \"in_mondo\"}\n```\n"
	var d := Contratto.estrai_json(testo)
	assert_eq(d.get("plausibilita"), "in_mondo")

func test_estrai_json_con_blocco_think():
	var testo := "<think>Rifletto: e' un vanto...</think>\n{\"tipo\": \"parola\"}"
	var d := Contratto.estrai_json(testo)
	assert_eq(d.get("tipo"), "parola")

func test_estrai_json_con_testo_attorno():
	var testo := "Certo! { \"tag\": [] } spero sia utile"
	var d := Contratto.estrai_json(testo)
	assert_true(d.has("tag"))

func test_estrai_json_irrecuperabile_ritorna_vuoto():
	assert_true(Contratto.estrai_json("non c'e' nessun json qui").is_empty())
	assert_true(Contratto.estrai_json("").is_empty())

func test_normalizza_coerce_intensita_float():
	var e := Contratto.normalizza({"tipo": "parola", "intensita": 2.0, "tag": ["vanto"]})
	assert_eq(typeof(e["intensita"]), TYPE_INT)
	assert_eq(e["intensita"], 2)

func test_normalizza_dio_invocato_in_minuscolo():
	# Un modello scrive spesso il nome proprio in maiuscolo: "Atena" -> "atena".
	var e := Contratto.normalizza({"tipo": "preghiera", "dio_invocato": "Atena", "tag": []})
	assert_eq(e["dio_invocato"], "atena")

func test_normalizza_dio_invocato_null_resta_null():
	var e := Contratto.normalizza({"tipo": "azione", "dio_invocato": null, "tag": []})
	assert_null(e["dio_invocato"])

func test_vocabolario_per_prompt_contiene_i_tag():
	var s := Contratto.vocabolario_per_prompt()
	assert_string_contains(s, "tracotanza")
	assert_string_contains(s, "xenia")
