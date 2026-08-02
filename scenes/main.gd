extends Control

## Fase 8 — Interfaccia grafica, stile "epico" dai mockup (odissea_interfaccia.html):
## mare profondo, osso, oro, rosso-sangue; serif classico (Cardo) per la voce del poeta.
## Schermata giocatore + Vista Olimpo (toggle, debug). Autoload GameManager/LLMManager.

## Versione mostrata nell'header: bumpala a ogni cambiamento, così si vede se l'app sul
## Mac è aggiornata (un'app già avviata NON ricarica i prompt: va rilanciata).
const VERSIONE := "2.19"

# --- palette (dal mockup) ---
const C_SEA_DEEP := Color("131020")
const C_SEA := Color("1a1630")
const C_SEA2 := Color("221c3a")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")
const C_GOLD_DEEP := Color("9a7a34")
const C_OXBLOOD := Color("b04a34")
const C_VERDIGRIS := Color("4e9a8e")

const PLACEHOLDER := ""  # dal file testi (vedi _colonna_rapsodia)

# id delle voci di menu
const VOCE_OLIMPO := 0
const VOCE_LOG := 1
const VOCE_CIURMA := 2
const VOCE_IMPOSTAZIONI := 10

var _serif: FontFile
var _serif_bold: FontFile
var _serif_italic: FontFile

var _narrazione: RichTextLabel
var _spunti_box: VBoxContainer
var _ultima_narrazione: String = ""
var _diario_box: VBoxContainer
var _diario_scroll: ScrollContainer
var _mappa: MappaViaggio
var _input: LineEdit
var _episodio: Label
var _fin_olimpo: FinestraTesto   # finestra separata: traccia dell'ultimo turno
var _fin_log: FinestraTesto      # finestra separata: log delle chiamate LLM
var _fin_ciurma: FinestraTesto   # chat INTERATTIVA coi compagni
var _btn_ciurma: Button
var _menu_view: PopupMenu
var _lbl_motore: Label
var _scala_schermo: float = 1.0
var _zoom_utente: float = 1.0
var _motore_da_ripristinare: int = -1
var _fin_impostazioni: FinestraImpostazioni
var _btn_olimpo: Button
var _btn_log: Button
var _btn_agisci: Button
var _chk_ollama: CheckButton
var _chk_esterno: CheckButton
var _opt_provider: OptionButton
var _opt_modello: OptionButton
var _stat_bars := {}
var _stat_vals := {}
var _busy := false
var _finita := false

func _line() -> Color:
	var c := C_GOLD
	c.a = 0.20
	return c

func _ready() -> void:
	_serif = load("res://fonts/Cardo-Regular.ttf")
	_serif_bold = load("res://fonts/Cardo-Bold.ttf")
	_serif_italic = load("res://fonts/Cardo-Italic.ttf")
	_prepara_finestra()
	_costruisci_ui()
	Impostazioni.applica_chiavi_all_ambiente()  # chiavi utente -> ambiente
	_ripristina_preferenze()
	LLMManager.llm_log.connect(_on_llm_log)
	GameManager.nuova_partita(0)
	_apri_scena()
	_ripristina_finestre()
	_apri_sipario()

## La schermata d'apertura sta SOPRA il gioco gia' pronto: mentre si guarda il marchio, la
## partita e' stata avviata e la scena aperta. Cosi' non aggiunge un solo istante d'attesa,
## copre quella che c'era. In headless (i test) non ha senso: non c'e' nessuno a guardarla.
func _apri_sipario() -> void:
	if _senza_schermo():
		return
	var s := Splash.new()
	add_child(s)   # ultimo figlio: sta davanti a tutto il resto della schermata

## Rimette le scelte dell'ultima sessione: dimensione interfaccia, provider/modello e
## motore. Cosi' non si riconfigura tutto a ogni avvio.
func _ripristina_preferenze() -> void:
	imposta_zoom(float(Impostazioni.leggi("zoom", 1.0)))
	_ripristina_provider()
	var modello := String(Impostazioni.leggi("modello", ""))
	if modello != "":
		LLMManager.imposta_modello(modello)
	LLMManager.mock_mode = true  # il motore reale si attiva dopo, senza bloccare l'avvio
	var motore := int(Impostazioni.leggi("motore", FinestraImpostazioni.MOTORE_MOCK))
	if motore != FinestraImpostazioni.MOTORE_MOCK:
		_motore_da_ripristinare = motore

## Rimette il provider scelto e se passare o no dal gateway. Due preferenze distinte,
## perché sono due scelte distinte.
##
## MIGRAZIONE: prima il gateway era una voce dell'elenco dei provider (la prima, dal file
## 0_gateway.json) e si salvava la POSIZIONE. Ora non è più un provider, quindi le vecchie
## posizioni sono tutte slittate di uno: la 0 voleva dire "gateway", le altre indicano il
## provider precedente. Senza questa conversione chi riapre il gioco si ritroverebbe un
## provider diverso da quello che aveva scelto, e senza capire perché.
func _ripristina_provider() -> void:
	var nome := String(Impostazioni.leggi("provider_nome", ""))
	if nome == "" and Impostazioni.leggi("provider_idx", null) != null:
		var vecchio := int(Impostazioni.leggi("provider_idx", 0))
		if vecchio == 0:
			Impostazioni.scrivi("usa_gateway", true)   # "0" era il gateway
		var nomi: Array = LLMManager.nomi_profili_esterni()
		var nuovo := clampi(vecchio - 1, 0, maxi(0, nomi.size() - 1))
		nome = String(nomi[nuovo]) if not nomi.is_empty() else ""
		Impostazioni.scrivi("provider_nome", nome)
		Impostazioni.dimentica("provider_idx")         # la vecchia chiave non vale più
	var idx := LLMManager.indice_profilo(nome)
	if idx >= 0:
		LLMManager.imposta_profilo_esterno(idx)
	LLMManager.usa_gateway = bool(Impostazioni.leggi("usa_gateway", false))

