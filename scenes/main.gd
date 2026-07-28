extends Control

## Fase 8 — Interfaccia grafica (dai mockup). Due voci:
##  - Schermata giocatore: input libero, narrazione di Omero, stat di Ulisse, diario.
##  - Vista Olimpo (toggle, debug): l'inverso — tutto nominato (envelope, dei, verdetto, ...).
## La UI e' costruita in codice per non dipendere da un .tscn complesso. Usa gli autoload
## GameManager/LLMManager. Mock di default; una spunta accende Ollama (dei/narratore reali).

const PLACEHOLDER := "Scrivi liberamente — parla, agisci, prega, taci…"
const COLORE_SFONDO := Color(0.09, 0.08, 0.11)

var _narrazione: RichTextLabel
var _diario: RichTextLabel
var _olimpo: RichTextLabel
var _input: LineEdit
var _stats: Label
var _episodio: Label
var _btn_olimpo: Button
var _pannello_olimpo: Control
var _chk_ollama: CheckButton
var _busy := false
var _finita := false

func _ready() -> void:
	_costruisci_ui()
	LLMManager.mock_mode = true
	GameManager.nuova_partita(0)
	_apri_scena()

# --- costruzione UI ---

func _costruisci_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var sfondo := ColorRect.new()
	sfondo.color = COLORE_SFONDO
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sfondo)

	var margine := MarginContainer.new()
	margine.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lato in ["left", "top", "right", "bottom"]:
		margine.add_theme_constant_override("margin_" + lato, 18)
	add_child(margine)

	var colonne := HBoxContainer.new()
	colonne.add_theme_constant_override("separation", 18)
	margine.add_child(colonne)

	# --- Colonna giocatore ---
	var sx := VBoxContainer.new()
	sx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sx.add_theme_constant_override("separation", 10)
	colonne.add_child(sx)

	var titolo := Label.new()
	titolo.text = "DEI IN MACHINA"
	titolo.add_theme_font_size_override("font_size", 26)
	sx.add_child(titolo)

	_episodio = Label.new()
	_episodio.add_theme_font_size_override("font_size", 15)
	_episodio.modulate = Color(0.8, 0.75, 0.6)
	sx.add_child(_episodio)

	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 14)
	sx.add_child(_stats)

	_narrazione = RichTextLabel.new()
	_narrazione.bbcode_enabled = true
	_narrazione.scroll_following = true
	_narrazione.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrazione.custom_minimum_size = Vector2(420, 260)
	sx.add_child(_narrazione)

	var riga_input := HBoxContainer.new()
	riga_input.add_theme_constant_override("separation", 8)
	sx.add_child(riga_input)
	_input = LineEdit.new()
	_input.placeholder_text = PLACEHOLDER
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(_on_invio)
	riga_input.add_child(_input)
	var btn := Button.new()
	btn.text = "Agisci"
	btn.pressed.connect(_on_agisci)
	riga_input.add_child(btn)

	var riga_opzioni := HBoxContainer.new()
	riga_opzioni.add_theme_constant_override("separation", 12)
	sx.add_child(riga_opzioni)
	_btn_olimpo = Button.new()
	_btn_olimpo.text = "Vista Olimpo"
	_btn_olimpo.toggle_mode = true
	_btn_olimpo.toggled.connect(_on_toggle_olimpo)
	riga_opzioni.add_child(_btn_olimpo)
	_chk_ollama = CheckButton.new()
	_chk_ollama.text = "Ollama (dei reali)"
	_chk_ollama.toggled.connect(_on_toggle_ollama)
	riga_opzioni.add_child(_chk_ollama)

	var lbl_diario := Label.new()
	lbl_diario.text = "Diario di bordo"
	lbl_diario.add_theme_font_size_override("font_size", 13)
	sx.add_child(lbl_diario)
	_diario = RichTextLabel.new()
	_diario.bbcode_enabled = true
	_diario.scroll_following = true
	_diario.custom_minimum_size = Vector2(420, 110)
	sx.add_child(_diario)

	# --- Colonna Olimpo (debug), nascosta di default ---
	_pannello_olimpo = VBoxContainer.new()
	_pannello_olimpo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pannello_olimpo.visible = false
	colonne.add_child(_pannello_olimpo)
	var lbl_ol := Label.new()
	lbl_ol.text = "VISTA OLIMPO (debug)"
	lbl_ol.add_theme_font_size_override("font_size", 18)
	_pannello_olimpo.add_child(lbl_ol)
	_olimpo = RichTextLabel.new()
	_olimpo.bbcode_enabled = false
	_olimpo.scroll_following = true
	_olimpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_olimpo.custom_minimum_size = Vector2(420, 400)
	_pannello_olimpo.add_child(_olimpo)

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
	_narrazione.append_text("[color=#8aa]> %s[/color]\n" % testo)
	_input.text = ""

	var esito: Dictionary = await GameManager.esegui_turno(testo)

	_narrazione.append_text("[i]Omero:[/i] %s\n\n" % esito["voce"].get("narrazione_omero", ""))
	_aggiorna_diario(esito["voce"])
	_aggiorna_stats()
	if _pannello_olimpo.visible:
		_olimpo.text = TraceFormatter.intestazione(GameManager.stato) + "\n\n" + TraceFormatter.turno(esito["voce"])

	if esito.get("avanzato", false) and esito["esito"] == "continua":
		_episodio.text = "· %s ·" % _nome_tappa()
		_narrazione.append_text("[color=#caa]~ %s ~[/color]\n[i]Omero:[/i] %s\n\n" % [_nome_tappa(), esito.get("intro", "")])

	if esito["esito"] != "continua":
		_finita = true
		_input.editable = false
		if esito["esito"] == "itaca":
			_narrazione.append_text("\n[b][color=#8d8]— VITTORIA: sei tornato a Itaca. —[/color][/b]\n")
		else:
			_narrazione.append_text("\n[b][color=#d88]— FINE: %s —[/color][/b]\n" % esito["esito"])
	else:
		_input.editable = true
		_input.grab_focus()
	_busy = false

