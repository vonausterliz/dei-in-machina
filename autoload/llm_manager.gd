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
		return profili_esterni[provider_esterno_idx]
	return config

## Carica i profili esterni da config/providers/*.json (ordinati per nome file). Ogni
## profilo ha almeno base_url e model; "nome" è l'etichetta mostrata nel menù.
func _carica_profili_esterni() -> Array:
	var out: Array = []
	var dir := DirAccess.open(PROVIDERS_DIR)
	if dir == null:
		return out
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.to_lower().ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROVIDERS_DIR + "/" + f))
		if typeof(parsed) == TYPE_DICTIONARY and parsed.has("base_url") and parsed.has("model"):
			if not parsed.has("nome"):
				parsed["nome"] = f
			out.append(parsed)
	return out

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
	if profili_esterni.is_empty():
		return false
	var idx := clampi(provider_esterno_idx, 0, profili_esterni.size() - 1)
	var cfg: Dictionary = profili_esterni[idx]
	if String(cfg.get("api_key_env", "")) == "":
		return true
	return _leggi_chiave(cfg) != ""

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
	_config_attiva()["model"] = nome
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
		_reg("✓ server attivo · modello «%s» disponibile." % atteso)
	else:
		_reg("✗ modello «%s» non caricato. Disponibili: %s" % [atteso, ", ".join(modelli) if not modelli.is_empty() else "(nessuno)"])
	return {"ok": presente, "attivo": true, "modello_presente": presente, "modelli": modelli, "atteso": atteso, "errore": ""}

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
