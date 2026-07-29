class_name Impostazioni
extends RefCounted

## Preferenze dell'utente, persistenti tra una partita e l'altra: chiavi API, motore
## scelto, provider/modello, dimensione dell'interfaccia, geometria delle finestre.
##
## Stanno in user://impostazioni.json — la cartella dati dell'utente, FUORI dal repo:
## le chiavi API non devono mai finire nel progetto. Tutto passa da qui, cosi' c'e' un
## solo posto in cui si legge e si scrive.

const PERCORSO := "user://impostazioni.json"

static var _dati: Dictionary = {}
static var _caricato := false

static func _carica() -> void:
	if _caricato:
		return
	_caricato = true
	if not FileAccess.file_exists(PERCORSO):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO))
	if typeof(parsed) == TYPE_DICTIONARY:
		_dati = parsed

static func leggi(chiave: String, predefinito: Variant = null) -> Variant:
	_carica()
	return _dati.get(chiave, predefinito)

## Scrive e salva subito: le preferenze non devono perdersi se il gioco viene chiuso male.
static func scrivi(chiave: String, valore: Variant) -> void:
	_carica()
	_dati[chiave] = valore
	salva()

static func salva() -> void:
	var f := FileAccess.open(PERCORSO, FileAccess.WRITE)
	if f == null:
		push_warning("Impostazioni: non riesco a scrivere %s" % PERCORSO)
		return
	f.store_string(JSON.stringify(_dati, "  "))
	f.close()

# --- chiavi API ---

static func chiavi() -> Dictionary:
	var c: Variant = leggi("chiavi", {})
	return c if typeof(c) == TYPE_DICTIONARY else {}

static func imposta_chiave(env: String, valore: String) -> void:
	var c := chiavi()
	if valore == "":
		c.erase(env)
	else:
		c[env] = valore
	scrivi("chiavi", c)

## Porta le chiavi salvate nell'ambiente del processo: il resto del codice continua a
## leggerle da OS.get_environment. L'ambiente vero ha sempre la precedenza.
static func applica_chiavi_all_ambiente() -> void:
	for env in chiavi():
		var valore := String(chiavi()[env])
		if valore != "" and not (OS.has_environment(env) and OS.get_environment(env) != ""):
			OS.set_environment(env, valore)

# --- geometria delle finestre ---

## Salva posizione e dimensione di una finestra, per ritrovarla dove l'avevi lasciata.
static func salva_geometria(nome: String, pos: Vector2i, dim: Vector2i, visibile: bool) -> void:
	var g: Dictionary = leggi("finestre", {})
	g[nome] = {"x": pos.x, "y": pos.y, "w": dim.x, "h": dim.y, "aperta": visibile}
	scrivi("finestre", g)

## Ritorna {pos, dim, aperta} oppure {} se non c'e' nulla di salvato.
static func geometria(nome: String) -> Dictionary:
	var g: Dictionary = leggi("finestre", {})
	var v: Variant = g.get(nome, null)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return {
		"pos": Vector2i(int(v.get("x", 0)), int(v.get("y", 0))),
		"dim": Vector2i(int(v.get("w", 0)), int(v.get("h", 0))),
		"aperta": bool(v.get("aperta", false)),
	}
