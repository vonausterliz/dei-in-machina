extends Node

## Autoload. Layer LLM provider-agnostico (formato chat-completions OpenAI, design sez. 9).
## Due percorsi, scelti da config/llm_config.json -> "mock":
##  - mock:true  -> LLMMock, deterministico e senza rete (default: test, FSM a LLM spento).
##  - mock:false -> LLMClient reale (Ollama/Mistral/...), con Interprete e JSON difensivo.
## Le chiamate sono coroutine (await) in entrambi i percorsi: i punti di chiamata non cambiano.
##
## Fase 1: implementato il percorso reale per interpreta(). Dei/Arbitro/Omero reali
## arrivano dalle fasi 2-3 (per ora restano sul mock anche in modalita' non-mock).

const CONFIG_PATH := "res://config/llm_config.json"
const PROVIDERS_DIR := "res://config/providers"  # un .json per provider, Ollama compreso

var mock_mode: bool = true
## Passare o no dalla coda locale del gateway. Ortogonale al provider scelto.
var usa_gateway := false
## Il profilo del trasporto (config/providers/ con "trasporto": true). Vuoto se assente.
var gateway_cfg: Dictionary = {}
## OLLAMA E' UN PROVIDER COME GLI ALTRI.
##
## Prima no: stava in config/llm_config.json, fuori dall'elenco, e si sceglieva con un
## interruttore suo («chi da' voce agli dei: Ollama / provider esterno»). Ma «con quale
## modello parlo» e' una domanda sola, e averla in due posti aveva una conseguenza precisa:
## col motore su Ollama il menu «Modello» mostrava il modello di un ALTRO provider, e i
## modelli installati in casa non erano raggiungibili da nessuna parte. Ora ha il suo file
## come tutti (1_ollama.json) e dichiara `locale: true` — l'unica differenza che gli resta.
var profilo_idx: int = 0
var profili: Array = []              # tutti i provider, da config/providers/*.json
var config: Dictionary = {}          # cio' che non appartiene a nessun provider: mock, stadio

## Nei dati dei provider la chiave API non c'e': c'e' questo segnaposto (vedi LLMClient).
const SEGNAPOSTO_CHIAVE := LLMClient.SEGNAPOSTO_CHIAVE

## I provider si chiamavano col nome di un modello («Mistral Small», «Gemini 3.5 Flash»):
## sbagliato due volte, perche' il modello si sceglie a parte e perche' cambiava sotto il
## nome. Rinominarli pero' fa perdere la scelta a chi aveva gia' giocato — la preferenza e'
## salvata per nome. Questa tabella la traduce, una volta.
const NOMI_STORICI := {
	"Mistral Small": "Mistral",
	"Gemini 3.5 Flash": "Google",
	"GPT-4o mini": "OpenAI",
}

var _mock := LLMMock.new()
var _client: LLMClient = null
var _interprete: Interprete = null
var _dio_agente: DioAgente = null
var _narratore: Narratore = null
var _arbitro: Arbitro = null
var _suggeritore: Suggeritore = null
var _cronista: Cronista = null
var _compagno: Compagno = null

func _ready() -> void:
	config = _carica_config()
	profili = _carica_profili()
	_applica_override_env()
	mock_mode = config.get("mock", true)
	if not mock_mode:
		_inizializza_reale()

## Profilo del provider selezionato, con il trasporto applicato. I punti di chiamata non
## cambiano: il client è provider-agnostico (formato chat-completions OpenAI).
func _config_attiva() -> Dictionary:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return {}
	return _attraverso_il_gateway(profili[profilo_idx])

## Il provider scelto gira in casa? Cambia una cosa sola: non gli servono chiavi, e non c'è
## nessun piano gratuito da rispettare — quindi nemmeno il gateway ha senso davanti a lui.
func e_locale() -> bool:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return false
	return bool(profili[profilo_idx].get("locale", false))

## IL GATEWAY E' UN TRASPORTO, NON UN PROVIDER.
##
## Prima era una voce dell'elenco dei provider: sceglierlo voleva dire NON scegliere
## Gemini. Ma "con quale modello parlo" e "ci passo attraverso la coda che rispetta i
## limiti del piano gratuito" sono due domande indipendenti, e mescolarle costringeva a
## rinunciare all'una per avere l'altra.
##
## Qui il profilo scelto resta quello, e cambia solo la strada: si va a localhost e il
## modello prende il prefisso d'instradamento («google/gemini-2.5-flash»). Le chiavi non
## servono piu' al gioco: le tiene il gateway.
func _attraverso_il_gateway(profilo: Dictionary) -> Dictionary:
	if not usa_gateway or gateway_cfg.is_empty():
		return profilo
	if bool(profilo.get("locale", false)):
		return profilo   # un server in casa non ha limiti da rispettare: la coda non serve
	var cfg := profilo.duplicate(true)
	cfg["base_url"] = gateway_cfg.get("base_url", "http://localhost:8800")
	cfg["chat_path"] = gateway_cfg.get("chat_path", "/v1/chat/completions")
	# CHI vogliamo elencare. L'endpoint dei modelli non porta il nome del modello, quindi il
	# gateway non aveva modo di sapere per quale provider stessimo chiedendo, e rispondeva
	# sempre col suo predefinito: con Google selezionato tornavano i modelli di Mistral. Il
	# provider si dice in query string; un gateway vecchio la ignora e si comporta come prima.
	var elenco: String = gateway_cfg.get("models_path", "/v1/models")
	var chi := String(profilo.get("provider", ""))
	cfg["models_path"] = "%s?provider=%s" % [elenco, chi.uri_encode()] if chi != "" else elenco
	cfg["timeout_sec"] = gateway_cfg.get("timeout_sec", 300)
	cfg["api_key_env"] = ""
	var provider := String(profilo.get("provider", ""))
	var modello := String(profilo.get("model", ""))
	# Il prefisso si aggiunge se non c'e' gia'. Su un provider a nome pieno (OpenRouter) la
	# barra c'e' sempre e appartiene al nome: il prefisso va messo DAVANTI, non saltato —
	# «openrouter/mistralai/…». Il gateway divide sulla prima barra, quindi legge
	# provider=openrouter e modello=mistralai/…, che e' esattamente cio' che serve.
	var pieno := bool(profilo.get("nome_pieno", false))
	if provider != "" and (pieno or not modello.contains("/")):
		cfg["model"] = "%s/%s" % [provider, modello]
	return cfg

