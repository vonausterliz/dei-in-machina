class_name Episodio
extends RefCounted

## Una tappa del viaggio (data/episodi.json).

var id: String = ""
var nome: String = ""
var intro: String = ""
var scena: String = ""   # ancora di scena (luogo + chi e' presente): grounding degli agenti LLM
var mappa: Vector2 = Vector2(0.5, 0.5)  # posizione normalizzata (0..1) sulla carta del viaggio
var dio_locale: Variant = null
var eventi_attivi: Array[String] = []
## Parole che NON possono comparire in uno spunto finche', in questa tappa, la cosa non e'
## accaduta: all'isola di Eolo veniva proposto di aprire l'otre prima che Eolo lo desse.
var non_ancora: Array[String] = []
## Appigli su misura per la tappa, quando quelli generati vengono scartati. Meglio dei
## generici, che non sanno dove ti trovi ("piega ai remi" chiuso nell'antro del Ciclope).
var spunti_di_riserva: Array = []
## tag dell'azione -> evento che quel tag fa ACCADERE in questa tappa, per sempre.
var emette_su_tag: Dictionary = {}
var avanza_su_tag: Variant = null
var turni_massimi: int = 0
## Turni di grazia prima che la tappa cominci a TRATTENERE (0 = non trattiene).
## Ogigia e' l'unica: «restare per sempre» e' il suo pericolo, e con turni_massimi la nave
## ripartiva da sola — non esisteva il modo di restare, e la sconfitta `prigionia_eterna`
## non poteva accadere. Chi indugia oltre la soglia viene ammonito, e poi resta li'.
var trattiene_dopo_turni: int = 0

static func from_dict(d: Dictionary) -> Episodio:
	var e := Episodio.new()
	e.id = d.get("id", "")
	e.nome = d.get("nome", "")
	e.intro = d.get("intro", "")
	e.scena = d.get("scena", "")
	# La posizione accetta due forme: [x, y] (come la genera il riallineamento sulle
	# coordinate reali) e {x, y} (la forma storica). Senza questo le tappe sarebbero
	# finite tutte al centro della carta, in silenzio.
	var m: Variant = d.get("mappa", null)
	if typeof(m) == TYPE_ARRAY and m.size() >= 2:
		e.mappa = Vector2(float(m[0]), float(m[1]))
	elif typeof(m) == TYPE_DICTIONARY:
		e.mappa = Vector2(float(m.get("x", 0.5)), float(m.get("y", 0.5)))
	e.dio_locale = d.get("dio_locale", null)
	var ev: Array[String] = []
	for v in d.get("eventi_attivi", []):
		ev.append(String(v))
	e.eventi_attivi = ev
	e.non_ancora = _stringhe_di(d.get("non_ancora", []))
	e.spunti_di_riserva = d.get("spunti_di_riserva", [])
	e.emette_su_tag = d.get("emette_su_tag", {})
	e.avanza_su_tag = d.get("avanza_su_tag", null)
	e.turni_massimi = int(d.get("turni_massimi", 0))
	e.trattiene_dopo_turni = int(d.get("trattiene_dopo_turni", 0))
	return e

static func _stringhe_di(sorgente: Array) -> Array[String]:
	var out: Array[String] = []
	for v in sorgente:
		out.append(String(v))
	return out
