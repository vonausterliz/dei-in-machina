extends GutTest

## Fase 6-bis: coalizioni (blocco divino) e strategie (piano/pazienza). Col mock,
## nel Ciclope il vanto sveglia Poseidone e Polifemo (entrambi contro-ritorno, castigo).

const VANTO := "Sono io, Odisseo, che t'ho accecato!"
const DENTRO := "Osservo l'antro."

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(333)
	GameManager.vai_a_tappa("ciclope")  # qui Poseidone e Polifemo (contro-ritorno) fanno blocco
	GameManager.prob_scavalcamento = 0.0  # isola le coalizioni

# --- Coalizioni ---

func test_coalizione_si_forma_da_blocco_punitivo():
	GameManager.prob_coalizione = 1.0
	await GameManager.esegui_turno(VANTO)
	assert_eq(GameManager.stato.coalizioni.size(), 1)
	var membri: Array = GameManager.stato.coalizioni[0]["membri"]
	assert_has(membri, "poseidone")
	assert_has(membri, "polifemo")

func test_nessuna_coalizione_se_prob_zero():
	GameManager.prob_coalizione = 0.0
	await GameManager.esegui_turno(VANTO)
	assert_eq(GameManager.stato.coalizioni.size(), 0)

func test_coalizione_decade_e_si_scioglie():
	GameManager.prob_coalizione = 1.0
	await GameManager.esegui_turno(VANTO)        # forma (coesione 70)
	GameManager.prob_coalizione = 0.0            # niente nuove
	var c0: int = GameManager.stato.coalizioni[0]["coesione"]
	await GameManager.esegui_turno(DENTRO)       # decade
	assert_lt(GameManager.stato.coalizioni[0]["coesione"], c0)
	# 70 -> 55 -> 40 -> 25 -> 10 -> -5(<=0 scioglie): pochi turni e sparisce.
	for i in 5:
		if not GameManager.stato.coalizioni.is_empty():
			await GameManager.esegui_turno(DENTRO)
	assert_eq(GameManager.stato.coalizioni.size(), 0, "a coesione esaurita la coalizione si scioglie")

# --- Strategie (piano: la pazienza di Poseidone) ---

func test_poseidone_ha_un_piano_a_orizzonte_lungo():
	assert_true(GameManager.stato.registro_divino["poseidone"].has("piano"))
	assert_eq(GameManager.stato.registro_divino["poseidone"]["piano"]["orizzonte"], "lungo")

func test_piano_colpisce_piu_forte_quando_ulisse_e_debole():
	# Isolo il piano: niente coalizioni. Poseidone base intensita' 1 (mock).
	GameManager.prob_coalizione = 0.0
	# Ulisse debole -> Poseidone colpisce piu' forte (intensita' salita).
	GameManager.stato.ulisse["stat"]["animo"] = 20
	var esito := await GameManager.esegui_turno(VANTO)
	assert_eq(esito["voce"]["verdetto"]["attore"], "poseidone")
	assert_gte(int(esito["voce"]["verdetto"]["intensita"]), 2, "colpisce nel momento peggiore")

func test_piano_aspetta_quando_ulisse_e_saldo():
	GameManager.prob_coalizione = 0.0
	GameManager.stato.ulisse["stat"]["animo"] = 90  # saldo
	var esito := await GameManager.esegui_turno(VANTO)
	# Pazienza: intensita' resta bassa (1).
	assert_eq(int(esito["voce"]["verdetto"]["intensita"]), 1)
