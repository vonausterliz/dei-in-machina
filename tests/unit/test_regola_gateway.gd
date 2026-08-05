extends GutTest

## LA REGOLA DEL GATEWAY, enunciata dall'umano e messa qui perché non possa più scivolare:
##
##   «ollama non deve usare il gateway. gli altri provider devono usare il gateway solo se
##    nei settings è spuntata la casella apposita, se non c'è la app deve andare diretta
##    verso il provider. il gateway è un elemento opzionale e serve solo per rimanere dentro
##    il free tier per i modelli che lo prevedono.»
##
## Sono tre righe di una tabella di verità, e finora esisteva solo a pezzi: qualche test la
## sfiorava di lato, nessuno la dichiarava. È la seconda volta che l'umano deve chiedere
## «perché passa dal gateway?», e la prima volta la risposta era un'altra ancora — quindi il
## punto non è solo che il codice sia giusto: è che si veda che lo è, senza rileggerlo.
##
## Il difetto vero trovato scrivendo questi: in `_ripristina_provider()` il trasporto veniva
## ripristinato DOPO il provider, e con un assegnamento diretto al campo. `imposta_profilo()`
## riconfigura il client leggendo `usa_gateway`, che a quel punto valeva ancora il valore di
## prima: il campo diceva una cosa e il client ne faceva un'altra.

var _idx_prima := 0
var _gw_prima := false

func before_each():
	LLMManager.mock_mode = true
	_idx_prima = LLMManager.profilo_idx
	_gw_prima = LLMManager.usa_gateway

func after_each():
	LLMManager.profilo_idx = _idx_prima
	LLMManager.usa_gateway = _gw_prima

func _indice_di(provider: String) -> int:
	for i in LLMManager.profili.size():
		if String(LLMManager.profili[i].get("provider", "")) == provider:
			return i
	return -1

## Dove finirebbe una chiamata adesso: l'indirizzo vero, composto come lo compone il client.
func _dove_va() -> String:
	var cfg := LLMManager._config_attiva()
	return String(cfg.get("base_url", "")).trim_suffix("/") + String(cfg.get("chat_path", ""))

const GATEWAY := "localhost:8800"

# --- riga 1: Ollama, mai ---

func test_ollama_non_passa_mai_dal_gateway_nemmeno_con_la_spunta():
	var i := _indice_di("ollama")
	if i < 0:
		pending("nessun profilo Ollama"); return
	LLMManager.profilo_idx = i
	LLMManager.usa_gateway = false
	assert_false(_dove_va().contains(GATEWAY), "spunta spenta: diretto")
	# E ANCHE CON LA SPUNTA. Non è una svista da tollerare: un server che gira in casa non ha
	# nessun piano gratuito da rispettare, e mettergli davanti una coda aggiungerebbe attesa
	# per non risparmiare niente. La spunta resta accesa per gli altri provider.
	LLMManager.usa_gateway = true
	assert_false(_dove_va().contains(GATEWAY),
		"Ollama gira in casa: il Gateway non deve toccarlo nemmeno se la spunta è attiva")
	assert_true(_dove_va().contains("11434"), "deve restare l'indirizzo di Ollama")

## L'inganno che ha fatto sbagliare una diagnosi: i due indirizzi si somigliano.
## `localhost:11434` è Ollama, `localhost:8800` è il Gateway. Un controllo che cerca
## «localhost» dice «passa dal gateway» in entrambi i casi — ed è successo davvero, a uno
## strumento diagnostico scritto apposta per rispondere a questa domanda.
func test_localhost_di_ollama_non_e_localhost_del_gateway():
	var i := _indice_di("ollama")
	if i < 0:
		pending("nessun profilo Ollama"); return
	LLMManager.profilo_idx = i
	LLMManager.usa_gateway = true
	var dove := _dove_va()
	assert_true(dove.contains("localhost"), "Ollama è pur sempre su localhost")
	assert_false(dove.contains(GATEWAY), "…ma non su quello del Gateway")