## Riapre le viste che erano aperte, dove e come erano; poi riattiva il motore scelto.
func _ripristina_finestre() -> void:
	if _senza_schermo():
		return
	for riga in _finestre_servizio():
		var g: Dictionary = Impostazioni.geometria(String(riga[0]))
		if g.is_empty():
			continue
		var fin: FinestraTesto = riga[1]
		if g["dim"].x > 200 and g["dim"].y > 150:
			fin.size = g["dim"]
		fin.position = g["pos"]
		if g["aperta"]:
			riga[2].button_pressed = true
			_spunta_view(int(riga[3]), true)
	if _motore_da_ripristinare >= 0:
		var m := _motore_da_ripristinare
		_motore_da_ripristinare = -1
		await _on_motore_scelto(m)

## Alla chiusura salvo dove sono finite le finestre, per ritrovarle uguali.
func _notification(che: int) -> void:
	if che == NOTIFICATION_WM_CLOSE_REQUEST or che == NOTIFICATION_PREDELETE:
		_salva_geometrie()

func _salva_geometrie() -> void:
	if _senza_schermo():
		return
	for riga in _finestre_servizio():
		var fin: FinestraTesto = riga[1]
		Impostazioni.salva_geometria(String(riga[0]), fin.position, fin.size, fin.visible)

## L'elenco unico delle finestre di servizio: [chiave, finestra, pulsante, voce di menu].
## Un elenco solo — quando ne ho aggiunta una a mano in tre punti diversi, la ciurma e'
## rimasta fuori da tutti e tre (scala, geometria, ripristino).
func _finestre_servizio() -> Array:
	var out: Array = []
	for riga in [["log", _fin_log, _btn_log, VOCE_LOG],
			["olimpo", _fin_olimpo, _btn_olimpo, VOCE_OLIMPO],
			["ciurma", _fin_ciurma, _btn_ciurma, VOCE_CIURMA]]:
		if riga[1] != null:
			out.append(riga)
	return out

## Vero in headless (i test): li' non esiste un vero server finestre e le operazioni di
## geometria falliscono. Le preferenze visive non hanno senso senza schermo.
func _senza_schermo() -> bool:
	return DisplayServer.get_name() == "headless"

func _prepara_finestra() -> void:
	var w := get_window()
	w.title = Testi.s("app/titolo_finestra")
	w.min_size = Vector2i(1000, 680)
	w.mode = Window.MODE_MAXIMIZED
	# HiDPI/Retina: su schermi ad alta densita' Godot disegna a pixel nativi e la UI
	# risulta minuscola. Applichiamo un fattore di scala. Usiamo la scala riportata dal
	# sistema; se non e' affidabile ma lo schermo e' molto largo, la deriviamo.
	var scr := w.current_screen
	var scala := maxf(DisplayServer.screen_get_scale(scr), 1.0)
	var larghezza := DisplayServer.screen_get_size(scr).x
	if scala <= 1.0 and larghezza >= 2560:
		scala = clampf(roundf(float(larghezza) / 1600.0), 1.0, 3.0)
	_scala_schermo = clampf(scala, 1.0, 3.0)
	_applica_scala()

## Scala dell'interfaccia = quella dello schermo per un moltiplicatore scelto dall'utente
## (Settings). Va applicata a OGNI finestra: le secondarie non la ereditano da sola.
func _applica_scala() -> void:
	var f := _scala_schermo * _zoom_utente
	get_window().content_scale_factor = clampf(f, 1.0, 3.0)
	for riga in _finestre_servizio():
		riga[1].applica_scala(f)
	if _fin_impostazioni:
		_fin_impostazioni.adegua_a_scala(f)  # cresce con la scala: altrimenti il contenuto sfora

## Chiamata da Settings quando l'utente cambia la dimensione dell'interfaccia.
func imposta_zoom(fattore: float) -> void:
	_zoom_utente = clampf(fattore, 0.8, 2.0)
	Impostazioni.scrivi("zoom", _zoom_utente)  # unico punto in cui la scelta si persiste
	_applica_scala()

# --- helper di stile ---

func _sfondo(pad: int, bg: Color, bordo: Color, spina_oro := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(3)
	s.border_color = bordo
	s.set_border_width_all(1)
	if spina_oro:
		s.border_width_left = 3
		s.border_color = C_GOLD  # unico colore: la spina sinistra piu' spessa fa da accento
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

func _titolo(testo: String, dim: int, col: Color, font: FontFile) -> Label:
	var l := Label.new()
	l.text = testo
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", dim)
	l.add_theme_color_override("font_color", col)
	return l

func _pannello(bg: Color, bordo: Color, spina_oro := false, pad := 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sfondo(pad, bg, bordo, spina_oro))
	return p

# --- costruzione UI ---

func _costruisci_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var sfondo := ColorRect.new()
	sfondo.color = C_SEA_DEEP
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sfondo)

	var margine := MarginContainer.new()
	margine.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lato in ["left", "top", "right", "bottom"]:
		margine.add_theme_constant_override("margin_" + lato, 26)
	add_child(margine)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margine.add_child(root)

	# Header: titolo oro + tag
	var header := HBoxContainer.new()
	root.add_child(header)
	var titolo := _titolo(Testi.s("app/titolo"), 30, C_GOLD, _serif_bold)
	header.add_child(titolo)
	# Numero di versione accanto al nome: per capire a colpo d'occhio se l'app è aggiornata.
	var ver := _titolo("v%s" % VERSIONE, 13, C_VERDIGRIS, _serif)
	ver.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	header.add_child(ver)
	# Barra dei menu: le viste di servizio e le impostazioni stanno qui, non sparse
	# tra i controlli di gioco.
	var stacco := Control.new()
	stacco.custom_minimum_size = Vector2(28, 0)
	header.add_child(stacco)
	var menu := _barra_menu()
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(menu)
	var spazio := Control.new()
	spazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spazio)
	var tag := _titolo(Testi.s("app/sottotitolo"), 13, C_BONE_DIM, _serif_italic)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(tag)
	root.add_child(_riga_oro())

	# Corpo: colonne
	var colonne := HBoxContainer.new()
	colonne.add_theme_constant_override("separation", 22)
	colonne.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(colonne)

	colonne.add_child(_colonna_rapsodia())
	colonne.add_child(_colonna_aside())
	_crea_finestre_servizio()

