class_name Marchio
extends RefCounted

## L'EMBLEMA DEL GIOCO: il meccanismo di Anticitera, disegnato in codice.
##
## E' il calcolatore a ingranaggi greco del II secolo a.C., che prevedeva il moto dei cieli.
## Per un gioco che si chiama «Dei in machina» non serviva inventare un simbolo: gli
## ingranaggi girano, e dentro c'e' una piccola nave che non sa di essere calcolata.
##
## Sta qui e non nello splash perche' ora lo portano in tre: la schermata d'apertura,
## l'icona dell'applicazione (tools/genera_marchio.gd) e il logo accanto al titolo. Finche'
## il disegno viveva dentro `splash.gd`, «un marchio solo, un posto solo» era una buona
## intenzione scritta in un commento; adesso e' una funzione sola.
##
## Non e' un nodo: e' un pennello. Chi disegna e' il chiamante (`disegna(su, ...)`), cosi'
## puo' essere una tela a schermo intero o una casella di 34 pixel in un'intestazione,
## animata o ferma, senza che il marchio debba sapere dove si trova.

const C_GOLD := Color("cba24b")
const C_GOLD_DEEP := Color("9a7a34")
const C_BONE := Color("eadfc7")
const C_VERDIGRIS := Color("4e9a8e")

## Sotto questo raggio i dettagli fini diventano sporco: le tacche del quadrante si
## impastano e la nave e' tre pixel storti. Si disegna la versione essenziale.
const RAGGIO_MINUTO := 26.0

## L'emblema intero. `t` e' il tempo (gli ingranaggi girano); `apparso` va da 0 a 1 e serve
## alla comparsa in dissolvenza dello splash — a 1 e' tutto visibile.
static func disegna(su: CanvasItem, centro: Vector2, r: float, t: float = 0.0,
		apparso: float = 1.0) -> void:
	var minuto := r < RAGGIO_MINUTO
	_corona_dentata(su, centro, r, t, apparso)
	if not minuto:
		_quadrante(su, centro, r, apparso)
	_ruota_interna(su, centro, r, t, apparso, minuto)
	_mare_e_nave(su, centro, r, t, apparso, minuto)

## La corona di denti: gira lenta, in senso orario.
static func _corona_dentata(su: CanvasItem, centro: Vector2, r: float, t: float, a: float) -> void:
	var col := Color(C_GOLD_DEEP.r, C_GOLD_DEEP.g, C_GOLD_DEEP.b, 0.85 * a)
	var spessore := maxf(1.0, r * 0.023)
	# Meno denti quando e' piccolo: ventiquattro tacche su un raggio di quindici pixel
	# diventano un anello sfocato, non una ruota.
	var denti := 24 if r >= RAGGIO_MINUTO else 12
	for i in denti:
		var ang := t * 0.18 + TAU * float(i) / float(denti)
		var dir := Vector2(cos(ang), sin(ang))
		su.draw_line(centro + dir * (r * 1.06), centro + dir * (r * 1.15), col, spessore, true)
	su.draw_arc(centro, r * 1.06, 0, TAU, 128, col, maxf(1.0, r * 0.015), true)

## Il quadrante inciso: tacche fitte, una lunga ogni cinque (i gradi del cielo).
static func _quadrante(su: CanvasItem, centro: Vector2, r: float, a: float) -> void:
	su.draw_arc(centro, r, 0, TAU, 128, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.95 * a),
		maxf(1.0, r * 0.015), true)
	for i in 60:
		var ang := TAU * float(i) / 60.0 - PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var lunga := i % 5 == 0
		su.draw_line(centro + dir * (r * (0.90 if lunga else 0.945)), centro + dir * (r * 0.995),
			Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, (0.85 if lunga else 0.45) * a),
			1.6 if lunga else 1.0, true)

## La ruota dentro, che gira al contrario: due ingranaggi che si parlano.
static func _ruota_interna(su: CanvasItem, centro: Vector2, r: float, t: float,
		a: float, minuto: bool) -> void:
	var rr := r * 0.60
	su.draw_arc(centro, rr, 0, TAU, 96,
		Color(C_VERDIGRIS.r, C_VERDIGRIS.g, C_VERDIGRIS.b, 0.55 * a), maxf(1.0, r * 0.012), true)
	if not minuto:
		for i in 8:
			var ang := -t * 0.31 + TAU * float(i) / 8.0
			var dir := Vector2(cos(ang), sin(ang))
			su.draw_line(centro + dir * (rr * 0.22), centro + dir * rr,
				Color(C_VERDIGRIS.r, C_VERDIGRIS.g, C_VERDIGRIS.b, 0.28 * a), 1.0, true)
	su.draw_circle(centro, maxf(1.0, rr * 0.10), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.7 * a))

## Dentro il meccanismo: il mare, e una nave che non sa di essere calcolata.
static func _mare_e_nave(su: CanvasItem, centro: Vector2, r: float, t: float,
		a: float, minuto: bool) -> void:
	var larg := r * 0.80
	if not minuto:
		for onda in 2:
			var y := centro.y + r * (0.30 + 0.17 * float(onda))
			var punti := PackedVector2Array()
			for i in 33:
				var f := float(i) / 32.0
				punti.append(Vector2(centro.x - larg + larg * 2.0 * f,
					y + sin(f * TAU * 1.6 + t * 1.1 + float(onda)) * r * 0.035))
			su.draw_polyline(punti,
				Color(C_VERDIGRIS.r, C_VERDIGRIS.g, C_VERDIGRIS.b, (0.5 - 0.18 * float(onda)) * a),
				1.5, true)

	# La nave, sull'onda alta: scafo, albero, vela.
	var b := centro + Vector2(0, r * 0.30 + sin(t * 1.1) * r * 0.035)
	var s := r * 0.17
	var col := Color(C_BONE.r, C_BONE.g, C_BONE.b, 0.95 * a)
	var tratto := maxf(1.0, r * 0.014)
	su.draw_polyline(PackedVector2Array([
		b + Vector2(-s * 1.5, 0), b + Vector2(-s * 1.05, s * 0.55),
		b + Vector2(s * 1.05, s * 0.55), b + Vector2(s * 1.5, 0),
	]), col, tratto, true)
	su.draw_line(b + Vector2(0, s * 0.5), b + Vector2(0, -s * 1.9), col, tratto, true)
	su.draw_colored_polygon(PackedVector2Array([
		b + Vector2(0.12 * s, -s * 1.8), b + Vector2(s * 1.2, -s * 0.2), b + Vector2(0.12 * s, -s * 0.2),
	]), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.85 * a))
