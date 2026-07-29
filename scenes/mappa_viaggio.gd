class_name MappaViaggio
extends Control

## Carta del viaggio su una cartina STILIZZATA del Mediterraneo: le coste (Iberia, Italia
## a stivale, Grecia, Anatolia, Africa) e le isole maggiori sono disegnate a poligoni
## vettoriali — non un asset geografico reale, ma una mappa riconoscibile. Sopra: la rotta
## percorsa e il segnaposto sulla posizione attuale di Ulisse. Riceve i dati via imposta().

const C_SEA := Color("0e0b16")
const C_SEA_HI := Color("161228")
const C_LAND := Color(0.16, 0.14, 0.10)      # terra: bruno caldo scuro
const C_COAST := Color(0.55, 0.44, 0.24, 0.7) # profilo costa: oro spento
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")

var _punti: Array = []          # [{id, nome, pos:Vector2(0..1)}]
var _corrente: String = ""
var _completati: Array = []
var _font: Font

# Coste (coordinate normalizzate 0..1; alcune escono dal riquadro: la terra continua fuori).
var _terre: Array = []          # Array di PackedVector2Array (poligoni, per il profilo costa)
var _tri: Array = []            # triangoli (coord normalizzate) pre-calcolati: fill robusto

func _ready() -> void:
	var f := load("res://fonts/Cardo-Italic.ttf")
	if f is Font:
		_font = f
	_costruisci_coste()
	_pretriangola()

## Triangola le terre UNA volta sola, a scala grande e fissa (robusto), e memorizza i
## triangoli in coordinate normalizzate. A ogni frame si disegnano solo triangoli (sempre
## validi): niente triangolazione per-frame, che a dimensioni piccole poteva fallire.
func _pretriangola() -> void:
	_tri.clear()
	for poly in _terre:
		var grande := PackedVector2Array()
		for p in poly:
			grande.append(p * 1000.0)
		var idx := Geometry2D.triangulate_polygon(grande)
		if idx.is_empty():
			push_warning("MappaViaggio: poligono costa non triangolabile, saltato")
			continue
		var i := 0
		while i < idx.size():
			_tri.append(PackedVector2Array([
				grande[idx[i]] / 1000.0, grande[idx[i + 1]] / 1000.0, grande[idx[i + 2]] / 1000.0]))
			i += 3

func imposta(punti: Array, corrente: String, completati: Array) -> void:
	_punti = punti
	_corrente = corrente
	_completati = completati
	queue_redraw()

func _v(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(p[0], p[1]))
	return out

func _costruisci_coste() -> void:
	# Europa + Anatolia: la costa mediterranea da ovest a est, poi si chiude in alto.
	_terre.append(_v([
		[-0.05, 0.33], [0.03, 0.35], [0.05, 0.45], [0.095, 0.50], [0.085, 0.44],
		[0.14, 0.42], [0.17, 0.36], [0.22, 0.335], [0.265, 0.35], [0.30, 0.40],
		[0.315, 0.50], [0.34, 0.60], [0.355, 0.66], [0.405, 0.625], [0.385, 0.53],
		[0.37, 0.43], [0.335, 0.40], [0.415, 0.40], [0.455, 0.44], [0.485, 0.49],
		[0.515, 0.565], [0.545, 0.49], [0.565, 0.43], [0.60, 0.41], [0.635, 0.40],
		[0.72, 0.42], [0.86, 0.45], [1.05, 0.44], [1.05, -0.05], [-0.05, -0.05],
	]))
	# Africa: la costa a sud, poi si chiude in basso.
	_terre.append(_v([
		[-0.05, 0.80], [0.07, 0.66], [0.16, 0.71], [0.30, 0.735], [0.44, 0.70],
		[0.50, 0.75], [0.575, 0.83], [0.66, 0.775], [0.80, 0.74], [0.92, 0.71],
		[1.05, 0.685], [1.05, 1.05], [-0.05, 1.05],
	]))
	# Isole maggiori.
	_terre.append(_v([[0.235, 0.42], [0.255, 0.42], [0.26, 0.475], [0.235, 0.475]]))       # Corsica
	_terre.append(_v([[0.23, 0.485], [0.258, 0.485], [0.262, 0.55], [0.228, 0.55]]))        # Sardegna
	_terre.append(_v([[0.385, 0.635], [0.445, 0.645], [0.415, 0.69]]))                      # Sicilia
	_terre.append(_v([[0.52, 0.615], [0.60, 0.605], [0.605, 0.63], [0.52, 0.635]]))         # Creta
	_terre.append(_v([[0.79, 0.505], [0.835, 0.50], [0.84, 0.525], [0.79, 0.53]]))          # Cipro

func _q(n: Vector2) -> Vector2:
	return Vector2(n.x * size.x, n.y * size.y)

func _scala(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(_q(p))
	return out

func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return  # primo frame prima del layout: niente da disegnare (evita poligoni degeneri)
	# Mare (con un lieve gradiente a bande, per non essere piatto).
	draw_rect(Rect2(Vector2.ZERO, size), C_SEA)
	draw_rect(Rect2(Vector2(0, size.y * 0.5), Vector2(size.x, size.y * 0.5)), C_SEA_HI)
	# Terre: solo triangoli pre-calcolati (fill sempre valido).
	for t in _tri:
		draw_colored_polygon(PackedVector2Array([_q(t[0]), _q(t[1]), _q(t[2])]), C_LAND)
	# Profilo di costa (la polyline concava non dà problemi).
	for poly in _terre:
		var pix := _scala(poly)
		var chiuso := pix.duplicate()
		chiuso.append(pix[0])
		draw_polyline(chiuso, C_COAST, 1.0, true)
	if _punti.is_empty():
		return

	# Rotta: la parte percorsa in oro, la futura fioca.
	var idx_corr := 0
	for i in _punti.size():
		if _punti[i]["id"] == _corrente:
			idx_corr = i
			break
	for i in range(_punti.size() - 1):
		var a := _q(_punti[i]["pos"])
		var b := _q(_punti[i + 1]["pos"])
		var percorsa := i < idx_corr
		draw_line(a, b, Color(C_GOLD, 0.55 if percorsa else 0.16), 2.0 if percorsa else 1.0)

	# Nodi + segnaposto sulla posizione attuale.
	for p in _punti:
		var pos := _q(p["pos"])
		var id: String = p["id"]
		if id == _corrente:
			draw_circle(pos, 9.0, Color(C_GOLD, 0.20))
			draw_circle(pos, 4.5, C_GOLD)
			if _font:
				var etichetta: String = String(p["nome"])
				var larg := _font.get_string_size(etichetta, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				var tpos := pos + Vector2(-larg * 0.5, -12)
				tpos.x = clampf(tpos.x, 4, size.x - larg - 4)
				tpos.y = clampf(tpos.y, 14, size.y - 4)
				# alone scuro dietro il testo, per leggibilita' sopra la terra
				draw_string_outline(_font, tpos, etichetta, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, C_SEA)
				draw_string(_font, tpos, etichetta, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_BONE)
		elif id in _completati:
			draw_circle(pos, 3.0, Color(C_BONE_DIM, 0.9))
		else:
			draw_circle(pos, 2.5, Color(C_BONE_DIM, 0.4))
