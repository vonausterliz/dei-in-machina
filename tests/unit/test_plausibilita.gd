extends GutTest

## IL FALSO ANACRONISMO — e perché è il guasto peggiore che questo gioco possa avere.
##
## Da un tracciato di partita vera (5 agosto 2026, gpt-4o-mini via OpenRouter), tre mosse
## respinte dall'Interprete. Nella colonna `tono` c'è la prova che il modello aveva capito
## benissimo cosa stava succedendo:
##
##   «torneremo a casa perché sono più forte degli dei dell'olimpo»
##       → plausibilita=anacronistico   tono=arrogante    tag=[]
##   «sono odisseo! il più forte guerriero acheo»
##       → plausibilita=anacronistico   tono=vanto        tag=[]
##   «distruggiamo tutta la città dei cicorni»
##       → plausibilita=assurdo_diegetico  tono=tracotanza  tag=[]
##
## Nessuna delle tre contiene niente di moderno. Due sono tracotanza pura — il motore del
## poema, ciò che desta Poseidone — e la terza è **canone**: il sacco di Ismaro, la tappa
## subito dopo Troia in `episodi.json`.
##
## E respingere non è gratis: `plausibilita != in_mondo` fa salire l'ammonizione, e la scala
## finisce in follia, cioè fine partita. Il gioco puniva come pazzia esattamente la cosa per
## cui esiste. Il commento in testa a `validazione.gd` lo diceva già — «qui il falso positivo
## uccide il gioco» — ma nessuna riga di codice lo pretendeva.
##
## Qui si pretende. Due regole, entrambe deterministiche:
##
##   1. «anacronistico» ha una definizione OGGETTIVA (cose di un'altra epoca) e un
##      riconoscitore deterministico. Senza marcatore, il verdetto è falso e non si applica:
##      non serve chiedere a nessuno.
##   2. Le altre classi fuori-mondo sono giudizi, e un giudizio che può chiudere la partita
##      vuole DUE pareri concordi. L'Interprete da solo non basta più.

const HYBRIS := [
	"torneremo a casa perché sono più forte degli dei dell'olimpo",
	"sono odisseo! il più forte guerriero acheo",
	"distruggiamo tutta la città dei cicorni",
]

## Come lo restituiva l'Interprete vero: classe sbagliata, tono giusto, e i tag gia' buttati.
func _respinto(classe: String, tono: String) -> Dictionary:
	return {"plausibilita": classe, "tipo": "azione", "tag": ["vanto", "tracotanza"],
		"dio_invocato": null, "bersaglio": null, "tono": tono, "intensita": 2}

func before_each():
	LLMManager.mock_mode = true       # il secondo parere tace: tutto resta deterministico
	GameManager.nuova_partita(2024)

func _vaglio() -> Validazione:
	return Validazione.new(GameManager.stato)

# --- regola 1: «anacronistico» senza marcatore è un verdetto falso ---

func test_anacronistico_senza_niente_di_moderno_non_si_accetta():
	for frase in HYBRIS:
		var e := _respinto("anacronistico", "vanto")
		await _vaglio().vaglia(e, frase)
		assert_eq(e["plausibilita"], "in_mondo",
			"respinta come anacronistica una frase senza niente di moderno: «%s»" % frase)

## …e la guardia non deve diventare un colabrodo: un anacronismo VERO resta respinto, anche
## quando l'Interprete l'aveva chiamato col nome giusto.
func test_un_anacronismo_vero_resta_respinto():
	var casi := [
		"sparo ai lotofagi",
		"prendo il telefono e chiamo penelope",
		"ordino di sterminare i ciconi con il mitra",
	]
	for frase in casi:
		var e := _respinto("anacronistico", "freddo")
		await _vaglio().vaglia(e, frase)
		assert_eq(e["plausibilita"], "anacronistico", "doveva restare respinta: «%s»" % frase)
		assert_eq(e["tag"], [], "respinta per davvero: i tag vanno via")

# --- regola 2: un giudizio che chiude la partita vuole due pareri ---

func test_assurdo_diegetico_dal_solo_interprete_non_basta():
	var e := _respinto("assurdo_diegetico", "tracotanza")
	await _vaglio().vaglia(e, "distruggiamo tutta la città dei cicorni")
	assert_eq(e["plausibilita"], "in_mondo",
		"l'Interprete da solo ha chiuso la strada al sacco di Ismaro, che è canone")

# --- e il motivo per cui tutto questo conta ---

## I TAG SOPRAVVIVONO A UN VERDETTO RIBALTATO. Sono `vanto` e `tracotanza`: i tag che
## destano Poseidone. Se il ribaltamento restituisse un envelope svuotato, la mossa sarebbe
## formalmente accettata e non sveglierebbe piu' nessuno — il guasto sopravvivrebbe alla
## correzione, in silenzio.
func test_i_tag_della_tracotanza_sopravvivono_al_ribaltamento():
	var e := _respinto("anacronistico", "arrogante")
	await _vaglio().vaglia(e, "sono odisseo! il più forte guerriero acheo")
	assert_eq(e["plausibilita"], "in_mondo")
	assert_true(e["tag"].has("tracotanza"),
		"la mossa è tornata valida ma senza i tag: non sveglierebbe nessuno")

## E la conseguenza vera, guardata dalla scala delle ammonizioni: vantarsi non è un errore
## da correggere. Tre vanterie di fila non devono avvicinare di un passo la follia.
func test_vantarsi_non_costa_ammonizioni():
	for frase in HYBRIS:
		var e := _respinto("anacronistico", "vanto")
		var v := _vaglio()
		await v.vaglia(e, frase)
		var esito: Dictionary = v.valida(e, frase)
		assert_true(esito["in_mondo"], "«%s» respinta" % frase)
		assert_eq(esito["classe"], "", "una vanteria ha preso un'ammonizione: «%s»" % frase)
	assert_eq(int(GameManager.stato.ammonizioni.get("contatore", 0)), 0,
		"tre vanterie hanno mosso il contatore verso la follia")
