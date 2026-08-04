extends GutTest

## I PROVIDER, E TRE DIFETTI CHE NON FACEVANO RUMORE.
##
## 1. «Aggiorna elenco» interrogava il MOTORE ACCESO invece del PROFILO SELEZIONATO.
##    Con Ollama in esecuzione e OpenRouter scelto nel menu, il gioco chiedeva la lista a
##    Ollama e la mostrava come se fosse di OpenRouter. Non un errore: la risposta di un
##    altro. Il bottone «Prova il modello», accanto, faceva la cosa giusta — due strade
##    diverse per la stessa domanda, e solo una corretta.
##
## 2. Il modello scritto nel profilo di OpenRouter NON ESISTEVA. L'avevo dedotto dal fatto
##    che OpenRouter ha modelli col suffisso «:free», senza verificarlo sul catalogo vero:
##    404 a ogni chiamata. I test controllavano che la barra non venisse tagliata, mai che
##    il nome esistesse. Offline non si puo' interrogare il provider, ma si puo' pretendere
##    che il predefinito sia uno dei modelli CURATI — e quelli li verifica
##    tools/verifica_modelli, che il catalogo vero ce l'ha davanti.
##
## 3. Scegliere un modello a motore ancora spento lo scriveva nel profilo di Ollama: il
##    menu si risincronizzava dal profilo vero, rimasto invariato, e la scelta tornava
##    indietro da sola sotto gli occhi di chi l'aveva appena fatta.

const NOMI_ATTESI := ["Ollama locale", "Mistral", "Google", "OpenAI", "Anthropic", "OpenRouter"]

var _idx_prima := 0
var _modelli_prima: Array = []

func before_each():
	LLMManager.mock_mode = true
	LLMManager.usa_gateway = false
	_idx_prima = LLMManager.profilo_idx
	_modelli_prima = []
	for p in LLMManager.profili:
		_modelli_prima.append(String(p.get("model", "")))

func after_each():
	for i in LLMManager.profili.size():
		LLMManager.profili[i]["model"] = _modelli_prima[i]
	LLMManager.profilo_idx = _idx_prima
	LLMManager.usa_gateway = false

# --- L'elenco dei provider ---

func test_ci_sono_i_sei_provider_richiesti():
	var nomi: Array = LLMManager.nomi_profili()
	for atteso in NOMI_ATTESI:
		assert_has(nomi, atteso, "manca il provider «%s»" % atteso)

## Ollama non e' piu' un motore a parte: e' un provider come gli altri, con la differenza
## che gira in casa e non vuole chiavi. Tenerlo fuori dall'elenco significava non avere
## nessun posto in cui scegliere quale dei modelli installati usare.
func test_ollama_e_un_provider_locale_senza_chiave():
	var i := LLMManager.indice_profilo("Ollama locale")
	assert_gte(i, 0)
	var p: Dictionary = LLMManager.profili[i]
	assert_true(bool(p.get("locale", false)), "gira in casa")
	assert_eq(String(p.get("api_key_env", "")), "", "un server locale non vuole chiavi")
	LLMManager.imposta_profilo(i)
	assert_true(LLMManager.chiave_presente(), "senza chiave dichiarata si puo' sempre partire")

func test_il_gateway_resta_fuori_dall_elenco():
	assert_eq(LLMManager.indice_profilo("Gateway (free tier)"), -1,
		"il gateway e' la strada, non una destinazione")
	assert_true(LLMManager.gateway_disponibile())

# --- I modelli curati ---

## L'invariante che avrebbe fermato il difetto di OpenRouter prima che arrivasse a schermo.
##
## Legge i FILE, non i profili in memoria: quelli li modificano gli altri test (e il gioco),
## e un'invariante sui dati va verificata sui dati. Costa una lettura da disco e vale la
## differenza fra «questo file e' scritto bene» e «nessuno l'ha ancora sporcato».
func test_ogni_provider_propone_modelli_e_il_predefinito_e_fra_quelli():
	for p in _profili_da_file():
		var nome := String(p.get("nome", "?"))
		var noti: Array = Array(p.get("modelli_noti", []))
		assert_false(noti.is_empty(), "%s non propone nessun modello" % nome)
		assert_has(noti, String(p.get("model", "")),
			"il predefinito di %s non e' fra i modelli curati" % nome)

