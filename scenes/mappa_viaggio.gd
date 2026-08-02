class_name MappaViaggio
extends Control

## Carta del viaggio. Le coste sono GEOGRAFIA VERA (Natural Earth 1:50m, pubblico dominio,
## convertita in data/coste_mediterraneo.json da tools/coste/converti_coste.py): prima
## erano poligoni disegnati a mano con pochi vertici, e nessuna resa grafica puo' salvare
## una geometria sbagliata.
##
## Lo stile invece resta nostro, e vuole sembrare una carta antica dentro la palette del
## gioco: mare notturno rigato come un'incisione, terre di bruno caldo, profilo di costa in
## oro sottile, rosa dei venti, rotta punteggiata. Niente pergamena chiara: la carta e'
## quella che Ulisse non ha, disegnata da chi lo guarda dall'alto.

const PERCORSO_COSTE := "res://data/coste_mediterraneo.json"

const C_SEA := Color("0e0b16")
const C_SEA_HI := Color("15122a")
const C_RIGA := Color(0.35, 0.30, 0.55, 0.10)  # rigatura del mare, come un'incisione
const C_LAND := Color(0.185, 0.150, 0.100)     # terra: bruno caldo
const C_LAND_HI := Color(0.245, 0.200, 0.130)  # terra piu' chiara verso nord: rilievo
const C_COAST := Color(0.72, 0.58, 0.31, 0.85) # profilo costa: oro spento
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")

var _punti: Array = []          # [{id, nome, pos:Vector2(0..1)}]
var _corrente: String = ""
var _completati: Array = []
var _font: Font
var _t := 0.0                   # per il battito del segnaposto

var _coste: Array = []          # PackedVector2Array normalizzate: il profilo
var _tri: Array = []            # triangoli normalizzati: il riempimento delle terre

func _ready() -> void:
	var f := load("res://fonts/Cardo-Italic.ttf")
	if f is Font:
		_font = f
	_carica_coste()
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

## Coste e terre dal file dati. Le terre si triangolano UNA volta sola, a scala grande e
## fissa: a dimensioni piccole la triangolazione puo' fallire, e rifarla a ogni frame
## costerebbe per niente.
func _carica_coste() -> void:
	if not FileAccess.file_exists(PERCORSO_COSTE):
		push_error("MappaViaggio: manca %s (rigenerarlo con tools/coste/converti_coste.py)" % PERCORSO_COSTE)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO_COSTE))
	if typeof(d) != TYPE_DICTIONARY:
		push_error("MappaViaggio: %s non e' un JSON valido" % PERCORSO_COSTE)
		return
	for linea in d.get("linee", []):
		var pv := PackedVector2Array()
		for p in linea:
			pv.append(Vector2(p[0], p[1]))
		if pv.size() >= 2:
			_coste.append(pv)
	const SCALA := 1000.0
	for terra in d.get("terre", []):
		var grande := PackedVector2Array()
		for p in terra:
			grande.append(Vector2(p[0], p[1]) * SCALA)
		var indici := Geometry2D.triangulate_polygon(grande)
		for i in range(0, indici.size(), 3):
			_tri.append([grande[indici[i]] / SCALA, grande[indici[i + 1]] / SCALA,
				grande[indici[i + 2]] / SCALA])

func imposta(punti: Array, corrente: String, completati: Array) -> void:
	_punti = punti
	_corrente = corrente
	_completati = completati
	queue_redraw()

## Normalizzato (0..1) -> pixel.
func _q(n: Vector2) -> Vector2:
	return Vector2(n.x * size.x, n.y * size.y)

