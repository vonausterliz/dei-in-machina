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

## A quale delle due finestre appartiene un canale. Senza questa distinzione la
## trascrizione riversava OGNI canale in OGNI vista: le voci dei compagni finivano
## nell'Olimpo. Ogni canale nasce sapendo dove va mostrato.
const VISTA_OLIMPO := "olimpo"
const VISTA_CIURMA := "ciurma"

## Tinte leggibili sul fondo notte, assegnate in modo stabile a chi parla: la stessa voce
## ha sempre lo stesso colore, senza doverlo dichiarare nei dati.
const _TINTE := [
	"#d8a657", "#7daea3", "#d3869b", "#a9b665",
	"#e78a4e", "#89b482", "#c48b9f", "#8ec07c",
]

var canali: Dictionary = {}   # id canale -> {titolo, membri: Array, messaggi: Array}

## Apre (o ritrova) un canale. 'membri' serve ai gruppi: chi ne fa parte.
## La vista si deduce dall'id (solo la ciurma sta sul ponte; tutto il resto e' Olimpo,
## comprese le coalizioni), cosi' nessun chiamante deve ricordarsi di dichiararla.
func canale(id: String, titolo: String = "", membri: Array = []) -> Dictionary:
	if not canali.has(id):
		canali[id] = {
			"titolo": titolo if titolo != "" else id,
			"membri": membri,
			"messaggi": [],
			"vista": VISTA_CIURMA if id == CANALE_CIURMA else VISTA_OLIMPO,
		}
	elif titolo != "":
		canali[id]["titolo"] = titolo
	return canali[id]

## Scrive un messaggio. tipo: "voce" (una battuta), "azione" (un gesto: *si desta*),
## "verdetto", "sistema" (nascita del canale, esiti).
func scrivi(id_canale: String, autore: String, testo: String, turno: int,
		tipo: String = "voce", simbolo: String = "") -> void:
	if testo.strip_edges() == "" and tipo == "voce":
		return  # il silenzio non si scrive
	canale(id_canale)["messaggi"].append({
		"autore": autore, "testo": testo, "turno": turno, "tipo": tipo, "simbolo": simbolo,
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

## Trascrizione in BBCode, stile chat: i canali di UNA vista sola, poi i messaggi.
## `solo_da_turno`: se > 0, mostra solo da quel turno in poi (per non allungare all'infinito).
func trascrizione(vista: String = VISTA_OLIMPO, solo_da_turno: int = 0) -> String:
	var attivi: Array = []
	for id in canali:
		var c: Dictionary = canali[id]
		if String(c.get("vista", VISTA_OLIMPO)) != vista:
			continue
		if c["messaggi"].any(func(m): return int(m["turno"]) >= solo_da_turno):
			attivi.append(c)
	if attivi.is_empty():
		return _silenzio(vista)
	var pezzi: Array[String] = []
	for c in attivi:
		# L'intestazione serve solo a distinguere piu' conversazioni: con una sola e'
		# rumore (la finestra ha gia' il suo titolo).
		if attivi.size() > 1:
			pezzi.append("[b][color=#cba24b]# %s[/color][/b]" % c["titolo"])
		# I turni si separano con una riga vuota, non con un'etichetta "— turno N —":
		# il respiro si vede, il meccanismo no. Una conversazione non e' un tabellone.
		var ultimo_turno := -1
		for m in c["messaggi"]:
			var t: int = int(m["turno"])
			if t < solo_da_turno:
				continue
			if ultimo_turno != -1 and t != ultimo_turno:
				pezzi.append("")
			ultimo_turno = t
			pezzi.append(_riga(m))
		pezzi.append("")
	return "\n".join(pezzi)

func _silenzio(vista: String) -> String:
	return Testi.s("agora/ciurma_muta" if vista == VISTA_CIURMA else "agora/olimpo_muto")

func _riga(m: Dictionary) -> String:
	var autore := String(m["autore"])
	var testo := String(m["testo"])
	var d := distintivo(autore, String(m.get("simbolo", "")))
	match String(m["tipo"]):
		"sistema":
			return "  [i][color=#6f6857]%s[/color][/i]" % testo
		"azione":
			return "  %s[i][color=%s]%s[/color] %s[/i]" % [d, tinta(autore), autore, testo]
		"verdetto":
			return "  %s[b][color=#cba24b]%s[/color][/b] — %s" % [d, autore, testo]
		_:
			return "  %s[b][color=%s]%s[/color][/b]  %s" % [d, tinta(autore), autore, testo]

## Il distintivo: due lettere greche su fondo colorato, come un avatar. Niente emoji —
## il font dell'interfaccia non le ha e uscirebbero quadratini vuoti (verificato).
## Il colore e' lo stesso, stabile, gia' assegnato alla voce: distintivo e nome si
## riconoscono insieme.
static func distintivo(autore: String, simbolo: String) -> String:
	if autore == "" or simbolo == "":
		return ""
	return "[bgcolor=%s][color=#12101f] %s [/color][/bgcolor] " % [tinta(autore), simbolo]