## I nomi curati devono avere la forma che il provider usa davvero: su OpenRouter la barra
## c'e' sempre, altrove non deve esserci (o verrebbe scambiata per l'instradamento).
func test_la_forma_dei_nomi_segue_il_provider():
	for p in _profili_da_file():
		var pieno := bool(p.get("nome_pieno", false))
		for m in Array(p.get("modelli_noti", [])):
			if pieno:
				assert_true(String(m).contains("/"),
					"su %s i nomi sono «autore/modello»: %s" % [p["nome"], m])
			else:
				assert_false(String(m).contains("/"),
					"su %s la barra sarebbe l'instradamento del Gateway: %s" % [p["nome"], m])

# --- Anthropic: l'unico che non parla del tutto la lingua di OpenAI ---

## Il layer di compatibilita' di Anthropic accetta il Bearer su /chat/completions, ma
## /models pretende «x-api-key» e rifiuta il Bearer. Invece di un ramo per Anthropic nel
## client, il profilo dichiara le intestazioni extra: resta un dato, non diventa codice.
func test_anthropic_dichiara_le_intestazioni_che_gli_servono():
	var i := LLMManager.indice_profilo("Anthropic")
	assert_gte(i, 0)
	var extra: Dictionary = LLMManager.profili[i].get("intestazioni", {})
	assert_true(extra.has("x-api-key"), "senza questa /models risponde 401")
	assert_true(extra.has("anthropic-version"), "l'API la pretende su ogni richiesta")
	assert_eq(String(extra["x-api-key"]), LLMManager.SEGNAPOSTO_CHIAVE,
		"la chiave non sta nei dati: c'e' un segnaposto che il client sostituisce")

func test_le_intestazioni_del_profilo_arrivano_al_client():
	var c := LLMClient.new()
	add_child_autofree(c)
	c.configura({"base_url": "https://esempio", "model": "m",
		"intestazioni": {"x-api-key": LLMManager.SEGNAPOSTO_CHIAVE, "anthropic-version": "2023-06-01"}},
		"chiave-finta")
	var h: Array = Array(c.intestazioni())
	assert_has(h, "x-api-key: chiave-finta", "il segnaposto va sostituito con la chiave vera")
	assert_has(h, "anthropic-version: 2023-06-01")

func test_senza_intestazioni_dichiarate_resta_il_solo_bearer():
	var c := LLMClient.new()
	add_child_autofree(c)
	c.configura({"base_url": "https://esempio", "model": "m"}, "k")
	var h: Array = Array(c.intestazioni())
	assert_has(h, "Authorization: Bearer k")
	for riga in h:
		assert_false(String(riga).begins_with("x-api-key"),
			"nessun provider deve ricevere intestazioni che non ha chiesto")

# --- «Aggiorna elenco»: il profilo scelto, non il motore acceso ---

## Il difetto n.1, reso visibile. Si punta un profilo a un indirizzo che rifiuta subito la
## connessione e si guarda DOVE e' andata la richiesta: se torna l'indirizzo del profilo
## selezionato, il bottone chiede a chi deve.
func test_l_elenco_si_chiede_al_profilo_selezionato_non_al_motore_acceso():
	var falso := {
		"nome": "Finto", "provider": "finto", "model": "m",
		"base_url": "http://127.0.0.1:9", "api_key_env": "", "timeout_sec": 3,
	}
	LLMManager.profili.append(falso)
	LLMManager.imposta_profilo(LLMManager.profili.size() - 1)
	var r: Dictionary = await LLMManager.elenca_modelli_del_profilo()
	LLMManager.profili.pop_back()
	LLMManager.profilo_idx = _idx_prima
	assert_eq(String(r.get("dove", "")), "http://127.0.0.1:9",
		"ha interrogato il profilo selezionato")
	assert_false(bool(r.get("ok", true)), "quell'indirizzo non risponde: deve dirlo")