## Solo per i test: il trasporto applicato a un profilo qualunque, senza toccare lo stato.
func attraverso_il_gateway_per_test(profilo: Dictionary) -> Dictionary:
	var prima := usa_gateway
	var prima_cfg := gateway_cfg
	usa_gateway = true
	if gateway_cfg.is_empty():
		gateway_cfg = {"base_url": "http://localhost:8800"}
	var out := _attraverso_il_gateway(profilo)
	usa_gateway = prima
	gateway_cfg = prima_cfg
	return out

## CHI HA LA CHIAVE, SECONDO IL GATEWAY.
##
## Col gateway acceso la chiave del gioco non conta: le chiamate le fa lui, con le SUE, lette
## dal proprio ambiente una volta sola all'avvio. E' una condizione invisibile che si
## manifesta solo come un 401 a valle — e' successo tre volte. Qui gliela si chiede, cosi'
## Settings puo' dirlo prima.
## Ritorna {raggiungibile: bool, chiavi: {provider -> bool}}.
func stato_gateway() -> Dictionary:
	if gateway_cfg.is_empty():
		return {"raggiungibile": false, "chiavi": {}}
	var c := LLMClient.new()
	add_child(c)
	c.configura({"base_url": gateway_cfg.get("base_url", "http://localhost:8800"), "timeout_sec": 5}, "")
	var r: Dictionary = await c.get_json("/stato")
	remove_child(c)
	c.queue_free()
	if not bool(r.get("ok", false)):
		return {"raggiungibile": false, "chiavi": {}}
	var chiavi: Dictionary = {}
	for nome in Dictionary(r["dati"].get("providers", {})):
		chiavi[String(nome)] = bool(r["dati"]["providers"][nome].get("chiave", false))
	return {"raggiungibile": true, "chiavi": chiavi}

## Il nome con cui il gateway conosce il provider selezionato (il campo `provider` del profilo).
func provider_id() -> String:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return ""
	return String(profili[profilo_idx].get("provider", ""))

## C'e' un gateway configurato (config/providers/ con "trasporto": true)?
func gateway_disponibile() -> bool:
	return not gateway_cfg.is_empty()

## Accende/spegne il passaggio dal gateway senza toccare il provider scelto.
func imposta_gateway(attivo: bool) -> void:
	usa_gateway = attivo
	_riconfigura()

## Rimette il client sul profilo selezionato. Prima ogni chiamante lo faceva a mano, e
## ognuno con la sua condizione: bastava dimenticarne una perche' il gioco continuasse a
## parlare col provider di prima senza dirlo a nessuno.
func _riconfigura() -> void:
	if _client == null:
		return
	var cfg := _config_attiva()
	if cfg.is_empty():
		return
	_client.configura(cfg, _leggi_chiave(cfg))

## Carica config/providers/*.json (ordinati per nome file): TUTTI i provider, compreso
## Ollama. Un file con "trasporto": true NON e' un provider ma la strada per raggiungerli
## (il Gateway): finisce in gateway_cfg e resta fuori dall'elenco fra cui si sceglie.
func _carica_profili() -> Array:
	var out: Array = []
	gateway_cfg = {}
	var dir := DirAccess.open(PROVIDERS_DIR)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.to_lower().ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROVIDERS_DIR + "/" + f))
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("base_url"):
			continue
		if not parsed.has("nome"):
			parsed["nome"] = f
		if bool(parsed.get("trasporto", false)):
			gateway_cfg = parsed
		elif parsed.has("model"):
			out.append(parsed)
	return out

## Indice del profilo dal NOME (come e' salvato nelle preferenze). -1 se non c'e' piu':
## salvare il nome invece della posizione evita che aggiungere o togliere un file in
## config/providers/ faccia scivolare la scelta su un altro provider. I nomi vecchi
## («Mistral Small» -> «Mistral») si traducono, cosi' chi aveva gia' scelto non si ritrova
## su un altro provider dopo un aggiornamento.
func indice_profilo(nome: String) -> int:
	var cercato := String(NOMI_STORICI.get(nome, nome))
	for i in profili.size():
		if String(profili[i].get("nome", "")) == cercato:
			return i
	return -1

func nome_profilo_corrente() -> String:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return ""
	return String(profili[profilo_idx].get("nome", ""))

## Almeno un provider configurato?
func c_e_un_provider() -> bool:
	return not profili.is_empty()

