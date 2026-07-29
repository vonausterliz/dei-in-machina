extends Control

## Fase 8 — Interfaccia grafica, stile "epico" dai mockup (odissea_interfaccia.html):
## mare profondo, osso, oro, rosso-sangue; serif classico (Cardo) per la voce del poeta.
## Schermata giocatore + Vista Olimpo (toggle, debug). Autoload GameManager/LLMManager.

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

const PLACEHOLDER := "Scrivi liberamente — parla, agisci, prega, taci…"

var _serif: FontFile
var _serif_bold: FontFile
var _serif_italic: FontFile

var _narrazione: RichTextLabel
var _diario_box: VBoxContainer
var _input: LineEdit
var _episodio: Label
var _olimpo: RichTextLabel
var _log_llm: RichTextLabel
var _col_olimpo: Control
var _btn_olimpo: Button
var _btn_agisci: Button
var _chk_ollama: CheckButton
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
	LLMManager.mock_mode = true
	LLMManager.llm_log.connect(_on_llm_log)
	GameManager.nuova_partita(0)
	_apri_scena()

func _prepara_finestra() -> void:
	var w := get_window()
	w.title = "Dei in machina"
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
	w.content_scale_factor = clampf(scala, 1.0, 3.0)

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
	var titolo := _titolo("DEI  IN  MACHINA", 30, C_GOLD, _serif_bold)
	titolo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titolo)
	var tag := _titolo("l'Odissea · gli dèi ti ascoltano", 13, C_BONE_DIM, _serif_italic)
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
	_col_olimpo = _colonna_olimpo()
	colonne.add_child(_col_olimpo)

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

	var marchio := _titolo("ΟΜΗΡΟΣ · la voce del poeta", 13, C_GOLD, _serif)
	v.add_child(marchio)

	_narrazione = RichTextLabel.new()
	_narrazione.bbcode_enabled = true
	_narrazione.scroll_following = true
	_narrazione.fit_content = false
	_narrazione.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrazione.add_theme_font_override("normal_font", _serif)
	_narrazione.add_theme_font_override("bold_font", _serif_bold)
	_narrazione.add_theme_font_override("italics_font", _serif_italic)
	_narrazione.add_theme_font_size_override("normal_font_size", 19)
	_narrazione.add_theme_color_override("default_color", C_BONE)
	v.add_child(_narrazione)

	v.add_child(_riga_oro())

	# "Cosa fai, Ulisse?" + campo input + hint
	var speak := _titolo("Cosa fai, Ulisse?", 15, C_GOLD, _serif_italic)
	v.add_child(speak)

	var campo := HBoxContainer.new()
	campo.add_theme_constant_override("separation", 10)
	v.add_child(campo)

	_input = LineEdit.new()
	_input.placeholder_text = PLACEHOLDER
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_color_override("font_color", C_BONE)
	_input.add_theme_color_override("font_placeholder_color", C_BONE_DIM)
	_input.add_theme_font_size_override("font_size", 15)
	_input.add_theme_stylebox_override("normal", _sfondo(11, C_SEA2, Color(C_OXBLOOD, 0.45)))
	_input.add_theme_stylebox_override("focus", _sfondo(11, C_SEA2, C_OXBLOOD))
	_input.text_submitted.connect(_on_invio)
	campo.add_child(_input)

	var btn := Button.new()
	btn.text = "Agisci"
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

	var hint := _titolo("Puoi scrivere qualunque cosa. Gli dèi ascoltano le parole, non i comandi.", 12, C_BONE_DIM, _serif_italic)
	v.add_child(hint)

	# opzioni
	var opz := HBoxContainer.new()
	opz.add_theme_constant_override("separation", 14)
	v.add_child(opz)
	_btn_olimpo = Button.new()
	_btn_olimpo.text = "Vista Olimpo"
	_btn_olimpo.toggle_mode = true
	_btn_olimpo.add_theme_color_override("font_color", C_BONE_DIM)
	_btn_olimpo.add_theme_stylebox_override("normal", _sfondo(8, C_SEA2, _line()))
	_btn_olimpo.add_theme_stylebox_override("hover", _sfondo(8, C_SEA2, C_GOLD))
	_btn_olimpo.add_theme_stylebox_override("pressed", _sfondo(8, C_GOLD_DEEP, C_GOLD))
	_btn_olimpo.toggled.connect(_on_toggle_olimpo)
	opz.add_child(_btn_olimpo)
	_chk_ollama = CheckButton.new()
	_chk_ollama.text = "Ollama (dèi reali)"
	_chk_ollama.add_theme_color_override("font_color", C_BONE_DIM)
	_chk_ollama.toggled.connect(_on_toggle_ollama)
	opz.add_child(_chk_ollama)

	# Selettore del modello: popolato quando Ollama e' attivo, coi modelli installati.
	_opt_modello = OptionButton.new()
	_opt_modello.disabled = true
	_opt_modello.add_theme_color_override("font_color", C_BONE)
	_opt_modello.add_theme_font_size_override("font_size", 13)
	_opt_modello.tooltip_text = "Modello Ollama (attiva «Ollama» per popolarlo)"
	_opt_modello.item_selected.connect(_on_modello_scelto)
	opz.add_child(_opt_modello)

	return pan

