class_name Pantheon
extends RefCounted

## Data layer statico: carica e indicizza data/pantheon.json.

var meta: Dictionary = {}
var _dei: Dictionary = {}  # id (String) -> Dio

static func carica(path: String) -> Pantheon:
	var p := Pantheon.new()
	if not FileAccess.file_exists(path):
		push_error("Pantheon: file non trovato: %s" % path)
		return p
	var testo := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(testo)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Pantheon: JSON non valido: %s" % path)
		return p
	var d: Dictionary = parsed
	p.meta = d.get("_meta", {})
	for voce in d.get("dei", []):
		var dio := Dio.from_dict(voce)
		if dio.id == "":
			push_warning("Pantheon: voce senza id ignorata.")
			continue
		p._dei[dio.id] = dio
	return p

func get_dio(id: String) -> Dio:
	return _dei.get(id, null)

func ha(id: String) -> bool:
	return _dei.has(id)

func tutti() -> Array[Dio]:
	var out: Array[Dio] = []
	for id in _dei.keys():
		out.append(_dei[id])
	return out

func tutti_gli_id() -> Array[String]:
	var out: Array[String] = []
	for id in _dei.keys():
		out.append(id)
	return out

func dei_attivi() -> Array[Dio]:
	var out: Array[Dio] = []
	for dio in tutti():
		if dio.attivo:
			out.append(dio)
	return out

## Tutti i dei locali legati a un episodio (per accenderli all'ingresso della tappa).
func locali_di_episodio(episodio: String) -> Array[Dio]:
	var out: Array[Dio] = []
	for dio in tutti():
		if dio.fascia == "locale" and dio.episodio != null and String(dio.episodio) == episodio:
			out.append(dio)
	return out

## Riporta tutti i locali a spenti (attivo=false). Usato all'inizio di una nuova partita
## perche' l'accensione delle tappe muta 'attivo' in memoria.
func spegni_locali() -> void:
	for dio in tutti():
		if dio.fascia == "locale":
			dio.attivo = false

func numero_dei() -> int:
	return _dei.size()

## Dei "in ascolto" questo turno: attivi e nella condizione di poter reagire.
## Persistente = sempre in ascolto; locale = solo quando si e' nel suo episodio.
## 'attivo' e' l'interruttore di rollout (stadio 1 = solo i persistenti attivi).
func eleggibili(episodio_corrente: String) -> Array[String]:
	var out: Array[String] = []
	for dio in tutti():
		if not dio.attivo:
			continue
		if dio.fascia == "persistente":
			out.append(dio.id)
		elif dio.fascia == "locale" and dio.episodio != null and String(dio.episodio) == episodio_corrente:
			out.append(dio.id)
	return out

## RISVEGLIO (macchina_del_turno.mermaid): tra gli eleggibili, chi si sveglia per
## via dei TRIGGER. Regola deterministica (GDScript), cuore del "nascosto ma leale":
## stessa azione -> stessi tag -> stessi dei svegliati. Un dio si sveglia se
##  - un suo trigger_azione e' tra i tag dell'envelope, OPPURE
##  - un suo trigger_evento e' tra gli eventi di mondo di questo turno, OPPURE
##  - e' il dio_invocato (Ulisse lo chiama per nome).
##
## NOTA DI DESIGN: il testo dice i persistenti "valutati ogni turno", ma la coerenza
## "vive nel trigger" e il diagramma gatea il risveglio sui trigger. Scelta: risveglio
## gated dai trigger (un persistente non-innescato resta silente), cosi' il segnale e'
## deducibile. L'esempio in stato_partita.json (svegli = tutti i persistenti) e' trattato
## come illustrativo, non normativo. Vedi STATO_LAVORI.md.
func risveglio(envelope: Dictionary, eventi: Array, episodio_corrente: String) -> Array[String]:
	var tag: Array = envelope.get("tag", [])
	var dio_invocato: Variant = envelope.get("dio_invocato", null)
	var out: Array[String] = []
	for id in eleggibili(episodio_corrente):
		var dio := get_dio(id)
		if _combacia(dio.trigger_azione, tag) \
				or _combacia(dio.trigger_evento, eventi) \
				or (dio_invocato != null and String(dio_invocato) == id):
			out.append(id)
	return out

func _combacia(triggers: Array, presenti: Array) -> bool:
	for t in triggers:
		if presenti.has(t):
			return true
	return false

## Risolve un riferimento a un dio dentro il testo libero — anche ALLUSIVO
## ("il capo dell'olimpo" -> zeus, "signore dei mari" -> poseidone) — cercando nome
## ed epiteti come sottostringhe. Ritorna l'id del dio, o "" se nessuno.
## Deterministico (GDScript): l'allusione la scioglie una regola, non l'LLM.
## Longest-match: se piu' epiteti combaciano, vince il piu' lungo (piu' specifico),
## cosi' "figlia di zeus" -> atena batte "zeus" -> zeus.
func risolvi_invocato(testo: String) -> String:
	var t := _normalizza_testo(testo)
	if t == "":
		return ""
	var best_id := ""
	var best_len := 0
	for dio in tutti():
		var alias_list: Array[String] = dio.epiteti.duplicate()
		if not alias_list.has(dio.nome):
			alias_list.append(dio.nome)
		for alias in alias_list:
			var a := _normalizza_testo(alias)
			if a.length() > best_len and a != "" and t.find(a) != -1:
				best_len = a.length()
				best_id = dio.id
	return best_id

## Minuscolo + accenti rimossi, per un confronto robusto sull'input del giocatore.
func _normalizza_testo(s: String) -> String:
	var out := s.to_lower()
	var da := ["à", "á", "è", "é", "ì", "í", "ò", "ó", "ù", "ú"]
	var a := ["a", "a", "e", "e", "i", "i", "o", "o", "u", "u"]
	for i in da.size():
		out = out.replace(da[i], a[i])
	return out