## Log LLM e Vista Olimpo vivono in finestre NATIVE separate: si aprono solo quando
## servono, si spostano su un altro schermo e lasciano tutto lo spazio alla narrazione.
func _crea_finestre_servizio() -> void:
	get_tree().root.gui_embed_subwindows = false  # finestre vere del sistema, non incorporate
	# Due finestre DISTINTE, in posizioni diverse: non devono sembrare la stessa che
	# cambia contenuto. Le sfalso in base allo schermo.
	# Dimensioni e posizioni RICAVATE DALLO SCHERMO, non fisse: due riquadri affiancati
	# che non si coprono mai. (Con misure fisse il window manager riposizionava la seconda
	# perche' usciva dallo schermo, e finivano una sopra l'altra.)
	var schermo := DisplayServer.screen_get_size()
	var margine := 24
	var larg: int = clampi(int((schermo.x - margine * 3) / 2.0), 420, 900)
	var alt: int = clampi(schermo.y - 160, 360, 900)
	var y := 70
	var alto := Vector2i(schermo.x - larg * 2 - margine * 2, y)
	var basso := Vector2i(schermo.x - larg - margine, y)
	if schermo.x < 1400:  # schermo stretto: impilate, ognuna di mezza altezza
		alt = clampi(int((schermo.y - 200) / 2.0), 260, 520)
		alto = Vector2i(maxi(margine, schermo.x - larg - margine), y)
		basso = Vector2i(alto.x, y + alt + 46)
	_fin_log = FinestraTesto.new(Testi.s("finestre/log_titolo"), true, Vector2i(larg, alt), alto)
	_fin_log.chiusa.connect(func():
		_btn_log.button_pressed = false
		_spunta_view(VOCE_LOG, false))
	add_child(_fin_log)
	_fin_impostazioni = FinestraImpostazioni.new()
	_fin_impostazioni.motore_scelto.connect(_on_motore_scelto)
	_fin_impostazioni.zoom_scelto.connect(imposta_zoom)
	add_child(_fin_impostazioni)
	_fin_olimpo = FinestraTesto.new(Testi.s("finestre/olimpo_titolo"), false, Vector2i(larg, alt), basso)
	_fin_olimpo.chiusa.connect(func():
		_btn_olimpo.button_pressed = false
		_spunta_view(VOCE_OLIMPO, false))
	add_child(_fin_olimpo)

	# La ciurma: stessa finestra, ma con la barra d'invio. E' l'unica vista in cui Ulisse
	# scrive davvero a qualcuno. La sfalso di poco, cosi' non nasce sopra le altre due.
	_fin_ciurma = FinestraTesto.new(Testi.s("ciurma/titolo"), false, Vector2i(larg, alt),
		basso + Vector2i(-36, 36))
	_fin_ciurma.interattiva = true
	_fin_ciurma.inviato.connect(_on_ciurma_invio)
	_fin_ciurma.chiusa.connect(func():
		_btn_ciurma.button_pressed = false
		_spunta_view(VOCE_CIURMA, false))
	add_child(_fin_ciurma)
	_applica_scala()  # le sub-window non ereditano la scala: gliela do io

## Barra dei menu (View, Settings). Le voci di View sono spuntabili: riflettono se la
## finestra è aperta.
func _barra_menu() -> Control:
	var barra := MenuBar.new()
	# IMPORTANTE su macOS: di default Godot sposta i menu nella barra di sistema in cima
	# allo schermo, e nella finestra non si vede nulla. Li vogliamo DENTRO la finestra,
	# uguali su tutti i sistemi.
	barra.prefer_global_menu = false
	barra.add_theme_font_size_override("font_size", 16)
	barra.custom_minimum_size = Vector2(210, 34)
	barra.add_theme_color_override("font_color", C_BONE)
	barra.add_theme_color_override("font_hover_color", C_GOLD)
	# Riquadro visibile: dev'essere chiaro che sono comandi, non decorazione del titolo.
	barra.add_theme_stylebox_override("normal", _sfondo(7, C_SEA2, Color(C_GOLD, 0.45)))
	barra.add_theme_stylebox_override("hover", _sfondo(7, C_SEA2, C_GOLD))
	barra.add_theme_stylebox_override("pressed", _sfondo(7, C_GOLD_DEEP, C_GOLD))

	_menu_view = PopupMenu.new()
	_menu_view.name = Testi.s("menu/view")
	_menu_view.add_check_item(Testi.s("menu/vista_olimpo"), VOCE_OLIMPO)
	_menu_view.add_check_item(Testi.s("menu/ciurma"), VOCE_CIURMA)
	_menu_view.add_check_item(Testi.s("menu/log_llm"), VOCE_LOG)
	_menu_view.id_pressed.connect(_on_menu_view)
	barra.add_child(_menu_view)

	var menu_set := PopupMenu.new()
	menu_set.name = Testi.s("menu/settings")
	menu_set.add_item(Testi.s("menu/impostazioni"), VOCE_IMPOSTAZIONI)
	menu_set.id_pressed.connect(func(id): if id == VOCE_IMPOSTAZIONI: _apri_impostazioni())
	barra.add_child(menu_set)
	return barra

## Scelta del motore dal menu Settings: mock / Ollama locale / provider esterno.
func _on_motore_scelto(modo: int) -> void:
	match modo:
		FinestraImpostazioni.MOTORE_MOCK:
			_chk_ollama.set_pressed_no_signal(false)
			_chk_esterno.set_pressed_no_signal(false)
			LLMManager.mock_mode = true
			_narrazione.append_text("[color=%s]%s[/color]\n" % [C_VERDIGRIS.to_html(), Testi.s("motore/dei_simulati")])
		FinestraImpostazioni.MOTORE_OLLAMA:
			_chk_esterno.set_pressed_no_signal(false)
			_chk_ollama.set_pressed_no_signal(true)
			await _attiva_reale(false)
		FinestraImpostazioni.MOTORE_ESTERNO:
			_chk_ollama.set_pressed_no_signal(false)
			_chk_esterno.set_pressed_no_signal(true)
			await _attiva_reale(true)
	_aggiorna_indicatore_motore()

