extends GutTest

## IL TETTO ALL'USCITA, e i due modi in cui poteva non esserci.
##
## `max_tokens` era supportato dal client, passato da `LLMManager`, e impostato da NESSUN
## agente: in un tracciato di partita vera compare solo nella «prova del modello». Il
## secondo modo e' piu' insidioso del primo — un tetto che c'e' nella tabella ma non arriva
## nel corpo HTTP e' indistinguibile, da fuori, da un tetto che non c'e'. Per questo qui si
## guarda il CORPO che partirebbe, non la tabella.

var _c: LLMClient

func before_each():
	Tetti.ricarica()
	_c = LLMClient.new()
	autofree(_c)
	_c.configura({"base_url": "http://localhost:1", "model": "prova"}, "")

func _corpo(agente: String, opzioni: Dictionary = {}) -> Dictionary:
	_c.agente = agente
	return _c.corpo_richiesta([{"role": "user", "content": "x"}], opzioni)

func test_ogni_agente_del_turno_parte_con_un_tetto():
	for a in ["Omero", "Cronista", "Interprete", "Suggeritore", "Vaglio", "Ricognitore"]:
		var corpo := _corpo(a)
		assert_true(corpo.has("max_tokens"), "«%s» parte senza tetto all'uscita" % a)
		assert_gt(int(corpo["max_tokens"]), 0, "tetto non positivo per «%s»" % a)

## Chi non e' in tabella — gli dei, che si annunciano col proprio nome — non resta scoperto.
func test_chi_non_e_in_tabella_prende_il_predefinito():
	for a in ["Atena", "Zeus", "Poseidone", "Arbitro"]:
		assert_true(_corpo(a).has("max_tokens"), "«%s» resta senza tetto" % a)

func test_i_compagni_si_riconoscono_dal_suffisso():
	assert_eq(int(_corpo("Euriloco (ciurma)")["max_tokens"]),
		Tetti.per_agente("Euriloco (ciurma)"))
	assert_gt(int(_corpo("Euriloco (ciurma)")["max_tokens"]), 0)

## IL PAVIMENTO. Il Vaglio produce 12 token: tre volte dodici sono trentasei, un tetto
## matematicamente corretto e praticamente letale — un modello che ragiona spende tutto il
## budget nel ragionamento e torna `content: null` con `finish_reason: length`. E' successo
## davvero in v2.38, con `max_tokens: 1` alla prova del modello.
func test_nessun_tetto_e_troppo_stretto_per_un_modello_che_ragiona():
	for a in ["Vaglio", "Ricognitore", "Interprete", "Euriloco (ciurma)", "Atena"]:
		assert_gte(int(_corpo(a)["max_tokens"]), 256,
			"«%s» ha un tetto sotto il pavimento: un modello che ragiona tornerebbe vuoto" % a)

## Omero e' il 28% del tempo di un turno e il piu' lungo di tutti: il suo tetto dev'essere
## il piu' alto, o sarebbe lui il primo a essere tagliato a meta'.
func test_omero_ha_il_tetto_piu_alto():
	var suo := int(_corpo("Omero")["max_tokens"])
	for a in ["Cronista", "Interprete", "Suggeritore", "Vaglio", "Atena"]:
		assert_gt(suo, int(_corpo(a)["max_tokens"]), "Omero non batte «%s»" % a)

## Chi passa un tetto esplicito comanda: e' la «prova del modello», che ne vuole uno minimo.
func test_il_tetto_esplicito_vince_su_quello_dell_agente():
	assert_eq(int(_corpo("Omero", {"max_tokens": 64})["max_tokens"]), 64,
		"il tetto chiesto da chi chiama e' stato scavalcato da quello dell'agente")

## E IL PARACADUTE: `attivo: false` riporta esattamente al comportamento di prima, cioe'
## nessun tetto in nessun corpo. Serve se un modello nuovo torna vuoto per `length`, e un
## paracadute che non si e' mai aperto non e' un paracadute.
func test_spegnendo_la_tabella_non_parte_nessun_tetto():
	Tetti.per_prova({"attivo": false, "predefinito": 512, "agenti": {"Omero": 1600}})
	for a in ["Omero", "Vaglio", "Atena", "Euriloco (ciurma)"]:
		assert_false(_corpo(a).has("max_tokens"),
			"tabella spenta e «%s» parte lo stesso col tetto" % a)

## CHI NON SI ANNUNCIA NON PRENDE TETTI. `"?"` e' il valore iniziale di `LLMClient.agente`:
## una chiamata che non ha detto chi e'. Dandole il `predefinito` finivo per tagliare
## richieste di cui non so niente — e l'ha trovato `test_llm_client.gd`, che pretendeva che
## nel corpo non comparisse nulla che nessuno avesse chiesto. Aveva ragione lui.
func test_chi_non_si_annuncia_non_prende_tetti():
	for ignoto in ["", "?"]:
		assert_eq(Tetti.per_agente(ignoto), 0, "tetto messo a un chiamante ignoto «%s»" % ignoto)
	assert_false(_corpo("?").has("max_tokens"),
		"«max_tokens» spedito da una chiamata che non si è annunciata")

func after_each():
	Tetti.ricarica()   # la tabella dettata non deve sopravvivere al test che l'ha dettata