func _aggiorna_stats() -> void:
	var st: Dictionary = GameManager.stato.ulisse["stat"]
	_stats.text = "metis %d   ·   animo %d   ·   ciurma %d/%d   ·   hybris %d" % [
		st["metis"], st["animo"], st["ciurma"]["vivi"], st["ciurma"]["iniziali"],
		GameManager.stato.ulisse["hybris"]]

func _aggiorna_diario(voce: Dictionary) -> void:
	# Diario reticente, senza nomi: la sintesi + un marcatore d'esito ambiguo.
	var ultime := GameManager.stato.diario
	if ultime.is_empty():
		return
	var d: Dictionary = ultime[-1]
	var segno: String = {"ill": "✗", "fair": "◇", "neutro": "·"}.get(d.get("esito", "neutro"), "·")
	_diario.append_text("[color=#998]%s[/color] %s\n" % [segno, d.get("voce", "")])

func _nome_tappa() -> String:
	var ep := GameManager.episodi.get_episodio(GameManager.stato.viaggio["corrente"])
	return ep.nome if ep else "?"

# --- toggle ---

func _on_toggle_olimpo(premuto: bool) -> void:
	_pannello_olimpo.visible = premuto
	if premuto and not GameManager.stato.storico_olimpo.is_empty():
		_olimpo.text = TraceFormatter.intestazione(GameManager.stato) + "\n\n" + TraceFormatter.turno(GameManager.stato.storico_olimpo[-1])

func _on_toggle_ollama(premuto: bool) -> void:
	if premuto:
		LLMManager.abilita_reale()
		_narrazione.append_text("[color=#a88][modalita' Ollama: dei e narratore reali, puo' essere lento][/color]\n")
	else:
		LLMManager.mock_mode = true
