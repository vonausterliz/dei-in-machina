extends GutTest

## OGIGIA NON TI LASCIA ANDARE DA SOLA.
##
## Prima, l'isola di Calipso aveva `turni_massimi: 8` come ogni altra tappa: dopo otto turni
## la nave riprendeva il mare da se'. Ma «restare per sempre» e' esattamente il pericolo di
## Ogigia — e con l'avanzamento automatico *non esisteva il modo di restare*. La sconfitta
## `prigionia_eterna`, dichiarata dal design, non poteva accadere.
##
## Ora l'isola non avanza da sola: si riparte solo scegliendo la rotta. Chi indugia oltre
## la soglia viene ammonito — tre volte, ricordandogli che la ragione lo sta lasciando — e
## poi resta li' per sempre. Stessa scala dell'empieta': avviso, avviso, fine.

const RESTA := "Mi siedo sulla riva e guardo il mare."
const PARTI := "Salpo verso Itaca."   # 'salp' -> tag 'rotta' nel mock

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(909)
	GameManager.vai_a_tappa("ogigia")

func _soglia() -> int:
	var ep := GameManager.episodi.get_episodio("ogigia")
	return ep.trattiene_dopo_turni

func test_ogigia_dichiara_che_trattiene():
	assert_gt(_soglia(), 0, "Ogigia deve trattenere: e' cio' che la rende Ogigia")
	var ep := GameManager.episodi.get_episodio("ogigia")
	assert_eq(ep.turni_massimi, 0, "non puo' avanzare da sola, o non si puo' restare")

## Le altre tappe non trattengono: la regola e' di Ogigia, non del gioco.
func test_le_altre_tappe_non_trattengono():
	for id in GameManager.episodi.ordine():
		if id == "ogigia":
			continue
		assert_eq(GameManager.episodi.get_episodio(id).trattiene_dopo_turni, 0,
			"solo Ogigia trattiene (%s)" % id)

## Entro la soglia si puo' indugiare in pace: guardare il mare non e' una colpa.
func test_entro_la_soglia_nessun_avviso():
	for i in _soglia():
		var esito := await GameManager.esegui_turno(RESTA)
		assert_eq(esito["esito"], "continua")
		assert_eq(String(esito["voce"].get("ammonizione", "")), "",
			"al turno %d non si e' ancora indugiato troppo" % (i + 1))

func test_oltre_la_soglia_arriva_l_ammonizione():
	for i in _soglia():
		await GameManager.esegui_turno(RESTA)
	var esito := await GameManager.esegui_turno(RESTA)
	assert_eq(esito["voce"]["ammonizione"], "prigionia", "l'isola comincia ad avvertire")
	assert_eq(esito["esito"], "continua", "il primo avviso non uccide")

## Tre avvisi, poi si resta per sempre. E' la stessa scala dell'empieta' reiterata,
## perche' e' lo stesso genere di rovina: si perde la ragione, e con quella il ritorno.
func test_dopo_tre_avvisi_si_resta_per_sempre():
	for i in _soglia():
		await GameManager.esegui_turno(RESTA)
	await GameManager.esegui_turno(RESTA)   # avviso 1
	await GameManager.esegui_turno(RESTA)   # avviso 2
	var esito := await GameManager.esegui_turno(RESTA)   # il terzo chiude
	assert_eq(esito["esito"], "prigionia_eterna")
	assert_eq(GameManager.stato.stato, "finita")
	assert_eq(GameManager.stato.esito, "prigionia_eterna")

func test_la_prigionia_ha_il_suo_congedo():
	for i in _soglia():
		await GameManager.esegui_turno(RESTA)
	await GameManager.esegui_turno(RESTA)
	await GameManager.esegui_turno(RESTA)
	var esito := await GameManager.esegui_turno(RESTA)
	var congedo := String(esito.get("congedo", "")).strip_edges()
	assert_false(congedo.is_empty(), "anche restare per sempre merita un commiato")
	for dio in PantheonManager.pantheon.tutti():
		assert_false(congedo.to_lower().contains(dio.nome.to_lower()),
			"il congedo non puo' nominare %s" % dio.nome)

## SI PUO' SEMPRE PARTIRE. E' il punto: la prigionia dev'essere una scelta, non una trappola.
func test_partire_scioglie_tutto():
	for i in _soglia() + 2:
		await GameManager.esegui_turno(RESTA)
	assert_gt(int(GameManager.stato.ammonizioni.get("prigionia", 0)), 0)
	var esito := await GameManager.esegui_turno(PARTI)
	assert_ne(esito["esito"], "prigionia_eterna", "chi salpa non resta")
	assert_true(esito.get("avanzato", false), "la rotta scelta apre la tappa successiva")

## Il commiato di ripiego vive nei dati, non nel codice.
func test_il_commiato_di_ripiego_vive_nei_dati():
	assert_true(Testi.ha("gioco/epitaffio_prigionia_eterna"), "manca in data/testi/it.json")
	assert_gt(Testi.s("gioco/epitaffio_prigionia_eterna").length(), 120,
		"un commiato epico non sta in una riga")

## Ogni classe di ammonizione deve avere il suo avviso nei dati. La console teneva una
## copia a mano di quei testi e, quando ne e' arrivata una nuova, e' rimasta muta senza
## che niente fallisse: e' il genere di buco che si vede solo giocando.
func test_ogni_ammonizione_ha_il_suo_avviso():
	for classe in ["richiamo", "smarrimento", "follia", "prigionia"]:
		assert_true(Testi.ha("avvisi/%s" % classe), "manca avvisi/%s" % classe)