## E si ferma li'. «Prova il modello» chiede l'elenco E genera una parola, e il suo esito
## lo dice ({genera, elencato, ms}); «Aggiorna elenco» risponde solo alla prima domanda, e
## il suo esito non ha nulla da dire sulla seconda. Con un provider a pagamento aggiornare
## un menu non deve costare un token.
func test_elencare_e_una_domanda_sola():
	var r: Dictionary = await LLMManager.elenca_modelli_del_profilo()
	assert_eq(r.keys().size(), 4, "ok, modelli, errore, dove — e nient'altro")
	for chiave in ["genera", "elencato", "ms"]:
		assert_false(r.has(chiave), "elencare non prova il modello: niente «%s»" % chiave)

# --- La scelta del modello non deve tornare indietro ---

## Il difetto n.3: a motore spento la scelta finiva nel profilo locale, e il menu la
## rileggeva dal profilo vero — invariato. Spariva davanti agli occhi.
func test_scegliere_un_modello_a_motore_spento_resta_nel_profilo_scelto():
	var i := LLMManager.indice_profilo("OpenRouter")
	assert_gte(i, 0)
	LLMManager.mock_mode = true          # nessun motore acceso, com'e' all'avvio
	LLMManager.imposta_profilo(i)
	LLMManager.imposta_modello("mistralai/mistral-medium-3.1")
	assert_eq(String(LLMManager.profili[i]["model"]), "mistralai/mistral-medium-3.1")
	assert_eq(LLMManager.modello_del_profilo(), "mistralai/mistral-medium-3.1",
		"e' quello che il menu rilegge: se non combacia, la scelta torna indietro")

func test_scegliere_un_modello_non_tocca_gli_altri_profili():
	var a := LLMManager.indice_profilo("Mistral")
	var b := LLMManager.indice_profilo("Ollama locale")
	var prima_b := String(LLMManager.profili[b]["model"])
	LLMManager.imposta_profilo(a)
	LLMManager.imposta_modello("mistral-large-latest")
	assert_eq(String(LLMManager.profili[b]["model"]), prima_b,
		"un modello appartiene al suo provider")

# --- Autore e modello: il menu a cascata ---

## OpenRouter offre oltre trecento modelli: un unico menu piatto non e' scegliibile.
## Si divide in due — prima l'autore, poi il modello — e la divisione e' una funzione
## pura, cosi' si prova senza aprire una finestra.
func test_i_modelli_si_raggruppano_per_autore():
	var elenco := ["mistralai/mistral-small-3.2-24b-instruct", "mistralai/mistral-medium-3.1",
		"google/gemma-4-31b-it:free", "openai/gpt-oss-20b:free"]
	assert_eq(LLMManager.autori(elenco), ["google", "mistralai", "openai"],
		"gli autori, in ordine, senza ripetizioni")
	assert_eq(LLMManager.modelli_di("mistralai", elenco),
		["mistralai/mistral-medium-3.1", "mistralai/mistral-small-3.2-24b-instruct"])

## Un provider a nome semplice ha un autore solo: il menu degli autori non deve comparire
## per finta con dentro un nome inventato.
func test_senza_barra_c_e_un_autore_solo():
	var elenco := ["mistral-small-latest", "mistral-large-latest"]
	assert_eq(LLMManager.autori(elenco), [], "niente autori da mostrare")
	assert_eq(LLMManager.modelli_di("", elenco),
		["mistral-large-latest", "mistral-small-latest"],
		"restano tutti, in ordine: un menu si legge, non si indovina")

func test_l_autore_del_modello_attuale_si_ritrova():
	assert_eq(LLMManager.autore_di("mistralai/mistral-medium-3.1"), "mistralai")
	assert_eq(LLMManager.autore_di("mistral-small-latest"), "")

