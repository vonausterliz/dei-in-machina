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

# Terra e mare devono distinguersi A COLPO D'OCCHIO, restando nella palette del gioco:
# il mare tira al blu notte, la terra al bruno-sabbia caldo. Prima erano due scuri quasi
# uguali e la carta sembrava un groviglio di fili d'oro.
const C_SEA := Color("0d1226")                 # mare: blu notte, non viola
const C_SEA_HI := Color("121a33")              # mare aperto, verso sud
const C_RIGA := Color(0.30, 0.42, 0.70, 0.10)  # rigatura del mare, come un'incisione
const C_LAND := Color(0.255, 0.205, 0.135)     # terra: bruno-sabbia caldo
const C_LAND_HI := Color(0.320, 0.260, 0.170)  # terra a nord: un accenno di rilievo
const C_COAST := Color(0.86, 0.72, 0.42, 0.95) # profilo costa: oro chiaro, netto
const C_OXBLOOD := Color("c0472f")             # dove si trova Ulisse, adesso
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
	for terra in d.get("terre", []):
		var anello := PackedVector2Array()
		for p in terra:
			anello.append(Vector2(p[0], p[1]))
		_tri.append_array(triangola(anello))

## Le coordinate sono normalizzate (0..1) e l'ear clipping di Godot su numeri cosi' piccoli
## perde precisione: si lavora in "grande" e si torna indietro alla fine.
const SCALA_TRIANGOLAZIONE := 1000.0

## Riduce un anello di terra a triangoli. Ritorna [] se non c'e' niente da riempire.
##
## SI RIPARA PRIMA DI TRIANGOLARE, ed e' il punto di tutta la funzione.
##
## Sulla carta si vedevano gialle solo Sicilia e Sardegna: 58 poligoni su 59 si
## triangolavano, e il 59esimo era la TERRAFERMA — un'area dodici volte tutte le isole
## messe insieme. `triangulate_polygon` non fallisce con un errore: ritorna un array vuoto,
## e quella terra semplicemente non veniva disegnata.
##
## La causa e' nel ritaglio a monte: il Sutherland-Hodgman del convertitore, su un anello
## concavo che esce e rientra dal riquadro molte volte, cuce i pezzi con dei "ponti"
## degeneri lungo il bordo. Il risultato e' auto-intersecante, e nessun ear clipping lo
## digerisce (nemmeno `decompose_polygon_in_convex`: fallisce anche lei).
##
## `merge_polygons(a, a)` — l'unione di un poligono con se stesso — e' il rimedio classico:
## ricostruisce i pezzi davvero distinti, gia' orientati, separando i solidi (antiorari)
## dai buchi (orari). La terraferma passa cosi' da 0 a 733 triangoli.
static func triangola(anello: PackedVector2Array) -> Array:
	if anello.size() < 3:
		return []
	var grande := PackedVector2Array()
	for p in anello:
		grande.append(p * SCALA_TRIANGOLAZIONE)
	var solidi: Array = []
	var buchi: Array = []
	for pezzo in Geometry2D.merge_polygons(grande, grande):
		if Geometry2D.is_polygon_clockwise(pezzo):
			buchi.append(pezzo)   # un lago, o un mare interno: non e' terra
		else:
			solidi.append(pezzo)
	var out: Array = []
	for solido in solidi:
		for netto in _senza_buchi(solido, buchi):
			out.append_array(_in_triangoli(netto))
	return out

## Ritaglia dai solidi i buchi che li attraversano, cosi' i laghi non si riempiono di terra.
static func _senza_buchi(solido: PackedVector2Array, buchi: Array) -> Array:
	var pezzi: Array = [solido]
	for buco in buchi:
		var dopo: Array = []
		for p in pezzi:
			var tagliati := Geometry2D.clip_polygons(p, buco)
			# clip_polygons puo' generare a sua volta anelli orari (nuovi buchi): li
			# ignoriamo, perche' rincorrerli all'infinito non serve a una decorazione.
			for t in tagliati:
				if not Geometry2D.is_polygon_clockwise(t):
					dopo.append(t)
		pezzi = dopo
	return pezzi

static func _in_triangoli(poly: PackedVector2Array) -> Array:
	var indici := Geometry2D.triangulate_polygon(poly)
	var out: Array = []
	for i in range(0, indici.size(), 3):
		out.append([
			poly[indici[i]] / SCALA_TRIANGOLAZIONE,
			poly[indici[i + 1]] / SCALA_TRIANGOLAZIONE,
			poly[indici[i + 2]] / SCALA_TRIANGOLAZIONE,
		])
	return out

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
			# ROSSO, non oro: dov'e' Ulisse adesso deve saltare all'occhio in mezzo a una
			# carta tutta d'oro e bruno. Battito lento, e un anello che lo circonda.
			var respiro := 0.5 + 0.5 * sin(_t * 2.0)
			draw_circle(pos, 9.0 + 4.0 * respiro, Color(C_OXBLOOD, 0.12 + 0.12 * respiro))
			draw_arc(pos, 8.0, 0, TAU, 24, Color(C_OXBLOOD, 0.55 + 0.25 * respiro), 1.5, true)
			draw_circle(pos, 4.5, C_OXBLOOD)
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
