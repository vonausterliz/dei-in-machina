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
## L'apertura ha finito la sua parte e aspetta: chi trattiene il sipario puo' agire.
## Distinto da `finito`, che vuol dire «me ne sono andata».
signal pronto
## Se vero, l'apertura non se ne va da sola: annuncia `pronto` e resta finche' non le si
## dice `lascia_andare()`. Vedi `congeda()`.
var trattieni := false
var _annunciato := false

const LIVELLO := 100         # sopra ogni cosa
## Quanto resta SENZA musica (headless, o se il file non c'e'): giusto il tempo di leggere
## il nome. Con la musica comanda lei — vedi ATTESA_DOPO_MUSICA.
const DURATA := 3.4
## Il respiro dopo l'ultima nota. Il brano finisce sfumando, e togliere la schermata
## nell'istante esatto del silenzio fa sembrare che sia stata interrotta.
const ATTESA_DOPO_MUSICA := 3.0
const DISSOLVENZA := 0.7     # durata della sfumatura d'uscita

## Il momento della colonna sonora a cui questa schermata corrisponde. Quale brano ci sia
## davvero lo dice `data/musica.json`: qui non si nomina nessun file.
const MOMENTO := "splash"

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

## La colonna sonora del gioco, prestata da Main: e' la stessa che suonera' i capitoli, e
## averne una sola vuol dire che l'apertura puo' sfumare dentro la musica del primo
## capitolo invece di accavallarsi. Se non c'e' (i test, il generatore d'icona), la
## schermata si regge sul tempo — un'apertura non deve dipendere da un asset per esistere.
var musica: ColonnaSonora

var _t := 0.0
var _uscita := -1.0
var _in_onda := false
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

## La musica, se c'e'. Se manca il brano il gioco parte lo stesso e la schermata torna a
## reggersi sul tempo: un'apertura non deve dipendere da un asset per esistere.
func _avvia_musica() -> void:
	if solo_marchio or musica == null or DisplayServer.get_name() == "headless":
		return
	if not musica.suona(MOMENTO):
		return
	_in_onda = true
	musica.brano_finito.connect(func(quale): if quale == MOMENTO: _muto_da = 0.0)

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
	if not _in_onda:
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

## Avvia la sfumatura d'uscita (idempotente). La musica se ne va con l'immagine: un suono
## che continua su una schermata sparita e' un pezzo d'apertura rimasto indietro.
func congeda() -> void:
	if _uscita >= 0.0:
		return
	# TRATTENUTO: il sipario resta alzato finche' non gli si dice di calare.
	#
	# Serve alla SOGLIA — il dialogo «riprendi / nuova / impostazioni». Senza, la schermata
	# d'apertura sfumava e sotto compariva una partita gia' cominciata, con la voce di Omero
	# e i tre appigli, mentre il dialogo chiedeva ancora cosa fare: si vedeva il gioco
	# rispondere a una domanda non ancora posta. Qui si annuncia soltanto (`pronto`), e chi
	# ascolta decide quando lasciar calare il sipario.
	if trattieni:
		if not _annunciato:
			_annunciato = true
			pronto.emit()
		return
	_uscita = 0.0
	if _in_onda and musica != null:
		musica.ferma(DISSOLVENZA)

## Chi tiene alzato il sipario lo cala con questo, quando ha finito.
func lascia_andare() -> void:
	trattieni = false
	congeda()

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
	# Il disegno vero sta in Marchio: lo condividono l'icona dell'app e il logo
	# nell'intestazione, e un emblema in tre posti dev'essere una funzione sola.
	Marchio.disegna(_tela, centro, r, _t, _rampa(_t, 0.0, 1.0))

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
