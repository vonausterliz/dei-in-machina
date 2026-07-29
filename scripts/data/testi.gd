class_name Testi
extends RefCounted

## Tutte le stringhe mostrate all'utente, fuori dal codice (data/testi/<codice>.json).
## Per tradurre il gioco: copiare it.json in en.json e tradurre i valori — niente
## GDScript da toccare.
##
## Uso:  Testi.s("gioco/agisci")            -> "Agisci"
##       Testi.s("gioco/fine", ["morte"])   -> "— FINE: morte —"
##
## Se una chiave manca, ritorna la chiave stessa: si vede subito cosa non e' tradotto,
## invece di mostrare una stringa vuota.

const CARTELLA := "res://data/testi"
const PREDEFINITA := "it"

static var _codice := ""
static var _dati: Dictionary = {}

static func usa(codice: String = PREDEFINITA) -> void:
	if _codice == codice and not _dati.is_empty():
		return
	var percorso := "%s/%s.json" % [CARTELLA, codice]
	if not FileAccess.file_exists(percorso):
		push_warning("Testi: manca %s, uso '%s'" % [percorso, PREDEFINITA])
		if codice != PREDEFINITA:
			usa(PREDEFINITA)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(percorso))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Testi: JSON non valido in %s" % percorso)
		return
	_dati = parsed
	_codice = codice

## Stringa per percorso "sezione/chiave", con eventuali sostituzioni (%s, %d).
static func s(percorso: String, argomenti: Array = []) -> String:
	if _dati.is_empty():
		usa(PREDEFINITA)
	var nodo: Variant = _dati
	for pezzo in percorso.split("/"):
		if typeof(nodo) != TYPE_DICTIONARY or not nodo.has(pezzo):
			push_warning("Testi: chiave mancante '%s'" % percorso)
			return percorso
		nodo = nodo[pezzo]
	var testo := String(nodo)
	return testo % argomenti if not argomenti.is_empty() else testo

static func codice() -> String:
	if _dati.is_empty():
		usa(PREDEFINITA)
	return _codice
