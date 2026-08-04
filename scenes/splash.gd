class_name Splash
extends CanvasLayer

## Schermata d'apertura. Il marchio non e' un'immagine ma un DISEGNO: come il resto
## dell'interfaccia nasce in codice, cosi' scala su qualunque schermo (Retina compresi),
## non ha un file da tenere allineato e puo' muoversi.
##
## Il simbolo e' il meccanismo di Anticitera — il calcolatore a ingranaggi greco del II
## secolo a.C., che prevedeva il moto dei cieli. Per un gioco che si chiama "Dei in
## machina" non serviva inventare un emblema: gli ingranaggi girano, e dentro c'e' una
## piccola nave che non sa di essere calcolata.
##
## E' un CanvasLayer, non un Control: un Control aggiunto alla schermata dipende dal
## layout del genitore per avere una dimensione, e al primo tentativo il fondo copriva
## solo un angolo. Un CanvasLayer sta sopra tutto e misura la finestra, punto.
##
## Si toglie al primo tasto/clic, oppure tre secondi dopo che la musica e' finita: una
## schermata d'apertura che non si puo' saltare diventa un pedaggio, ma una che sparisce
## mentre la musica sta ancora suonando e' peggio — taglia la frase a meta'.

signal finito

const LIVELLO := 100         # sopra ogni cosa
## Quanto resta SENZA musica (headless, o se il file non c'e'): giusto il tempo di leggere
## il nome. Con la musica comanda lei — vedi ATTESA_DOPO_MUSICA.
const DURATA := 3.4
## Il respiro dopo l'ultima nota. Il brano finisce sfumando, e togliere la schermata
## nell'istante esatto del silenzio fa sembrare che sia stata interrotta.
const ATTESA_DOPO_MUSICA := 3.0
const DISSOLVENZA := 0.7     # durata della sfumatura d'uscita

## Il proemio: circa trenta secondi di lira e bordone, generati da
## tools/musica/genera_proemio.py (che e' anche la partitura: si legge e si riesegue).
const MUSICA := "res://assets/audio/proemio.ogg"

const C_SEA_DEEP := Color("131020")
const C_SEA := Color("1a1630")
const C_GOLD := Color("cba24b")
const C_GOLD_DEEP := Color("9a7a34")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_VERDIGRIS := Color("4e9a8e")

## Quanti dei vegliano attorno al meccanismo. Non sono nominati e non si vedono bene:
## e' esattamente il loro modo di stare nel gioco.
const DEI := 7

## Solo l'emblema, senza scritte: serve a `tools/genera_marchio.gd` per ricavare l'icona
## dell'applicazione dallo stesso disegno. Un marchio solo, un posto solo.
var solo_marchio := false

var _t := 0.0
var _uscita := -1.0
var _suono: AudioStreamPlayer
## Da quando la musica e' finita, o -1 se sta ancora suonando (o se non c'e' musica).
var _muto_da := -1.0
var _tela: Control          # dove si disegna, e cio' che sfuma all'uscita
var _posto_marchio: Control # riserva lo spazio: il marchio si disegna esattamente qui
var _titolo: Label
var _sottotitolo: Label
var _invito: Label

func _ready() -> void:
	layer = LIVELLO
	var serif: FontFile = load("res://fonts/Cardo-Regular.ttf")
	var serif_bold: FontFile = load("res://fonts/Cardo-Bold.ttf")
	var serif_italic: FontFile = load("res://fonts/Cardo-Italic.ttf")

	_tela = Control.new()
	_tela.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tela.mouse_filter = Control.MOUSE_FILTER_STOP   # niente clic di sfuggita sul gioco sotto
	_tela.draw.connect(_disegna)
	add_child(_tela)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tela.add_child(v)

	# Lo spazio del marchio. Il disegno lo prende come riferimento invece di calcolarsi
	# un centro per conto suo: cosi' emblema e scritte non possono scollarsi.
	_posto_marchio = Control.new()
	_posto_marchio.custom_minimum_size = Vector2(0, 300)
	_posto_marchio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_posto_marchio)

	_titolo = _riga(Testi.s("app/titolo"), 44, C_GOLD, serif_bold)
	_titolo.visible = not solo_marchio
	v.add_child(_titolo)
	_sottotitolo = _riga(Testi.s("app/sottotitolo"), 17, C_BONE_DIM, serif_italic)
	_sottotitolo.visible = not solo_marchio
	v.add_child(_sottotitolo)
	var spazio := Control.new()
	spazio.custom_minimum_size = Vector2(0, 40)
	spazio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spazio)
	_invito = _riga(Testi.s("splash/prosegui"), 14, C_VERDIGRIS, serif)
	_invito.visible = not solo_marchio
	v.add_child(_invito)
	spazio.visible = not solo_marchio
	if solo_marchio:
		_posto_marchio.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_avvia_musica()
	set_process(true)

