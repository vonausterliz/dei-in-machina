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

var mock_mode: bool = true
var config: Dictionary = {}

var _mock := LLMMock.new()
var _client: LLMClient = null
var _interprete: Interprete = null

func _ready() -> void:
	config = _carica_config()
	mock_mode = config.get("mock", true)
	if not mock_mode:
		_inizializza_reale()

func _inizializza_reale() -> void:
	_client = LLMClient.new()
	add_child(_client)
	_client.configura(config, _leggi_chiave(config))
	var id_dei: Array = PantheonManager.pantheon.tutti_gli_id() if PantheonManager.pantheon else []
	_interprete = Interprete.new(id_dei)

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

func interpreta(testo_libero: String, seed: int = 0) -> Dictionary:
	if mock_mode:
		await get_tree().process_frame
		return _mock.interpreta(testo_libero)
	return await _interprete.interpreta(testo_libero, _client.chat, seed)

func proposta_dio(dio: Dio, contesto: Dictionary) -> Dictionary:
	await get_tree().process_frame
	if mock_mode:
		return _mock.proposta_dio(dio, contesto)
	push_error("LLMManager: dei-agenti reali non ancora implementati (fase 3).")
	return _mock.proposta_dio(dio, contesto)

func verdetto_arbitro(proposte: Array) -> Dictionary:
	await get_tree().process_frame
	if mock_mode:
		return _mock.verdetto_arbitro(proposte)
	push_error("LLMManager: Arbitro reale non ancora implementato (fase 3).")
	return _mock.verdetto_arbitro(proposte)

func narrazione_omero(contesto: Dictionary) -> String:
	await get_tree().process_frame
	if mock_mode:
		return _mock.narrazione_omero(contesto)
	push_error("LLMManager: Omero reale non ancora implementato (fase 3).")
	return _mock.narrazione_omero(contesto)
