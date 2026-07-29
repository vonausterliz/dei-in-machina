class_name Bilanciamento
extends RefCounted

## Valori-seme del gioco letti da data/bilanciamento.json, fuori dal codice: tarare il
## gioco (probabilita', soglie, quanto pesa un castigo) non deve richiedere di toccare
## GDScript. Se il file manca o una voce non c'e', si usa il valore di ripiego passato
## alla chiamata: il gioco non si rompe mai per una preferenza assente.
##
## Uso:  Bilanciamento.val("coalizioni/prob_coalizione", 0.4)

const PERCORSO := "res://data/bilanciamento.json"

static var _dati: Dictionary = {}
static var _caricato := false

static func _carica() -> void:
	if _caricato:
		return
	_caricato = true
	if not FileAccess.file_exists(PERCORSO):
		push_warning("Bilanciamento: manca %s, uso i valori di ripiego." % PERCORSO)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO))
	if typeof(parsed) == TYPE_DICTIONARY:
		_dati = parsed
	else:
		push_error("Bilanciamento: JSON non valido in %s" % PERCORSO)

## Valore per percorso "sezione/chiave" (o "sezione/sotto/chiave").
static func val(percorso: String, ripiego: Variant) -> Variant:
	_carica()
	var nodo: Variant = _dati
	for pezzo in percorso.split("/"):
		if typeof(nodo) != TYPE_DICTIONARY or not nodo.has(pezzo):
			return ripiego
		nodo = nodo[pezzo]
	return nodo

static func num(percorso: String, ripiego: float) -> float:
	return float(val(percorso, ripiego))

static func intero(percorso: String, ripiego: int) -> int:
	return int(val(percorso, ripiego))
