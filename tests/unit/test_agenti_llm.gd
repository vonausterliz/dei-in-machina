extends GutTest

## Dei-agenti e Narratore: parti deterministiche (prompt + parsing + invarianti),
## con chat_fn finta, senza rete.

class FakeChat:
	var risposte: Array = []
	var chiamate: int = 0
	func chat(_m: Array, _o: Dictionary) -> Dictionary:
		var i: int = min(chiamate, risposte.size() - 1)
		chiamate += 1
		return risposte[i]

func _ok(c: String) -> Dictionary:
	return {"ok": true, "content": c, "error": ""}

var _p: Pantheon

func before_each():
	_p = Pantheon.carica("res://data/pantheon.json")

# --- DioAgente ---

func test_prompt_dio_include_guardrail_e_voce():
	var ag := DioAgente.new()
	var sp := ag.system_prompt(_p.get_dio("poseidone"))
	assert_string_contains(sp, "non un assistente")   # guardrail
	assert_string_contains(sp, "Poseidone")
	assert_string_contains(sp, "castigo")             # un suo registro

func test_proposta_valida_parsata():
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"registro":"castigo","intensita":3,"dice":"Il mare non dimentica."}')]
	var p := await ag.proponi(_p.get_dio("poseidone"), {"envelope": {}}, fake.chat)
	assert_eq(p["registro"], "castigo")
	assert_eq(p["intensita"], 3)
	assert_eq(p["dio"], "poseidone")

func test_registro_non_ammesso_diventa_silenzio():
	# 'aiuto' non e' tra i registri di Poseidone: va rifiutato.
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"registro":"aiuto","intensita":2,"dice":"Ti aiuto."}')]
	var p := await ag.proponi(_p.get_dio("poseidone"), {"envelope": {}}, fake.chat)
	assert_eq(p["registro"], "silenzio")

func test_output_malformato_diventa_silenzio():
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok("non so cosa fare")]
	var p := await ag.proponi(_p.get_dio("atena"), {"envelope": {}}, fake.chat)
	assert_eq(p["registro"], "silenzio")

func test_intensita_clampata():
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"registro":"aiuto","intensita":9,"dice":"x"}')]
	var p := await ag.proponi(_p.get_dio("atena"), {"envelope": {}}, fake.chat)
	assert_eq(p["intensita"], 3)

# --- Narratore (invariante nessun nome di dio) ---

func _nomi() -> Array:
	var out: Array = []
	for d in _p.tutti():
		out.append(d.nome)
	return out

func test_narrazione_pulita_passa():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("Il mare si gonfio' senza ragione, e il vento giro' contro di te.")]
	var testo := await nar.narra({"sintesi": "x"}, fake.chat)
	assert_string_contains(testo, "mare")
	assert_false(nar.nomina_un_dio(testo))

func test_nome_di_dio_scatena_retry():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("Poseidone gonfio' le onde contro di te."),          # nomina: rifiutata
		_ok("Un dio del profondo gonfio' le onde contro di te."), # pulita
	]
	var testo := await nar.narra({"sintesi": "x"}, fake.chat)
	assert_false(nar.nomina_un_dio(testo))
	assert_eq(fake.chiamate, 2)

func test_redazione_ultima_difesa():
	# Se il modello insiste a nominare, il narratore redige il nome.
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("Atena ti guido' la mano.")]  # unica risposta, sempre con nome
	var testo := await nar.narra({"sintesi": "x"}, fake.chat)
	assert_false(nar.nomina_un_dio(testo), "il nome va redatto: %s" % testo)
	assert_string_contains(testo.to_lower(), "un dio")