## Etichette dei provider, per il menù a tendina.
func nomi_profili() -> Array:
	var out: Array = []
	for p in profili:
		out.append(String(p.get("nome", "?")))
	return out

## Seleziona quale provider usare, e riconfigura subito il client.
##
## Prima riconfigurava solo «se il percorso esterno e' gia' acceso»: scegliere un provider
## in Settings prima di iniziare non arrivava al client, e la verifica successiva
## interrogava ancora quello di prima. Era la meta' del difetto di «Aggiorna elenco».
func imposta_profilo(idx: int) -> void:
	if idx < 0 or idx >= profili.size():
		return
	profilo_idx = idx
	_riconfigura()

## La chiave API del provider selezionato è disponibile?
## Un profilo che non dichiara api_key_env non ne ha bisogno (Ollama, che gira in casa, o
## il Gateway locale, che le chiavi le tiene lui): in quel caso va sempre bene.
func chiave_presente() -> bool:
	if profili.is_empty():
		return false
	if e_locale():
		return true
	if usa_gateway and gateway_disponibile():
		return true   # passando dal gateway le chiavi le tiene lui, non il gioco
	var idx := clampi(profilo_idx, 0, profili.size() - 1)
	var cfg: Dictionary = profili[idx]
	if String(cfg.get("api_key_env", "")) == "":
		return true
	return _leggi_chiave(cfg) != ""

## Il modello del provider SELEZIONATO come partira' davvero, cioe' col prefisso
## d'instradamento se si passa dal gateway. Serve ai messaggi della prova, che devono
## nominare cio' che e' stato mandato.
func modello_del_profilo() -> String:
	return String(_config_attiva().get("model", "?"))

## Il modello SCELTO, nudo: quello scritto nel profilo, senza le decorazioni del trasporto.
##
## E' cio' che va mostrato e confrontato nei menu. Col gateway acceso l'altro diventa
## «mistral/mistral-small-latest», e quella barra e' instradamento — ma il menu la leggeva
## come se separasse un autore dal modello, e davanti a Mistral compariva una riga «Autore:
## mistral» che non vuol dire niente. La barra significa cose diverse a seconda del
## provider, e l'unico che lo sa e' il profilo: e' la stessa lezione di `nome_nudo`.
func modello_scelto() -> String:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return ""
	return String(profili[profilo_idx].get("model", ""))

## La configurazione del provider SELEZIONATO, col trasporto applicato.
func config_del_profilo() -> Dictionary:
	return _config_attiva()

## I modelli che il profilo propone senza chiedere niente a nessuno.
##
## Un menu vuoto finche' non premi «Aggiorna» costringe a essere online per capire cosa si
## puo' scegliere; e un elenco salvato in cache invecchia in silenzio — che e' esattamente
## l'errore da cui viene tutto questo. Qui sono scritti nel file del provider, e
## `tools/verifica_modelli` li confronta col catalogo vero quando glielo si chiede.
func modelli_noti() -> Array:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return []
	return Array(profili[profilo_idx].get("modelli_noti", []))

## PROVA IL MODELLO CONFIGURATO, senza accendere niente e senza disturbare la partita.
##
## Due domande separate, perche' falliscono in modi diversi e si rimediano in modi diversi:
##  - il server risponde?      (indirizzo sbagliato, gateway spento, rete)
##  - il modello genera?       (nome ritirato, chiave mancante, quota finita)
## Un modello puo' comparire nell'elenco ed essere morto: e' successo due volte in una
## sera con Gemini. Per questo si tenta una generazione vera da un token.
##
## LA PROVA HA UN TETTO SUO, piu' basso di quello della partita. Il profilo di Ollama
## concede 300 secondi, che per un turno vero sono ragionevoli — un modello grosso ci mette
## a caricarsi. Ma per rispondere «ok» a una parola sola, cinque minuti di attesa davanti a
## una finestra ferma non sono una verifica: sono un blocco. Trenta secondi, poi si chiude e
## si dice cosa e' successo. Con un modello enorme puo' voler dire «non ha fatto in tempo a
## caricarsi» invece di «e' rotto» — e infatti il messaggio dice proprio quello.
const SECONDI_PROVA := 30

## La configurazione con il tetto della prova al posto di quello della partita.
##
## C'ERA IN UN PERCORSO SOLO, ed era il percorso sbagliato per chi gioca. `prova_profilo()`
## e' il bottone in Settings; ma il motore si accende da `verifica_provider()`, che fa la
## stessa identica prova — una generazione da un token — e quella era rimasta a 300 secondi.
## Risultato visto dal vivo: due minuti buoni di «in attesa di Ollama» su un modello lento,
## con la finestra ferma e nessun modo di sapere se stesse succedendo qualcosa. Le due
## strade fanno la stessa domanda: devono avere la stessa pazienza.
func _config_prova() -> Dictionary:
	var cfg := config_del_profilo()
	if cfg.is_empty():
		return cfg
	var c := cfg.duplicate(true)
	c["timeout_sec"] = SECONDI_PROVA
	return c