## Riga discreta sotto l'input: quale motore sta dando voce agli dèi.
func _aggiorna_indicatore_motore() -> void:
	if _lbl_motore == null:
		return
	if LLMManager.mock_mode:
		_lbl_motore.text = Testi.s("motore/simulato")
	else:
		var dove := Testi.s("motore/nome_esterno") if LLMManager.provider_esterno else Testi.s("motore/nome_ollama")
		_lbl_motore.text = Testi.s("motore/in_uso", [dove, LLMManager.modello_atteso()])

func _apri_impostazioni() -> void:
	_fin_impostazioni.popup_centered()

func _on_menu_view(id: int) -> void:
	var i := _menu_view.get_item_index(id)
	var acceso := not _menu_view.is_item_checked(i)
	_menu_view.set_item_checked(i, acceso)
	match id:
		VOCE_OLIMPO: _btn_olimpo.button_pressed = acceso
		VOCE_CIURMA: _btn_ciurma.button_pressed = acceso
		_: _btn_log.button_pressed = acceso

## Tiene la spunta del menu allineata allo stato reale della finestra.
func _spunta_view(id: int, acceso: bool) -> void:
	if _menu_view:
		_menu_view.set_item_checked(_menu_view.get_item_index(id), acceso)

func _riga_oro() -> Control:
	var r := ColorRect.new()
	r.color = _line()
	r.custom_minimum_size = Vector2(0, 1)
	return r

func _colonna_rapsodia() -> Control:
	var pan := _pannello(C_SEA, _line(), true, 28)
	pan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pan.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pan.add_child(v)

	var marchio := _titolo(Testi.s("app/marchio_poeta"), 13, C_GOLD, _serif)
	v.add_child(marchio)

	_narrazione = RichTextLabel.new()
	_narrazione.bbcode_enabled = true
	_narrazione.scroll_following = true
	_narrazione.fit_content = false
	_narrazione.selection_enabled = true       # si può selezionare il testo…
	_narrazione.context_menu_enabled = true     # …e copiarlo col tasto destro / Cmd+C
	_narrazione.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrazione.add_theme_font_override("normal_font", _serif)
	_narrazione.add_theme_font_override("bold_font", _serif_bold)
	_narrazione.add_theme_font_override("italics_font", _serif_italic)
	_narrazione.add_theme_font_size_override("normal_font_size", 21)
	_narrazione.add_theme_color_override("default_color", C_BONE)
	v.add_child(_narrazione)

	v.add_child(_riga_oro())

	# Gli spunti d'azione generati sul contesto (cliccabili), sotto la domanda.
	v.add_child(_titolo(Testi.s("gioco/domanda"), 15, C_GOLD, _serif_italic))
	_spunti_box = VBoxContainer.new()
	_spunti_box.add_theme_constant_override("separation", 7)
	v.add_child(_spunti_box)

	# Il quarto percorso: scrivere liberamente.

	var campo := HBoxContainer.new()
	campo.add_theme_constant_override("separation", 10)
	v.add_child(campo)

	_input = LineEdit.new()
	_input.placeholder_text = Testi.s("gioco/placeholder")
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_color_override("font_color", C_BONE)
	_input.add_theme_color_override("font_placeholder_color", C_BONE_DIM)
	_input.add_theme_font_size_override("font_size", 17)
	_input.add_theme_stylebox_override("normal", _sfondo(11, C_SEA2, Color(C_OXBLOOD, 0.45)))
	_input.add_theme_stylebox_override("focus", _sfondo(11, C_SEA2, C_OXBLOOD))
	_input.text_submitted.connect(_on_invio)
	campo.add_child(_input)

	var btn := Button.new()
	btn.text = Testi.s("gioco/agisci")
	btn.add_theme_font_override("font", _serif)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", _sfondo(12, C_OXBLOOD, C_OXBLOOD))
	btn.add_theme_stylebox_override("hover", _sfondo(12, Color("c4553e"), Color("c4553e")))
	btn.add_theme_stylebox_override("pressed", _sfondo(12, C_GOLD_DEEP, C_GOLD_DEEP))
	btn.pressed.connect(_on_agisci)
	campo.add_child(btn)
	_btn_agisci = btn

	var hint := _titolo(Testi.s("gioco/suggerimento"), 12, C_BONE_DIM, _serif_italic)
	v.add_child(hint)
	_lbl_motore = _titolo("", 12, C_VERDIGRIS, _serif)
	v.add_child(_lbl_motore)

	# opzioni
	# I comandi del motore LLM sono nel menu Settings: qui restano solo come attuatori
	# (invisibili), così la schermata di gioco non si riempie di interruttori.
	var opz := HBoxContainer.new()
	opz.add_theme_constant_override("separation", 14)
	opz.visible = false
	v.add_child(opz)
	_btn_olimpo = Button.new()
	_btn_olimpo.text = Testi.s("menu/vista_olimpo")
	_btn_olimpo.toggle_mode = true
	_btn_olimpo.add_theme_color_override("font_color", C_BONE_DIM)
	_btn_olimpo.add_theme_stylebox_override("normal", _sfondo(8, C_SEA2, _line()))
	_btn_olimpo.add_theme_stylebox_override("hover", _sfondo(8, C_SEA2, C_GOLD))
	_btn_olimpo.add_theme_stylebox_override("pressed", _sfondo(8, C_GOLD_DEEP, C_GOLD))
	_btn_olimpo.toggled.connect(_on_toggle_olimpo)
	opz.add_child(_btn_olimpo)  # nel contenitore invisibile: comandato dal menu View
	# Log LLM: finestra separata col traffico verso il modello.
	_btn_log = Button.new()
	_btn_log.text = Testi.s("menu/log_llm")
	_btn_log.toggle_mode = true
	_btn_log.add_theme_color_override("font_color", C_BONE_DIM)
	_btn_log.add_theme_stylebox_override("normal", _sfondo(8, C_SEA2, _line()))
	_btn_log.add_theme_stylebox_override("hover", _sfondo(8, C_SEA2, C_GOLD))
	_btn_log.add_theme_stylebox_override("pressed", _sfondo(8, C_GOLD_DEEP, C_GOLD))
	_btn_ciurma = Button.new()
	_btn_ciurma.toggle_mode = true
	_btn_ciurma.visible = false
	_btn_ciurma.toggled.connect(_on_toggle_ciurma)
	opz.add_child(_btn_ciurma)
	_btn_log.toggled.connect(_on_toggle_log)
	opz.add_child(_btn_log)     # idem: comandato dal menu View
	_chk_ollama = CheckButton.new()
	_chk_ollama.text = "Ollama (locale)"
	_chk_ollama.add_theme_color_override("font_color", C_BONE_DIM)
	_chk_ollama.toggled.connect(_on_toggle_ollama)
	opz.add_child(_chk_ollama)

	# Flag: usa un LLM esterno (API cloud) invece di Ollama locale.
	_chk_esterno = CheckButton.new()
	_chk_esterno.text = "LLM esterno (API)"
	_chk_esterno.add_theme_color_override("font_color", C_BONE_DIM)
	_chk_esterno.tooltip_text = Testi.s("impostazioni/tooltip_esterno")
	_chk_esterno.toggled.connect(_on_toggle_esterno)
	opz.add_child(_chk_esterno)

	# Quale provider esterno (Mistral / Gemini / OpenAI …).
	_opt_provider = OptionButton.new()
	_opt_provider.add_theme_color_override("font_color", C_BONE)
	_opt_provider.add_theme_font_size_override("font_size", 13)
	_opt_provider.tooltip_text = Testi.s("impostazioni/tooltip_provider")
	for nome in LLMManager.nomi_profili_esterni():
		_opt_provider.add_item(String(nome))
	_opt_provider.disabled = _opt_provider.item_count == 0
	_opt_provider.item_selected.connect(_on_provider_scelto)
	opz.add_child(_opt_provider)

	# Selettore del modello: popolato quando Ollama e' attivo, coi modelli installati.
	_opt_modello = OptionButton.new()
	_opt_modello.disabled = true
	_opt_modello.add_theme_color_override("font_color", C_BONE)
	_opt_modello.add_theme_font_size_override("font_size", 13)
	_opt_modello.tooltip_text = Testi.s("impostazioni/tooltip_modello")
	_opt_modello.item_selected.connect(_on_modello_scelto)
	opz.add_child(_opt_modello)

	return pan

