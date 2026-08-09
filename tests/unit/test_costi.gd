extends GutTest

## I PROFILI DI COSTO.
##
## Molte scelte del gioco non sono state prese perche' lo rendevano migliore, ma perche'
## una chiamata LLM in piu' costava troppo sul tier gratuito. Erano sparse fra costanti nel
## codice e voci di bilanciamento.json: chi gioca con un piano a pagamento subiva limiti che
## non lo riguardavano, e non aveva modo di accorgersene.

var _prima: Dictionary = {}

func before_each():
	# I test NON devono sporcare le preferenze vere dell'utente: si salva tutto e si rimette.
	_prima = {
		"attivo": Impostazioni.leggi(Costi.CHIAVE_ATTIVO, null),
		"utente": Impostazioni.leggi(Costi.CHIAVE_UTENTE, null),
	}
	Impostazioni.dimentica(Costi.CHIAVE_ATTIVO)
	Impostazioni.dimentica(Costi.CHIAVE_UTENTE)
	Costi.dimentica()

func after_each():
	for chiave in [[Costi.CHIAVE_ATTIVO, "attivo"], [Costi.CHIAVE_UTENTE, "utente"]]:
		if _prima[chiave[1]] == null:
			Impostazioni.dimentica(String(chiave[0]))
		else:
			Impostazioni.scrivi(String(chiave[0]), _prima[chiave[1]])

func test_i_due_profili_predefiniti_esistono():
	var id: Array = Costi.profili().map(func(p): return p["id"])
	assert_has(id, "frugale")
	assert_has(id, "libero")

func test_i_predefiniti_non_si_possono_modificare():
	for p in Costi.profili():
		if p["id"] in ["frugale", "libero"]:
			assert_true(p["predefinito"], "%s e' il riferimento della taratura" % p["id"])
	assert_false(Costi.imposta("frugale", "max_repliche", 99),
		"un profilo predefinito non si tocca")

## Senza scelte, si parte prudenti: e' il profilo con cui il gioco e' stato tarato.
func test_si_parte_dal_frugale():
	assert_eq(Costi.attivo(), "frugale")
	assert_eq(Costi.limite("max_repliche"), 2)
	assert_eq(Costi.limite("cronaca_ogni"), 4)
	assert_false(Costi.acceso("vaglia_sempre"))

func test_il_profilo_libero_alza_e_toglie():
	Costi.usa("libero")
	assert_eq(Costi.attivo(), "libero")
	assert_true(Costi.acceso("vaglia_sempre"), "i limiti di puro costo si tolgono")
	assert_true(Costi.acceso("spunti_separati"))
	assert_eq(Costi.limite("cronaca_ogni"), 1)
	# ALZATI, non tolti: la ragione di questi due non era solo il costo — oltre un certo
	# numero la Vista Olimpo diventa un coro e la chat della ciurma illeggibile.
	assert_between(Costi.limite("max_repliche"), 3, 5)
	assert_between(Costi.limite("compagni_per_turno"), 2, 3)

## Un profilo scelto e poi cancellato non deve lasciare il gioco senza limiti: ritrovarsi
## per sbaglio su quello caro e' peggio che ritrovarsi su quello prudente.
func test_un_profilo_sparito_torna_al_prudente():
	Impostazioni.scrivi(Costi.CHIAVE_ATTIVO, "utente:mai_esistito")
	assert_eq(Costi.attivo(), "frugale")

# --- profili dell'utente ---

func test_creare_un_profilo_parte_da_uno_esistente():
	var id := Costi.crea("Il mio", "libero")
	assert_ne(id, "")
	var p := Costi.get_profilo(id)
	assert_eq(String(p["nome"]), "Il mio")
	assert_false(p["predefinito"])
	assert_eq(int(p["valori"]["cronaca_ogni"]), 1, "eredita i valori del profilo di partenza")

func test_un_profilo_utente_si_modifica_e_vale():
	var id := Costi.crea("Il mio", "frugale")
	Costi.usa(id)
	assert_true(Costi.imposta(id, "max_repliche", 5))
	assert_eq(Costi.limite("max_repliche"), 5)

func test_cancellare_il_profilo_attivo_riporta_al_prudente():
	var id := Costi.crea("Usa e getta")
	Costi.usa(id)
	assert_true(Costi.cancella(id))
	assert_eq(Costi.attivo(), "frugale")

func test_un_nome_vuoto_non_crea_niente():
	assert_eq(Costi.crea("   "), "")

## Un profilo salvato prima che un limite esistesse non deve rispondere zero: eredita dal
## Frugale, cioe' dal comportamento con cui il gioco e' stato tarato.
func test_un_limite_ignoto_al_profilo_eredita_dal_frugale():
	var id := Costi.crea("Vecchio")
	Costi.usa(id)
	var elenco: Array = Impostazioni.leggi(Costi.CHIAVE_UTENTE, [])
	elenco[0]["valori"].erase("max_repliche")
	Impostazioni.scrivi(Costi.CHIAVE_UTENTE, elenco)
	assert_eq(Costi.limite("max_repliche"), 2, "non 0: si eredita il valore tarato")

