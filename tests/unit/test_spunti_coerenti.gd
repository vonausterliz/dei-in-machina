extends GutTest

## IL GIOCO NON PUO' RIFIUTARE CIO' CHE HA APPENA PROPOSTO.
##
## Successo sul campo: fra i tre spunti compariva «Sguaina il bronzo e rispondi
## all'affronto con il ferro che i Ciconi rispettano» — perfettamente omerica — e cliccarla
## dava «Quel gesto non appartiene a questo mondo». Il gioco offriva una mossa e poi la
## bocciava.
##
## Il vaglio di plausibilita' passa da un LLM, quindi sbaglia: e' inevitabile. Ma su un
## testo che ha scritto Omero non c'e' niente da vagliare — e' in-mondo per costruzione.
## Saltarlo toglie la contraddizione E una chiamata.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(909)

func test_il_gioco_ricorda_cosa_ha_proposto():
	var esito: Dictionary = await GameManager.esegui_turno("Sciolgo le vele.")
	assert_eq(GameManager.stato.spunti_proposti, _testi(esito.get("spunti", [])),
		"cio' che si mostra al giocatore va ricordato")

func test_uno_spunto_proposto_non_viene_mai_bocciato():
	GameManager.stato.spunti_proposti = ["Sguaina il bronzo e rispondi all'affronto."]
	assert_true(GameManager.gia_proposto("Sguaina il bronzo e rispondi all'affronto."))
	# Le differenze di spaziatura o di maiuscole non devono contare: il bottone incolla il
	# testo nel campo, e da li' puo' passare di tutto.
	assert_true(GameManager.gia_proposto("  sguaina il bronzo e rispondi all'affronto.  "))

func test_cio_che_non_e_stato_proposto_resta_da_vagliare():
	GameManager.stato.spunti_proposti = ["Piega ai remi."]
	assert_false(GameManager.gia_proposto("sparo ai lotofagi"))

## L'invariante vero: lo spunto proposto attraversa il turno senza essere dichiarato
## fuori-mondo, qualunque cosa ne pensi il vaglio.
func test_lo_spunto_proposto_attraversa_il_turno():
	GameManager.stato.spunti_proposti = ["Sguaina il bronzo contro i Ciconi."]
	var esito: Dictionary = await GameManager.esegui_turno("Sguaina il bronzo contro i Ciconi.")
	assert_true(esito["in_mondo"], "il gioco non boccia la propria proposta")
	assert_eq(String(esito["voce"]["envelope"]["plausibilita"]), "in_mondo")

## Ma un anacronismo vero resta un anacronismo, anche se qualcuno lo mette fra gli spunti:
## la salvaguardia deterministica non si scavalca.
func test_un_anacronismo_vero_non_passa_nemmeno_se_proposto():
	GameManager.stato.spunti_proposti = ["Sparo ai Ciconi col fucile."]
	var esito: Dictionary = await GameManager.esegui_turno("Sparo ai Ciconi col fucile.")
	assert_false(esito["in_mondo"], "i marcatori deterministici valgono sempre")

func _testi(spunti: Array) -> Array:
	var out: Array = []
	for s in spunti:
		out.append(String(s.get("testo", "")))
	return out

## Anche gli spunti della schermata iniziale (generati fuori da un turno) valgono.
func test_valgono_anche_gli_spunti_dell_apertura():
	GameManager.ricorda_spunti([{"testo": "Sciogli le vele verso occidente.", "rischio": false}])
	assert_true(GameManager.gia_proposto("Sciogli le vele verso occidente."))

## Trappola d'ordine: durante il turno la UI toglie subito i bottoni degli spunti. Se
## togliesse anche il ricordo, lo spunto appena cliccato tornerebbe rifiutabile — cioe' il
## difetto si ripresenterebbe proprio nel caso che deve risolvere.
func test_svuotare_i_bottoni_non_cancella_il_ricordo():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._mostra_spunti([{"testo": "Sguaina il bronzo.", "rischio": false}])
	ui._pulisci_spunti()
	assert_true(GameManager.gia_proposto("Sguaina il bronzo."),
		"i bottoni spariscono, l'impegno no")