func _colonna_aside() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(320, 0)
	v.size_flags_horizontal = Control.SIZE_FILL
	v.add_theme_constant_override("separation", 22)

	# Carta del viaggio (dove si trova Ulisse)
	var carta_m := _pannello(Color(1, 1, 1, 0.012), _line())
	v.add_child(carta_m)
	var vm := VBoxContainer.new()
	vm.add_theme_constant_override("separation", 10)
	carta_m.add_child(vm)
	vm.add_child(_titolo(Testi.s("pannelli/carta_viaggio"), 13, C_GOLD, _serif_bold))
	_mappa = MappaViaggio.new()
	_mappa.custom_minimum_size = Vector2(0, 200)
	vm.add_child(_mappa)

	# Carta Diario di bordo (scorrevole: cresce di una voce a turno e non deve gonfiare il
	# layout, altrimenti spinge l'input fuori schermo). Si espande per riempire lo spazio.
	var carta_d := _pannello(Color(1, 1, 1, 0.012), _line())
	carta_d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(carta_d)
	var vd := VBoxContainer.new()
	vd.add_theme_constant_override("separation", 12)
	carta_d.add_child(vd)
	vd.add_child(_titolo(Testi.s("pannelli/diario"), 13, C_GOLD, _serif_bold))
	_diario_scroll = ScrollContainer.new()
	_diario_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_diario_scroll.custom_minimum_size = Vector2(0, 140)
	_diario_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vd.add_child(_diario_scroll)
	_diario_box = VBoxContainer.new()
	_diario_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diario_box.add_theme_constant_override("separation", 8)
	_diario_scroll.add_child(_diario_box)
	_episodio = _titolo("", 13, C_BONE_DIM, _serif_italic)
	vd.add_child(_episodio)

	# Carta La tua condizione
	var carta_c := _pannello(Color(1, 1, 1, 0.012), _line())
	v.add_child(carta_c)
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 14)
	carta_c.add_child(vc)
	vc.add_child(_titolo(Testi.s("pannelli/condizione"), 13, C_GOLD, _serif_bold))
	vc.add_child(_meter(Testi.s("pannelli/astuzia"), "metis"))
	vc.add_child(_meter(Testi.s("pannelli/animo"), "animo"))
	vc.add_child(_meter(Testi.s("pannelli/ciurma"), "ciurma"))
	vc.add_child(_meter(Testi.s("pannelli/tracotanza"), "hybris"))
	var absent := _titolo(Testi.s("pannelli/nota_dei_nascosti"), 12, C_BONE_DIM, _serif_italic)
	absent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	absent.custom_minimum_size = Vector2(290, 0)
	vc.add_child(absent)

	return v

func _meter(etichetta: String, chiave: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var riga := HBoxContainer.new()
	box.add_child(riga)
	var k := _titolo(etichetta, 14, C_BONE_DIM, _serif_italic)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	riga.add_child(k)
	var val := _titolo("—", 15, C_BONE, _serif)
	riga.add_child(val)
	_stat_vals[chiave] = val

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.06)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = C_GOLD if chiave != "hybris" else C_OXBLOOD
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	_stat_bars[chiave] = bar
	box.add_child(bar)
	return box

func _on_llm_log(riga: String) -> void:
	if _fin_log:
		_fin_log.aggiungi(riga)

# --- gioco ---

func _apri_scena() -> void:
	_episodio.text = "· %s ·" % _nome_tappa()
	_ultima_narrazione = GameManager.intro_corrente()
	_narrazione.append_text("[i]" + Testi.s("gioco/omero") + "[/i] %s\n\n" % _ultima_narrazione)
	_aggiorna_stats()
	_aggiorna_mappa()
	_aggiorna_ciurma()
	_aggiorna_indicatore_motore()
	_input.grab_focus()
	await _rigenera_spunti()

