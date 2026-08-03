class_name Costi
extends RefCounted

## I PROFILI DI COSTO: quali limiti nati per risparmiare chiamate LLM tenere accesi.
##
## Molte scelte di questo gioco non sono state prese perche' lo rendevano migliore, ma
## perche' una chiamata in piu' costava troppo sul tier gratuito. Erano sparse fra costanti
## nel codice e voci di bilanciamento.json, e da fuori non si vedevano: chi giocava con un
## piano a pagamento subiva limiti che non lo riguardavano.
##
## Uso:  Costi.limite("max_repliche")   -> 2 (Frugale) o 4 (Senza vincoli)
##       Costi.acceso("vaglia_sempre")  -> false / true
##
## Due profili predefiniti in data/profili_costo.json (non modificabili); quelli creati
## dall'utente vivono nelle sue preferenze. Inventario e classificazione dei limiti —
## quali sono puro costo e quali avevano anche una ragione narrativa — in docs/costi.md.

const PERCORSO := "res://data/profili_costo.json"
const CHIAVE_ATTIVO := "profilo_costo"
const CHIAVE_UTENTE := "profili_costo_utente"
const PREDEFINITO := "frugale"

static var _dati: Dictionary = {}

static func _carica() -> void:
	if not _dati.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Costi: %s non e' un JSON valido" % PERCORSO)
		_dati = {"limiti": {}, "profili": []}
		return
	_dati = parsed

## Ricarica dal file (test).
static func dimentica() -> void:
	_dati = {}

## I limiti dichiarati, con tipo ed etichetta: e' da qui che Settings costruisce il pannello,
## cosi' aggiungere un limite non richiede di toccare l'interfaccia.
static func descrittori() -> Dictionary:
	_carica()
	return _dati.get("limiti", {})

## Tutti i profili: prima i due predefiniti, poi quelli dell'utente.
static func profili() -> Array:
	_carica()
	var out: Array = []
	for p in _dati.get("profili", []):
		var q: Dictionary = (p as Dictionary).duplicate(true)
		q["predefinito"] = true      # non si modifica ne' si cancella
		out.append(q)
	for p in _profili_utente():
		var q: Dictionary = (p as Dictionary).duplicate(true)
		q["predefinito"] = false
		out.append(q)
	return out

static func _profili_utente() -> Array:
	var v: Variant = Impostazioni.leggi(CHIAVE_UTENTE, [])
	return v if typeof(v) == TYPE_ARRAY else []

static func get_profilo(id: String) -> Dictionary:
	for p in profili():
		if String(p.get("id", "")) == id:
			return p
	return {}

## L'id del profilo attivo. Se quello scelto non esiste piu' (l'utente l'ha cancellato,
## o e' un salvataggio vecchio) si torna al predefinito invece di restare senza limiti:
## ritrovarsi per sbaglio sul profilo caro e' peggio che ritrovarsi su quello prudente.
static func attivo() -> String:
	var id := String(Impostazioni.leggi(CHIAVE_ATTIVO, PREDEFINITO))
	return id if not get_profilo(id).is_empty() else PREDEFINITO

static func usa(id: String) -> void:
	if get_profilo(id).is_empty():
		return
	Impostazioni.scrivi(CHIAVE_ATTIVO, id)

static func nome_attivo() -> String:
	return String(get_profilo(attivo()).get("nome", attivo()))

# --- Leggere un limite ---

## Il valore del limite nel profilo attivo. `ripiego` serve solo se il limite non esiste
## (profilo utente vecchio, salvato prima che il limite fosse introdotto).
static func limite(chiave: String, ripiego: int = 0) -> int:
	var v: Variant = _valore(chiave)
	return int(v) if v != null else ripiego

static func acceso(chiave: String, ripiego: bool = false) -> bool:
	var v: Variant = _valore(chiave)
	return bool(v) if v != null else ripiego

static func _valore(chiave: String) -> Variant:
	var p := get_profilo(attivo())
	var valori: Dictionary = p.get("valori", {})
	if valori.has(chiave):
		return valori[chiave]
	# Un profilo utente puo' essere nato prima di un limite nuovo: si eredita dal Frugale,
	# che e' il comportamento con cui il gioco e' stato tarato.
	var base := get_profilo(PREDEFINITO)
	var base_valori: Dictionary = base.get("valori", {})
	return base_valori.get(chiave, null)

# --- Profili dell'utente ---

## Crea (o sovrascrive) un profilo dell'utente. Ritorna l'id.
## Parte dai valori del profilo `da`, cosi' si modifica invece di compilare da zero.
static func crea(nome: String, da: String = PREDEFINITO) -> String:
	var pulito := nome.strip_edges()
	if pulito == "":
		return ""
	var id := "utente:" + pulito.to_lower().replace(" ", "_")
	var sorgente := get_profilo(da)
	var elenco := _profili_utente()
	var nuovo := {
		"id": id, "nome": pulito,
		"descrizione": "",
		"valori": (sorgente.get("valori", {}) as Dictionary).duplicate(true),
	}
	var sostituito := false
	for i in elenco.size():
		if String(elenco[i].get("id", "")) == id:
			elenco[i] = nuovo
			sostituito = true
			break
	if not sostituito:
		elenco.append(nuovo)
	Impostazioni.scrivi(CHIAVE_UTENTE, elenco)
	return id

## Cambia un valore in un profilo dell'utente. I predefiniti non si toccano: sono il
## riferimento con cui il gioco e' stato tarato, e devono restare tali.
static func imposta(id: String, chiave: String, valore: Variant) -> bool:
	var elenco := _profili_utente()
	for i in elenco.size():
		if String(elenco[i].get("id", "")) == id:
			var valori: Dictionary = elenco[i].get("valori", {})
			valori[chiave] = valore
			elenco[i]["valori"] = valori
			Impostazioni.scrivi(CHIAVE_UTENTE, elenco)
			return true
	return false

static func cancella(id: String) -> bool:
	var elenco := _profili_utente()
	for i in elenco.size():
		if String(elenco[i].get("id", "")) == id:
			elenco.remove_at(i)
			Impostazioni.scrivi(CHIAVE_UTENTE, elenco)
			if attivo() == id:
				Impostazioni.scrivi(CHIAVE_ATTIVO, PREDEFINITO)
			return true
	return false
