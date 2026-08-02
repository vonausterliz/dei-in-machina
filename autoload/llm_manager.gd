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
const PROVIDERS_DIR := "res://config/providers"  # profili API esterni (un .json per provider)

var mock_mode: bool = true
var provider_esterno: bool = false   # false = Ollama locale; true = API esterna
## Passare o no dalla coda locale del gateway. Ortogonale al provider scelto.
var usa_gateway := false
## Il profilo del trasporto (config/providers/ con "trasporto": true). Vuoto se assente.
var gateway_cfg: Dictionary = {}
var provider_esterno_idx: int = 0    # quale profilo esterno è selezionato
var config: Dictionary = {}          # profilo locale (Ollama)
var profili_esterni: Array = []      # profili API esterni caricati da config/providers/*.json

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
	profili_esterni = _carica_profili_esterni()
	_applica_override_env()
	mock_mode = config.get("mock", true)
	if not mock_mode:
		_inizializza_reale()

## Profilo del provider attivo (locale o esterno). I punti di chiamata non cambiano: il
## client è provider-agnostico (formato chat-completions OpenAI).
func _config_attiva() -> Dictionary:
	if provider_esterno and provider_esterno_idx >= 0 and provider_esterno_idx < profili_esterni.size():
		return _attraverso_il_gateway(profili_esterni[provider_esterno_idx])
	return config

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
	var cfg := profilo.duplicate(true)
	cfg["base_url"] = gateway_cfg.get("base_url", "http://localhost:8800")
	cfg["chat_path"] = gateway_cfg.get("chat_path", "/v1/chat/completions")
	cfg["models_path"] = gateway_cfg.get("models_path", "/v1/models")
	cfg["timeout_sec"] = gateway_cfg.get("timeout_sec", 300)
	cfg["api_key_env"] = ""
	var provider := String(profilo.get("provider", ""))
	var modello := String(profilo.get("model", ""))
	if provider != "" and not modello.contains("/"):
		cfg["model"] = "%s/%s" % [provider, modello]
	return cfg

## C'e' un gateway configurato (config/providers/ con "trasporto": true)?
func gateway_disponibile() -> bool:
	return not gateway_cfg.is_empty()

## Accende/spegne il passaggio dal gateway senza toccare il provider scelto.
func imposta_gateway(attivo: bool) -> void:
	usa_gateway = attivo
	if _client and provider_esterno:
		var cfg := _config_attiva()
		_client.configura(cfg, _leggi_chiave(cfg))

## Carica config/providers/*.json (ordinati per nome file). Un file con "trasporto": true
## NON e' un provider ma la strada per raggiungerli (il Gateway): finisce in gateway_cfg e
## resta fuori dall'elenco fra cui si sceglie.
func _carica_profili_esterni() -> Array:
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
## config/providers/ faccia scivolare la scelta su un altro provider.
func indice_profilo(nome: String) -> int:
	for i in profili_esterni.size():
		if String(profili_esterni[i].get("nome", "")) == nome:
			return i
	return -1

func nome_profilo_corrente() -> String:
	if provider_esterno_idx < 0 or provider_esterno_idx >= profili_esterni.size():
		return ""
	return String(profili_esterni[provider_esterno_idx].get("nome", ""))

## Almeno un profilo esterno disponibile?
func provider_esterno_disponibile() -> bool:
	return not profili_esterni.is_empty()

## Etichette dei profili esterni, per il menù a tendina.
func nomi_profili_esterni() -> Array:
	var out: Array = []
	for p in profili_esterni:
		out.append(String(p.get("nome", "?")))
	return out

## Seleziona quale profilo esterno usare; se il percorso esterno è già attivo, riconfigura.
func imposta_profilo_esterno(idx: int) -> void:
	if idx < 0 or idx >= profili_esterni.size():
		return
	provider_esterno_idx = idx
	if _client and provider_esterno:
		var cfg := _config_attiva()
		_client.configura(cfg, _leggi_chiave(cfg))

## La chiave API del profilo esterno selezionato è esportata nell'ambiente?
## Un profilo che non dichiara api_key_env non ne ha bisogno (es. il Gateway locale, che
## tiene lui le chiavi, o un endpoint senza autenticazione): in quel caso va sempre bene.
func chiave_esterno_presente() -> bool:
	if usa_gateway and gateway_disponibile():
		return true   # passando dal gateway le chiavi le tiene lui, non il gioco
	if profili_esterni.is_empty():
		return false
	var idx := clampi(provider_esterno_idx, 0, profili_esterni.size() - 1)
	var cfg: Dictionary = profili_esterni[idx]
	if String(cfg.get("api_key_env", "")) == "":
		return true
	return _leggi_chiave(cfg) != ""

## Il modello del profilo SELEZIONATO nel menu (col prefisso se si passa dal gateway).
## Diverso da modello_atteso(): quello dice cosa parte davvero adesso, e all'avvio il
## percorso esterno non e' ancora acceso — in Settings comparirebbe il modello di Ollama
## mentre il menu mostra "Gemini". Qui si mostra cio' che si sta scegliendo.
func modello_del_profilo() -> String:
	if provider_esterno_idx < 0 or provider_esterno_idx >= profili_esterni.size():
		return String(config.get("model", "?"))
	return String(_attraverso_il_gateway(profili_esterni[provider_esterno_idx]).get("model", "?"))

## La configurazione del profilo SELEZIONATO (col trasporto applicato), a prescindere da
## quale motore stia girando adesso. Serve alla prova in Settings: si sta configurando
## Gemini col gioco ancora su simulato, e provare "il provider attivo" proverebbe Ollama.
func config_del_profilo() -> Dictionary:
	if provider_esterno_idx < 0 or provider_esterno_idx >= profili_esterni.size():
		return config
	return _attraverso_il_gateway(profili_esterni[provider_esterno_idx])

