extends Node

## Autoload. Layer LLM provider-agnostico (formato chat-completions OpenAI).
## Fase 0/1: solo il mock e' implementato (senza rete); il client HTTP reale
## verso Ollama/Mistral e' lo spike della fase 1 (vedi roadmap, design sez. 13).
## Chiamate pensate come coroutine fin da subito, anche se il mock e' sincrono:
## quando arrivera' il provider reale, i punti di chiamata non cambieranno.

const CONFIG_PATH := "res://config/llm_config.json"

var mock_mode: bool = true
var config: Dictionary = {}
var _mock := LLMMock.new()

func _ready() -> void:
	config = _carica_config()
	mock_mode = config.get("mock", true)

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

func interpreta(testo_libero: String) -> Dictionary:
	await get_tree().process_frame
	if mock_mode:
		return _mock.interpreta(testo_libero)
	push_error("LLMManager: provider reale non ancora implementato (fase 1).")
	return {}

func proposta_dio(dio: Dio, contesto: Dictionary) -> Dictionary:
	await get_tree().process_frame
	if mock_mode:
		return _mock.proposta_dio(dio, contesto)
	push_error("LLMManager: provider reale non ancora implementato (fase 1).")
	return {}

func verdetto_arbitro(proposte: Array) -> Dictionary:
	await get_tree().process_frame
	if mock_mode:
		return _mock.verdetto_arbitro(proposte)
	push_error("LLMManager: provider reale non ancora implementato (fase 1).")
	return {}

func narrazione_omero(contesto: Dictionary) -> String:
	await get_tree().process_frame
	if mock_mode:
		return _mock.narrazione_omero(contesto)
	push_error("LLMManager: provider reale non ancora implementato (fase 1).")
	return ""
