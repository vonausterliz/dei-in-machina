class_name MappaViaggio
extends Control

## Carta stilizzata del viaggio: le tappe come porti su un mare, unite dalla rotta,
## con un segnaposto sulla posizione attuale di Ulisse. Non è una mappa geografica reale
## (nessun asset di costa), ma un colpo d'occhio su "dove sei" e sul cammino percorso.
## Riceve i dati via imposta(); ridisegna da sé.

const C_SEA := Color("0e0b16")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")
const C_OXBLOOD := Color("b04a34")

var _punti: Array = []          # [{id, nome, pos:Vector2(0..1)}]
var _corrente: String = ""
var _completati: Array = []
var _font: Font

func _ready() -> void:
	var f := load("res://fonts/Cardo-Italic.ttf")
	if f is Font:
		_font = f

func imposta(punti: Array, corrente: String, completati: Array) -> void:
	_punti = punti
	_corrente = corrente
	_completati = completati
	queue_redraw()

func _p(n: Vector2) -> Vector2:
	# margine interno per non toccare i bordi
	var m := Vector2(16, 16)
	return m + Vector2(n.x * (size.x - 2 * m.x), n.y * (size.y - 2 * m.y))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_SEA)
	if _punti.is_empty():
		return

	# Rotta: linea sottile che unisce le tappe in ordine (percorsa = oro, futura = fioca).
	var idx_corr := 0
	for i in _punti.size():
		if _punti[i]["id"] == _corrente:
			idx_corr = i
			break
	for i in range(_punti.size() - 1):
		var a := _p(_punti[i]["pos"])
		var b := _p(_punti[i + 1]["pos"])
		var percorsa := i < idx_corr
		draw_line(a, b, Color(C_GOLD, 0.5 if percorsa else 0.14), 2.0 if percorsa else 1.0)

	# Nodi + segnaposto.
	for p in _punti:
		var pos := _p(p["pos"])
		var id: String = p["id"]
		if id == _corrente:
			draw_circle(pos, 9.0, Color(C_GOLD, 0.18))         # alone
			draw_circle(pos, 4.5, C_GOLD)                       # segnaposto
			if _font:
				var etichetta: String = String(p["nome"])
				var larg := _font.get_string_size(etichetta, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				var tpos := pos + Vector2(-larg * 0.5, 22)
				tpos.x = clampf(tpos.x, 4, size.x - larg - 4)
				draw_string(_font, tpos, etichetta, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_BONE)
		elif id in _completati:
			draw_circle(pos, 3.0, Color(C_BONE_DIM, 0.9))       # tappa già percorsa
		else:
			draw_circle(pos, 2.5, Color(C_BONE_DIM, 0.35))      # tappa futura, fioca
