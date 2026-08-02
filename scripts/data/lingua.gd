class_name Lingua
extends RefCounted

## Dati DIPENDENTI DALLA LINGUA usati da regole deterministiche, tenuti fuori dal codice
## (data/lingua/<codice>.json). Sono la parte insidiosa della traduzione: se il gioco
## viene tradotto e questi restano in italiano, i controlli smettono di funzionare in
## silenzio — "gun" non verrebbe riconosciuto come anacronismo, "I pray" come invocazione.
##
## Per aggiungere una lingua: copiare it.json in en.json, tradurre le voci, chiamare
## Lingua.usa("en"). Nessuna riga di codice da toccare.

const CARTELLA := "res://data/lingua"
const PREDEFINITA := "it"

static var _codice := ""
static var _dati: Dictionary = {}

## Carica la lingua indicata (una sola volta; ricarica se cambia il codice).
static func usa(codice: String = PREDEFINITA) -> void:
	if _codice == codice and not _dati.is_empty():
		return
	var percorso := "%s/%s.json" % [CARTELLA, codice]
	if not FileAccess.file_exists(percorso):
		push_warning("Lingua: manca %s, uso '%s'" % [percorso, PREDEFINITA])
		if codice != PREDEFINITA:
			usa(PREDEFINITA)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(percorso))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Lingua: JSON non valido in %s" % percorso)
		return
	_dati = parsed
	_codice = codice

static func codice() -> String:
	_assicura()
	return _codice

static func _assicura() -> void:
	if _dati.is_empty():
		usa(PREDEFINITA)

## Parole inequivocabilmente moderne: se compaiono, l'azione e' fuori dal mondo dell'Odissea.
static func marcatori_anacronismo() -> Array:
	_assicura()
	return _dati.get("marcatori_anacronismo", [])

## Parole-spia di invocazione: delimitano quando vale la pena chiedere all'LLM se Ulisse
## si sta rivolgendo a un dio.
static func cue_invocazione() -> Array:
	_assicura()
	return _dati.get("cue_invocazione", [])

## Spunti d'azione di ripiego (mock e fallback), sempre 3.
## I momenti del giorno, in ordine. Sono testo, quindi stanno nei dati: si traducono con
## tutto il resto.
static func momenti_del_giorno() -> Array:
	_assicura()
	var m: Array = _dati.get("momenti_del_giorno", [])
	return m if not m.is_empty() else ["all'alba", "a mezzogiorno", "nella notte"]

static func spunti_generici() -> Array:
	_assicura()
	return _dati.get("spunti_generici", []).duplicate(true)
