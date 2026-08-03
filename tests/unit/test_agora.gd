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

## Il verdetto chiude la discussione, ma con delle PAROLE: «prevale X: castigo» era un
## verbale. Senza contesa basta una riga di servizio; con la contesa parla Zeus.
func test_il_verdetto_chiude_la_discussione():
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var t := GameManager.agora.trascrizione()
	assert_false(t.contains("prevale "), "niente referti nella chat")
	assert_string_contains(t, "volontà", "la chiusura si legge come una frase")

func test_una_voce_ha_sempre_lo_stesso_colore():
	assert_eq(Agora.tinta("Atena"), Agora.tinta("Atena"))

## I due sguardi non si mescolano: l'Olimpo e' cio' che dicono gli dei, la ciurma e'
## un'altra conversazione. Vederli insieme rompe l'illusione (e confonde e basta).
func test_la_trascrizione_olimpo_esclude_la_ciurma():
	GameManager.agora.scrivi(Agora.CANALE_CIURMA, "Euriloco", "Ne abbiamo perduti abbastanza.", 1)
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var t := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	assert_string_contains(t, "Poseidone", "le voci degli dei restano")
	assert_false(t.contains("# Ciurma"), "la ciurma non appartiene alla vista Olimpo")
	assert_false(t.contains("Euriloco"), "nessuna voce di ciurma nell'Olimpo")

func test_la_trascrizione_ciurma_esclude_gli_dei():
	GameManager.agora.scrivi(Agora.CANALE_CIURMA, "Euriloco", "Ne abbiamo perduti abbastanza.", 1)
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var t := GameManager.agora.trascrizione(Agora.VISTA_CIURMA)
	assert_string_contains(t, "Euriloco")
	assert_false(t.contains("# Olimpo"), "gli dei non si sentono dal ponte della nave")

## Le coalizioni sono discorsi fra dei: seguono l'Olimpo, non la ciurma.
func test_il_canale_di_gruppo_appartiene_all_olimpo():
	GameManager.prob_coalizione = 1.0
	GameManager.prob_scavalcamento = 0.0
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	assert_string_contains(GameManager.agora.trascrizione(Agora.VISTA_OLIMPO), "Blocco:")
	assert_false(GameManager.agora.trascrizione(Agora.VISTA_CIURMA).contains("Blocco:"))
