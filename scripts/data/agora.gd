class_name Agora
extends RefCounted

## Le conversazioni del gioco, organizzate in CANALI come una chat.
##
## Serve due viste molto diverse:
##  - OLIMPO, in sola lettura: gli dei si parlano tra loro. Il giocatore assiste e basta
##    (restano nascosti: non li sente davvero, e' una finestra per lui, non un canale).
##  - CIURMA, interattiva: li' Ulisse scrive davvero ai compagni.
##
## Nota di progetto: i messaggi degli dei NON costano chiamate LLM in piu'. Le proposte
## hanno gia' un campo "dice" (una battuta) e il round di repliche e' gia' un botta e
## risposta: qui li raccogliamo e li mostriamo per quello che sono.

const CANALE_OLIMPO := "olimpo"
const CANALE_CIURMA := "ciurma"

## Tinte leggibili sul fondo notte, assegnate in modo stabile a chi parla: la stessa voce
## ha sempre lo stesso colore, senza doverlo dichiarare nei dati.
const _TINTE := [
	"#d8a657", "#7daea3", "#d3869b", "#a9b665",
	"#e78a4e", "#89b482", "#c48b9f", "#8ec07c",
]

var canali: Dictionary = {}   # id canale -> {titolo, membri: Array, messaggi: Array}

## Apre (o ritrova) un canale. 'membri' serve ai gruppi: chi ne fa parte.
func canale(id: String, titolo: String = "", membri: Array = []) -> Dictionary:
	if not canali.has(id):
		canali[id] = {"titolo": titolo if titolo != "" else id, "membri": membri, "messaggi": []}
	elif titolo != "":
		canali[id]["titolo"] = titolo
	return canali[id]

## Scrive un messaggio. tipo: "voce" (una battuta), "azione" (un gesto: *si desta*),
## "verdetto", "sistema" (nascita del canale, esiti).
func scrivi(id_canale: String, autore: String, testo: String, turno: int, tipo: String = "voce") -> void:
	if testo.strip_edges() == "" and tipo == "voce":
		return  # il silenzio non si scrive
	canale(id_canale)["messaggi"].append({
		"autore": autore, "testo": testo, "turno": turno, "tipo": tipo,
	})

## Canale di gruppo per una coalizione: nasce quando gli dei fanno blocco.
func apri_gruppo(membri: Array, nomi: Array, turno: int) -> String:
	var id := "coalizione_" + "_".join(membri)
	var titolo := "Blocco: " + " · ".join(nomi)
	canale(id, titolo, membri)
	scrivi(id, "", "%s si sono intesi: parlano tra loro." % " e ".join(nomi), turno, "sistema")
	return id

func chiudi_gruppo(id_canale: String, turno: int) -> void:
	if canali.has(id_canale):
		scrivi(id_canale, "", "L'intesa si e' sciolta.", turno, "sistema")

## Colore stabile per chi parla (dal nome: nessun dato in piu' da mantenere).
static func tinta(autore: String) -> String:
	if autore == "":
		return "#8a8172"
	return _TINTE[abs(autore.hash()) % _TINTE.size()]

## Trascrizione in BBCode, stile chat: intestazione di canale, poi i messaggi.
## `solo_da_turno`: se > 0, mostra solo da quel turno in poi (per non allungare all'infinito).
func trascrizione(solo_da_turno: int = 0) -> String:
	if canali.is_empty():
		return "[i]Nessuna voce, per ora. Gli dei tacciono.[/i]"
	var pezzi: Array[String] = []
	for id in canali:
		var c: Dictionary = canali[id]
		var messaggi: Array = c["messaggi"].filter(func(m): return int(m["turno"]) >= solo_da_turno)
		if messaggi.is_empty():
			continue
		pezzi.append("[b][color=#cba24b]# %s[/color][/b]" % c["titolo"])
		var ultimo_turno := -1
		for m in messaggi:
			var t: int = int(m["turno"])
			if t != ultimo_turno:
				pezzi.append("[color=#5c5548]— turno %d —[/color]" % t)
				ultimo_turno = t
			pezzi.append(_riga(m))
		pezzi.append("")
	return "\n".join(pezzi)

func _riga(m: Dictionary) -> String:
	var autore := String(m["autore"])
	var testo := String(m["testo"])
	match String(m["tipo"]):
		"sistema":
			return "  [i][color=#6f6857]%s[/color][/i]" % testo
		"azione":
			return "  [i][color=%s]%s[/color] %s[/i]" % [tinta(autore), autore, testo]
		"verdetto":
			return "  [b][color=#cba24b]%s[/color][/b] — %s" % [autore, testo]
		_:
			return "  [b][color=%s]%s[/color][/b]  %s" % [tinta(autore), autore, testo]