## La musica, se c'e'. Se il file manca il gioco parte lo stesso e la schermata torna a
## reggersi sul tempo: un'apertura non deve dipendere da un asset per esistere.
func _avvia_musica() -> void:
	if solo_marchio or DisplayServer.get_name() == "headless":
		return
	if not ResourceLoader.exists(MUSICA):
		return
	var flusso: AudioStream = load(MUSICA)
	if flusso == null:
		return
	_suono = AudioStreamPlayer.new()
	_suono.stream = flusso
	_suono.bus = "Master"
	add_child(_suono)
	_suono.finished.connect(func(): _muto_da = 0.0)
	_suono.play()

func _riga(testo: String, dim: int, col: Color, font: FontFile) -> Label:
	var l := Label.new()
	l.text = testo
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", dim)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate.a = 0.0   # entrano una dopo l'altra, in _process
	return l

func _process(delta: float) -> void:
	_t += delta
	_aggiorna_opacita()
	if _uscita < 0.0 and _t >= _quando_congedarsi(delta):
		congeda()
	if _uscita >= 0.0:
		_uscita += delta
		_tela.modulate.a = maxf(0.0, 1.0 - _uscita / DISSOLVENZA)
		# La musica se ne va con l'immagine: un suono che continua su una schermata sparita
		# e' un pezzo di apertura rimasto indietro.
		if _suono and _suono.playing:
			_suono.volume_db = linear_to_db(maxf(0.0001, 1.0 - _uscita / DISSOLVENZA))
		if _uscita >= DISSOLVENZA:
			set_process(false)
			finito.emit()
			queue_free()
			return
	_tela.queue_redraw()

## L'istante in cui congedarsi. Senza musica e' un tempo fisso; con la musica si aspetta
## che finisca, e poi ancora tre secondi. Ritorna un traguardo per `_t`, cosi' il confronto
## nel processo resta uno solo.
func _quando_congedarsi(delta: float) -> float:
	if _suono == null:
		return DURATA
	if _muto_da < 0.0:
		return INF        # sta ancora suonando: non c'e' nessun traguardo
	_muto_da += delta
	return _t + (ATTESA_DOPO_MUSICA - _muto_da)

## Le righe compaiono sfalsate: prima il marchio, poi il nome, poi il resto.
func _aggiorna_opacita() -> void:
	_titolo.modulate.a = _rampa(_t, 0.5, 0.9)
	_sottotitolo.modulate.a = _rampa(_t, 1.1, 0.7)
	# L'invito respira: si vede che aspetta un gesto.
	_invito.modulate.a = _rampa(_t, 1.9, 0.6) * (0.55 + 0.45 * sin(_t * 2.2))

## Ferma il marchio a un istante scelto, gia' del tutto comparso: lo usa il generatore
## delle immagini, che non puo' stare ad aspettare l'animazione.
func fissa(istante: float) -> void:
	set_process(false)
	_t = istante
	_aggiorna_opacita()
	_tela.queue_redraw()

## 0 -> 1 a partire da `da`, in `durata` secondi.
func _rampa(t: float, da: float, durata: float) -> float:
	return clampf((t - da) / durata, 0.0, 1.0)

func _input(evento: InputEvent) -> void:
	if _uscita >= 0.0:
		return
	if (evento is InputEventKey and evento.pressed) \
			or (evento is InputEventMouseButton and evento.pressed):
		get_viewport().set_input_as_handled()
		congeda()

## Avvia la sfumatura d'uscita (idempotente).
func congeda() -> void:
	if _uscita < 0.0:
		_uscita = 0.0

# --- il marchio ---

func _disegna() -> void:
	var tutto := _tela.size
	# Il centro dell'emblema e' il centro dello spazio che gli ho riservato nel VBox:
	# un solo punto di verita' per disegno e impaginazione.
	var centro := _posto_marchio.position + _posto_marchio.size * 0.5
	# A schermo intero l'emblema e' un dettaglio in cima alla pagina, e non deve
	# soverchiare il nome; da solo (l'icona) e' tutto cio' che c'e', e riempie il riquadro.
	var r: float = minf(tutto.x, tutto.y) * 0.36 if solo_marchio \
		else clampf(minf(_posto_marchio.size.y * 0.42, tutto.x * 0.14), 60.0, 130.0)
	_fondo(tutto, centro, r)
	# Le presenze attorno: a dimensione d'icona sarebbero puntini sporchi, non figure.
	if not solo_marchio:
		_dei_attorno(centro, r)
	_corona_dentata(centro, r)
	_quadrante(centro, r)
	_ruota_interna(centro, r)
	_mare_e_nave(centro, r)

## Notte e un alone: il mare profondo del resto dell'interfaccia.
func _fondo(tutto: Vector2, centro: Vector2, r: float) -> void:
	_tela.draw_rect(Rect2(Vector2.ZERO, tutto), C_SEA_DEEP)
	for i in 14:
		var f := float(i) / 14.0
		_tela.draw_circle(centro, r * (1.6 + f * 5.0), Color(C_SEA.r, C_SEA.g, C_SEA.b, 0.05 * (1.0 - f)))