## Ogni valore dei profili predefiniti dev'essere un limite DICHIARATO, e ogni limite
## dichiarato dev'esserci in entrambi. Senza, Settings mostrerebbe un pannello incompleto
## o un profilo avrebbe buchi — e i buchi qui si vedono solo a partita iniziata.
func test_i_profili_e_i_descrittori_combaciano():
	var dichiarati: Array = Costi.descrittori().keys()
	assert_gt(dichiarati.size(), 0)
	for id in ["frugale", "libero"]:
		var valori: Dictionary = Costi.get_profilo(id)["valori"]
		for k in dichiarati:
			assert_true(valori.has(k), "%s non dichiara il limite '%s'" % [id, k])
		for k in valori:
			assert_has(dichiarati, k, "%s ha un valore non dichiarato: '%s'" % [id, k])

func test_ogni_descrittore_ha_tipo_ed_etichetta():
	for k in Costi.descrittori():
		var d: Dictionary = Costi.descrittori()[k]
		assert_has(["intero", "booleano"], String(d.get("tipo", "")), "tipo di '%s'" % k)
		assert_false(String(d.get("etichetta", "")).is_empty(), "etichetta di '%s'" % k)

# --- I limiti devono avere EFFETTO, non solo esistere ---
#
# Un knob dichiarato e non collegato e' peggio di un knob assente: l'utente lo muove,
# non succede niente, e non c'e' modo di accorgersene.

func test_il_tetto_alle_repliche_segue_il_profilo():
	assert_eq(GameManager.max_repliche(), 2, "col Frugale resta quello tarato")
	Costi.usa("libero")
	assert_gt(GameManager.max_repliche(), 2, "col profilo libero gli dei si parlano di piu'")

func test_il_taccuino_tiene_piu_ricordi_col_profilo_libero():
	var t := Taccuino.new(StatoPartita.nuova(PantheonManager.pantheon, 1))
	assert_eq(t.ricordi_per_dio(), 5)
	Costi.usa("libero")
	assert_gt(t.ricordi_per_dio(), 5)

func test_la_cronaca_si_aggiorna_piu_spesso_col_profilo_libero():
	GameManager.nuova_partita(31)
	assert_eq(GameManager._cronaca_ogni(), 4)
	Costi.usa("libero")
	assert_eq(GameManager._cronaca_ogni(), 1, "memoria fresca a ogni turno")

## Il piu' visibile: col profilo libero commentano in due invece che uno.
func test_parlano_piu_compagni_col_profilo_libero():
	LLMManager.mock_mode = true
	Costi.usa("libero")
	GameManager.nuova_partita(88)
	await GameManager.esegui_turno("Scendo a riva e cerco acqua dolce.")
	var voci: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"].filter(
		func(m): return String(m["autore"]) != "Ulisse" and String(m["tipo"]) == "voce")
	assert_eq(voci.size(), 2, "due compagni commentano")
	assert_ne(voci[0]["autore"], voci[1]["autore"], "e non e' due volte lo stesso")

func test_col_frugale_ne_parla_uno_solo():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(88)
	await GameManager.esegui_turno("Scendo a riva e cerco acqua dolce.")
	var voci: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"].filter(
		func(m): return String(m["autore"]) != "Ulisse" and String(m["tipo"]) == "voce")
	assert_eq(voci.size(), 1)

## IL PROFILO DECIDE QUANTO SI SPENDE, NON SE IL GIOCO SI CONTRADDICE.
##
## Questo test asseriva i due flag — `vaglia_sempre` spento col Frugale, acceso col Libero —
## e restava verde mentre col Libero il gioco bocciava i propri appigli. Un test che
## sorveglia lo stato interno invece dell'invariante osservabile difende la decisione
## sbagliata: e' la trappola annotata in v2.43, ripresentata qui.
##
## L'invariante osservabile e' uno solo, e non dipende dal profilo: l'appiglio offerto
## attraversa il turno. (Il resto della promessa sta in test_spunti_coerenti.gd.)
func test_la_promessa_sugli_appigli_non_dipende_dal_profilo():
	LLMManager.mock_mode = true
	for profilo in ["frugale", "libero"]:
		Costi.usa(profilo)
		GameManager.nuova_partita(5)
		LLMManager.mock_vaglio_classe = "assurdo_diegetico"   # il vaglio boccia
		GameManager.ricorda_spunti([{"testo": "Scendo a riva.", "rischio": false}])
		assert_true(GameManager.gia_proposto("Scendo a riva."))
		var esito: Dictionary = await GameManager.esegui_turno("Scendo a riva.")
		LLMManager.mock_vaglio_classe = ""
		assert_true(esito["in_mondo"], "col profilo «%s» il gioco non si rimangia un appiglio" % profilo)