func _aggiorna_mappa() -> void:
	if _mappa == null:
		return
	var punti: Array = []
	for id in GameManager.episodi.ordine():
		var ep := GameManager.episodi.get_episodio(id)
		if ep:
			punti.append({"id": id, "nome": ep.nome, "pos": ep.mappa})
	_mappa.imposta(punti, GameManager.stato.viaggio["corrente"], GameManager.stato.viaggio.get("completati", []))

func _on_invio(_t: String) -> void:
	_on_agisci()

## Un turno di gioco pieno: il mondo gira e gli dei deliberano. Le parole scambiate coi
## compagni passano invece da _on_ciurma_invio, che costa una chiamata sola.
func _on_agisci() -> void:
	if _busy or _finita:
		return
	var testo := _input.text.strip_edges()
	if testo == "":
		return
	_busy = true
	_input.editable = false
	_btn_agisci.text = Testi.s("gioco/attesa")
	_btn_agisci.disabled = true
	_narrazione.append_text("[color=#8a9bb0]› %s[/color]\n" % testo)
	_input.text = ""
	if not LLMManager.mock_mode:
		_on_llm_log("[color=%s]— turno %d —[/color]" % [C_VERDIGRIS.to_html(), GameManager.stato.turno + 1])

	# Mentre il turno gira, gli spunti vecchi non valgono piu': li svuoto.
	_pulisci_spunti()
	var esito: Dictionary = await GameManager.esegui_turno(testo)

	_ultima_narrazione = String(esito["voce"].get("narrazione_omero", ""))
	if _ultima_narrazione != "":
		_narrazione.append_text("[i]" + Testi.s("gioco/omero") + "[/i] %s\n\n" % _ultima_narrazione)
	# Fuori-mondo: Omero tace, al suo posto un avviso in chiaro (non è la voce del poeta).
	var ammon := String(esito["voce"].get("ammonizione", ""))
	if ammon != "":
		_narrazione.append_text(_avviso(ammon))
	_aggiungi_diario()
	_aggiorna_stats()
	if _fin_olimpo.visible:
		_aggiorna_olimpo()
	_aggiorna_ciurma()
	# La traccia del turno va nel Log: e' lo strumento di ispezione, non una voce di chat.
	# Sempre, anche col motore simulato — serve proprio quando l'LLM non parla.
	# Le parentesi quadre della traccia (tag=[...], [registro]) sono BBCode per la
	# RichTextLabel: vanno protette, o il testo sparisce a pezzi.
	_on_llm_log("[color=%s]%s[/color]" % [
		C_GOLD.to_html(), TraceFormatter.turno(esito["voce"]).replace("[", "[lb]")])

	# Traversata verso la nuova tappa: il beat di partenza/viaggio, così non ci si
	# "teletrasporta" da un luogo all'altro.
	var trans := String(esito.get("transizione", ""))
	if esito.get("avanzato", false) and trans != "":
		_narrazione.append_text("[i]" + Testi.s("gioco/omero") + "[/i] %s\n\n" % trans)
	if esito.get("avanzato", false) and esito["esito"] == "continua":
		_episodio.text = "· %s ·" % _nome_tappa()
		_ultima_narrazione = String(esito.get("intro", ""))
		_narrazione.append_text("[color=%s]— %s —[/color]\n[i]Omero:[/i] %s\n\n" % [C_GOLD.to_html(), _nome_tappa(), _ultima_narrazione])
	_aggiorna_mappa()

	if esito["esito"] != "continua":
		_finita = true
		_input.editable = false
		if esito["esito"] == "itaca":
			_narrazione.append_text("\n[b][color=%s]%s[/color][/b]\n" % [C_VERDIGRIS.to_html(), Testi.s("gioco/vittoria")])
		else:
			_narrazione.append_text("\n[b][color=%s]%s[/color][/b]\n" % [C_OXBLOOD.to_html(), Testi.s("gioco/fine", [esito["esito"]])])
	else:
		# Gli spunti arrivano gia' insieme alla narrazione: nessuna seconda chiamata.
		# Eccezione: se la tappa e' cambiata si riferirebbero alla scena vecchia, e allora
		# vale la pena rigenerarli sulla nuova.
		if esito.get("avanzato", false):
			await _rigenera_spunti()
		else:
			_mostra_spunti(esito.get("spunti", []))
		_input.editable = true
		_input.grab_focus()
	_btn_agisci.text = Testi.s("gioco/agisci")
	_btn_agisci.disabled = false
	_busy = false

# --- spunti (pre-confezionati, generati dall'LLM sul contesto) ---

func _rigenera_spunti() -> void:
	_pulisci_spunti()
	if not LLMManager.mock_mode:  # in reale la generazione e' lenta: mostro un'attesa
		_spunti_box.add_child(_titolo(Testi.s("gioco/spunti_in_arrivo"), 13, C_BONE_DIM, _serif_italic))
	var contesto := {
		"episodio": _nome_tappa(),
		"scena": GameManager.scena_corrente(),
		"cronaca": GameManager.stato.cronaca,  # memoria: spunti coerenti col già accaduto
		"narrazione": _ultima_narrazione,
	}
	_mostra_spunti(await LLMManager.suggerisci(contesto))

## Mette a schermo tre appigli. Separata dalla generazione perche' gli spunti possono
## arrivare da due strade: insieme alla narrazione di Omero (il caso normale, gratis) o
## dal Suggeritore (all'apertura di una scena, dove Omero non e' stato chiamato).
func _mostra_spunti(spunti: Array) -> void:
	_pulisci_spunti()
	for sp in spunti:
		_spunti_box.add_child(_cue(String(sp.get("testo", "")), bool(sp.get("rischio", false))))

func _pulisci_spunti() -> void:
	for c in _spunti_box.get_children():
		c.queue_free()

