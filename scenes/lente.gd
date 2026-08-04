class_name Lente
extends Control

## LA LENTE: guarda grande cio' che nella pagina sta stretto.
##
## Incastrare la carta e le due chat nella colonna di destra le ha rese sempre presenti — si
## leggono mentre si gioca, senza cambiare finestra — ma le ha anche ridotte a un terzo di
## colonna l'una. Per una conversazione lunga o per una carta del Mediterraneo e' poco.
##
## La lente e' la contropartita: un velo sopra tutta la schermata con dentro lo STESSO
## contenuto, grande quanto c'e' posto. Non e' una finestra — non si sposta, non si
## ridimensiona, non va ritrovata al prossimo avvio: si apre, si guarda, si chiude con Esc o
## con un clic fuori. Il difetto delle finestre separate era proprio quello, e non aveva
## senso reintrodurlo dalla porta di servizio.
##
## Il contenuto non si SPOSTA qui dentro: sarebbe un riparenting da annullare alla chiusura,
## e basta un'eccezione per lasciare mezza interfaccia in un velo chiuso. Si passa invece un
## COSTRUTTORE (`Callable` che ritorna un Control nuovo): la lente ne fabbrica una copia
## fresca ogni volta, e chiudendola la butta.

const C_SEA_DEEP := Color("131020")
const C_SEA := Color("1a1630")
const C_GOLD := Color("cba24b")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")

## Quanto della schermata occupa il riquadro ingrandito.
const QUOTA := 0.86

var _titolo: Label
var _dentro: MarginContainer

func _ready() -> void:
	# ANCHORS *E* OFFSETS. `set_anchors_preset` da solo imposta gli ancoraggi ma lascia il
	# rettangolo com'e' — e il rettangolo di un nodo appena creato e' (0,0,0,0). Gli
	# ancoraggi si applicherebbero al prossimo ridimensionamento del genitore, che pero' e'
	# gia' stato dimensionato: la lente restava un riquadro di zero pixel in alto a
	# sinistra, con dentro il titolo e il bottone «Chiudi» e nient'altro. Si e' vista solo
	# guardando uno scatto.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # il gioco sotto non si clicca per sbaglio
	focus_mode = Control.FOCUS_ALL             # senza, grab_focus() e' un errore a runtime
	visible = false

	var velo := ColorRect.new()
	velo.color = Color(C_SEA_DEEP.r, C_SEA_DEEP.g, C_SEA_DEEP.b, 0.88)
	velo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	velo.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			chiudi())
	add_child(velo)

	var centro := MarginContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centro)

	var riquadro := PanelContainer.new()
	riquadro.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	riquadro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SEA
	sb.set_border_width_all(1)
	sb.border_color = Color(C_GOLD, 0.45)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	riquadro.add_theme_stylebox_override("panel", sb)
	centro.add_child(riquadro)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	riquadro.add_child(v)

	var testa := HBoxContainer.new()
	v.add_child(testa)
	_titolo = Label.new()
	_titolo.add_theme_font_override("font", load("res://fonts/Cardo-Bold.ttf"))
	_titolo.add_theme_font_size_override("font_size", 17)
	_titolo.add_theme_color_override("font_color", C_GOLD)
	_titolo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	testa.add_child(_titolo)
	var chiudi_b := Button.new()
	chiudi_b.text = Testi.s("lente/chiudi")
	chiudi_b.add_theme_color_override("font_color", C_BONE_DIM)
	chiudi_b.add_theme_color_override("font_hover_color", C_BONE)
	chiudi_b.pressed.connect(chiudi)
	testa.add_child(chiudi_b)

	_dentro = MarginContainer.new()
	_dentro.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dentro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_dentro)

	# La dimensione si ricava dalla schermata, non da misure fisse: su un portatile e su un
	# monitor grande la lente deve occupare la stessa QUOTA di pagina.
	resized.connect(_ridimensiona)
	_ridimensiona.call_deferred()

func _ridimensiona() -> void:
	if _dentro == null:
		return
	# Mai negativo: con la lente non ancora dimensionata la sottrazione andava sotto zero,
	# e un minimo negativo e' un minimo che non vincola niente.
	_dentro.custom_minimum_size = (size * QUOTA - Vector2(60, 90)).max(Vector2(320, 220))

## Apre la lente su un contenuto costruito ora. `costruisci` deve tornare un Control nuovo:
## non si sposta qui dentro quello della pagina (vedi sopra).
func mostra(titolo: String, costruisci: Callable) -> void:
	for c in _dentro.get_children():
		c.queue_free()
	_titolo.text = titolo
	var nodo: Variant = costruisci.call()
	if nodo is Control:
		nodo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nodo.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_dentro.add_child(nodo)
	visible = true
	_ridimensiona()
	grab_focus()

func chiudi() -> void:
	visible = false
	for c in _dentro.get_children():
		c.queue_free()

## Esc chiude. Non in `_gui_input`: li' i tasti arrivano solo se il velo ha il fuoco, e il
## fuoco puo' finire su un bottone dentro il contenuto ingrandito. Qui arriva comunque.
func _unhandled_key_input(evento: InputEvent) -> void:
	if visible and evento is InputEventKey and evento.pressed and evento.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		chiudi()

## Il bottone della lente, uguale nei tre riquadri che ce l'hanno. Il simbolo e' DISEGNATO,
## non scritto: il font dell'interfaccia (Cardo) non ha i glifi delle emoji ne' «⌕», e li
## renderebbe come quadratini vuoti — verificato, e gia' costato una volta.
static func bottone(quando_premuto: Callable, cosa: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(24, 24)
	b.flat = true
	b.tooltip_text = Testi.s("lente/tooltip", [cosa]) if cosa != "" else Testi.s("lente/chiudi")
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(quando_premuto)
	b.draw.connect(_disegna_lente.bind(b))
	return b

static func _disegna_lente(b: Button) -> void:
	var col := C_GOLD if b.is_hovered() else Color(C_BONE.r, C_BONE.g, C_BONE.b, 0.55)
	var c := b.size * 0.5 - Vector2(1.5, 1.5)
	var r: float = minf(b.size.x, b.size.y) * 0.28
	b.draw_arc(c, r, 0, TAU, 24, col, 1.6, true)
	b.draw_line(c + Vector2(0.72, 0.72) * r, c + Vector2(1.9, 1.9) * r, col, 1.8, true)
	# La crocetta dentro: e' quella che la fa leggere come «ingrandisci» e non come «cerca».
	b.draw_line(c - Vector2(r * 0.45, 0), c + Vector2(r * 0.45, 0), col, 1.2, true)
	b.draw_line(c - Vector2(0, r * 0.45), c + Vector2(0, r * 0.45), col, 1.2, true)
