class_name FinestraTesto
extends Window

## Finestra di servizio staccata dal gioco (Log LLM, Vista Olimpo): finestra NATIVA
## ridimensionabile, spostabile su un altro schermo, con testo selezionabile e copiabile.
## Tenerle fuori dalla schermata di gioco libera spazio per la narrazione e le rende
## davvero consultabili quando servono.

const C_SEA := Color("0e0b16")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")
const C_VERDIGRIS := Color("4e9a8e")

var testo: RichTextLabel
var dimensione_testo: int = 18   # leggibile anche su Retina; regolabile con A+/A−
var _accodante: bool = true      # true = log (si accoda), false = vista (si sostituisce)

func _init(titolo_finestra: String, accodante: bool = true, dimensione := Vector2i(760, 560), posizione := Vector2i(-1, -1)) -> void:
	title = titolo_finestra
	_accodante = accodante
	size = dimensione
	if posizione != Vector2i(-1, -1):
		position = posizione  # finestre distinte: ognuna col suo posto, non sovrapposte
	unresizable = false
	visible = false
	always_on_top = true  # viste di servizio: restano davanti al gioco mentre si legge

## Le finestre secondarie NON ereditano il content_scale_factor della principale: su uno
## schermo Retina il testo verrebbe disegnato a pixel nativi, cioè minuscolo (ed è il
## motivo per cui A+/A− sembravano non funzionare: cambiavano di 1 px su scala dimezzata).
func applica_scala(fattore: float) -> void:
	content_scale_factor = clampf(fattore, 1.0, 3.0)
	# Chiudendo dalla X la finestra si nasconde soltanto: lo stato del gioco non cambia.
	close_requested.connect(_su_chiusura)

func _ready() -> void:
	var sfondo := ColorRect.new()
	sfondo.color = C_SEA
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sfondo)

	var margine := MarginContainer.new()
	margine.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lato in ["left", "top", "right", "bottom"]:
		margine.add_theme_constant_override("margin_" + lato, 12)
	add_child(margine)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margine.add_child(v)

	# Barra: copia / pulisci
	var barra := HBoxContainer.new()
	barra.add_theme_constant_override("separation", 8)
	v.add_child(barra)
	barra.add_child(_bottone("Copia tutto", _copia))
	if _accodante:
		barra.add_child(_bottone("Pulisci", _pulisci))
	var riempi := Control.new()
	riempi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	barra.add_child(riempi)
	barra.add_child(_bottone("A−", func(): _ridimensiona(-1)))
	barra.add_child(_bottone("A+", func(): _ridimensiona(+1)))

	testo = RichTextLabel.new()
	testo.bbcode_enabled = true
	testo.scroll_following = _accodante
	testo.selection_enabled = true
	testo.context_menu_enabled = true
	testo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	testo.add_theme_color_override("default_color", C_BONE)
	testo.add_theme_font_size_override("normal_font_size", dimensione_testo)
	testo.add_theme_font_size_override("bold_font_size", dimensione_testo)
	testo.add_theme_font_size_override("italics_font_size", dimensione_testo)
	v.add_child(testo)

func _bottone(etichetta: String, azione: Callable) -> Button:
	var b := Button.new()
	b.text = etichetta
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(azione)
	return b

## Accoda una riga (finestre-log).
func aggiungi(riga: String) -> void:
	if testo:
		testo.append_text("%s\n" % riga)

## Sostituisce il contenuto (finestre-vista).
func imposta(contenuto: String) -> void:
	if testo:
		testo.text = contenuto

func _ridimensiona(passo: int) -> void:
	dimensione_testo = clampi(dimensione_testo + passo * 2, 10, 36)  # passo di 2: si vede
	for chiave in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		testo.add_theme_font_size_override(chiave, dimensione_testo)

func _copia() -> void:
	if testo:
		DisplayServer.clipboard_set(testo.get_parsed_text())

func _pulisci() -> void:
	if testo:
		testo.clear()

func _su_chiusura() -> void:
	hide()
	chiusa.emit()

signal chiusa