func _colonna_aside() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(320, 0)
	v.size_flags_horizontal = Control.SIZE_FILL
	v.add_theme_constant_override("separation", 22)

	# Carta Diario di bordo
	var carta_d := _pannello(Color(1, 1, 1, 0.012), _line())
	v.add_child(carta_d)
	var vd := VBoxContainer.new()
	vd.add_theme_constant_override("separation", 12)
	carta_d.add_child(vd)
	vd.add_child(_titolo("DIARIO DI BORDO", 13, C_GOLD, _serif_bold))
	_diario_box = VBoxContainer.new()
	_diario_box.add_theme_constant_override("separation", 8)
	vd.add_child(_diario_box)
	_episodio = _titolo("", 13, C_BONE_DIM, _serif_italic)
	vd.add_child(_episodio)

	# Carta La tua condizione
	var carta_c := _pannello(Color(1, 1, 1, 0.012), _line())
	v.add_child(carta_c)
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", 14)
	carta_c.add_child(vc)
	vc.add_child(_titolo("LA TUA CONDIZIONE", 13, C_GOLD, _serif_bold))
	vc.add_child(_meter("Astuzia", "metis"))
	vc.add_child(_meter("Animo", "animo"))
	vc.add_child(_meter("Ciurma", "ciurma"))
	vc.add_child(_meter("Tracotanza", "hybris"))
	var absent := _titolo("Degli dèi non vedrai nulla: né volti, né favori, né la misura della loro ira. Solo il mare, e ciò che ne segue.", 12, C_BONE_DIM, _serif_italic)
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

func _colonna_olimpo() -> Control:
	var pan := _pannello(Color("0e0b16"), _line(), false, 16)
	pan.custom_minimum_size = Vector2(420, 0)
	pan.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pan.add_child(v)

	# Log Ollama (live): che cosa sta facendo il modello, turno per turno.
	v.add_child(_titolo("LOG OLLAMA · elaborazione", 14, C_VERDIGRIS, _serif_bold))
	_log_llm = RichTextLabel.new()
	_log_llm.bbcode_enabled = true
	_log_llm.scroll_following = true
	_log_llm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_llm.custom_minimum_size = Vector2(0, 220)
	_log_llm.add_theme_color_override("default_color", C_BONE_DIM)
	_log_llm.add_theme_font_size_override("normal_font_size", 12)
	v.add_child(_log_llm)

	v.add_child(_riga_oro())

	# Vista Olimpo: la traccia completa dell'ultimo turno.
	v.add_child(_titolo("ULTIMO TURNO · dietro le quinte", 14, C_VERDIGRIS, _serif_bold))
	_olimpo = RichTextLabel.new()
	_olimpo.bbcode_enabled = false
	_olimpo.scroll_following = true
	_olimpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_olimpo.add_theme_color_override("default_color", C_BONE_DIM)
	_olimpo.add_theme_font_size_override("normal_font_size", 13)
	v.add_child(_olimpo)
	return pan

func _on_llm_log(riga: String) -> void:
	if _log_llm:
		_log_llm.append_text("%s\n" % riga)

# --- gioco ---

func _apri_scena() -> void:
	_episodio.text = "· %s ·" % _nome_tappa()
	_narrazione.append_text("[i]Omero:[/i] %s\n\n" % GameManager.intro_corrente())
	_aggiorna_stats()
	_input.grab_focus()

func _on_invio(_t: String) -> void:
	_on_agisci()

