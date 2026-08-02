extends GutTest

## IL GATEWAY E' UN TRASPORTO, NON UN PROVIDER.
##
## Prima era uno dei profili nell'elenco: sceglierlo voleva dire NON scegliere Gemini.
## Ma "con quale modello parlo" e "ci passo attraverso la coda che rispetta i limiti del
## piano gratuito" sono due domande indipendenti, e mescolarle costringeva a rinunciare
## all'una per avere l'altra. Ora sono due comandi separati.

var _esterno_prima := false
var _idx_prima := 0

func before_each():
	# Il gateway riguarda il percorso ESTERNO: senza questo _config_attiva() tornerebbe
	# il profilo Ollama locale e i test misurerebbero tutt'altro.
	_esterno_prima = LLMManager.provider_esterno
	_idx_prima = LLMManager.provider_esterno_idx
	LLMManager.provider_esterno = true
	LLMManager.usa_gateway = false

func after_each():
	# Stato globale: va rimesso com'era, o si sporcano gli altri test.
	LLMManager.usa_gateway = false
	LLMManager.provider_esterno = _esterno_prima
	LLMManager.provider_esterno_idx = _idx_prima

func test_il_gateway_non_compare_fra_i_provider():
	for nome in LLMManager.nomi_profili_esterni():
		assert_false(String(nome).to_lower().contains("gateway"),
			"il gateway non e' un provider fra cui scegliere: e' la strada per arrivarci")

func test_il_gateway_esiste_come_trasporto():
	assert_true(LLMManager.gateway_disponibile(), "config/providers/ deve dichiararne uno")
	assert_string_contains(String(LLMManager.gateway_cfg.get("base_url", "")), "localhost")

## Senza gateway si va dritti al provider, col suo nome di modello nudo.
func test_senza_gateway_si_va_diritti_al_provider():
	var i := _indice_di("gemini")
	if i < 0:
		pending("nessun profilo Gemini configurato"); return
	LLMManager.imposta_profilo_esterno(i)
	var cfg := LLMManager._config_attiva()
	assert_string_contains(String(cfg["base_url"]), "googleapis")
	assert_false(String(cfg["model"]).contains("/"), "niente prefisso: parla col provider")

## Col gateway acceso si va a localhost, e il modello prende il prefisso d'instradamento.
## E' esattamente cio' che prima si poteva ottenere solo rinunciando a scegliere Gemini.
func test_col_gateway_acceso_ci_si_passa_attraverso_TENENDO_il_provider():
	var i := _indice_di("gemini")
	if i < 0:
		pending("nessun profilo Gemini configurato"); return
	LLMManager.imposta_profilo_esterno(i)
	LLMManager.usa_gateway = true
	var cfg := LLMManager._config_attiva()
	assert_string_contains(String(cfg["base_url"]), "localhost", "si passa dalla coda locale")
	assert_eq(String(cfg["model"]), "google/gemini-2.5-flash", "prefisso = instradamento")
	assert_eq(String(cfg.get("api_key_env", "")), "", "le chiavi le tiene il gateway")

func test_il_prefisso_usa_il_provider_del_profilo_non_il_suo_nome():
	var i := _indice_di("mistral")
	if i < 0:
		pending("nessun profilo Mistral configurato"); return
	LLMManager.imposta_profilo_esterno(i)
	LLMManager.usa_gateway = true
	assert_true(String(LLMManager._config_attiva()["model"]).begins_with("mistral/"))

## Il modello mostrato e verificato dev'essere quello che parte davvero, prefisso compreso:
## altrimenti il preflight controlla una cosa e il gioco ne chiama un'altra.
func test_il_modello_atteso_e_quello_che_parte_davvero():
	var i := _indice_di("gemini")
	if i < 0:
		pending("nessun profilo Gemini configurato"); return
	LLMManager.imposta_profilo_esterno(i)
	LLMManager.usa_gateway = true
	assert_eq(LLMManager.modello_atteso(), String(LLMManager._config_attiva()["model"]))

## Spegnere il gateway non deve far perdere il provider scelto.
func test_accendere_e_spegnere_il_gateway_non_cambia_provider():
	var i := _indice_di("gemini")
	if i < 0:
		pending("nessun profilo Gemini configurato"); return
	LLMManager.imposta_profilo_esterno(i)
	LLMManager.usa_gateway = true
	LLMManager.usa_gateway = false
	assert_eq(LLMManager.provider_esterno_idx, i, "il provider resta quello che avevi scelto")
	assert_string_contains(String(LLMManager._config_attiva()["base_url"]), "googleapis")

func _indice_di(pezzo: String) -> int:
	var nomi: Array = LLMManager.nomi_profili_esterni()
	for i in nomi.size():
		if String(nomi[i]).to_lower().contains(pezzo):
			return i
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
	assert_eq(LLMManager.nome_profilo_corrente(), LLMManager.nomi_profili_esterni()[1],
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
	var i := _indice_di("gemini")
	if i < 0:
		pending("nessun profilo Gemini configurato"); return
	LLMManager.provider_esterno = false        # com'e' all'avvio
	LLMManager.imposta_profilo_esterno(i)
	LLMManager.provider_esterno_idx = i
	assert_string_contains(LLMManager.modello_del_profilo(), "gemini")
	LLMManager.usa_gateway = true
	assert_eq(LLMManager.modello_del_profilo(), "google/gemini-2.5-flash")
