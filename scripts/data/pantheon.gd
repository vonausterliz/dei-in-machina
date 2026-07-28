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

func numero_dei() -> int:
	return _dei.size()