func _scala(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(_q(p))
	return out

func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return  # primo frame prima del layout: niente da disegnare
	_mare()
	for t in _tri:
		# Le terre a nord un filo piu' chiare: un accenno di rilievo, non una mappa fisica.
		var alto: float = (t[0].y + t[1].y + t[2].y) / 3.0
		draw_colored_polygon(PackedVector2Array([_q(t[0]), _q(t[1]), _q(t[2])]),
			C_LAND_HI.lerp(C_LAND, clampf(alto, 0.0, 1.0)))
	for costa in _coste:
		draw_polyline(_scala(costa), C_COAST, 1.0, true)
	_rosa_dei_venti()
	if _punti.is_empty():
		return
	_rotta()
	_tappe()

## Mare notturno, rigato come un'incisione antica.
func _mare() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_SEA)
	draw_rect(Rect2(Vector2(0, size.y * 0.45), Vector2(size.x, size.y * 0.55)), C_SEA_HI)
	var passo := maxf(6.0, size.y / 26.0)
	var y := passo * 0.5
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), C_RIGA, 1.0)
		y += passo
	# Cornice sottile: la carta ha un bordo, come le carte incise.
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color(C_GOLD, 0.22), false, 1.0)

## Rosa dei venti in un angolo di mare libero: il segno che dice "questa e' una carta".
func _rosa_dei_venti() -> void:
	var r: float = clampf(minf(size.x, size.y) * 0.09, 10.0, 26.0)
	# In alto a sinistra: li' il riquadro e' oceano aperto. In basso a destra finiva
	# addosso alla costa del Levante.
	var c := Vector2(r * 1.5, r * 1.5)
	for i in 8:
		var a := TAU * float(i) / 8.0 - PI * 0.5
		var lunga := i % 2 == 0
		var punta := c + Vector2(cos(a), sin(a)) * (r if lunga else r * 0.55)
		draw_line(c, punta, Color(C_GOLD, 0.5 if lunga else 0.28), 1.0, true)
	draw_arc(c, r * 0.30, 0, TAU, 24, Color(C_GOLD, 0.35), 1.0, true)
	if _font:
		draw_string(_font, c + Vector2(-3, -r - 2), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
			Color(C_GOLD, 0.65))

## La rotta: percorsa in oro pieno, da percorrere punteggiata e fioca — cio' che deve
## ancora accadere non e' una linea tracciata.
func _rotta() -> void:
	var idx := 0
	for i in _punti.size():
		if _punti[i]["id"] == _corrente:
			idx = i
			break
	for i in range(_punti.size() - 1):
		var a := _q(_punti[i]["pos"])
		var b := _q(_punti[i + 1]["pos"])
		if i < idx:
			draw_line(a, b, Color(C_GOLD, 0.6), 2.0, true)
		else:
			_punteggiata(a, b, Color(C_GOLD, 0.18))

func _punteggiata(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var lung := d.length()
	if lung < 1.0:
		return
	var dir := d / lung
	var passo := 6.0
	var x := 0.0
	while x < lung:
		draw_line(a + dir * x, a + dir * minf(x + 3.0, lung), col, 1.0, true)
		x += passo

func _tappe() -> void:
	for p in _punti:
		var pos := _q(p["pos"])
		var id: String = p["id"]
		if id == _corrente:
			# Battito lento: la nave e' qui, adesso.
			var respiro := 0.5 + 0.5 * sin(_t * 2.0)
			draw_circle(pos, 8.0 + 3.0 * respiro, Color(C_GOLD, 0.10 + 0.10 * respiro))
			draw_circle(pos, 4.0, C_GOLD)
			_etichetta(pos, String(p["nome"]))
		elif id in _completati:
			draw_circle(pos, 3.0, Color(C_BONE_DIM, 0.9))
		else:
			draw_circle(pos, 2.0, Color(C_BONE_DIM, 0.35))

func _etichetta(pos: Vector2, testo: String) -> void:
	if _font == null:
		return
	var larg := _font.get_string_size(testo, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var t := pos + Vector2(-larg * 0.5, -12)
	t.x = clampf(t.x, 4, maxf(4.0, size.x - larg - 4))
	t.y = clampf(t.y, 14, size.y - 4)
	# Alone scuro dietro il testo: sopra la terra bruna, l'osso da solo non si legge.
	draw_string_outline(_font, t, testo, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, C_SEA)
	draw_string(_font, t, testo, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_BONE)