# --- riga 2: gli altri, solo con la spunta ---

func test_senza_spunta_ogni_provider_va_diretto():
	for p in ["mistral", "google", "openai", "anthropic", "openrouter"]:
		var i := _indice_di(p)
		if i < 0:
			continue
		LLMManager.profilo_idx = i
		LLMManager.usa_gateway = false
		var dove := _dove_va()
		assert_false(dove.contains(GATEWAY), "«%s» senza spunta deve andare diretto (va a %s)" % [p, dove])
		assert_true(dove.begins_with("https://"),
			"«%s» diretto significa l'indirizzo del provider, non un localhost (%s)" % [p, dove])

func test_con_la_spunta_ogni_provider_remoto_passa_dal_gateway():
	for p in ["mistral", "google", "openai", "anthropic", "openrouter"]:
		var i := _indice_di(p)
		if i < 0:
			continue
		LLMManager.profilo_idx = i
		LLMManager.usa_gateway = true
		assert_true(_dove_va().contains(GATEWAY),
			"«%s» con la spunta deve passare dal Gateway (va a %s)" % [p, _dove_va()])

## Accendere e spegnere dev'essere REVERSIBILE senza lasciare tracce. Se spegnendo la spunta
## restasse una qualunque parte dell'instradamento — il prefisso nel nome del modello, la
## query string, il timeout lungo — si tornerebbe «diretti» solo per metà.
func test_spegnere_la_spunta_riporta_tutto_com_era():
	var i := _indice_di("openrouter")
	if i < 0:
		pending("nessun profilo OpenRouter"); return
	LLMManager.profilo_idx = i
	LLMManager.usa_gateway = false
	var prima := LLMManager._config_attiva().duplicate(true)
	LLMManager.usa_gateway = true
	LLMManager.usa_gateway = false
	var dopo := LLMManager._config_attiva()
	for campo in ["base_url", "chat_path", "models_path", "model", "api_key_env", "timeout_sec"]:
		assert_eq(dopo.get(campo), prima.get(campo),
			"«%s» non è tornato com'era dopo un giro di spunta" % campo)

# --- riga 3: il campo e il client non possono divergere ---

## IL DIFETTO D'ORDINE. `imposta_profilo()` riconfigura il client leggendo `usa_gateway`:
## cambiare il campo dopo lascia il client sulla strada di prima. `imposta_gateway()` cambia
## tutti e due insieme, ed è per questo che esiste.
func test_cambiare_provider_non_puo_cambiare_la_strada():
	var o := _indice_di("openrouter")
	var m := _indice_di("mistral")
	if o < 0 or m < 0:
		pending("servono OpenRouter e Mistral"); return
	LLMManager.imposta_gateway(false)
	LLMManager.imposta_profilo(o)
	assert_false(_dove_va().contains(GATEWAY))
	LLMManager.imposta_profilo(m)
	assert_false(_dove_va().contains(GATEWAY),
		"cambiare provider ha acceso il Gateway che nessuno aveva chiesto")
	LLMManager.imposta_gateway(true)
	LLMManager.imposta_profilo(o)
	assert_true(_dove_va().contains(GATEWAY),
		"cambiare provider ha spento il Gateway che era stato chiesto")

## Senza un trasporto configurato la spunta non può fare nulla: si va diretti invece di
## puntare a un indirizzo dove non risponde nessuno.
func test_senza_trasporto_configurato_la_spunta_non_dirotta():
	var i := _indice_di("openrouter")
	if i < 0:
		pending("nessun profilo OpenRouter"); return
	var cfg_prima := LLMManager.gateway_cfg
	LLMManager.gateway_cfg = {}
	LLMManager.profilo_idx = i
	LLMManager.usa_gateway = true
	var dove := _dove_va()
	LLMManager.gateway_cfg = cfg_prima
	assert_false(dove.contains(GATEWAY), "senza trasporto non c'è nessun gateway a cui andare")
	assert_true(dove.begins_with("https://openrouter.ai"), "si va diretti: %s" % dove)