func prova_profilo() -> Dictionary:
	if _client == null:
		_inizializza_reale()
	var cfg := config_del_profilo()
	var atteso := String(cfg.get("model", "?"))
	_client.configura(_config_prova(), _leggi_chiave(cfg))
	var t0 := Time.get_ticks_msec()
	var elenco: Dictionary = await _client.elenca_modelli()
	var esito := {
		"atteso": atteso, "dove": String(cfg.get("base_url", "?")),
		"raggiungibile": bool(elenco.get("ok", false)),
		"modelli": elenco.get("modelli", []),
		"elencato": false, "genera": false, "errore": String(elenco.get("errore", "")),
		"ms": 0,
	}
	if esito["raggiungibile"]:
		esito["elencato"] = _modello_presente(atteso, esito["modelli"])
		var prova := await _prova_generazione()
		esito["genera"] = prova["ok"]
		if not prova["ok"]:
			esito["errore"] = prova["errore"]
	esito["ms"] = Time.get_ticks_msec() - t0
	# L'ESITO SI RICORDA. Un modello provato e muto viene segnato, e il menu lo mostra rosso
	# col motivo vero — che la stima sulla memoria non avrebbe mai indovinato. Uno che genera
	# cancella il segno: se aggiorni Ollama e riparte, il rosso deve sparire da solo.
	if esito["raggiungibile"]:
		if esito["genera"]:
			dimentica_fallimento(atteso)
		else:
			segna_fallimento(atteso, String(esito["errore"]))
	_riconfigura()   # la partita non deve accorgersi della prova
	return esito

## I MODELLI DEL PROFILO SELEZIONATO, con la loro taglia dove il provider sa dirla.
##
## Serve al verdetto «questo modello gira su questa macchina?»: senza la dimensione non c'e'
## niente da confrontare con la memoria. Solo Ollama la espone (`tags_path`); per gli altri
## la domanda non si pone — il ferro e' loro.
## Ritorna {ok, modelli: [{nome, byte, parametri, quantizzazione}], errore, dove}.
func dettagli_modelli_del_profilo() -> Dictionary:
	if _client == null:
		_inizializza_reale()
	var cfg := config_del_profilo()
	var dove := String(cfg.get("base_url", "?"))
	if cfg.is_empty() or String(cfg.get("tags_path", "")) == "":
		return {"ok": false, "modelli": [], "errore": "nessun elenco dettagliato", "dove": dove}
	_client.configura(cfg, _leggi_chiave(cfg))
	var r: Dictionary = await _client.elenca_dettagli()
	_riconfigura()
	r["dove"] = dove
	return r

# --- La memoria dei fallimenti ---
#
# ESSERE ELENCATO NON VUOL DIRE FUNZIONARE, e la stima sulla memoria non lo sa. Su questa
# macchina `mistral-small3.2` occupa 15 GB su 60 di RAM — ci starebbe comodo — ma non parte,
# perche' Ollama 0.5.11 non lo conosce. La stima gli darebbe il segno giallo «lento»; la
# verita' e' che non si avvia. Quando una prova lo scopre, il gioco se lo ricorda: e' un
# dato misurato, e batte qualunque previsione.
#
# Si ricorda PER PROVIDER e si dimentica appena quel modello genera: se aggiorni Ollama e
# il modello riparte, il primo «Prova il modello» riuscito cancella il segno rosso.

func _chiave_falliti(idx: int) -> String:
	return "falliti:%s" % (String(profili[idx].get("nome", idx)) if idx >= 0 and idx < profili.size() else "?")

func _falliti() -> Dictionary:
	var v: Variant = Impostazioni.leggi(_chiave_falliti(profilo_idx), {})
	return v if typeof(v) == TYPE_DICTIONARY else {}

## Il motivo per cui quel modello non e' partito l'ultima volta che ci si e' provati.
## "" = non e' mai stato provato, oppure l'ultima prova e' andata bene.
func fallimento(modello: String) -> String:
	return String(_falliti().get(modello, ""))

func segna_fallimento(modello: String, motivo: String) -> void:
	if modello == "" or motivo == "":
		return
	var d := _falliti()
	d[modello] = motivo.substr(0, 300)
	Impostazioni.scrivi(_chiave_falliti(profilo_idx), d)

func dimentica_fallimento(modello: String) -> void:
	var d := _falliti()
	if d.erase(modello):
		Impostazioni.scrivi(_chiave_falliti(profilo_idx), d)

## SOLO L'ELENCO DEI MODELLI, e solo dal provider SELEZIONATO nel menu.
##
## Questo e' cio' che «Aggiorna elenco» avrebbe dovuto fare da sempre. Chiamava invece
## verifica_provider(), che interroga il MOTORE ACCESO: con Ollama in esecuzione e OpenRouter
## scelto nel menu, il gioco chiedeva la lista a Ollama e la mostrava come se fosse di
## OpenRouter. Non un errore a schermo — la risposta di un altro. Il bottone «Prova il
## modello», accanto, faceva gia' la cosa giusta: due strade per la stessa domanda, e solo
## una corretta.
##
## E si ferma qui: nessuna generazione di prova. Aggiornare un elenco non deve costare un
## token, e la prova del modello ha gia' il suo bottone.
## Ritorna {ok, modelli, errore, dove} — `dove` e' l'indirizzo interrogato davvero.
func elenca_modelli_del_profilo() -> Dictionary:
	if _client == null:
		_inizializza_reale()
	var cfg := config_del_profilo()
	var dove := String(cfg.get("base_url", "?"))
	if cfg.is_empty():
		return {"ok": false, "modelli": [], "errore": "nessun provider selezionato", "dove": dove}
	_client.configura(cfg, _leggi_chiave(cfg))
	_reg("→ elenco dei modelli di «%s» (%s)…" % [nome_profilo_corrente(), dove])
	var r: Dictionary = await _client.elenca_modelli()
	_reg("← %d modelli · %s" % [Array(r.get("modelli", [])).size(), String(r.get("errore", "ok"))])
	_riconfigura()
	return {
		"ok": bool(r.get("ok", false)), "modelli": r.get("modelli", []),
		"errore": String(r.get("errore", "")), "dove": dove,
	}

