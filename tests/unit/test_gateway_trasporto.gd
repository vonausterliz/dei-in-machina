extends GutTest

## IL GATEWAY E' UN TRASPORTO, NON UN PROVIDER.
##
## Prima era uno dei profili nell'elenco: sceglierlo voleva dire NON scegliere Gemini.
## Ma "con quale modello parlo" e "ci passo attraverso la coda che rispetta i limiti del
## piano gratuito" sono due domande indipendenti, e mescolarle costringeva a rinunciare
## all'una per avere l'altra. Ora sono due comandi separati.

var _idx_prima := 0

func before_each():
	# Il gateway riguarda i provider REMOTI: davanti a Ollama, che gira in casa, non c'e'
	# nessun piano gratuito da rispettare e il trasporto si tira indietro da solo.
	_idx_prima = LLMManager.profilo_idx
	LLMManager.usa_gateway = false

func after_each():
	# Stato globale: va rimesso com'era, o si sporcano gli altri test.
	LLMManager.usa_gateway = false
	LLMManager.profilo_idx = _idx_prima

func test_il_gateway_non_compare_fra_i_provider():
	for nome in LLMManager.nomi_profili():
		assert_false(String(nome).to_lower().contains("gateway"),
			"il gateway non e' un provider fra cui scegliere: e' la strada per arrivarci")

func test_il_gateway_esiste_come_trasporto():
	assert_true(LLMManager.gateway_disponibile(), "config/providers/ deve dichiararne uno")
	assert_string_contains(String(LLMManager.gateway_cfg.get("base_url", "")), "localhost")

## Senza gateway si va dritti al provider, col suo nome di modello nudo.
func test_senza_gateway_si_va_diritti_al_provider():
	var i := _indice_di("google")
	LLMManager.imposta_profilo(i)
	var cfg := LLMManager._config_attiva()
	assert_string_contains(String(cfg["base_url"]), "googleapis")
	assert_false(String(cfg["model"]).contains("/"), "niente prefisso: parla col provider")

## Col gateway acceso si va a localhost, e il modello prende il prefisso d'instradamento.
## E' esattamente cio' che prima si poteva ottenere solo rinunciando a scegliere Gemini.
func test_col_gateway_acceso_ci_si_passa_attraverso_TENENDO_il_provider():
	var i := _indice_di("google")
	LLMManager.imposta_profilo(i)
	LLMManager.usa_gateway = true
	var cfg := LLMManager._config_attiva()
	assert_string_contains(String(cfg["base_url"]), "localhost", "si passa dalla coda locale")
	# Il NOME del modello non si fissa nei test: e' esattamente la cosa che il provider
	# cambia sotto i piedi. Si controlla il meccanismo — prefisso = provider del profilo.
	assert_eq(String(cfg["model"]), "google/%s" % _modello_del_file(i), "prefisso = instradamento")
	assert_eq(String(cfg.get("api_key_env", "")), "", "le chiavi le tiene il gateway")

func test_il_prefisso_usa_il_provider_del_profilo_non_il_suo_nome():
	var i := _indice_di("mistral")
	if i < 0:
		pending("nessun profilo Mistral configurato"); return
	LLMManager.imposta_profilo(i)
	LLMManager.usa_gateway = true
	assert_true(String(LLMManager._config_attiva()["model"]).begins_with("mistral/"))

## Il modello mostrato e verificato dev'essere quello che parte davvero, prefisso compreso:
## altrimenti il preflight controlla una cosa e il gioco ne chiama un'altra.
func test_il_modello_atteso_e_quello_che_parte_davvero():
	var i := _indice_di("google")
	LLMManager.imposta_profilo(i)
	LLMManager.usa_gateway = true
	assert_eq(LLMManager.modello_atteso(), String(LLMManager._config_attiva()["model"]))

## Spegnere il gateway non deve far perdere il provider scelto.
func test_accendere_e_spegnere_il_gateway_non_cambia_provider():
	var i := _indice_di("google")
	LLMManager.imposta_profilo(i)
	LLMManager.usa_gateway = true
	LLMManager.usa_gateway = false
	assert_eq(LLMManager.profilo_idx, i, "il provider resta quello che avevi scelto")
	assert_string_contains(String(LLMManager._config_attiva()["base_url"]), "googleapis")

## Il modello come sta nel file del profilo: cosi' il test resta valido quando il modello
## cambia (e cambiera').
func _modello_del_file(idx: int) -> String:
	return String(LLMManager.profili[idx].get("model", ""))

## Cerca per PROVIDER, non per nome mostrato. Cercava «gemini» nel nome; il giorno in cui
## il profilo si e' chiamato «Google» sei test di questo file sono diventati pending —
## verdi, silenziosi e inutili. Il campo `provider` e' quello che non cambia, e se manca il
## test fallisce invece di dichiararsi non pertinente.
func _indice_di(provider: String) -> int:
	for i in LLMManager.profili.size():
		if String(LLMManager.profili[i].get("provider", "")) == provider:
			return i
	assert_true(false, "config/providers/ deve contenere un profilo con provider «%s»" % provider)
	return -1

# --- Migrazione della preferenza salvata ---

