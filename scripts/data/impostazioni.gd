class_name Impostazioni
extends RefCounted

## Preferenze dell'utente, persistenti tra una partita e l'altra: chiavi API, motore
## scelto, provider/modello, dimensione dell'interfaccia, geometria delle finestre.
##
## Stanno in user://impostazioni.json — la cartella dati dell'utente, FUORI dal repo:
## le chiavi API non devono mai finire nel progetto. Tutto passa da qui, cosi' c'e' un
## solo posto in cui si legge e si scrive.

const PERCORSO := "user://impostazioni.json"

## LE PREFERENZE DEI TEST NON SONO LE TUE.
##
## I test scrivono qui dentro: scelgono un provider, ne dimenticano un altro, spengono il
## gateway. Finche' scrivevano nello stesso file dell'utente, eseguire la suite voleva dire
## CANCELLARE le sue scelte — e il gioco, al riavvio, ripiegava in silenzio sul primo
## provider dell'elenco. Sintomo: «ho configurato OpenRouter e va lentissimo», perche' in
## realta' stava girando su Ollama con un 24B.
##
## Non si e' rimediato test per test: la cura che dipende dalla disciplina di chi scrive il
## prossimo test non e' una cura. `avvia.sh test` esporta DEI_IMPOSTAZIONI con un percorso
## usa-e-getta, e da quel momento nessun test puo' toccare il file vero neanche volendo.
static func percorso() -> String:
	var alt := OS.get_environment("DEI_IMPOSTAZIONI")
	return alt if alt != "" else PERCORSO

static var _dati: Dictionary = {}
static var _caricato := false

static func _carica() -> void:
	if _caricato:
		return
	_caricato = true
	if not FileAccess.file_exists(percorso()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(percorso()))
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

## Toglie una preferenza. Serve alle migrazioni: una chiave che non vale piu' va
## rimossa, non messa a null — altrimenti resta li' a confondere chi legge il file.
static func dimentica(chiave: String) -> void:
	_carica()
	if _dati.erase(chiave):
		salva()

static func salva() -> void:
	var f := FileAccess.open(percorso(), FileAccess.WRITE)
	if f == null:
		push_warning("Impostazioni: non riesco a scrivere %s" % percorso())
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
##
## DOVE, non SE. Si salvava anche `aperta`, e all'avvio il Log LLM si riapriva da solo:
## una finestra di diagnosi che tornava davanti alla narrazione a ogni partenza. Ora le
## viste di servizio nascono chiuse sempre, e questo dato non lo legge piu' nessuno — quindi
## non si scrive piu'. Nei file di impostazioni gia' esistenti la chiave resta e viene
## ignorata: non vale un'operazione di pulizia.
static func salva_geometria(nome: String, pos: Vector2i, dim: Vector2i) -> void:
	var g: Dictionary = leggi("finestre", {})
	g[nome] = {"x": pos.x, "y": pos.y, "w": dim.x, "h": dim.y}
	scrivi("finestre", g)

## Ritorna {pos, dim} oppure {} se non c'e' nulla di salvato.
static func geometria(nome: String) -> Dictionary:
	var g: Dictionary = leggi("finestre", {})
	var v: Variant = g.get(nome, null)
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	return {
		"pos": Vector2i(int(v.get("x", 0)), int(v.get("y", 0))),
		"dim": Vector2i(int(v.get("w", 0)), int(v.get("h", 0))),
	}