## --- La scelta del modello, ricordata PER PROVIDER ---
##
## C'era una preferenza sola per tutto il gioco. Ma un modello appartiene al suo provider:
## «gemini-3.5-flash» non vuol dire niente per Mistral. E veniva riapplicata all'avvio,
## quando il percorso esterno non e' ancora acceso, quindi finiva nel profilo di Ollama:
## sceglievi Gemini, riaprivi, e ritrovavi il modello di prima. Senza un errore, senza una
## riga di log. Ora ogni provider ha la sua chiave.

## Il nome del modello senza fronzoli: né il prefisso d'instradamento del gateway
## («google/…») né quello dell'elenco di Google («models/…»).
##
## `nome_pieno`: LA BARRA FA PARTE DEL NOME, non toccarla. Su OpenRouter i modelli si
## chiamano «autore/modello» (`mistralai/mistral-small-3.2-24b-instruct:free`) e togliere
## il primo pezzo significherebbe chiedere un modello che non esiste: 404 a ogni chiamata,
## e nessun indizio sul perché. Lo dichiara il profilo del provider, che è l'unico a saperlo.
static func nome_nudo(nome: String, nome_pieno: bool = false) -> String:
	if nome_pieno:
		# Anche qui il prefisso dell'ELENCO va via: è dell'endpoint, non del modello.
		return nome.trim_prefix("models/")
	return nome.get_slice("/", 1) if nome.contains("/") else nome

## Il profilo selezionato dichiara nomi «autore/modello»?
func nome_pieno() -> bool:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return false
	return bool(profili[profilo_idx].get("nome_pieno", false))

func _chiave_modello(idx: int) -> String:
	if idx < 0 or idx >= profili.size():
		return "modello:locale"
	return "modello:%s" % String(profili[idx].get("nome", idx))

## Ricorda il modello scelto per il provider CORRENTE (e lo applica subito).
func ricorda_modello(nome: String) -> void:
	var pulito := nome_nudo(nome.strip_edges(), nome_pieno())
	if pulito == "":
		return
	Impostazioni.scrivi(_chiave_modello(profilo_idx), pulito)
	imposta_modello(pulito)

# --- Autore e modello: il menu a cascata ---
#
# OpenRouter offre oltre trecento modelli. Un unico menu a tendina con dentro trecento voci
# non e' un elenco fra cui scegliere, e' un muro: si divide in due, prima l'autore poi il
# modello. Sono funzioni pure perche' cosi' si provano senza aprire una finestra.

## «mistralai/mistral-medium-3.1» -> «mistralai». Senza barra non c'e' autore: e' un
## provider a nome semplice, e inventargliene uno riempirebbe il menu di una voce falsa.
static func autore_di(nome: String) -> String:
	return nome.get_slice("/", 0) if nome.contains("/") else ""

## Gli autori presenti nell'elenco, in ordine e senza ripetizioni. Vuoto se nessuno ne ha.
static func autori(modelli: Array) -> Array:
	var visti: Dictionary = {}
	for m in modelli:
		var a := autore_di(String(m))
		if a != "":
			visti[a] = true
	var out: Array = visti.keys()
	out.sort()
	return out

## I modelli di quell'autore, in ordine. Con autore vuoto: tutti (provider a nome semplice).
static func modelli_di(autore: String, modelli: Array) -> Array:
	var out: Array = []
	for m in modelli:
		if autore == "" or autore_di(String(m)) == autore:
			out.append(String(m))
	out.sort()
	return out

func modello_ricordato(idx: int) -> String:
	return String(Impostazioni.leggi(_chiave_modello(idx), ""))

## Rimette in ogni profilo il modello che l'utente aveva scelto per quel provider.
## Scrive nei profili DIRETTAMENTE: all'avvio il percorso esterno non e' ancora acceso, e
## passare da imposta_modello() manderebbe la scelta sul provider locale.
func applica_modelli_ricordati() -> void:
	for i in profili.size():
		var m := modello_ricordato(i)
		if m != "":
			profili[i]["model"] = m

## L'elenco dei modelli, senza quelli che non sanno scrivere testo. Gli endpoint dei
## provider restituiscono tutto il catalogo — sintesi vocale, immagini, video, embedding —
## e offrirli nel menu significa proporre scelte che non possono funzionare.
## I frammenti da escludere stanno nel profilo del provider (`escludi_modelli`): li conosce
## lui, non il gioco.
static func solo_modelli_testuali(modelli: Array, escludi: Array, pieno: bool = false) -> Array:
	if escludi.is_empty():
		return modelli
	var out: Array = []
	for m in modelli:
		var nome := nome_nudo(String(m), pieno).to_lower()
		var scartare := false
		for pezzo in escludi:
			if nome.contains(String(pezzo).to_lower()):
				scartare = true
				break
		if not scartare:
			out.append(m)
	return out

## I frammenti da escludere dichiarati dal profilo selezionato.
func filtro_modelli() -> Array:
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return []
	return Array(profili[profilo_idx].get("escludi_modelli", []))

## Modello atteso dal provider attivo (per messaggi/verifica).
func modello_atteso() -> String:
	return String(_config_attiva().get("model", "?"))