## PROVA IL MODELLO CONFIGURATO, senza accendere niente e senza disturbare la partita.
##
## Due domande separate, perche' falliscono in modi diversi e si rimediano in modi diversi:
##  - il server risponde?      (indirizzo sbagliato, gateway spento, rete)
##  - il modello genera?       (nome ritirato, chiave mancante, quota finita)
## Un modello puo' comparire nell'elenco ed essere morto: e' successo due volte in una
## sera con Gemini. Per questo si tenta una generazione vera da un token.
func prova_profilo() -> Dictionary:
	if _client == null:
		_inizializza_reale()
	var cfg := config_del_profilo()
	var atteso := String(cfg.get("model", "?"))
	_client.configura(cfg, _leggi_chiave(cfg))
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
	# La partita non deve accorgersi della prova: il client torna com'era.
	var attuale := _config_attiva()
	_client.configura(attuale, _leggi_chiave(attuale))
	return esito

## Modello atteso dal provider attivo (per messaggi/verifica).
func modello_atteso() -> String:
	return String(_config_attiva().get("model", "?"))

## Il modello puo' essere scelto senza toccare il JSON: variabile d'ambiente DEI_MODELLO
## (impostata da ./avvia.sh con MODELLO=...). Comodo per provare modelli diversi su M1.
func _applica_override_env() -> void:
	if OS.has_environment("DEI_MODELLO"):
		var m := OS.get_environment("DEI_MODELLO").strip_edges()
		if m != "":
			config["model"] = m

## Cambia il modello a runtime (usato dal menu a tendina della GUI). Effetto dal turno dopo.
func imposta_modello(nome: String) -> void:
	if nome.strip_edges() == "":
		return
	# Va scritto sul profilo VERO, non su cio' che ritorna _config_attiva(): col gateway
	# acceso quello e' una copia col prefisso d'instradamento, e la modifica si perderebbe.
	# Il prefisso non appartiene al nome del modello: lo rimette il trasporto.
	var pulito := nome.get_slice("/", 1) if nome.contains("/") else nome
	if provider_esterno and provider_esterno_idx >= 0 and provider_esterno_idx < profili_esterni.size():
		profili_esterni[provider_esterno_idx]["model"] = pulito
	else:
		config["model"] = pulito
	if _client:
		_client.model = nome
	_reg("modello impostato: %s" % nome)

## Abilita il percorso LLM reale a runtime. esterno=false -> Ollama locale; true -> API
## esterna (profilo config_esterno). Riconfigura il client sul provider scelto. Idempotente.
func abilita_reale(esterno: bool = false) -> void:
	mock_mode = false
	provider_esterno = esterno
	if _client == null:
		_inizializza_reale()
	else:
		var cfg := _config_attiva()
		_client.configura(cfg, _leggi_chiave(cfg))

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
func verifica_ollama() -> Dictionary:
	if _client == null:
		_inizializza_reale()
	var atteso: String = modello_atteso()
	_reg("→ verifica: server LLM e modello «%s»…" % atteso)
	var r: Dictionary = await _client.elenca_modelli()
	if not r["ok"]:
		_reg("✗ server non raggiungibile: %s" % r["errore"])
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
	else:
		_reg("✓ modello «%s» funzionante." % atteso)
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
		return Lingua.spunti_generici()
	_reg("→ Suggeritore: 3 spunti…")
	var t0 := Time.get_ticks_msec()
	var sp := await _suggeritore.suggerisci(contesto, _client.chat, seed)
	for s in sp:
		if _narratore and _narratore.nomina_un_dio(s["testo"]):
			s["testo"] = _narratore.redigi(s["testo"])  # invariante: mai un nome di dio
	if sp.is_empty():
		sp = Lingua.spunti_generici()
	_reg("← Suggeritore: %d spunti · %d ms" % [sp.size(), Time.get_ticks_msec() - t0])
	return sp

## Narrazione E tre spunti in UNA chiamata (vedi Narratore.narra_e_suggerisci): sotto il
## free tier ogni chiamata costa ~1 secondo di pavimento, e questa ne toglie una a ogni
## turno. Se il modello non produce spunti usabili, si ripiega su quelli generici: in UI
## ce ne sono sempre tre.
func narrazione_e_spunti(contesto: Dictionary, seed: int = 0) -> Dictionary:
	if mock_mode:
		await get_tree().process_frame
		return {"narrazione": _mock.narrazione_omero(contesto), "spunti": Lingua.spunti_generici()}
	_reg("→ Omero narra (e propone gli spunti)…")
	var t0 := Time.get_ticks_msec()
	var r := await _narratore.narra_e_suggerisci(contesto, _client.chat, seed)
	var spunti: Array = r.get("spunti", [])
	for s in spunti:
		if _narratore.nomina_un_dio(s["testo"]):
			s["testo"] = _narratore.redigi(s["testo"])  # invariante: mai un nome di dio
	if spunti.is_empty():
		spunti = Lingua.spunti_generici()
	_reg("← Omero + %d spunti · %d ms" % [spunti.size(), Time.get_ticks_msec() - t0])
	return {"narrazione": String(r.get("narrazione", "")), "spunti": spunti}

func narrazione_omero(contesto: Dictionary, seed: int = 0) -> String:
	if mock_mode:
		await get_tree().process_frame
		return _mock.narrazione_omero(contesto)
	_reg("→ Omero narra…")
	var t0 := Time.get_ticks_msec()
	var testo := await _narratore.narra(contesto, _client.chat, seed)
	_reg("← Omero · %d ms" % (Time.get_ticks_msec() - t0))
	return testo
