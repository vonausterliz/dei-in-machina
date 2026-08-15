class_name PannelloChat
extends PanelContainer

## UNA CHAT INCASTRATA NELLA PAGINA, non una finestra a se'.
##
## L'Olimpo e la ciurma vivevano in due finestre native separate: si aprivano dal menu View,
## si spostavano su un altro schermo, e lasciavano tutto lo spazio alla narrazione. Alla
## prova del gioco era la scelta sbagliata — due finestre che nascono altrove, si coprono a
## vicenda e vanno ritrovate a ogni avvio, per due cose che si guardano di continuo mentre
## si gioca. Ora stanno nella colonna di destra, sotto la carta, e ci si legge senza
## cambiare finestra.
##
## Il prezzo dell'incastro e' lo spazio: mezza colonna a testa e' poco per una
## conversazione lunga. Per questo ogni pannello ha la sua LENTE — un bottone che apre lo
## stesso contenuto grande quanto la schermata (vedi `lente.gd`).
##
## Serve due usi che sembrano uno solo: l'Olimpo e' in SOLA LETTURA (il giocatore assiste,
## non partecipa: gli dei restano nascosti), la ciurma e' INTERATTIVA — li' Ulisse scrive
## davvero. La differenza e' una barra d'invio, e non un secondo componente.

signal inviato(testo: String)
signal lente_premuta

const C_SEA2 := Color("221c3a")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")
const C_OXBLOOD := Color("b04a34")

var testo: RichTextLabel
var campo: LineEdit
var interattiva := false

var _titolo_testo := ""
var _segnaposto := ""
var _dim_testo := 15
var _serif: FontFile
var _serif_bold: FontFile
var _serif_italic: FontFile

## Stato soltanto visivo: non viene restituito da contenuto(), quindi non puo' finire
## in Agora, nella lente, nei salvataggi o in una trascrizione.
var _contenuto_persistente := ""
var _autore_in_attesa := ""

func _init(titolo: String, interazione := false, segnaposto := "") -> void:
	_titolo_testo = titolo
	interattiva = interazione
	_segnaposto = segnaposto

func _ready() -> void:
	_serif = load("res://fonts/Cardo-Regular.ttf")
	_serif_bold = load("res://fonts/Cardo-Bold.ttf")
	_serif_italic = load("res://fonts/Cardo-Italic.ttf")
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var bordo := StyleBoxFlat.new()
	bordo.bg_color = Color(1, 1, 1, 0.012)
	bordo.set_border_width_all(1)
	bordo.border_color = Color(C_GOLD, 0.20)
	bordo.set_corner_radius_all(6)
	bordo.set_content_margin_all(14)
	add_theme_stylebox_override("panel", bordo)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	# L'intestazione: il nome della vista e, all'estremita', la lente. Sta in alto a destra
	# perche' e' li' che si cerca un ingrandimento, e perche' cosi' e' nello stesso posto
	# in tutti e tre i riquadri della colonna.
	var testa := HBoxContainer.new()
	v.add_child(testa)
	var et := Label.new()
	et.text = _titolo_testo
	et.add_theme_font_override("font", _serif_bold)
	et.add_theme_font_size_override("font_size", 13)
	et.add_theme_color_override("font_color", C_GOLD)
	et.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	testa.add_child(et)
	testa.add_child(Lente.bottone(func(): lente_premuta.emit(), _titolo_testo))

	testo = RichTextLabel.new()
	testo.bbcode_enabled = true
	testo.scroll_following = true
	testo.selection_enabled = true
	testo.context_menu_enabled = true
	testo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Basso di proposito: e' un MINIMO, e i due pannelli si prendono tutto lo spazio che
	# avanza (SIZE_EXPAND_FILL). Se il minimo fosse generoso, su uno schermo scalato la
	# somma dei minimi sforerebbe la finestra e la riga in fondo finirebbe sotto il bordo —
	# e' successo, e si vede solo guardando uno scatto.
	testo.custom_minimum_size = Vector2(0, 55)
	_font(testo)
	v.add_child(testo)

	if interattiva:
		campo = LineEdit.new()
		campo.placeholder_text = _segnaposto
		campo.add_theme_color_override("font_color", C_BONE)
		campo.add_theme_color_override("font_placeholder_color", C_BONE_DIM)
		campo.add_theme_font_size_override("font_size", 14)
		campo.add_theme_stylebox_override("normal", _riquadro(Color(C_OXBLOOD, 0.35)))
		campo.add_theme_stylebox_override("focus", _riquadro(C_OXBLOOD))
		campo.text_submitted.connect(_invia)
		v.add_child(campo)

func _font(r: RichTextLabel) -> void:
	r.add_theme_font_override("normal_font", _serif)
	r.add_theme_font_override("bold_font", _serif_bold)
	r.add_theme_font_override("italics_font", _serif_italic)
	r.add_theme_font_size_override("normal_font_size", _dim_testo)
	r.add_theme_color_override("default_color", C_BONE)

func _riquadro(bordo: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_SEA2
	s.set_border_width_all(1)
	s.border_color = bordo
	s.set_corner_radius_all(4)
	s.set_content_margin_all(8)
	return s

func _invia(t: String) -> void:
	var pulito := t.strip_edges()
	if pulito == "":
		return
	campo.text = ""
	inviato.emit(pulito)

## Sostituisce il contenuto. Il pannello mostra una TRASCRIZIONE, non un registro che si
## accoda: la conversazione si ricostruisce intera a ogni turno da Agora, che e' la fonte.
func imposta(contenuto: String) -> void:
	_contenuto_persistente = contenuto
	_ridisegna()

func mostra_indicatore(autore: String) -> void:
	_autore_in_attesa = autore.strip_edges()
	_ridisegna()

func nascondi_indicatore() -> void:
	_autore_in_attesa = ""
	_ridisegna()

func ha_indicatore() -> bool:
	return _autore_in_attesa != ""

func contenuto() -> String:
	return _contenuto_persistente

func _ridisegna() -> void:
	if testo == null:
		return
	testo.clear()
	testo.append_text(_contenuto_persistente)
	if _autore_in_attesa != "":
		var autore := Bbcode.neutro(_autore_in_attesa)
		testo.append_text("\n  [i][color=%s]%s sta rispondendo · · ·[/color][/i]" % [C_BONE_DIM.to_html(), autore])
