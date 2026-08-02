extends GutTest

## La Vista Olimpo come chat: gli dei "parlano" nei canali, e le coalizioni aprono un
## canale di gruppo. Deterministico col mock.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(333)
	GameManager.vai_a_tappa("ciclope")

func test_il_risveglio_e_la_proposta_finiscono_in_chat():
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var t := GameManager.agora.trascrizione()
	assert_string_contains(t, "# Olimpo")
	assert_string_contains(t, "si desta")
	assert_string_contains(t, "Poseidone", "chi reagisce deve comparire nella chat")

func test_la_coalizione_apre_un_canale_di_gruppo():
	GameManager.prob_coalizione = 1.0
	GameManager.prob_scavalcamento = 0.0
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	assert_eq(GameManager.stato.coalizioni.size(), 1)
	var c: Dictionary = GameManager.stato.coalizioni[0]
	assert_true(c.has("canale"), "la coalizione ha il suo canale")
	assert_string_contains(GameManager.agora.trascrizione(), "Blocco:")

func test_il_verdetto_chiude_la_discussione():
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	assert_string_contains(GameManager.agora.trascrizione(), "prevale")

func test_una_voce_ha_sempre_lo_stesso_colore():
	assert_eq(Agora.tinta("Atena"), Agora.tinta("Atena"))