# --- letto dai file, non dalla memoria ---

## I profili come stanno su disco. `LLMManager.profili` e' stato scritto e riscritto da chi
## ha girato prima: per un'invariante sui DATI serve la fonte, non la copia in uso.
func _profili_da_file() -> Array:
	var out: Array = []
	var dir := DirAccess.open(LLMManager.PROVIDERS_DIR)
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(LLMManager.PROVIDERS_DIR + "/" + f))
		if typeof(d) == TYPE_DICTIONARY and d.has("model") and not bool(d.get("trasporto", false)):
			out.append(d)
	assert_gt(out.size(), 0, "config/providers/ non deve essere vuota")
	return out

# --- Il tetto sulla prova ---

## LE DUE STRADE DEVONO AVERE LA STESSA PAZIENZA.
##
## `prova_profilo()` è il bottone in Settings; `verifica_provider()` è quello che accende il
## motore. Fanno la stessa identica domanda — una generazione da un token — ma il tetto
## l'aveva solo la prima. Visto dal vivo: due minuti di «in attesa di Ollama» all'accensione
## su un modello lento, con la finestra ferma. Il tetto ora sta in un posto solo.
func test_la_prova_ha_un_tetto_piu_basso_di_quello_della_partita():
	var i := LLMManager.indice_profilo("Ollama locale")
	LLMManager.imposta_profilo(i)
	var partita: float = float(LLMManager.config_del_profilo().get("timeout_sec", 0))
	var prova: float = float(LLMManager._config_prova().get("timeout_sec", 0))
	assert_eq(prova, float(LLMManager.SECONDI_PROVA))
	assert_lt(prova, partita, "un turno vero può durare di più: è la PROVA che dev'essere breve")

## E il tetto dev'essere lo stesso per ogni provider: è una proprietà della domanda, non
## del provider a cui la si fa.
func test_il_tetto_della_prova_vale_per_tutti_i_provider():
	for n in NOMI_ATTESI:
		LLMManager.imposta_profilo(LLMManager.indice_profilo(n))
		assert_eq(float(LLMManager._config_prova().get("timeout_sec", 0)),
			float(LLMManager.SECONDI_PROVA), "tetto diverso su «%s»" % n)

# --- Richieste che si sovrappongono ---

## DUE DOMANDE INDIPENDENTI NON DEVONO CONTENDERSI UN TUBO SOLO.
##
## LLMClient aveva un HTTPRequest solo, riusato da tutti, e HTTPRequest ne regge una alla
## volta. Ci ho messo una guardia, ed è stato peggio: la collisione è diventata un errore
## visibile che accusava la rete — «Non raggiungo http://localhost:11434» con Ollama
## perfettamente in ascolto. Bastava aprire Impostazioni (che chiede le taglie dei modelli)
## mentre il motore si stava accendendo.
##
## Qui si puntano due richieste a una porta che rifiuta subito: devono fallire ENTRAMBE per
## il motivo vero — nessuno risponde — e nessuna delle due per essersi trovata la strada
## occupata dall'altra.
func test_due_richieste_insieme_non_si_ostacolano():
	var c := LLMClient.new()
	add_child_autofree(c)
	await wait_frames(1)
	c.configura({"base_url": "http://127.0.0.1:9", "model": "m", "timeout_sec": 3}, "")

	var esiti: Array = []
	var prendi := func(): esiti.append(await c.elenca_modelli())
	prendi.call_deferred()
	prendi.call_deferred()
	for i in 200:
		if esiti.size() >= 2:
			break
		await wait_frames(1)

	assert_eq(esiti.size(), 2, "tutt'e due devono tornare, non una sola")
	for e in esiti:
		assert_false(bool(e["ok"]), "quella porta non risponde")
		assert_false(String(e["errore"]).contains("in volo"),
			"il motivo dev'essere il server, non la coda interna: «%s»" % e["errore"])