## Il modello puo' essere scelto senza toccare il JSON: variabile d'ambiente DEI_MODELLO
## (impostata da ./avvia.sh con MODELLO=...). Comodo per provare modelli diversi su M1.
## Vale per Ollama: e' il provider che ./avvia.sh prepara col preflight.
func _applica_override_env() -> void:
	if not OS.has_environment("DEI_MODELLO"):
		return
	var m := OS.get_environment("DEI_MODELLO").strip_edges()
	if m == "":
		return
	for p in profili:
		if bool(p.get("locale", false)):
			p["model"] = m
			return

## Cambia il modello a runtime (usato dal menu a tendina della GUI). Effetto dal turno dopo.
func imposta_modello(nome: String) -> void:
	if nome.strip_edges() == "":
		return
	# Va scritto sul profilo VERO, non su cio' che ritorna _config_attiva(): col gateway
	# acceso quello e' una copia col prefisso d'instradamento, e la modifica si perderebbe.
	# Il prefisso non appartiene al nome del modello: lo rimette il trasporto. Su un provider
	# a nome pieno (OpenRouter) invece la barra e' del nome e non si tocca.
	#
	# QUI C'ERA UN «if provider_esterno»: a motore ancora spento — cioe' ogni volta che si
	# apriva Settings prima di iniziare — la scelta finiva nel profilo di Ollama. Poi il menu
	# si risincronizzava dal profilo vero, rimasto invariato, e la scelta tornava indietro
	# da sola sotto gli occhi di chi l'aveva appena fatta. Il modello appartiene al provider
	# SELEZIONATO, che il motore sia acceso o no.
	var pulito := nome_nudo(nome, nome_pieno())
	if profilo_idx < 0 or profilo_idx >= profili.size():
		return
	profili[profilo_idx]["model"] = pulito
	# Cio' che il client manda dev'essere il nome EFFETTIVO, ricalcolato: senza gateway il
	# nome nudo, col gateway quello col prefisso d'instradamento. Prima si assegnava `nome`
	# cosi' com'era arrivato — e dall'elenco di Google arriva come «models/gemini-3.5-flash»:
	# il profilo teneva il nome pulito e il client ne mandava un altro. Due verita' diverse
	# per la stessa cosa, ed e' il genere di divergenza che si vede solo a valle, in un 404.
	var effettivo := String(_config_attiva().get("model", pulito))
	if _client:
		_client.model = effettivo
	_reg("modello impostato: %s" % effettivo)

## Abilita il percorso LLM reale a runtime sul provider selezionato. Idempotente.
func abilita_reale() -> void:
	mock_mode = false
	if _client == null:
		_inizializza_reale()
	else:
		_riconfigura()

func _inizializza_reale() -> void:
	_client = LLMClient.new()
	add_child(_client)
	var cfg := _config_attiva()
	_client.configura(cfg, _leggi_chiave(cfg))
	_client.logger = Callable(self, "_reg")  # il traffico HTTP finisce nel log di debug
	var id_dei: Array = PantheonManager.pantheon.tutti_gli_id() if PantheonManager.pantheon else []
	_interprete = Interprete.new(id_dei, PantheonManager.pantheon)
	_dio_agente = DioAgente.new()
	var nomi: Array = []
	if PantheonManager.pantheon:
		for d in PantheonManager.pantheon.tutti():
			nomi.append(d.nome)
	_narratore = Narratore.new(nomi)
	_arbitro = Arbitro.new(PantheonManager.pantheon)
	_suggeritore = Suggeritore.new()
	_cronista = Cronista.new()
	_compagno = Compagno.new()

## La chiave API sta fuori dal repo: variabile d'ambiente il cui nome e' in config.
func _leggi_chiave(cfg: Dictionary) -> String:
	var nome_env: String = cfg.get("api_key_env", "")
	if nome_env == "" or not OS.has_environment(nome_env):
		return ""
	return OS.get_environment(nome_env)

func _carica_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_warning("LLMManager: config mancante in %s, uso mock di default." % CONFIG_PATH)
		return {"mock": true}
	var testo := FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed: Variant = JSON.parse_string(testo)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("LLMManager: config JSON non valido in %s" % CONFIG_PATH)
		return {"mock": true}
	return parsed

## Log delle chiamate LLM (percorso reale), per la finestra di debug della GUI.
signal llm_log(riga: String)

func _reg(r: String) -> void:
	llm_log.emit(r)

