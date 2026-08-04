class_name DioAgente
extends RefCounted

## Dio-agente: data la situazione (envelope) e il suo stato (favore/ira), un dio decide
## in carattere COME reagire — registro + intensita' + una battuta. La REGOLA (trigger,
## delta) sta altrove: qui l'LLM mette solo voce e capriccio.
##
## Il registro proposto e' vincolato ai registri ammessi del dio (contratto dati): se
## l'LLM ne inventa uno, o l'output e' malformato, si ripiega su "silenzio" (inerte).
## chat_fn iniettabile: Callable(messaggi, opzioni) -> {ok, content, error}.

const PROMPT_SYSTEM := "res://prompts/dio_agente_system.txt"
const PROMPT_GUARDRAIL := "res://prompts/guardrail_anti_assistente.txt"
const PROMPT_MONDO := "res://prompts/mondo.txt"

var _template: String = ""
var _guardrail: String = ""
var _mondo: String = ""
var _cache_prompt: Dictionary = {}  # id dio -> system prompt

func _init() -> void:
	_template = _leggi(PROMPT_SYSTEM)
	_guardrail = _leggi(PROMPT_GUARDRAIL)
	_mondo = _leggi(PROMPT_MONDO)

func _leggi(path: String) -> String:
	if not FileAccess.file_exists(path):
		push_error("DioAgente: prompt mancante: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)

func system_prompt(dio: Dio) -> String:
	if _cache_prompt.has(dio.id):
		return _cache_prompt[dio.id]
	var sp := _template
	sp = sp.replace("{{GUARDRAIL}}", _guardrail)
	sp = sp.replace("{{MONDO}}", _mondo)
	sp = sp.replace("{{NOME}}", dio.nome)
	sp = sp.replace("{{DOMINIO}}", dio.dominio)
	sp = sp.replace("{{AGENDA}}", dio.agenda)
	sp = sp.replace("{{VOCE}}", dio.voce)
	sp = sp.replace("{{TEMPERAMENTO}}", dio.temperamento)
	sp = sp.replace("{{ANTI_PATTERN}}", dio.anti_pattern)
	sp = sp.replace("{{ESEMPI}}", "\n".join(dio.esempi_voce))
	sp = sp.replace("{{ANTEFATTO}}", dio.antefatto)
	sp = sp.replace("{{REGISTRI}}", ", ".join(dio.registri))
	_cache_prompt[dio.id] = sp
	return sp

func costruisci_messaggi(dio: Dio, contesto: Dictionary) -> Array:
	var env: Dictionary = contesto.get("envelope", {})
	var cronaca: String = contesto.get("cronaca", "")
	var memoria := ("La vicenda finora: %s\n\n" % cronaca) if cronaca != "" else ""
	var situazione := memoria + "Ulisse ha appena: %s\n(tag: %s, tono: %s, intensita: %s)\nIl tuo animo verso di lui ora: favore %s, ira %s." % [
		env.get("sintesi", "qualcosa"), env.get("tag", []), env.get("tono", "?"),
		env.get("intensita", 1), contesto.get("favore", 0), contesto.get("ira", 0),
	]
	# Cio' che Ulisse ha mormorato ai suoi uomini fra un'azione e l'altra. Un dio ha
	# orecchie: un proposito detto a voce pesa quanto un gesto, a volte di piu'.
	var detto: String = contesto.get("detto_ai_compagni", "")
	if detto != "":
		situazione += "\n\nPoco fa, ai suoi compagni, ha detto: «%s»" % detto
	# Il suo taccuino: cio' che ha gia' voluto, e come e' finita. E' la differenza fra una
	# potenza con una storia e un generatore di battute che ricomincia ogni turno da capo.
	var ricordi: Array = contesto.get("memoria", [])
	var riassunto: String = contesto.get("memoria_riassunto", "")
	if not ricordi.is_empty() or riassunto != "":
		situazione += "\n\nQUELLO CHE HAI GIA' FATTO in questo viaggio (lo ricordi bene):"
		if riassunto != "":
			situazione += "\n" + riassunto   # il condensato di cio' che e' piu' lontano
		if not ricordi.is_empty():
			situazione += "\n" + "\n".join(ricordi)
	# Round di replica: il dio vede cosa hanno proposto gli ALTRI dei e puo' ribattere.
	var altri: Array = contesto.get("altri_dei", [])
	if not altri.is_empty():
		var voci: Array[String] = []
		for a in altri:
			voci.append("- %s vuole %s: \"%s\"" % [a.get("nome", "un dio"), a.get("registro", "?"), a.get("dice", "")])
		situazione += "\n\nAltri dei si sono fatti sentire:\n%s\nRibatti in carattere: insisti, rilancia o cambia idea." % "\n".join(voci)
	return [
		{"role": "system", "content": system_prompt(dio)},
		{"role": "user", "content": situazione},
	]

## Ritorna {dio, registro, intensita, dice}. Sempre valido (fallback silenzio).
func proponi(dio: Dio, contesto: Dictionary, chat_fn: Callable, seed: int = 0) -> Dictionary:
	var opzioni := {"temperature": 0.8, "json_mode": true}
	if seed != 0:
		opzioni["seed"] = seed
	var risposta = await chat_fn.call(costruisci_messaggi(dio, contesto), opzioni)
	if typeof(risposta) != TYPE_DICTIONARY or not risposta.get("ok", false):
		return _silenzio(dio)

	var grezzo := Contratto.estrai_json(risposta.get("content", ""))
	if grezzo.is_empty():
		return _silenzio(dio)

	var registro := String(grezzo.get("registro", "silenzio"))
	var intensita: int = clampi(int(grezzo.get("intensita", 1)), 1, 3)
	var dice := String(grezzo.get("dice", "")).strip_edges()
	# Il GESTO: cio' che il dio fa, se la sua volonta' passa. Ripulito qui e non a valle,
	# perche' e' output di un modello: arriva col nome in testa, fra asterischi, o lungo
	# un paragrafo. Se manca, resta "" e la vista mette il ripiego per quel registro.
	var gesto := Gesto.ripulisci(String(grezzo.get("gesto", "")), dio.nome)
	# Vincolo ai registri ammessi: un registro inventato non si applica. Ma la BATTUTA
	# resta: prima si ripiegava su _silenzio(), che azzera anche `dice`, e la voce del dio
	# spariva per un errore di etichetta — nella Vista Olimpo restava solo «si desta.».
	# Agire e parlare sono due cose diverse anche quando il modello sbaglia.
	if registro != "silenzio" and not dio.registri.has(registro):
		return {"dio": dio.id, "registro": "silenzio", "intensita": 1, "dice": dice, "gesto": ""}
	# Col silenzio il gesto si butta: e' la definizione di silenzio (non agisco), e un
	# modello che sceglie "silenzio" e poi descrive un atto sta contraddicendo se stesso.
	return {
		"dio": dio.id, "registro": registro, "intensita": intensita, "dice": dice,
		"gesto": "" if registro == "silenzio" else gesto,
	}

func _silenzio(dio: Dio) -> Dictionary:
	return {"dio": dio.id, "registro": "silenzio", "intensita": 1, "dice": "", "gesto": ""}