## Prima il gateway era il PRIMO provider dell'elenco e si salvava la posizione. Ora non e'
## piu' un provider: tutte le vecchie posizioni sono slittate di uno. Senza conversione,
## chi riapre il gioco si ritrova un provider diverso da quello scelto e non capisce perche'.
func test_la_vecchia_scelta_salvata_per_posizione_viene_convertita():
	var ui = load("res://scenes/Main.tscn").instantiate()
	Impostazioni.dimentica("provider_nome")
	Impostazioni.scrivi("provider_idx", 2)      # con il gateway in testa: il 2° provider vero
	Impostazioni.scrivi("usa_gateway", false)
	add_child_autofree(ui)
	await wait_frames(2)
	ui._ripristina_provider()
	assert_eq(LLMManager.nome_profilo_corrente(), LLMManager.nomi_profili()[1],
		"la vecchia posizione 2 (col gateway in testa) e' la 1 di oggi")
	assert_null(Impostazioni.leggi("provider_idx"), "la chiave vecchia sparisce")

func test_chi_aveva_scelto_il_gateway_se_lo_ritrova_acceso():
	var ui = load("res://scenes/Main.tscn").instantiate()
	Impostazioni.dimentica("provider_nome")
	Impostazioni.scrivi("provider_idx", 0)      # "0" era il profilo Gateway
	Impostazioni.scrivi("usa_gateway", false)
	add_child_autofree(ui)
	await wait_frames(2)
	ui._ripristina_provider()
	assert_true(LLMManager.usa_gateway, "chi passava dal gateway continua a passarci")
	Impostazioni.dimentica("provider_nome")
	Impostazioni.scrivi("usa_gateway", false)

## In Settings si mostra il modello del profilo SCELTO, non quello che parte adesso:
## all'avvio il percorso esterno non e' ancora acceso, e comparirebbe Ollama sotto la
## voce "Gemini".
func test_settings_mostra_il_modello_del_profilo_scelto():
	var i := _indice_di("google")
	LLMManager.imposta_profilo(i)
	LLMManager.profilo_idx = i
	assert_string_contains(LLMManager.modello_del_profilo(), "gemini")
	LLMManager.usa_gateway = true
	assert_eq(LLMManager.modello_del_profilo(), "google/%s" % _modello_del_file(i))

## L'elenco di Google restituisce i nomi come «models/gemini-3.5-flash». Sceglierne uno dal
## menu non deve lasciare due verita' in giro: il profilo col nome pulito e il client con
## un altro. Il nome effettivo si ricalcola sempre dal profilo + trasporto.
func test_il_prefisso_dell_elenco_non_si_porta_dietro():
	var i := _indice_di("google")
	LLMManager.imposta_profilo(i)
	LLMManager.imposta_modello("models/gemini-3.5-flash")
	assert_eq(String(LLMManager.profili[i]["model"]), "gemini-3.5-flash",
		"nel profilo si salva il nome nudo")
	assert_eq(LLMManager.modello_atteso(), "gemini-3.5-flash", "e si manda quello")
	LLMManager.usa_gateway = true
	assert_eq(LLMManager.modello_atteso(), "google/gemini-3.5-flash",
		"col gateway il prefisso e' quello d'instradamento, non quello dell'elenco")

## L'ELENCO DEI MODELLI DEVE DIRE PER CHI.
##
## L'endpoint /v1/models non porta il nome del modello, quindi passando dal gateway non
## c'era niente che dicesse quale provider ci interessasse: il gateway rispondeva sempre col
## suo predefinito. Con Mistral selezionato andava bene per caso — è il predefinito — ma con
## Google si ottenevano i modelli di Mistral etichettati come suoi. È la risposta di un
## altro, cioè lo stesso difetto di «Aggiorna elenco» che interrogava il motore acceso.
func test_col_gateway_l_elenco_dice_di_quale_provider():
	var cfg := LLMManager.attraverso_il_gateway_per_test(
		{"provider": "google", "model": "gemini-3.5-flash"})
	assert_string_contains(String(cfg["models_path"]), "provider=google")

func test_senza_provider_dichiarato_non_si_inventa_una_query():
	var cfg := LLMManager.attraverso_il_gateway_per_test({"model": "qualcosa"})
	assert_false(String(cfg["models_path"]).contains("?"),
		"un gateway vecchio deve continuare a funzionare come prima")

## Il messaggio di un 401 deve dire CHI chiede la chiave. Passando dal gateway il consiglio
## solito — «mettila in Settings» — sarebbe sbagliato: la chiave ce l'ha lui, nel suo ambiente.
func test_un_401_dal_gateway_manda_a_cercare_la_chiave_nel_posto_giusto():
	var c := LLMClient.new()
	add_child_autofree(c)
	c.configura({"base_url": "http://localhost:8800", "model": "m"}, "")
	var msg := c._perche(401, "no api key".to_utf8_buffer())
	assert_string_contains(msg, "Gateway")
	assert_string_contains(msg, "no api key", "il motivo del provider non si butta via")

func test_un_401_diretto_accusa_il_provider_non_il_gateway():
	var c := LLMClient.new()
	add_child_autofree(c)
	c.configura({"base_url": "https://api.mistral.ai", "model": "m"}, "")
	assert_false(c._perche(401, PackedByteArray()).contains("Gateway"))