func _cue(testo: String, rischio: bool) -> Button:
	var accento := C_OXBLOOD if rischio else C_GOLD
	var b := Button.new()
	b.text = "›  " + testo
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_override("font", _serif)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", C_BONE)
	b.add_theme_color_override("font_hover_color", C_BONE)
	b.add_theme_stylebox_override("normal", _sfondo(11, Color(1, 1, 1, 0.015), _line()))
	b.add_theme_stylebox_override("hover", _sfondo(11, Color(accento, 0.09), Color(accento, 0.5)))
	b.add_theme_stylebox_override("pressed", _sfondo(11, Color(accento, 0.16), accento))
	b.pressed.connect(_scegli_spunto.bind(testo))
	return b

func _scegli_spunto(testo: String) -> void:
	if _busy or _finita:
		return
	_input.text = testo
	_on_agisci()

## Avviso per l'azione fuori-mondo. Colore CHIARO e testo dritto in grassetto: il
## rosso-sangue scuro in corsivo, su fondo notte, era illeggibile.
func _avviso(classe: String) -> String:
	var giallo := "#f0c26a"   # ambra chiara: buon contrasto sul fondo scuro
	var chiaro := "#f3b9a4"   # rosso sbiadito ma leggibile
	match classe:
		"richiamo":
			return "[b][color=%s]%s[/color][/b]\n\n" % [giallo, Testi.s("avvisi/richiamo")]
		"smarrimento":
			return "[b][color=%s]%s[/color][/b]\n\n" % [chiaro, Testi.s("avvisi/smarrimento")]
		"follia":
			return "[b][color=%s]%s[/color][/b]\n\n" % [chiaro, Testi.s("avvisi/follia")]
	return ""

var _stat_prec := {}  # valori del turno prima: per mostrare di quanto sono cambiati

func _aggiorna_stats() -> void:
	var st: Dictionary = GameManager.stato.ulisse["stat"]
	var ciurma: Dictionary = st["ciurma"]
	var hybris: int = int(GameManager.stato.ulisse["hybris"])
	_imposta_stat("metis", st["metis"], 100, "%d%s" % [st["metis"], _variazione("metis", int(st["metis"]))])
	_imposta_stat("animo", st["animo"], 100, "%d%s" % [st["animo"], _variazione("animo", int(st["animo"]))])
	_imposta_stat("ciurma", 100.0 * float(ciurma["vivi"]) / max(1, int(ciurma["iniziali"])), 100,
		Testi.s("pannelli/ciurma_conteggio", [ciurma["vivi"], ciurma["iniziali"]]) + _variazione("ciurma", int(ciurma["vivi"])))
	_imposta_stat("hybris", hybris, 100, "%d%s" % [hybris, _variazione("hybris", hybris)])

## Scarto rispetto al turno precedente, es. "  −2": rende visibile CHE COSA e' cambiato.
func _variazione(chiave: String, valore: int) -> String:
	var prec: int = _stat_prec.get(chiave, valore)
	_stat_prec[chiave] = valore
	var d := valore - prec
	if d == 0:
		return ""
	return "  %s%d" % ["+" if d > 0 else "−", abs(d)]

func _imposta_stat(chiave: String, valore: float, _massimo: int, testo: String) -> void:
	if _stat_bars.has(chiave):
		_stat_bars[chiave].value = valore
	if _stat_vals.has(chiave):
		_stat_vals[chiave].text = testo

func _aggiungi_diario() -> void:
	var ultime: Array = GameManager.stato.diario
	if ultime.is_empty():
		return
	var d: Dictionary = ultime[-1]
	var col: Color = {"ill": C_OXBLOOD, "fair": C_VERDIGRIS, "neutro": C_BONE_DIM}.get(d.get("esito", "neutro"), C_BONE_DIM)
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	var punto := ColorRect.new()
	punto.color = col
	punto.custom_minimum_size = Vector2(7, 7)
	punto.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	riga.add_child(punto)
	var testo := RichTextLabel.new()
	testo.text = d.get("voce", "")
	testo.fit_content = true
	testo.scroll_active = false
	testo.selection_enabled = true       # anche il diario è copiabile
	testo.context_menu_enabled = true
	testo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	testo.add_theme_font_override("normal_font", _serif)
	testo.add_theme_font_size_override("normal_font_size", 15)
	testo.add_theme_color_override("default_color", C_BONE)
	testo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	testo.custom_minimum_size = Vector2(240, 0)
	riga.add_child(testo)
	_diario_box.add_child(riga)
	# scorri all'ultima voce (dopo che il layout ha calcolato l'altezza)
	if _diario_scroll:
		_diario_scroll.set_deferred("scroll_vertical", 1_000_000)

## La Vista Olimpo e' una CHAT in sola lettura, e SOLO quello: gli dei si parlano e il
## giocatore assiste. La traccia tecnica del turno (envelope, risvegli, delta) non e' una
## voce e non sta qui: va nel Log LLM, dove si guardano i numeri.
func _aggiorna_olimpo() -> void:
	if _fin_olimpo == null or GameManager.agora == null:
		return
	_fin_olimpo.imposta(GameManager.agora.trascrizione(Agora.VISTA_OLIMPO))

func _nome_tappa() -> String:
	var ep := GameManager.episodi.get_episodio(GameManager.stato.viaggio["corrente"])
	return ep.nome if ep else "?"

# --- toggle ---

func _on_toggle_olimpo(premuto: bool) -> void:
	# NIENTE move_to_center: sovrascriverebbe la posizione scelta e le due finestre
	# finirebbero una sopra l'altra (era proprio il difetto segnalato).
	if premuto:
		_fin_olimpo.mostra()
		_aggiorna_olimpo()
	else:
		_fin_olimpo.hide()

## La chat della ciurma: si apre come le altre, ma qui si puo' scrivere.
func _on_toggle_ciurma(premuto: bool) -> void:
	if premuto:
		_fin_ciurma.mostra()
		_aggiorna_ciurma()
	else:
		_fin_ciurma.hide()

func _aggiorna_ciurma() -> void:
	if _fin_ciurma == null or GameManager.agora == null:
		return
	_fin_ciurma.imposta(GameManager.agora.trascrizione(Agora.VISTA_CIURMA))