func _on_agisci() -> void:
	if _busy or _finita:
		return
	var testo := _input.text.strip_edges()
	if testo == "":
		return
	_busy = true
	_input.editable = false
	_btn_agisci.text = "…"
	_btn_agisci.disabled = true
	_narrazione.append_text("[color=#8a9bb0]› %s[/color]\n" % testo)
	_input.text = ""
	if not LLMManager.mock_mode:
		_on_llm_log("[color=%s]— turno %d —[/color]" % [C_VERDIGRIS.to_html(), GameManager.stato.turno + 1])

	var esito: Dictionary = await GameManager.esegui_turno(testo)

	_narrazione.append_text("[i]Omero:[/i] %s\n\n" % esito["voce"].get("narrazione_omero", ""))
	_aggiungi_diario()
	_aggiorna_stats()
	if _col_olimpo.visible:
		_aggiorna_olimpo(esito["voce"])

	if esito.get("avanzato", false) and esito["esito"] == "continua":
		_episodio.text = "· %s ·" % _nome_tappa()
		_narrazione.append_text("[color=%s]— %s —[/color]\n[i]Omero:[/i] %s\n\n" % [C_GOLD.to_html(), _nome_tappa(), esito.get("intro", "")])

	if esito["esito"] != "continua":
		_finita = true
		_input.editable = false
		if esito["esito"] == "itaca":
			_narrazione.append_text("\n[b][color=%s]— VITTORIA: sei tornato a Itaca. —[/color][/b]\n" % C_VERDIGRIS.to_html())
		else:
			_narrazione.append_text("\n[b][color=%s]— FINE: %s —[/color][/b]\n" % [C_OXBLOOD.to_html(), esito["esito"]])
	else:
		_input.editable = true
		_input.grab_focus()
	_btn_agisci.text = "Agisci"
	_btn_agisci.disabled = false
	_busy = false

func _aggiorna_stats() -> void:
	var st: Dictionary = GameManager.stato.ulisse["stat"]
	var ciurma: Dictionary = st["ciurma"]
	_imposta_stat("metis", st["metis"], 100, "%d" % st["metis"])
	_imposta_stat("animo", st["animo"], 100, "%d" % st["animo"])
	_imposta_stat("ciurma", 100.0 * float(ciurma["vivi"]) / max(1, int(ciurma["iniziali"])), 100, "%d di %d" % [ciurma["vivi"], ciurma["iniziali"]])
	_imposta_stat("hybris", GameManager.stato.ulisse["hybris"], 100, "%d" % GameManager.stato.ulisse["hybris"])

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
	var testo := _titolo(d.get("voce", ""), 14, C_BONE, _serif)
	testo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	testo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	testo.custom_minimum_size = Vector2(240, 0)
	riga.add_child(testo)
	_diario_box.add_child(riga)

func _aggiorna_olimpo(voce: Dictionary) -> void:
	_olimpo.text = TraceFormatter.intestazione(GameManager.stato) + "\n\n" + TraceFormatter.turno(voce)

func _nome_tappa() -> String:
	var ep := GameManager.episodi.get_episodio(GameManager.stato.viaggio["corrente"])
	return ep.nome if ep else "?"

# --- toggle ---

func _on_toggle_olimpo(premuto: bool) -> void:
	_col_olimpo.visible = premuto
	if premuto and not GameManager.stato.storico_olimpo.is_empty():
		_aggiorna_olimpo(GameManager.stato.storico_olimpo[-1])

func _on_toggle_ollama(premuto: bool) -> void:
	if not premuto:
		LLMManager.mock_mode = true
		return
	# Apri la colonna di debug col log, cosi' si vede subito la verifica e il traffico.
	_btn_olimpo.button_pressed = true
	_col_olimpo.visible = true
	_chk_ollama.disabled = true
	LLMManager.abilita_reale()
	var v: Dictionary = await LLMManager.verifica_ollama()
	_chk_ollama.disabled = false
	if not v["attivo"]:
		LLMManager.mock_mode = true
		_chk_ollama.set_pressed_no_signal(false)
		_narrazione.append_text("[color=%s]Ollama non risponde. Avvialo con «ollama serve» (o rilancia ./avvia.sh). Resto sui dèi simulati (mock).[/color]\n" % C_OXBLOOD.to_html())
		return
	if v["modelli"].is_empty():
		LLMManager.mock_mode = true
		_chk_ollama.set_pressed_no_signal(false)
		_narrazione.append_text("[color=%s]Nessun modello installato su Ollama: scaricane uno con «ollama pull …». Resto sui dèi simulati (mock).[/color]\n" % C_OXBLOOD.to_html())
		return
	# Modello: quello di config se presente, altrimenti il primo disponibile (lo dico).
	var scelto: String = v["atteso"]
	if not v["modello_presente"]:
		scelto = String(v["modelli"][0])
		LLMManager.imposta_modello(scelto)
		_narrazione.append_text("[color=%s]Il modello «%s» non è installato: uso «%s». Puoi cambiarlo dal menù accanto.[/color]\n" % [C_OXBLOOD.to_html(), v["atteso"], scelto])
	_popola_modelli(v["modelli"], scelto)
	_narrazione.append_text("[color=%s][modalità Ollama: dèi e narratore reali (%s). Può essere lento; guarda il log a destra.][/color]\n" % [C_VERDIGRIS.to_html(), scelto])

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