## Verifica pre-partita del percorso reale: il server risponde? il modello atteso
## (config.model) e' caricato? Ritorna {ok, attivo, modello_presente, modelli, atteso, errore}.
## Non attiva nulla da sola: la GUI decide se procedere o restare sul mock.
func verifica_provider() -> Dictionary:
	if _client == null:
		_inizializza_reale()
	var atteso: String = modello_atteso()
	# Stesso tetto del bottone «Prova il modello»: qui si fa la stessa domanda, e prima
	# questa strada aspettava i 300 secondi del profilo.
	var cfg_prova := _config_prova()
	if not cfg_prova.is_empty():
		_client.configura(cfg_prova, _leggi_chiave(cfg_prova))
	_reg("→ verifica: «%s» su %s (tetto %d s)…" % [atteso, nome_profilo_corrente(), SECONDI_PROVA])
	var r: Dictionary = await _client.elenca_modelli()
	if not r["ok"]:
		_reg("✗ server non raggiungibile: %s" % r["errore"])
		_riconfigura()
		return {"ok": false, "attivo": false, "modello_presente": false, "modelli": [], "atteso": atteso, "errore": r["errore"]}
	var modelli: Array = r["modelli"]
	var presente := _modello_presente(atteso, modelli)
	if presente:
		_reg("✓ server attivo · modello «%s» elencato." % atteso)
	else:
		_reg("✗ modello «%s» non caricato. Disponibili: %s" % [atteso, ", ".join(modelli) if not modelli.is_empty() else "(nessuno)"])

	# ESSERE ELENCATO NON VUOL DIRE FUNZIONARE. Google ha continuato a elencare
	# «gemini-2.0-flash» dopo averlo ritirato: il controllo diceva "disponibile" e poi ogni
	# singola chiamata tornava 404. Il giocatore si trovava una partita muta senza capire
	# perche'. Una richiesta vera da un token costa pochissimo e non lascia dubbi.
	var prova := await _prova_generazione()
	if not prova["ok"]:
		_reg("✗ il modello «%s» e' elencato ma NON risponde: %s" % [atteso, prova["errore"]])
		segna_fallimento(atteso, String(prova["errore"]))
	else:
		_reg("✓ modello «%s» funzionante." % atteso)
		dimentica_fallimento(atteso)
	_riconfigura()   # rimette il tetto della partita: un turno vero puo' durare di piu'
	return {
		"ok": presente and prova["ok"], "attivo": true, "modello_presente": presente,
		"genera": prova["ok"], "errore_genera": prova["errore"],
		"modelli": modelli, "atteso": atteso, "errore": "",
	}

## La prova del nove: una generazione minima. Se il modello e' ritirato, dietro un piano
## sbagliato o senza quota, si scopre QUI e non a meta' partita.
func _prova_generazione() -> Dictionary:
	var r = await _client.chat([{"role": "user", "content": "ok"}], {"max_tokens": 1, "temperature": 0.0})
	if typeof(r) == TYPE_DICTIONARY and r.get("ok", false):
		return {"ok": true, "errore": ""}
	var motivo := "risposta non valida"
	if typeof(r) == TYPE_DICTIONARY:
		motivo = String(r.get("error", r.get("errore", motivo)))
	return {"ok": false, "errore": motivo.substr(0, 200)}

## Confronto tollerante: ignora il tag (":latest") E il prefisso di provider usato dal
## Gateway ("mistral/mistral-small-latest" == "mistral-small-latest"). Senza questo, col
## Gateway attivo il modello richiesto risultava assente e ne veniva scelto un altro.
func _modello_presente(atteso: String, modelli: Array) -> bool:
	var norm_atteso := _senza_prefisso(atteso)
	for m in modelli:
		if _senza_prefisso(String(m)) == norm_atteso:
			return true
	if atteso in modelli:
		return true
	var base := norm_atteso.get_slice(":", 0)
	for m in modelli:
		if _senza_prefisso(String(m)).get_slice(":", 0) == base:
			return true
	return false

## "mistral/mistral-small-latest" -> "mistral-small-latest" (il prefisso e' l'instradamento
## del Gateway, non fa parte del nome del modello presso il provider).
func _senza_prefisso(nome: String) -> String:
	return nome.get_slice("/", 1) if nome.find("/") != -1 else nome

func interpreta(testo_libero: String, seed: int = 0) -> Dictionary:
	if mock_mode:
		await get_tree().process_frame
		return _mock.interpreta(testo_libero)
	_reg("→ Interprete: «%s»" % testo_libero.substr(0, 70))
	var t0 := Time.get_ticks_msec()
	var env := await _interprete.interpreta(testo_libero, _client.chat, seed)
	_reg("← Interprete: tag %s · %s · %d ms" % [str(env.get("tag", [])), env.get("plausibilita", "?"), Time.get_ticks_msec() - t0])
	return env

## Aggiorna il riassunto rotolante della vicenda (memoria condivisa da tutti gli agenti).
## In mock ritorna "" (nessuna cronaca: i test restano deterministici). Sanifica i nomi
## divini: la cronaca finisce anche in agenti player-facing (Omero, Suggeritore).
func aggiorna_cronaca(contesto: Dictionary, seed: int = 0) -> String:
	if mock_mode:
		return ""
	_reg("→ Cronista: aggiorno la memoria della vicenda…")
	var t0 := Time.get_ticks_msec()
	var testo := await _cronista.aggiorna(contesto, _client.chat, seed)
	if testo != "" and _narratore and _narratore.nomina_un_dio(testo):
		testo = _narratore.redigi(testo)  # invariante: la memoria non tradisce i nomi
	_reg("← Cronista: %d caratteri · %d ms" % [testo.length(), Time.get_ticks_msec() - t0])
	return testo

## Secondo parere dedicato sulla plausibilità (anacronismi che la lista non prevede).
## In mock ritorna "" (i test restano deterministici). "" = nessun cambiamento.
func verifica_plausibilita(testo_libero: String, seed: int = 0) -> String:
	if mock_mode:
		return ""
	_reg("→ Vaglio: questa mossa appartiene al mondo dell'Odissea?")
	var t0 := Time.get_ticks_msec()
	var classe := await _interprete.verifica_plausibilita(testo_libero, _client.chat, seed)
	_reg("← Vaglio: %s · %d ms" % [classe if classe != "" else "(incerto)", Time.get_ticks_msec() - t0])
	return classe

