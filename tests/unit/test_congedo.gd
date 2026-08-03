extends GutTest

## IL CONGEDO: una partita che finisce non deve chiudersi con un'etichetta.
##
## Prima, morire dava «— FINE: follia —»: una riga di verbale in fondo a un poema. Un
## gioco che per venti turni ti parla con la voce di Omero non puo' congedarti come un
## form che si chiude. L'ultima cosa che si legge e' quella che resta.
##
## Il congedo lo scrive Omero (una chiamata sola, e solo a partita finita). Ma il testo di
## ripiego NON e' un ripiego qualunque: e' cio' che si legge col motore simulato, nei test,
## e ogni volta che il modello fallisce. Quindi dev'essere gia' epico di suo.

const FUORI := "estraggo la pistola e sparo al ciclope"

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(4242)
	GameManager.stato.ammonizioni["soglia"] = 3

func _muori() -> Dictionary:
	await GameManager.esegui_turno(FUORI)
	await GameManager.esegui_turno(FUORI)
	return await GameManager.esegui_turno(FUORI)

func test_la_morte_porta_un_congedo():
	var esito := await _muori()
	assert_eq(esito["esito"], "morte")
	assert_false(String(esito.get("congedo", "")).strip_edges().is_empty(),
		"chi muore merita un commiato, non un'etichetta")

## Il congedo e' l'ultima cosa che il giocatore legge: se tradisse l'invariante lo farebbe
## nel momento di massima attenzione.
func test_il_congedo_non_nomina_un_dio():
	var esito := await _muori()
	var t := String(esito.get("congedo", "")).to_lower()
	for dio in PantheonManager.pantheon.tutti():
		assert_false(t.contains(dio.nome.to_lower()),
			"il congedo non puo' nominare %s" % dio.nome)

## E' la follia della GUERRA che lo distrugge, non il mare: dieci anni a Troia prima
## ancora del primo naufragio. Il commiato deve ricordare quello.
func test_il_congedo_ricorda_la_guerra():
	var esito := await _muori()
	var t := String(esito.get("congedo", "")).to_lower()
	assert_true(t.contains("troia") or t.contains("guerra"),
		"il commiato deve ricordare da dove viene questa rovina")

func test_un_turno_qualunque_non_ha_congedo():
	var esito := await GameManager.esegui_turno("Scendo a riva e cerco acqua dolce.")
	assert_eq(esito["esito"], "continua")
	assert_eq(String(esito.get("congedo", "")), "", "non ci si congeda a meta' viaggio")

## Il ripiego dev'esserci nei dati, non nel codice: e' testo, e un giorno si tradurra'.
func test_il_commiato_di_ripiego_vive_nei_dati():
	assert_true(Testi.ha("gioco/epitaffio_morte"), "manca la voce in data/testi/it.json")
	assert_gt(Testi.s("gioco/epitaffio_morte").length(), 120,
		"un commiato epico non sta in una riga")

## UNA CHIAVE MANCANTE NON E' UN TESTO. `Testi.s` ritorna il percorso stesso quando la voce
## non c'e' (perche' si veda subito cosa manca), e un finale senza commiato scritto avrebbe
## stampato in faccia al giocatore «gioco/epitaffio_ciurma_perduta». Serve chiedere PRIMA
## se la voce esiste, non indovinarlo dalla forma della stringa.
func test_sapere_se_una_voce_esiste():
	assert_true(Testi.ha("gioco/epitaffio_morte"))
	assert_false(Testi.ha("gioco/epitaffio_inventato"))
	assert_false(Testi.ha("sezione/che/non/esiste"))

func test_un_finale_senza_commiato_non_stampa_la_chiave():
	var senza := await GameManager._congedo("un_esito_senza_testo")
	assert_eq(senza, "", "meglio nessun congedo che il nome di una chiave")
