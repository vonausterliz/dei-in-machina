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
var avanza_su_tag: Variant = null
var turni_massimi: int = 0

static func from_dict(d: Dictionary) -> Episodio:
	var e := Episodio.new()
	e.id = d.get("id", "")
	e.nome = d.get("nome", "")
	e.intro = d.get("intro", "")
	e.scena = d.get("scena", "")
	var m: Dictionary = d.get("mappa", {})
	e.mappa = Vector2(float(m.get("x", 0.5)), float(m.get("y", 0.5)))
	e.dio_locale = d.get("dio_locale", null)
	var ev: Array[String] = []
	for v in d.get("eventi_attivi", []):
		ev.append(String(v))
	e.eventi_attivi = ev
	e.avanza_su_tag = d.get("avanza_su_tag", null)
	e.turni_massimi = int(d.get("turni_massimi", 0))
	return e
