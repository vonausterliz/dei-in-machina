extends GutTest

## Finto client: restituisce risposte predefinite in coda (l'ultima si ripete).
## Simula LLMClient.chat senza rete: Callable(messaggi, opzioni) -> {ok, content, error}.
class FakeChat:
	var risposte: Array = []
	var chiamate: int = 0
	var ultimi_messaggi: Array = []
	func chat(messaggi: Array, _opzioni: Dictionary) -> Dictionary:
		ultimi_messaggi = messaggi
		var i: int = min(chiamate, risposte.size() - 1)
		chiamate += 1
		return risposte[i]

func _ok(content: String) -> Dictionary:
	return {"ok": true, "content": content, "error": ""}

var _interprete: Interprete

func before_each():
	_interprete = Interprete.new(["atena", "zeus", "poseidone", "polifemo"])

# --- costruzione del prompt ---

func test_system_prompt_include_il_guardrail():
	# Invariante CLAUDE.md: il guardrail anti-assistente e' in OGNI agente.
	assert_string_contains(_interprete.system_prompt(), "non un assistente")

func test_system_prompt_include_tutto_il_vocabolario():
	var sp := _interprete.system_prompt()
	for tag in Contratto.TAG_VOCABOLARIO:
		assert_string_contains(sp, tag)

func test_system_prompt_non_ha_placeholder_residui():
	var sp := _interprete.system_prompt()
	assert_eq(sp.find("{{"), -1, "tutti i placeholder devono essere sostituiti")

func test_messaggi_hanno_system_e_user():
	var m := _interprete.costruisci_messaggi("grido il mio nome")
	assert_eq(m.size(), 2)
	assert_eq(m[0]["role"], "system")
	assert_eq(m[1]["role"], "user")
	assert_eq(m[1]["content"], "grido il mio nome")

# --- pipeline interpreta ---

func test_interpreta_risposta_pulita():
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"plausibilita":"in_mondo","tipo":"parola","tag":["vanto","tracotanza"],"dio_invocato":null,"bersaglio":"polifemo","tono":"sfida","intensita":2,"sintesi":"Ulisse si vanta"}')]
	var env := await _interprete.interpreta("Sono io, Odisseo!", fake.chat)
	assert_eq(env["plausibilita"], "in_mondo")
	assert_has(env["tag"], "vanto")
	assert_eq(fake.chiamate, 1, "una risposta valida non deve innescare retry")

func test_interpreta_risposta_sporca_recuperabile():
	# fence markdown + testo attorno: deve comunque estrarre e validare.
	var fake := FakeChat.new()
	fake.risposte = [_ok("Ecco:\n```json\n{\"plausibilita\":\"in_mondo\",\"tipo\":\"azione\",\"tag\":[],\"intensita\":1,\"sintesi\":\"x\"}\n```")]
	var t := await _interprete.interpreta_tracciato("guardo il mare", fake.chat)
	assert_true(t["valido"])
	assert_false(t["fallback_usato"])

func test_interpreta_retry_poi_successo():
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("non riesco a rispondere in JSON, scusa"),  # tentativo 1: irrecuperabile
		_ok('{"plausibilita":"in_mondo","tipo":"azione","tag":[],"intensita":1,"sintesi":"ok"}'),  # tentativo 2: valido
	]
	var t := await _interprete.interpreta_tracciato("mi guardo attorno", fake.chat)
	assert_true(t["valido"])
	assert_false(t["fallback_usato"])
	assert_eq(fake.chiamate, 2, "deve aver ritentato una volta")

func test_interpreta_fallback_quando_tutto_fallisce():
	var fake := FakeChat.new()
	fake.risposte = [_ok("blah"), _ok("ancora niente JSON")]
	var t := await _interprete.interpreta_tracciato("xyz", fake.chat)
	assert_false(t["valido"])
	assert_true(t["fallback_usato"])
	# Il fallback e' inerte: nessun tag, quindi nessun dio svegliato per errore.
	assert_eq(t["envelope"]["tag"], [])
	assert_true(Contratto.valida_envelope(t["envelope"])["ok"])

func test_interpreta_envelope_con_tag_invalido_scatena_retry():
	var fake := FakeChat.new()
	fake.risposte = [
		_ok('{"plausibilita":"in_mondo","tipo":"parola","tag":["inesistente"],"intensita":1,"sintesi":"x"}'),
		_ok('{"plausibilita":"in_mondo","tipo":"parola","tag":["astuzia"],"intensita":1,"sintesi":"x"}'),
	]
	var t := await _interprete.interpreta_tracciato("uso l'inganno", fake.chat)
	assert_true(t["valido"])
	assert_eq(fake.chiamate, 2)
	assert_has(t["envelope"]["tag"], "astuzia")

func test_interpreta_errore_client_va_in_fallback():
	var fake := FakeChat.new()
	fake.risposte = [{"ok": false, "content": "", "error": "connessione rifiutata"}]
	var t := await _interprete.interpreta_tracciato("qualcosa", fake.chat)
	assert_true(t["fallback_usato"])

# --- riconoscimento ibrido del dio (parafrasi) ---

func test_identifica_dio_da_parafrasi():
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"dio":"atena"}')]
	var id := await _interprete.identifica_dio("colei che nacque dalla testa del padre, aiutami", fake.chat)
	assert_eq(id, "atena")

func test_identifica_dio_nessuno():
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"dio":"nessuno"}')]
	var id := await _interprete.identifica_dio("riempio gli otri d'acqua", fake.chat)
	assert_eq(id, "")

func test_identifica_dio_id_inventato_rifiutato():
	# Vincolo: un id fuori dal pantheon non deve passare (niente dei inventati).
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"dio":"afrodite"}')]
	var id := await _interprete.identifica_dio("invoco la dea dell'amore", fake.chat)
	assert_eq(id, "", "un id non valido viene scartato")

func test_identifica_dio_errore_client():
	var fake := FakeChat.new()
	fake.risposte = [{"ok": false, "content": "", "error": "giu'"}]
	var id := await _interprete.identifica_dio("qualcosa", fake.chat)
	assert_eq(id, "")
