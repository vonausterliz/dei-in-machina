class_name Ciurma
extends RefCounted

## I compagni di Ulisse (data/ciurma.json). A differenza degli dei non sono nascosti:
## Omero puo' nominarli e Ulisse parla con loro nella chat della ciurma.
##
## Chi muore TACE: la voce sparisce dalla conversazione. E' il modo piu' efficace di far
## sentire le perdite — molto piu' di un contatore che scende.

const PERCORSO := "res://data/ciurma.json"

var compagni: Array = []          # [{id, nome, ruolo, carattere, voce, esempi, morte?}]
var caduti: Array = []            # id di chi non parla piu'

static func carica(percorso: String = PERCORSO) -> Ciurma:
	var c := Ciurma.new()
	if not FileAccess.file_exists(percorso):
		push_error("Ciurma: file non trovato: %s" % percorso)
		return c
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(percorso))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Ciurma: JSON non valido: %s" % percorso)
		return c
	c.compagni = parsed.get("compagni", [])
	return c

func get_compagno(id: String) -> Dictionary:
	for c in compagni:
		if String(c.get("id", "")) == id:
			return c
	return {}

## Chi e' ancora vivo e puo' parlare.
func vivi() -> Array:
	return compagni.filter(func(c): return not caduti.has(String(c.get("id", ""))))

func nomi_vivi() -> Array:
	return vivi().map(func(c): return String(c.get("nome", "")))

## Fa tacere un compagno (morto in scena). Ritorna il suo nome, "" se gia' caduto.
func fai_cadere(id: String) -> String:
	if caduti.has(id):
		return ""
	var c := get_compagno(id)
	if c.is_empty():
		return ""
	caduti.append(id)
	return String(c.get("nome", ""))

## Compagni che muoiono entrando in una certa tappa, secondo il poema (Antifo nel Ciclope,
## Elpenore da Circe). Li applica il GameManager quando la tappa si chiude.
func destinati_a_cadere(episodio: String) -> Array:
	var out: Array = []
	for c in vivi():
		var m: Variant = c.get("morte", null)
		if typeof(m) == TYPE_DICTIONARY and String(m.get("episodio", "")) == episodio:
			out.append(String(c["id"]))
	return out

## Risolve un destinatario scritto da Ulisse ("@euriloco", "Euriloco", "euriloco").
## Ritorna l'id, "" se non e' un compagno vivo.
func risolvi_destinatario(testo: String) -> String:
	var t := testo.to_lower().strip_edges().trim_prefix("@")
	for c in vivi():
		if String(c.get("id", "")) == t or String(c.get("nome", "")).to_lower() == t:
			return String(c["id"])
	return ""

## Tutti i compagni nominati in un testo libero (per capire a chi si rivolge Ulisse).
func destinatari_in(testo: String) -> Array:
	var t := testo.to_lower()
	var out: Array = []
	for c in vivi():
		var nome := String(c.get("nome", "")).to_lower()
		var re := RegEx.new()
		re.compile("(?i)@?\\b" + nome + "\\b")
		if re.search(t) != null:
			out.append(String(c["id"]))
	return out