## Sette presenze attorno al meccanismo: pulsano piano, non hanno nome e non si vedono
## bene. E' il loro modo di stare nel gioco.
func _dei_attorno(centro: Vector2, r: float) -> void:
	var apparsi := _rampa(_t, 0.9, 1.6)
	for i in DEI:
		var a := TAU * float(i) / float(DEI) - PI * 0.5 + _t * 0.06
		var dir := Vector2(cos(a), sin(a) * 0.62)
		var p := centro + dir * (r * 2.05)
		var battito := 0.45 + 0.55 * sin(_t * 1.3 + float(i) * 1.7)
		var alpha := 0.30 * battito * apparsi
		_tela.draw_line(centro + dir * (r * 1.25), p,
			Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, alpha * 0.35), 1.0, true)
		_tela.draw_circle(p, 2.6, Color(C_BONE.r, C_BONE.g, C_BONE.b, alpha))

## La corona di denti: gira lenta, in senso orario.
func _corona_dentata(centro: Vector2, r: float) -> void:
	var alpha := _rampa(_t, 0.0, 1.0)
	var col := Color(C_GOLD_DEEP.r, C_GOLD_DEEP.g, C_GOLD_DEEP.b, 0.85 * alpha)
	var denti := 24
	for i in denti:
		var a := _t * 0.18 + TAU * float(i) / float(denti)
		var dir := Vector2(cos(a), sin(a))
		_tela.draw_line(centro + dir * (r * 1.06), centro + dir * (r * 1.15), col, 3.0, true)
	_tela.draw_arc(centro, r * 1.06, 0, TAU, 128, col, 2.0, true)

## Il quadrante inciso: tacche fitte, una lunga ogni cinque (i gradi del cielo).
func _quadrante(centro: Vector2, r: float) -> void:
	var alpha := _rampa(_t, 0.15, 1.0)
	_tela.draw_arc(centro, r, 0, TAU, 128, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.95 * alpha), 2.0, true)
	for i in 60:
		var a := TAU * float(i) / 60.0 - PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var lunga := i % 5 == 0
		_tela.draw_line(centro + dir * (r * (0.90 if lunga else 0.945)), centro + dir * (r * 0.995),
			Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, (0.85 if lunga else 0.45) * alpha),
			1.6 if lunga else 1.0, true)

## La ruota dentro, che gira al contrario: due ingranaggi che si parlano.
func _ruota_interna(centro: Vector2, r: float) -> void:
	var alpha := _rampa(_t, 0.3, 1.0)
	var rr := r * 0.60
	_tela.draw_arc(centro, rr, 0, TAU, 96, Color(C_VERDIGRIS.r, C_VERDIGRIS.g, C_VERDIGRIS.b, 0.55 * alpha), 1.5, true)
	for i in 8:
		var a := -_t * 0.31 + TAU * float(i) / 8.0
		var dir := Vector2(cos(a), sin(a))
		_tela.draw_line(centro + dir * (rr * 0.22), centro + dir * rr,
			Color(C_VERDIGRIS.r, C_VERDIGRIS.g, C_VERDIGRIS.b, 0.28 * alpha), 1.0, true)
	_tela.draw_circle(centro, rr * 0.10, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.7 * alpha))

## Dentro il meccanismo: il mare, e una nave che non sa di essere calcolata.
func _mare_e_nave(centro: Vector2, r: float) -> void:
	var alpha := _rampa(_t, 0.45, 1.2)
	var larg := r * 0.80
	for onda in 2:
		var y := centro.y + r * (0.30 + 0.17 * float(onda))
		var punti := PackedVector2Array()
		for i in 33:
			var f := float(i) / 32.0
			punti.append(Vector2(centro.x - larg + larg * 2.0 * f,
				y + sin(f * TAU * 1.6 + _t * 1.1 + float(onda)) * r * 0.035))
		_tela.draw_polyline(punti,
			Color(C_VERDIGRIS.r, C_VERDIGRIS.g, C_VERDIGRIS.b, (0.5 - 0.18 * float(onda)) * alpha), 1.5, true)

	# La nave, sull'onda alta: scafo, albero, vela.
	var b := Vector2(centro.x, centro.y + r * 0.30 + sin(_t * 1.1) * r * 0.035)
	var s := r * 0.17
	var col := Color(C_BONE.r, C_BONE.g, C_BONE.b, 0.95 * alpha)
	_tela.draw_polyline(PackedVector2Array([
		b + Vector2(-s * 1.5, 0), b + Vector2(-s * 1.05, s * 0.55),
		b + Vector2(s * 1.05, s * 0.55), b + Vector2(s * 1.5, 0),
	]), col, 1.8, true)
	_tela.draw_line(b + Vector2(0, s * 0.5), b + Vector2(0, -s * 1.9), col, 1.6, true)
	_tela.draw_colored_polygon(PackedVector2Array([
		b + Vector2(0.12 * s, -s * 1.8), b + Vector2(s * 1.2, -s * 0.2), b + Vector2(0.12 * s, -s * 0.2),
	]), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.85 * alpha))
