extends GutTest

## Politica divina: scavalcamento (un dio bocciato agisce di nascosto) e resa dei conti
## (Zeus scopre, cova ira, il conto rimbalza su Ulisse). Deterministico col mock.

const CONFLITTO := "Mi vanto della mia astuzia davanti a tutti"  # Atena(aiuto) vs Poseidone(castigo)
const DENTRO := "Riempio gli otri d'acqua alla sorgente."

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(777)
	# La politica divina (scavalcamenti, resa dei conti) presuppone Poseidone in campo, e
	# lui entra in campo con l'accecamento del figlio: qui si parte da dopo.
	GameManager.stato.eventi_accaduti.append("maledizione_di_polifemo")

func test_scavalcamento_forzato_crea_pendente_e_delta_nascosto():
	GameManager.prob_scavalcamento = 1.0
	var esito := await GameManager.esegui_turno(CONFLITTO)
	# Poseidone (castigo) ha perso il verdetto (vince Atena): scavalca.
	assert_false(esito["voce"]["scavalcamento"].is_empty())
	assert_eq(esito["voce"]["scavalcamento"]["colpevole"], "poseidone")
	assert_eq(GameManager.stato.scavalcamenti_pendenti.size(), 1)
	assert_has(esito["fsm_path"], "SCAVALCAMENTO")

func test_nessuno_scavalcamento_se_prob_zero():
	GameManager.prob_scavalcamento = 0.0
	var esito := await GameManager.esegui_turno(CONFLITTO)
	assert_true(esito["voce"]["scavalcamento"].is_empty())
	assert_eq(GameManager.stato.scavalcamenti_pendenti.size(), 0)

func test_resa_dei_conti_scopre_e_cova_ira():
	GameManager.prob_scavalcamento = 1.0
	await GameManager.esegui_turno(CONFLITTO)          # crea il pendente (sospetto 0)
	GameManager.prob_scavalcamento = 0.0               # niente nuovi scavalcamenti
	var ira0: int = GameManager.stato.relazioni["zeus_verso"]["poseidone"]

	# sospetto sale di 20/turno (soglia 60): scoperto al terzo turno successivo.
	await GameManager.esegui_turno(DENTRO)             # sospetto 20
	await GameManager.esegui_turno(DENTRO)             # 40
	assert_eq(GameManager.stato.relazioni["zeus_verso"]["poseidone"], ira0, "non ancora scoperto")
	await GameManager.esegui_turno(DENTRO)             # 60 -> scoperto

	assert_gt(GameManager.stato.relazioni["zeus_verso"]["poseidone"], ira0, "Zeus cova ira verso il colpevole")
	assert_true(GameManager.stato.scavalcamenti_pendenti[0]["rilevato"])

func test_sospetto_sale_ogni_turno():
	GameManager.prob_scavalcamento = 1.0
	await GameManager.esegui_turno(CONFLITTO)
	GameManager.prob_scavalcamento = 0.0
	await GameManager.esegui_turno(DENTRO)
	assert_eq(GameManager.stato.scavalcamenti_pendenti[0]["sospetto_zeus"], 20)
