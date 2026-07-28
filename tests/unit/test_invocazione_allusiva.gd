extends GutTest

## Risoluzione di riferimenti (diretti e ALLUSIVI) a un dio nel testo libero.

var _p: Pantheon

func before_each():
	_p = Pantheon.carica("res://data/pantheon.json")

func test_nome_diretto():
	assert_eq(_p.risolvi_invocato("O grande Zeus, ascoltami"), "zeus")
	assert_eq(_p.risolvi_invocato("Atena, guida la mia mano"), "atena")

func test_epiteto_allusivo():
	assert_eq(_p.risolvi_invocato("Invoco il capo dell'olimpo"), "zeus")
	assert_eq(_p.risolvi_invocato("prego il signore dei mari di placarsi"), "poseidone")

func test_maiuscole_e_accenti_ignorati():
	assert_eq(_p.risolvi_invocato("IL CAPO DELL'OLIMPO"), "zeus")
	# 'perche' con accento non deve rompere il confronto
	assert_eq(_p.risolvi_invocato("Perché, o pallade, mi abbandoni?"), "atena")

func test_longest_match_vince():
	# "figlia di zeus" (atena) deve battere "zeus" (zeus): epiteto piu' specifico.
	assert_eq(_p.risolvi_invocato("supplico la figlia di zeus"), "atena")

func test_nessun_riferimento():
	assert_eq(_p.risolvi_invocato("Riempio gli otri d'acqua"), "")
	assert_eq(_p.risolvi_invocato(""), "")

func test_menzione_di_passaggio_risolve_comunque_il_testo():
	# risolvi_invocato guarda solo il testo; il GATING sull'intento e' in GameManager.
	assert_eq(_p.risolvi_invocato("racconto la furia del signore dei mari"), "poseidone")
