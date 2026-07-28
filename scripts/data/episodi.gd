class_name Episodi
extends RefCounted

## Data layer statico delle tappe: carica e indicizza data/episodi.json, in ordine.

var meta: Dictionary = {}
var _ordine: Array[String] = []
var _per_id: Dictionary = {}  # id -> Episodio

static func carica(path: String) -> Episodi:
	var e := Episodi.new()
	if not FileAccess.file_exists(path):
		push_error("Episodi: file non trovato: %s" % path)
		return e
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Episodi: JSON non valido: %s" % path)
		return e
	e.meta = parsed.get("_meta", {})
	for voce in parsed.get("episodi", []):
		var ep := Episodio.from_dict(voce)
		if ep.id == "":
			continue
		e._ordine.append(ep.id)
		e._per_id[ep.id] = ep
	return e

func ordine() -> Array[String]:
	return _ordine.duplicate()

func get_episodio(id: String) -> Episodio:
	return _per_id.get(id, null)

func primo() -> String:
	return _ordine[0] if not _ordine.is_empty() else ""

## L'id della tappa successiva a `id`, o "" se e' l'ultima.
func successivo(id: String) -> String:
	var i := _ordine.find(id)
	if i == -1 or i + 1 >= _ordine.size():
		return ""
	return _ordine[i + 1]

func numero() -> int:
	return _ordine.size()
