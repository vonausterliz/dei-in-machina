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

# --- Contesto di mondo condiviso (in OGNI agente, nessun placeholder residuo) ---

func test_mondo_in_tutti_gli_agenti():
	var prompts := [
		DioAgente.new().system_prompt(_p.get_dio("atena")),
		Narratore.new(_nomi()).system_prompt(),
		Arbitro.new(_p).system_prompt(),
		Suggeritore.new().system_prompt(),
		Interprete.new([], _p).system_prompt(),
	]
	for sp in prompts:
		assert_string_contains(sp, "età del bronzo", "il blocco mondo dev'essere presente")
		assert_eq(sp.find("{{"), -1, "nessun placeholder residuo")

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

func test_narratore_include_la_scena_nel_messaggio():
	# La scena (grounding) deve arrivare a Omero, per non far derivare la narrazione.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({"sintesi": "guardo il mare", "scena": "Antro del ciclope, chiuso da un masso."})
	assert_string_contains(m[1]["content"], "Antro del ciclope")

func test_narratore_include_storia_e_orientamento():
	# Continuita' del discorso + orientamento discreto: storia, ultima voce, luogo/progresso.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({
		"sintesi": "prego", "storia": ["accecato il ciclope", "fuggito dall'antro"],
		"ultima_narrazione": "Il mare si gonfiò contro di te.",
		"luogo": "L'isola di Eolo", "progresso": "mezzo", "morale": "duro",
	})
	var testo: String = m[1]["content"]
	assert_string_contains(testo, "accecato il ciclope")   # storia
	assert_string_contains(testo, "Il mare si gonfiò")     # continuita' immediata
	assert_string_contains(testo, "L'isola di Eolo")       # orientamento (luogo)

func test_narratore_usa_azione_grezza():
	# Omero deve ricevere le parole esatte di Ulisse, per rispondere proprio a quelle.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({"azione": "chiedo udienza al re", "sintesi": "richiesta"})
	assert_string_contains(m[1]["content"], "chiedo udienza al re")

func test_narratore_passaggio_tra_tappe():
	# Il passaggio genera un messaggio dedicato (traversata), non la narrazione normale.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({"passaggio": {"da": "Ismaro", "a": "la terra dei Lotofagi"}})
	assert_string_contains(m[1]["content"], "PASSAGGIO")
	assert_string_contains(m[1]["content"], "Ismaro")
	assert_string_contains(m[1]["content"], "Lotofagi")

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

# --- Suggeritore (spunti d'azione player-facing) ---

func test_prompt_suggeritore_include_guardrail():
	var s := Suggeritore.new()
	assert_string_contains(s.system_prompt(), "non un assistente")

func test_suggeritore_parsa_tre_spunti():
	var s := Suggeritore.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"spunti":[{"testo":"Piega ai remi","rischio":false},{"testo":"Prega chi veglia sugli astuti","rischio":false},{"testo":"Sfida il mare","rischio":true}]}')]
	var sp := await s.suggerisci({"episodio": "il mare"}, fake.chat)
	assert_eq(sp.size(), 3)
	assert_eq(sp[0]["testo"], "Piega ai remi")
	assert_true(sp[2]["rischio"], "il terzo e' marcato rischioso")

func test_suggeritore_taglia_a_tre():
	var s := Suggeritore.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"spunti":[{"testo":"a"},{"testo":"b"},{"testo":"c"},{"testo":"d"}]}')]
	var sp := await s.suggerisci({}, fake.chat)
	assert_eq(sp.size(), 3, "al massimo 3 spunti")

func test_suggeritore_malformato_vuoto():
	var s := Suggeritore.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok("non so proprio")]
	var sp := await s.suggerisci({}, fake.chat)
	assert_eq(sp, [], "output inservibile -> vuoto (il manager mette i generici)")

# --- Arbitro (Zeus) ---

func _proposte_conflitto() -> Array:
	return [
		{"dio": "atena", "registro": "aiuto", "intensita": 2, "dice": "Lo difendo."},
		{"dio": "poseidone", "registro": "castigo", "intensita": 3, "dice": "Che il mare lo prenda."},
	]

func test_arbitro_verdetto_valido():
	var arb := Arbitro.new(_p)
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"attore":"poseidone","registro":"castigo","intensita":2,"dice":"Il mare avra il suo pegno, ma non la vita."}')]
	var v := await arb.decidi(_proposte_conflitto(), fake.chat)
	assert_eq(v["attore"], "poseidone")
	assert_eq(v["registro"], "castigo")
	assert_eq(v["intensita"], 2, "Zeus puo' ridurre l'intensita'")

func test_arbitro_attore_non_in_campo_va_in_fallback():
	# Zeus nomina un dio che non era in campo: verdetto rifiutato -> fallback (piu' intensa).
	var arb := Arbitro.new(_p)
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"attore":"circe","registro":"trappola","intensita":3,"dice":"x"}')]
	var v := await arb.decidi(_proposte_conflitto(), fake.chat)
	assert_eq(v["attore"], "poseidone", "fallback: la proposta piu' intensa")

func test_arbitro_malformato_va_in_fallback():
	var arb := Arbitro.new(_p)
	var fake := FakeChat.new()
	fake.risposte = [_ok("Decido io e basta.")]
	var v := await arb.decidi(_proposte_conflitto(), fake.chat)
	assert_eq(v["attore"], "poseidone")
	assert_eq(v["registro"], "castigo")