## La battuta di un compagno di ciurma. In mock ne usa una dai suoi esempi (deterministico
## e senza rete), cosi' la chat della ciurma vive anche a LLM spento.
func parla_compagno(c: Dictionary, contesto: Dictionary, seed: int = 0) -> String:
	if mock_mode:
		var esempi: Array = c.get("esempi", [])
		return String(esempi[0]) if not esempi.is_empty() else "…"
	var nome := String(c.get("nome", "?"))
	_reg("→ %s (ciurma) risponde…" % nome)
	var t0 := Time.get_ticks_msec()
	var battuta := await _compagno.parla(c, contesto, _client.chat, seed)
	_reg("← %s: «%s» · %d ms" % [nome, battuta, Time.get_ticks_msec() - t0])
	return battuta

## Ibrido: riconoscimento LLM del dio invocato quando il deterministico non trova nulla.
## In mock ritorna "" (i test restano deterministici: il risveglio nei test non dipende
## dall'LLM). In reale delega all'Interprete con output vincolato agli id del pantheon.
func identifica_dio(testo_libero: String, seed: int = 0) -> String:
	if mock_mode:
		return ""
	_reg("→ Ricognizione LLM del dio invocato (anche parafrasi)…")
	var t0 := Time.get_ticks_msec()
	var id := await _interprete.identifica_dio(testo_libero, _client.chat, seed)
	_reg("← dio riconosciuto: %s · %d ms" % [id if id != "" else "(nessuno)", Time.get_ticks_msec() - t0])
	return id

func proposta_dio(dio: Dio, contesto: Dictionary, seed: int = 0) -> Dictionary:
	if mock_mode:
		await get_tree().process_frame
		return _mock.proposta_dio(dio, contesto)
	_reg("→ %s medita…" % dio.nome)
	var t0 := Time.get_ticks_msec()
	var p := await _dio_agente.proponi(dio, contesto, _client.chat, seed)
	_reg("← %s: %s «%s» · %d ms" % [dio.nome, p.get("registro", "?"), p.get("dice", ""), Time.get_ticks_msec() - t0])
	return p

func verdetto_arbitro(proposte: Array, seed: int = 0) -> Dictionary:
	if mock_mode:
		await get_tree().process_frame
		return _mock.verdetto_arbitro(proposte)
	_reg("→ Zeus arbitra (%d proposte)…" % proposte.size())
	var t0 := Time.get_ticks_msec()
	var v := await _arbitro.decidi(proposte, _client.chat, seed)
	_reg("← Zeus: %s → %s · %d ms" % [v.get("attore", "?"), v.get("registro", "?"), Time.get_ticks_msec() - t0])
	return v

## 3 spunti d'azione per il giocatore, generati sul contesto della scena. In mock (e come
## fallback) usa spunti generici. Sanitizza: nessuno spunto puo' nominare un dio.
func suggerisci(contesto: Dictionary = {}, seed: int = 0) -> Array:
	if mock_mode:
		return []   # niente appigli inventati: chi chiama usa quelli della tappa
	_reg("→ Suggeritore: 3 spunti…")
	var t0 := Time.get_ticks_msec()
	var sp := await _suggeritore.suggerisci(contesto, _client.chat, seed)
	for s in sp:
		if _narratore and _narratore.nomina_un_dio(s["testo"]):
			s["testo"] = _narratore.redigi(s["testo"])  # invariante: mai un nome di dio
	if sp.is_empty():
		sp = []
	_reg("← Suggeritore: %d spunti · %d ms" % [sp.size(), Time.get_ticks_msec() - t0])
	return sp

## Narrazione E tre spunti in UNA chiamata (vedi Narratore.narra_e_suggerisci): sotto il
## free tier ogni chiamata costa ~1 secondo di pavimento, e questa ne toglie una a ogni
## turno. Se il modello non produce spunti usabili, si ripiega su quelli generici: in UI
## ce ne sono sempre tre.
func narrazione_e_spunti(contesto: Dictionary, seed: int = 0) -> Dictionary:
	if mock_mode:
		await get_tree().process_frame
		return {"narrazione": _mock.narrazione_omero(contesto), "spunti": []}
	_reg("→ Omero narra (e propone gli spunti)…")
	var t0 := Time.get_ticks_msec()
	var r := await _narratore.narra_e_suggerisci(contesto, _client.chat, seed)
	var spunti: Array = r.get("spunti", [])
	for s in spunti:
		if _narratore.nomina_un_dio(s["testo"]):
			s["testo"] = _narratore.redigi(s["testo"])  # invariante: mai un nome di dio
	if spunti.is_empty():
		spunti = []
	_reg("← Omero + %d spunti · %d ms" % [spunti.size(), Time.get_ticks_msec() - t0])
	return {"narrazione": String(r.get("narrazione", "")), "spunti": spunti}

func narrazione_omero(contesto: Dictionary, seed: int = 0) -> String:
	if mock_mode:
		await get_tree().process_frame
		# Il CONGEDO in mock ritorna "": chi chiama usa il commiato scritto nei dati, che
		# non e' un ripiego di fortuna ma il testo definitivo per il motore simulato. Stessa
		# regola degli spunti — il finto non inventa contenuti, li lascia ai dati.
		if contesto.has("congedo"):
			return ""
		return _mock.narrazione_omero(contesto)
	_reg("→ Omero narra…")
	var t0 := Time.get_ticks_msec()
	var testo := await _narratore.narra(contesto, _client.chat, seed)
	_reg("← Omero · %d ms" % (Time.get_ticks_msec() - t0))
	return testo
