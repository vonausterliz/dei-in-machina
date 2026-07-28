class_name Contratto
extends RefCounted

## Fonte di verita' unica del Contratto dell'Interprete (docs/contratto_interprete.md v0.1).
## Vocabolario tag chiuso + enum + validazione envelope + parsing JSON difensivo.
## La usano SIA il validatore dei dati (tools/validator) SIA l'Interprete a runtime
## (scripts/llm/interprete.gd): se parlassero due lingue diverse, gli dei non si
## sveglierebbero mai. Un'unica costante evita la deriva.

## Vocabolario chiuso dei tag (docs/contratto_interprete.md sez. 1).
const TAG_VOCABOLARIO: Array[String] = [
	# Condotta
	"tracotanza", "vanto", "astuzia", "inganno", "misura", "coraggio", "violenza", "empieta", "rispetto",
	# Atti verso il divino o l'altro
	"preghiera", "supplica", "sacrificio", "xenia", "giuramento", "evocazione",
	# Pulsioni e stati
	"desiderio", "curiosita", "nostalgia", "stanchezza", "fame", "disperazione", "fiducia", "sospetto",
	# Scelte pratiche
	"intrusione", "rotta", "sfida", "fuga",
]

## Tag il cui falso positivo puo' far scattare un castigo divino: parsimonia
## (contratto sez. 4, regola 4). Qui solo documentati; la parsimonia vive nel prompt.
const TAG_PUNITIVI: Array[String] = ["tracotanza", "empieta", "violenza"]

const PLAUSIBILITA_ENUM: Array[String] = ["in_mondo", "assurdo_diegetico", "anacronistico", "meta_nonsenso"]
const TIPO_ENUM: Array[String] = ["parola", "azione", "preghiera", "rituale", "movimento"]

const INTENSITA_MIN := 1
const INTENSITA_MAX := 3

## Envelope di ripiego, sempre valido e inerte: nessun tag, nessun dio svegliato.
## Usato quando l'LLM produce output irrecuperabile (contratto: "nel dubbio, non taggare").
static func envelope_fallback(sintesi: String = "") -> Dictionary:
	return {
		"plausibilita": "in_mondo",
		"tipo": "azione",
		"tag": [],
		"dio_invocato": null,
		"bersaglio": null,
		"tono": "neutro",
		"intensita": 1,
		"sintesi": sintesi,
	}

## Valida un envelope contro il contratto. Ritorna {ok: bool, errori: Array[String]}.
## `id_dei_validi`: se fornito (non vuoto), controlla che dio_invocato sia un id noto.
static func valida_envelope(envelope: Dictionary, id_dei_validi: Array = []) -> Dictionary:
	var errori: Array[String] = []

	if not envelope.has("plausibilita") or not PLAUSIBILITA_ENUM.has(envelope["plausibilita"]):
		errori.append("plausibilita '%s' non valida" % envelope.get("plausibilita", "<assente>"))
	if not envelope.has("tipo") or not TIPO_ENUM.has(envelope["tipo"]):
		errori.append("tipo '%s' non valido" % envelope.get("tipo", "<assente>"))

	var tag = envelope.get("tag", [])
	if typeof(tag) != TYPE_ARRAY:
		errori.append("tag deve essere un array")
	else:
		for t in tag:
			if not TAG_VOCABOLARIO.has(t):
				errori.append("tag '%s' fuori dal vocabolario chiuso" % t)

	var intensita = envelope.get("intensita", null)
	if typeof(intensita) not in [TYPE_INT, TYPE_FLOAT] or int(intensita) < INTENSITA_MIN or int(intensita) > INTENSITA_MAX:
		errori.append("intensita '%s' fuori da [%d, %d]" % [intensita, INTENSITA_MIN, INTENSITA_MAX])

	var dio_invocato = envelope.get("dio_invocato", null)
	if dio_invocato != null and not id_dei_validi.is_empty() and not id_dei_validi.has(dio_invocato):
		errori.append("dio_invocato '%s' non e' un id noto" % dio_invocato)

	# Regola 5 del contratto: se plausibilita != in_mondo, di norma tag vuoti.
	if envelope.get("plausibilita", "") != "in_mondo" and typeof(tag) == TYPE_ARRAY and tag.size() > 0:
		errori.append("plausibilita != in_mondo ma tag non vuoti (regola 5)")

	return {"ok": errori.is_empty(), "errori": errori}

## Normalizza un envelope grezzo dall'LLM riempiendo i campi mancanti coi default
## e coercendo i tipi ovvi. Non inventa tag: campi ignoti -> default inerti.
static func normalizza(grezzo: Dictionary) -> Dictionary:
	var e := envelope_fallback()
	for chiave in e.keys():
		if grezzo.has(chiave) and grezzo[chiave] != null:
			e[chiave] = grezzo[chiave]
	# dio_invocato e bersaglio possono essere legittimamente null.
	# dio_invocato deve combaciare con un id del pantheon (minuscolo): un modello
	# che scrive "Atena" intende "atena". Normalizziamo il case (JSON difensivo);
	# bersaglio invece e' testo libero, non lo tocchiamo.
	var dio_invocato = grezzo.get("dio_invocato", null)
	if typeof(dio_invocato) == TYPE_STRING and dio_invocato != "":
		e["dio_invocato"] = String(dio_invocato).to_lower()
	else:
		e["dio_invocato"] = null
	e["bersaglio"] = grezzo.get("bersaglio", null)
	if typeof(e["intensita"]) == TYPE_FLOAT:
		e["intensita"] = int(e["intensita"])
	var tag_norm: Array = []
	if typeof(e.get("tag")) == TYPE_ARRAY:
		for t in e["tag"]:
			tag_norm.append(String(t))
	e["tag"] = tag_norm
	return e

## Parsing JSON difensivo: estrae il primo oggetto JSON da un testo che potrebbe
## contenere rumore attorno (fence markdown ```json, blocchi <think> dei modelli
## reasoning, testo prima/dopo). Ritorna un Dictionary, o {} se irrecuperabile.
static func estrai_json(testo: String) -> Dictionary:
	if testo.strip_edges() == "":
		return {}
	var pulito := testo
	# Rimuovi i blocchi di ragionamento tipo <think>...</think> (deepseek-r1 & co.)
	var re_think := RegEx.new()
	re_think.compile("(?s)<think>.*?</think>")
	pulito = re_think.sub(pulito, "", true)
	# Prova diretta
	var diretto: Variant = _prova_parse(pulito)
	if typeof(diretto) == TYPE_DICTIONARY:
		return diretto
	# Estrai la sottostringa dal primo '{' bilanciato all'ultimo '}'
	var inizio := pulito.find("{")
	var fine := pulito.rfind("}")
	if inizio != -1 and fine != -1 and fine > inizio:
		var candidato := pulito.substr(inizio, fine - inizio + 1)
		var parsed: Variant = _prova_parse(candidato)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}

## Parse che NON logga un errore di engine sul fallimento (JSON.new().parse()
## ritorna un codice invece di push_error, a differenza di JSON.parse_string).
static func _prova_parse(testo: String) -> Variant:
	var json := JSON.new()
	if json.parse(testo) == OK and typeof(json.data) == TYPE_DICTIONARY:
		return json.data
	return null

## Descrizione testuale del vocabolario chiuso, da iniettare nel prompt dell'Interprete
## cosi' che il modello conosca esattamente i tag ammessi (una sola fonte).
static func vocabolario_per_prompt() -> String:
	return ", ".join(TAG_VOCABOLARIO)