## Ulisse parla ai compagni: e' un BEAT, non un turno. Costa una chiamata sola invece di
## nove — gli dei non convocano l'assemblea per ogni frase detta a bordo. Le parole non
## si perdono: il prossimo turno vero le consegna all'Interprete, agli dei e a Omero.
func _on_ciurma_invio(testo: String) -> void:
	if _busy or _finita:
		return
	_busy = true
	await GameManager.esegui_beat(testo)
	_busy = false
	_aggiorna_ciurma()

func _on_toggle_log(premuto: bool) -> void:
	if premuto:
		_fin_log.mostra()
	else:
		_fin_log.hide()

func _on_toggle_ollama(premuto: bool) -> void:
	if not premuto:
		if not _chk_esterno.button_pressed:
			LLMManager.mock_mode = true
		return
	_chk_esterno.set_pressed_no_signal(false)  # mutuamente esclusivi
	await _attiva_reale(false)

func _on_toggle_esterno(premuto: bool) -> void:
	if not premuto:
		if not _chk_ollama.button_pressed:
			LLMManager.mock_mode = true
		return
	if not LLMManager.provider_esterno_disponibile():
		_chk_esterno.set_pressed_no_signal(false)
		_narrazione.append_text("[color=%s]Nessun provider esterno configurato (config/llm_config.esterno.json). Resto sui dèi simulati (mock).[/color]\n" % C_OXBLOOD.to_html())
		return
	LLMManager.imposta_profilo_esterno(_opt_provider.selected)
	if not LLMManager.chiave_esterno_presente():
		_chk_esterno.set_pressed_no_signal(false)
		_narrazione.append_text("[color=%s]Manca la chiave API per «%s»: esporta la variabile d'ambiente e rilancia. Resto sui dèi simulati (mock).[/color]\n" % [C_OXBLOOD.to_html(), _opt_provider.get_item_text(_opt_provider.selected)])
		return
	_chk_ollama.set_pressed_no_signal(false)  # mutuamente esclusivi
	await _attiva_reale(true)

## Cambio provider esterno dal menù: se il percorso esterno è già attivo, ri-verifica.
func _on_provider_scelto(idx: int) -> void:
	LLMManager.imposta_profilo_esterno(idx)
	if _chk_esterno.button_pressed and not _busy and not _finita:
		await _attiva_reale(true)

## Attiva il percorso reale sul provider scelto (Ollama locale o API esterna), verifica
## e popola il selettore dei modelli. Se non è pronto, torna ai dèi simulati e spiega.
func _attiva_reale(esterno: bool) -> void:
	var chk := _chk_esterno if esterno else _chk_ollama
	var dove := Testi.s("motore/nome_esterno") if esterno else Testi.s("motore/nome_ollama")
	# Apri la finestra del log, cosi' si vede subito la verifica e il traffico.
	_btn_log.button_pressed = true
	_spunta_view(VOCE_LOG, true)
	_chk_ollama.disabled = true
	_chk_esterno.disabled = true
	LLMManager.abilita_reale(esterno)
	var v: Dictionary = await LLMManager.verifica_ollama()
	_chk_ollama.disabled = false
	_chk_esterno.disabled = false
	if not v["attivo"]:
		LLMManager.mock_mode = true
		chk.set_pressed_no_signal(false)
		var aiuto := Testi.s("motore/aiuto_esterno") if esterno else Testi.s("motore/aiuto_ollama")
		_narrazione.append_text("[color=%s]%s[/color]\n" % [C_OXBLOOD.to_html(), Testi.s("motore/non_risponde", [dove, v.get("errore", "?"), aiuto])])
		return
	if v["modelli"].is_empty():
		LLMManager.mock_mode = true
		chk.set_pressed_no_signal(false)
		_narrazione.append_text("[color=%s]%s[/color]\n" % [C_OXBLOOD.to_html(), Testi.s("motore/niente_modelli", [dove])])
		return
	# Modello: si TIENE quello richiesto anche se non compare nell'elenco. Sostituirlo
	# d'ufficio col primo disponibile poteva dirottare su un modello piu' costoso (e fuori
	# dal piano gratuito) senza che il giocatore se ne accorgesse: meglio avvisare.
	var scelto: String = v["atteso"]
	# Elencato ma muto: e' il caso di un modello ritirato dal provider. Non ha senso
	# lasciare acceso un motore che risponde 404 a ogni chiamata — il gioco degraderebbe
	# in silenzio e il giocatore vedrebbe solo dèi muti senza sapere perche'.
	if not v.get("genera", true):
		LLMManager.mock_mode = true
		chk.set_pressed_no_signal(false)
		_narrazione.append_text("[color=%s]%s[/color]\n" % [C_OXBLOOD.to_html(),
			Testi.s("motore/non_genera", [scelto, dove, v.get("errore_genera", "?")])])
		_popola_modelli(v["modelli"], scelto)
		return
	if not v["modello_presente"]:
		_narrazione.append_text("[color=%s]%s[/color]\n" % [C_OXBLOOD.to_html(), Testi.s("motore/modello_assente", [scelto])])
	_popola_modelli(v["modelli"], scelto)
	_narrazione.append_text("[color=%s]%s[/color]\n" % [C_VERDIGRIS.to_html(), Testi.s("motore/attivo", [dove, scelto])])
	if not _busy and not _finita:
		await _rigenera_spunti()  # spunti contestuali generati dal modello

func _popola_modelli(modelli: Array, selezionato: String) -> void:
	_opt_modello.clear()
	for i in modelli.size():
		_opt_modello.add_item(String(modelli[i]))
		if String(modelli[i]) == selezionato:
			_opt_modello.select(i)
	_opt_modello.disabled = modelli.is_empty()

func _on_modello_scelto(idx: int) -> void:
	var nome := _opt_modello.get_item_text(idx)
	LLMManager.imposta_modello(nome)
	_narrazione.append_text("[color=%s][modello impostato: %s — vale dal prossimo turno][/color]\n" % [C_VERDIGRIS.to_html(), nome])
