# Dei in machina — gioco narrativo agentico sull'Odissea.
# Copyright (C) 2026 vonausterliz
#
# Programma libero: puoi ridistribuirlo e modificarlo secondo i termini della GNU Affero
# General Public License, versione 3, pubblicata dalla Free Software Foundation. Distribuito
# nella speranza che sia utile, ma SENZA ALCUNA GARANZIA. Il testo completo e' in LICENSE.

class_name Main
extends Control

## Fase 8 — Interfaccia grafica, stile "epico" dai mockup (odissea_interfaccia.html):
## mare profondo, osso, oro, rosso-sangue; serif classico (Cardo) per la voce del poeta.
## Schermata giocatore + Vista Olimpo (toggle, debug). Autoload GameManager/LLMManager.

## Versione mostrata nell'header: bumpala a ogni cambiamento, così si vede se l'app sul
## Mac è aggiornata (un'app già avviata NON ricarica i prompt: va rilanciata).
const VERSIONE := "2.36"

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
const VOCE_ABOUT := 11
const VOCE_SALVA := 20
const VOCE_CARICA := 21

var _serif: FontFile
var _serif_bold: FontFile
var _serif_italic: FontFile

var _narrazione: RichTextLabel
var _spunti_box: VBoxContainer
var _ultima_narrazione: String = ""
## L'ultimo momento del giorno mostrato: il marcatore compare solo quando cambia.
var _ultimo_momento: String = ""
var _mappa: MappaViaggio
var _input: LineEdit
var _episodio: Label
var _fin_log: FinestraTesto      # l'unica rimasta a se': il traffico verso il modello
## Le due conversazioni, incastrate nella colonna di destra (v2.34).
var _pan_olimpo: PannelloChat
var _pan_ciurma: PannelloChat
## Il velo che mostra grande carta e chat.
var _lente: Lente
var _menu_view: PopupMenu
var _scala_schermo: float = 1.0
var _zoom_utente: float = 1.0
var _motore_da_ripristinare: int = -1
var _fin_impostazioni: FinestraImpostazioni
var _dlg_about: AcceptDialog
## L'unica finestra che interrompe: un problema col motore. Vedi _guaio_motore().
var _dlg_guaio: AcceptDialog
var _btn_log: Button
var _btn_agisci: Button
var _chk_reale: CheckButton
var _stat_bars := {}
var _stat_vals := {}
var _busy := false
var _finita := false
## La musica: un brano per momento del gioco, secondo data/musica.json.
var _musica: ColonnaSonora

func _line() -> Color:
	var c := C_GOLD
	c.a = 0.20
	return c

func _ready() -> void:
	_serif = load("res://fonts/Cardo-Regular.ttf")
	_serif_bold = load("res://fonts/Cardo-Bold.ttf")
	_serif_italic = load("res://fonts/Cardo-Italic.ttf")
	# Prima di tutto il resto: l'apertura la vuole gia' pronta, e i capitoli la useranno poi.
	_musica = ColonnaSonora.new()
	add_child(_musica)
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
	s.musica = _musica   # una colonna sonora sola: l'apertura e i capitoli non si accavallano
	# Il capitolo attacca quando il sipario e' calato, non prima: sotto la schermata
	# d'apertura la partita e' gia' avviata, e senza questo le due musiche si sovrapporrebbero.
	s.finito.connect(_musica_del_capitolo)
	add_child(s)   # ultimo figlio: sta davanti a tutto il resto della schermata

## La musica della tappa in cui ci si trova. Il momento e' l'id del capitolo, lo stesso di
## `data/episodi.json`: chi aggiunge un brano non deve imparare un secondo vocabolario.
## Se quel capitolo e' muto (oggi lo sono tutti) non succede niente, e va bene cosi'.
func _musica_del_capitolo() -> void:
	if _musica == null or _senza_schermo():
		return
	_musica.suona(String(GameManager.stato.viaggio.get("corrente", "")))

## Rimette le scelte dell'ultima sessione: dimensione interfaccia, provider/modello e
## motore. Cosi' non si riconfigura tutto a ogni avvio.
func _ripristina_preferenze() -> void:
	imposta_zoom(float(Impostazioni.leggi("zoom", 1.0)))
	_ripristina_provider()
	# Ogni profilo riprende il modello che l'utente aveva scelto PER QUEL provider. Scrive
	# nei profili direttamente: qui il percorso esterno non e' ancora acceso, e passare da
	# imposta_modello() manderebbe la scelta sul provider locale (era il difetto).
	LLMManager.applica_modelli_ricordati()
	# Si parte tecnicamente sul simulato solo per non bloccare l'avvio con una chiamata di
	# rete; il motore vero si accende subito dopo. Il valore predefinito e' il PROVIDER
	# ESTERNO, non il simulato: quello non e' una modalita' di gioco.
	LLMManager.mock_mode = true
	_motore_da_ripristinare = FinestraImpostazioni.motore_salvato()

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
		var nomi: Array = LLMManager.nomi_profili()
		var nuovo := clampi(vecchio - 1, 0, maxi(0, nomi.size() - 1))
		nome = String(nomi[nuovo]) if not nomi.is_empty() else ""
		Impostazioni.scrivi("provider_nome", nome)
		Impostazioni.dimentica("provider_idx")         # la vecchia chiave non vale più
	var idx := LLMManager.indice_profilo(nome)
	if idx >= 0:
		LLMManager.imposta_profilo(idx)
	LLMManager.usa_gateway = bool(Impostazioni.leggi("usa_gateway", false))

## Rimette le viste di servizio DOVE erano — non le riapre. Poi riattiva il motore scelto.
##
## IL LOG PARTE SEMPRE CHIUSO. Prima si riapriva se era aperto all'ultima uscita, ed era la
## scelta sbagliata per cio' che il Log e': non una vista di gioco, ma uno strumento di
## diagnosi. Chi l'aveva aperto una volta per capire un errore se lo ritrovava davanti alla
## narrazione a ogni avvio, e la prima cosa che vedeva del gioco era una finestra di traffico
## HTTP. Posizione e dimensione si ricordano lo stesso: quando lo riapri e' dove l'avevi
## lasciato.
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
	if _motore_da_ripristinare >= 0:
		var m := _motore_da_ripristinare
		_motore_da_ripristinare = -1
		await _on_motore_scelto(m == FinestraImpostazioni.MOTORE_REALE)

## Alla chiusura salvo dove sono finite le finestre, per ritrovarle uguali.
func _notification(che: int) -> void:
	if che == NOTIFICATION_WM_CLOSE_REQUEST or che == NOTIFICATION_PREDELETE:
		_salva_geometrie()

func _salva_geometrie() -> void:
	if _senza_schermo():
		return
	for riga in _finestre_servizio():
		var fin: FinestraTesto = riga[1]
		Impostazioni.salva_geometria(String(riga[0]), fin.position, fin.size)

## L'elenco unico delle finestre di servizio: [chiave, finestra].
## Un elenco solo — quando ne ho aggiunta una a mano in tre punti diversi, la ciurma e'
## rimasta fuori da tutti e tre (scala, geometria, ripristino).
##
## Portava anche pulsante e voce di menu: servivano solo a RIAPRIRE la finestra all'avvio.
## Da quando il Log parte sempre chiuso non li legge piu' nessuno, e un elenco che trasporta
## dati che nessuno usa e' il modo in cui una struttura smette di dire la verita'.
func _finestre_servizio() -> Array:
	var out: Array = []
	for riga in [["log", _fin_log]]:
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

	root.add_child(_intestazione())
	root.add_child(_riga_oro())

	# Corpo: colonne
	var colonne := HBoxContainer.new()
	colonne.add_theme_constant_override("separation", 22)
	colonne.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(colonne)

	colonne.add_child(_colonna_rapsodia())
	colonne.add_child(_colonna_aside())

	# LA CONDIZIONE IN FONDO, su una riga sola. Era una carta nella colonna di destra, con
	# quattro barre impilate: prendeva un terzo della colonna per quattro numeri che si
	# leggono di sfuggita. In fondo alla pagina sta sotto l'occhio senza rubare spazio a
	# cio' che si legge davvero.
	root.add_child(_riga_oro())
	root.add_child(_riga_condizione())

	_crea_finestre_servizio()
	# La lente sta SOPRA tutto, quindi si aggiunge per ultima e fuori dai margini.
	_lente = Lente.new()
	add_child(_lente)

## L'INTESTAZIONE: emblema, nome, sottotitolo — e i comandi tutti all'altro capo.
##
## Prima qui stavano anche il numero di versione e lo stato del motore LLM, e i tre menu
## erano incastrati fra il nome e il sottotitolo. Su richiesta (v2.34) la riga e' stata
## sfoltita: la versione e' passata sotto Settings › Informazioni, dove si cerca; il nome
## del modello e' rimasto solo in Settings, che e' il posto in cui lo si sceglie.
func _intestazione() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)

	# L'emblema del gioco, lo stesso della schermata d'apertura e dell'icona: un marchio
	# solo, disegnato in un posto solo (scenes/marchio.gd).
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(42, 42)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.draw.connect(func(): Marchio.disegna(logo, logo.size * 0.5, logo.size.x * 0.40))
	header.add_child(logo)

	var titolo := _titolo(Testi.s("app/titolo"), 30, C_GOLD, _serif_bold)
	titolo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(titolo)
	# Il sottotitolo SUBITO dopo il nome: e' il seguito della frase, non una didascalia da
	# mandare all'altro capo della riga.
	var tag := _titolo(Testi.s("app/sottotitolo"), 13, C_BONE_DIM, _serif_italic)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	header.add_child(tag)

	var spazio := Control.new()
	spazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spazio)

	var menu := _barra_menu()
	menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(menu)
	return header

## Astuzia · Animo · Ciurma · Tracotanza, e il capitolo in corso all'altro capo. Una riga.
func _riga_condizione() -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 26)
	for coppia in [[Testi.s("pannelli/astuzia"), "metis"], [Testi.s("pannelli/animo"), "animo"],
			[Testi.s("pannelli/ciurma"), "ciurma"], [Testi.s("pannelli/tracotanza"), "hybris"]]:
		r.add_child(_meter(String(coppia[0]), String(coppia[1])))
	var spazio := Control.new()
	spazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(spazio)
	_episodio = _titolo("", 13, C_BONE_DIM, _serif_italic)
	_episodio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(_episodio)
	return r

## Log LLM e Vista Olimpo vivono in finestre NATIVE separate: si aprono solo quando
## servono, si spostano su un altro schermo e lasciano tutto lo spazio alla narrazione.
func _crea_finestre_servizio() -> void:
	get_tree().root.gui_embed_subwindows = false  # finestre vere del sistema, non incorporate
	# NE E' RIMASTA UNA. Olimpo e ciurma stavano qui, in due finestre native che nascevano
	# affiancate e andavano ritrovate a ogni avvio; ora sono nella pagina (v2.34). Il Log
	# resta a se' per la ragione opposta a quella per cui le altre due ne sono uscite: non
	# si guarda mentre si gioca, si apre quando qualcosa non torna — e allora lo si vuole
	# grande, magari su un altro schermo.
	var schermo := DisplayServer.screen_get_size()
	var margine := 24
	var larg: int = clampi(int((schermo.x - margine * 3) / 2.0), 420, 900)
	var alt: int = clampi(schermo.y - 160, 360, 900)
	_fin_log = FinestraTesto.new(Testi.s("finestre/log_titolo"), true, Vector2i(larg, alt),
		Vector2i(maxi(margine, schermo.x - larg - margine), 70))
	_fin_log.chiusa.connect(func():
		_btn_log.button_pressed = false
		_spunta_view(VOCE_LOG, false))
	add_child(_fin_log)
	_fin_impostazioni = FinestraImpostazioni.new()
	_fin_impostazioni.motore_scelto.connect(_on_motore_scelto)
	_fin_impostazioni.zoom_scelto.connect(imposta_zoom)
	add_child(_fin_impostazioni)
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

	# Olimpo e Ciurma non sono piu' qui: sono nella pagina, sempre visibili. Restava il Log,
	# che e' l'unica vista di servizio vera — la si apre quando qualcosa non torna.
	_menu_view = PopupMenu.new()
	_menu_view.name = Testi.s("menu/view")
	_menu_view.add_check_item(Testi.s("menu/log_llm"), VOCE_LOG)
	_menu_view.id_pressed.connect(_on_menu_view)
	barra.add_child(_menu_view)

	# Salvare e riprendere: una partita dura ~76 turni: perderla chiudendo la finestra e'
	# una perdita vera.
	var menu_partita := PopupMenu.new()
	menu_partita.name = Testi.s("menu/partita")
	menu_partita.add_item(Testi.s("menu/salva"), VOCE_SALVA)
	menu_partita.add_item(Testi.s("menu/carica"), VOCE_CARICA)
	menu_partita.id_pressed.connect(_on_menu_partita)
	barra.add_child(menu_partita)

	var menu_set := PopupMenu.new()
	menu_set.name = Testi.s("menu/settings")
	menu_set.add_item(Testi.s("menu/impostazioni"), VOCE_IMPOSTAZIONI)
	menu_set.add_separator()
	# La versione stava accanto al nome del gioco. E' un'informazione che si cerca due volte
	# l'anno — quando si sospetta che l'app sul Mac sia vecchia — e occupava un posto in
	# prima fila. Qui la si trova dove la si cerca.
	menu_set.add_item(Testi.s("menu/about"), VOCE_ABOUT)
	menu_set.id_pressed.connect(_on_menu_settings)
	barra.add_child(menu_set)
	return barra

func _on_menu_settings(id: int) -> void:
	match id:
		VOCE_IMPOSTAZIONI: _apri_impostazioni()
		VOCE_ABOUT: _mostra_about()

## I DIALOGHI SONO FINESTRE DI SISTEMA, e nascono col tema grigio di Godot: fondo chiaro,
## carattere di sistema, testo appiccicato al bordo. In mezzo a una schermata di mare
## profondo e oro sembrano un errore dell'applicazione, non una sua parte — e il dialogo del
## guaio e' proprio quello che deve essere creduto. Il fondo lo da' la stessa `_sfondo()` di
## tutti i riquadri, e i suoi margini interni sono cio' che stacca il testo dal bordo.
func _veste_dialogo(d: AcceptDialog) -> void:
	d.add_theme_stylebox_override("panel", _sfondo(18, C_SEA, _line()))
	var l := d.get_label()
	l.add_theme_color_override("font_color", C_BONE)
	l.add_theme_font_override("font", _serif)
	l.add_theme_font_size_override("font_size", 17)
	for b in d.get_ok_button().get_parent().get_children():
		if b is Button:
			b.add_theme_color_override("font_color", C_BONE)
			b.add_theme_font_override("font", _serif)
			b.add_theme_font_size_override("font_size", 16)
			b.add_theme_stylebox_override("normal", _sfondo(8, C_SEA2, _line()))
			b.add_theme_stylebox_override("hover", _sfondo(8, C_SEA2, C_GOLD))
			b.add_theme_stylebox_override("pressed", _sfondo(8, C_GOLD_DEEP, C_GOLD))

func _mostra_about() -> void:
	if _dlg_about == null:
		_dlg_about = AcceptDialog.new()
		_dlg_about.title = Testi.s("about/titolo")
		# Un AcceptDialog e' una Window a se' e NON eredita content_scale_factor dal
		# genitore: senza questa riga esce minuscolo sugli schermi ad alta densita'.
		add_child(_dlg_about)
		_veste_dialogo(_dlg_about)
	_dlg_about.dialog_text = Testi.s("about/corpo",
		[Testi.s("app/sottotitolo"), VERSIONE, Engine.get_version_info().get("string", "?")])
	_dlg_about.content_scale_factor = get_window().content_scale_factor
	_dlg_about.popup_centered()

## Salva / riprendi. Durante un turno non si tocca niente: lo stato e' a meta' strada.
func _on_menu_partita(id: int) -> void:
	if _busy:
		return
	match id:
		VOCE_SALVA:
			_nota(Testi.s("gioco/salvata" if GameManager.salva_partita() else "gioco/salvataggio_fallito"))
		VOCE_CARICA:
			if not GameManager.carica_partita():
				_nota(Testi.s("gioco/nessun_salvataggio"))
				return
			_riapri_partita_ripresa()

## Rimette a schermo una partita ripresa: la scena riparte dall'ultima voce di Omero, e le
## chat, il diario, le stat e la carta tornano com'erano.
func _riapri_partita_ripresa() -> void:
	_finita = GameManager.stato.stato != "in_corso"
	_input.editable = not _finita
	_ultima_narrazione = GameManager._ultima_narrazione
	_ultimo_momento = ""
	_narrazione.clear()
	_narrazione.append_text("[color=%s]— %s —[/color]\n[i]%s[/i] %s\n\n" % [
		C_GOLD.to_html(), _nome_tappa(), Testi.s("gioco/omero"), _fuori(_ultima_narrazione)])
	_nota(Testi.s("gioco/ripresa"))
	_episodio.text = _nome_tappa()
	_aggiorna_stats()
	_aggiorna_mappa()
	_aggiorna_olimpo()
	_aggiorna_ciurma()
	_pulisci_spunti()
	if not _finita:
		await _rigenera_spunti()

## TESTO CHE VIENE DA FUORI dentro la narrazione: la voce di Omero, il commiato, cio' che
## digita chi gioca, il messaggio d'errore di un server. La narrazione e' una RichTextLabel
## in BBCode, quindi una quadra arrivata da fuori aprirebbe un marcatore vero. Si
## neutralizza al confine — vedi scripts/data/bbcode.gd.
func _fuori(t: String) -> String:
	return Bbcode.neutro(t)

func _nota(testo: String) -> void:
	_narrazione.append_text("[color=%s]%s[/color]\n\n" % [C_VERDIGRIS.to_html(), testo])

## Accendi i dei veri sul provider selezionato. Erano due interruttori — «Ollama» e «LLM
## esterno», mutuamente esclusivi — perche' Ollama era un motore a parte invece che un
## provider: due comandi per dire «quale provider», e nessuno per dire «acceso o spento».
## Il simulato NON e' fra le scelte: non e' una modalita' di gioco (vedi blocca_simulato).
func _on_motore_scelto(reale: bool) -> void:
	if reale:
		_chk_reale.set_pressed_no_signal(true)
		await _attiva_reale()
	else:
		LLMManager.mock_mode = true
		_chk_reale.set_pressed_no_signal(false)
	_aggiorna_indicatore_motore()

## IL SIMULATO NON E' UNA MODALITA' DI GIOCO.
##
## Il mock resta — ci girano i 227 test e la console headless, ed e' l'unico modo di
## verificare la macchina del turno senza rete ne' token. Ma davanti a una finestra aperta
## non e' una partita: con dèi finti e la stessa frase di Omero a ogni turno si continua a
## giocare senza accorgersene. E' successo. Meglio un gioco che si ferma e spiega.
##
## Puro apposta: cosi' si puo' verificare anche il ramo "con schermo", che nei test
## headless non si presenterebbe mai.
static func blocca_simulato(simulato: bool, con_schermo: bool) -> bool:
	return simulato and con_schermo

func _simulato_blocca() -> bool:
	return blocca_simulato(LLMManager.mock_mode, not _senza_schermo())

## Col motore simulato non si gioca: si spegne il campo e si dice perche'.
##
## LA SCRITTA COL NOME DEL MODELLO NON C'E' PIU'. Stava nell'intestazione dopo che si erano
## giocati quattro turni col simulato credendo di parlare con gli dei veri — l'avviso di
## allora era in fondo alla pagina e in colore tenue. Su richiesta esplicita (v2.34) e'
## stata tolta dall'interfaccia: il motore si vede e si sceglie in Settings. Il presidio
## VERO contro quel guaio pero' resta, ed e' piu' forte di un'etichetta: col simulato il
## campo d'azione e' disabilitato e il segnaposto dice cosa fare. Non e' un avviso da
## leggere, e' una porta chiusa.
func _aggiorna_indicatore_motore() -> void:
	var bloccato := _simulato_blocca()
	if _input:
		_input.editable = not bloccato
		_input.placeholder_text = Testi.s("motore/serve_un_motore") if bloccato else Testi.s("gioco/placeholder")
	if _btn_agisci:
		_btn_agisci.disabled = bloccato

func _apri_impostazioni() -> void:
	_fin_impostazioni.popup_centered()

func _on_menu_view(id: int) -> void:
	var i := _menu_view.get_item_index(id)
	var acceso := not _menu_view.is_item_checked(i)
	_menu_view.set_item_checked(i, acceso)
	_btn_log.button_pressed = acceso

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

	# opzioni
	# I comandi del motore LLM sono nel menu Settings: qui restano solo come attuatori
	# (invisibili), così la schermata di gioco non si riempie di interruttori.
	var opz := HBoxContainer.new()
	opz.add_theme_constant_override("separation", 14)
	opz.visible = false
	v.add_child(opz)
	# Log LLM: l'unica vista rimasta in una finestra a se'.
	_btn_log = Button.new()
	_btn_log.text = Testi.s("menu/log_llm")
	_btn_log.toggle_mode = true
	_btn_log.add_theme_color_override("font_color", C_BONE_DIM)
	_btn_log.add_theme_stylebox_override("normal", _sfondo(8, C_SEA2, _line()))
	_btn_log.add_theme_stylebox_override("hover", _sfondo(8, C_SEA2, C_GOLD))
	_btn_log.add_theme_stylebox_override("pressed", _sfondo(8, C_GOLD_DEEP, C_GOLD))
	_btn_log.toggled.connect(_on_toggle_log)
	opz.add_child(_btn_log)     # idem: comandato dal menu View
	# Un interruttore solo: dei finti o dei veri. Quale provider lo dice il menu accanto.
	_chk_reale = CheckButton.new()
	_chk_reale.text = Testi.s("motore/dei_veri")
	_chk_reale.add_theme_color_override("font_color", C_BONE_DIM)
	_chk_reale.tooltip_text = Testi.s("motore/tooltip_dei_veri")
	_chk_reale.toggled.connect(_on_toggle_reale)
	opz.add_child(_chk_reale)

	# I menu «provider» e «modello» stavano anche qui, invisibili: erano il doppione di
	# quelli in Settings, da quando il provider si sceglieva in due posti. Peggio che
	# inutili — `_on_toggle_reale` leggeva `_opt_provider.selected`, che su un menu che
	# nessuno puo' toccare vale sempre 0: avrebbe forzato il primo provider dell'elenco
	# sopra la scelta fatta in Settings. Un comando invisibile che decide qualcosa e' la
	# forma peggiore di codice morto.
	return pan

## LA COLONNA DI DESTRA: la carta, e sotto le due conversazioni.
##
## Olimpo e ciurma stavano in due finestre native separate, aperte dal menu View. In teoria
## era la scelta giusta — si spostano su un altro schermo e lasciano tutta la pagina alla
## narrazione. Alla prova del gioco no: sono due cose che si guardano di CONTINUO mentre si
## gioca, e ogni volta bisognava ritrovarle, riportarle davanti, richiuderle. Incastrate qui
## si leggono senza cambiare finestra; per quando lo spazio non basta c'e' la lente.
##
## Il diario di bordo, che stava in mezzo, e' stato tolto: raccontava in una riga per turno
## cio' che la narrazione racconta per esteso due colonne piu' in la'. I dati restano
## (`stato.diario`: li usa il salvataggio, e Omero per ricordare), a sparire e' il riquadro.
func _colonna_aside() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(340, 0)
	v.size_flags_horizontal = Control.SIZE_FILL
	v.add_theme_constant_override("separation", 16)

	# Carta del viaggio (dove si trova Ulisse). Non si tocca: va bene com'e', le si e'
	# aggiunta solo la lente.
	var carta_m := _pannello(Color(1, 1, 1, 0.012), _line())
	v.add_child(carta_m)
	var vm := VBoxContainer.new()
	vm.add_theme_constant_override("separation", 10)
	carta_m.add_child(vm)
	var testa := HBoxContainer.new()
	var tm := _titolo(Testi.s("pannelli/carta_viaggio"), 13, C_GOLD, _serif_bold)
	tm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	testa.add_child(tm)
	testa.add_child(Lente.bottone(_ingrandisci_mappa, Testi.s("pannelli/carta_viaggio")))
	vm.add_child(testa)
	_mappa = MappaViaggio.new()
	# 120, non di piu': la colonna destra somma tre riquadri, e la somma dei loro MINIMI
	# decide se la riga della condizione entra nella finestra o finisce sotto il bordo.
	# Misurato: con 170 la pagina chiedeva 744 punti su 689 disponibili. Il dettaglio della
	# carta si guarda con la lente, che e' esattamente perche' esiste.
	_mappa.custom_minimum_size = Vector2(0, 120)
	vm.add_child(_mappa)

	_pan_olimpo = PannelloChat.new(Testi.s("pannelli/olimpo"))
	_pan_olimpo.lente_premuta.connect(_ingrandisci_olimpo)
	v.add_child(_pan_olimpo)

	_pan_ciurma = PannelloChat.new(Testi.s("pannelli/ciurma_titolo"), true,
		Testi.s("ciurma/placeholder"))
	_pan_ciurma.inviato.connect(_on_ciurma_invio)
	_pan_ciurma.lente_premuta.connect(_ingrandisci_ciurma)
	v.add_child(_pan_ciurma)

	return v

# --- la lente ---

func _ingrandisci_mappa() -> void:
	# Una MappaViaggio NUOVA, non quella della pagina: spostare il nodo vivo vorrebbe dire
	# rimetterlo a posto alla chiusura, e basta un'eccezione per lasciare un buco nel layout.
	_lente.mostra(Testi.s("pannelli/carta_viaggio"), func():
		var m := MappaViaggio.new()
		m.custom_minimum_size = Vector2(700, 460)
		m.ready.connect(_popola_mappa.bind(m), CONNECT_ONE_SHOT)
		return m)

func _ingrandisci_olimpo() -> void:
	_lente.mostra(Testi.s("pannelli/olimpo"),
		_grande.bind(GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)))

func _ingrandisci_ciurma() -> void:
	_lente.mostra(Testi.s("pannelli/ciurma_titolo"),
		_grande.bind(GameManager.agora.trascrizione(Agora.VISTA_CIURMA)))

## La stessa trascrizione, in corpo grande. Non e' il pannello spostato: e' una copia, e la
## conversazione e' la stessa perche' la fonte e' una sola (Agora).
func _grande(contenuto: String) -> Control:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.selection_enabled = true
	r.context_menu_enabled = true
	r.add_theme_font_override("normal_font", _serif)
	r.add_theme_font_override("bold_font", _serif_bold)
	r.add_theme_font_override("italics_font", _serif_italic)
	r.add_theme_font_size_override("normal_font_size", 19)
	r.add_theme_color_override("default_color", C_BONE)
	r.text = contenuto
	return r

## Un contatore su una riga: «Astuzia 60 ▁▁▁▁». La barra e' sottile e corta — nella riga in
## fondo alla pagina serve a dare l'ordine di grandezza a colpo d'occhio, non a essere letta.
func _meter(etichetta: String, chiave: String) -> Control:
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 7)
	var k := _titolo(etichetta, 13, C_BONE_DIM, _serif_italic)
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	riga.add_child(k)
	var val := _titolo("—", 14, C_BONE, _serif)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	riga.add_child(val)
	_stat_vals[chiave] = val

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(56, 5)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.06)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = C_GOLD if chiave != "hybris" else C_OXBLOOD
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	_stat_bars[chiave] = bar
	riga.add_child(bar)
	return riga

func _on_llm_log(riga: String) -> void:
	if _fin_log:
		_fin_log.aggiungi(riga)

# --- gioco ---

func _apri_scena() -> void:
	_episodio.text = "· %s ·" % _nome_tappa()
	_ultima_narrazione = GameManager.intro_corrente()
	_narrazione.append_text("[i]" + Testi.s("gioco/omero") + "[/i] %s\n\n" % _fuori(_ultima_narrazione))
	_aggiorna_stats()
	_aggiorna_mappa()
	# Anche l'Olimpo, non solo la ciurma: finche' era una finestra che si apriva a mano si
	# riempiva all'apertura, ora e' sempre a schermo e dev'essere sempre giusto.
	_aggiorna_olimpo()
	_aggiorna_ciurma()
	_aggiorna_indicatore_motore()
	_input.grab_focus()
	await _rigenera_spunti()

func _aggiorna_mappa() -> void:
	_popola_mappa(_mappa)

## Riempie UNA carta (quella della colonna o quella grande della lente) con le tappe, dove
## si trova Ulisse e cosa ha gia' passato. Una funzione sola: le due carte devono dire la
## stessa cosa, e due copie dello stesso calcolo divergono al primo cambiamento.
func _popola_mappa(m: MappaViaggio) -> void:
	if m == null:
		return
	var punti: Array = []
	for id in GameManager.episodi.ordine():
		var ep := GameManager.episodi.get_episodio(id)
		if ep:
			punti.append({"id": id, "nome": ep.nome, "pos": ep.mappa})
	m.imposta(punti, GameManager.stato.viaggio["corrente"], GameManager.stato.viaggio.get("completati", []))

func _on_invio(_t: String) -> void:
	_on_agisci()

## Un turno di gioco pieno: il mondo gira e gli dei deliberano. Le parole scambiate coi
## compagni passano invece da _on_ciurma_invio, che costa una chiamata sola.
func _on_agisci() -> void:
	if _busy or _finita:
		return
	# E' il momento in cui il guaio si fa sentire davvero: hai scritto e premuto Agisci, e non
	# succede niente. Una riga in fondo al racconto non basta — qui ci vuole la finestra.
	if _simulato_blocca():
		_guaio_motore(Testi.s("motore/serve_un_motore"))
		return
	var testo := _input.text.strip_edges()
	if testo == "":
		return
	_busy = true
	_input.editable = false
	_btn_agisci.text = Testi.s("gioco/attesa")
	_btn_agisci.disabled = true
	# Lo stesso marcatore che apre il gruppo nelle chat: e' il collante fra le tre viste.
	# Compare solo quando il momento cambia, altrimenti diventerebbe un orologio.
	var momento := GameManager.momento_corrente()
	if momento != _ultimo_momento:
		_ultimo_momento = momento
		_narrazione.append_text("\n[color=#5c5548]≈ %s ≈[/color]\n" % momento)
	_narrazione.append_text("[color=#8a9bb0]› %s[/color]\n" % _fuori(testo))
	_input.text = ""
	if not LLMManager.mock_mode:
		_on_llm_log("[color=%s]— turno %d —[/color]" % [C_VERDIGRIS.to_html(), GameManager.stato.turno + 1])

	# Mentre il turno gira, gli spunti vecchi non valgono piu': li svuoto.
	_pulisci_spunti()
	var esito: Dictionary = await GameManager.esegui_turno(testo)

	_ultima_narrazione = String(esito["voce"].get("narrazione_omero", ""))
	if _ultima_narrazione != "":
		_narrazione.append_text("[i]" + Testi.s("gioco/omero") + "[/i] %s\n\n" % _fuori(_ultima_narrazione))
	# Fuori-mondo: Omero tace, al suo posto un avviso in chiaro (non è la voce del poeta).
	var ammon := String(esito["voce"].get("ammonizione", ""))
	if ammon != "":
		_narrazione.append_text(_avviso(ammon))
	_aggiorna_stats()
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
		_narrazione.append_text("[i]" + Testi.s("gioco/omero") + "[/i] %s\n\n" % _fuori(trans))
	if esito.get("avanzato", false) and esito["esito"] == "continua":
		_episodio.text = "· %s ·" % _nome_tappa()
		_ultima_narrazione = String(esito.get("intro", ""))
		_narrazione.append_text("[color=%s]— %s —[/color]\n[i]Omero:[/i] %s\n\n" % [C_GOLD.to_html(), _nome_tappa(), _fuori(_ultima_narrazione)])
		_musica_del_capitolo()   # nuovo capitolo, nuovo brano (se ne ha uno)
	_aggiorna_mappa()

	if esito["esito"] != "continua":
		_finita = true
		# Il finale ha una musica sua: e' l'ultima cosa che si ascolta, e non puo' essere
		# il capitolo di prima che continua come se niente fosse.
		if _musica:
			_musica.suona("fine_%s" % String(esito["esito"]))
		_input.editable = false
		if esito["esito"] == "itaca":
			_narrazione.append_text("\n[b][color=%s]%s[/color][/b]\n" % [C_VERDIGRIS.to_html(), Testi.s("gioco/vittoria")])
		else:
			# IL CONGEDO PRIMA DELL'ETICHETTA. Chi ha giocato venti turni con la voce di un
			# aedo non merita di essere congedato da «— FINE: morte —»: l'ultima cosa che si
			# legge e' quella che resta. L'etichetta viene dopo, piccola, come una lapide.
			_congedo(String(esito.get("congedo", "")))
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
	# Cio' che finisce a schermo e' cio' che il gioco si impegna a non rifiutare: qui passa
	# ogni strada, quindi qui si registra. NB: _pulisci_spunti() svuota solo i BOTTONI e non
	# deve toccare la memoria — durante un turno i bottoni si tolgono subito, e se sparisse
	# anche il ricordo lo spunto appena cliccato tornerebbe rifiutabile.
	# Filtro, scarto dei bivi e rammendo con gli appigli della tappa stanno tutti in
	# GameManager.spunti_da_mostrare: qui si disegna soltanto.
	var buoni := GameManager.spunti_da_mostrare(spunti)
	GameManager.ricorda_spunti(buoni)
	_pulisci_spunti()
	if buoni.is_empty():
		# Non si inventa niente: il campo libero c'e' sempre, e lo si dice.
		_spunti_box.add_child(_titolo(Testi.s("gioco/nessuno_spunto"), 13, C_BONE_DIM, _serif_italic))
		return
	for sp in buoni:
		_spunti_box.add_child(_cue(String(sp.get("testo", ""))))

func _pulisci_spunti() -> void:
	for c in _spunti_box.get_children():
		c.queue_free()

## UN APPIGLIO, tutti uguali. Prima ce n'era una specie a parte — il bivio, segnato «‡» e
## in rosso — e non reggeva la lettura: fra tre frasi omeriche ne compariva una con un
## simbolo strano che apriva una finestrella di conferma. I bivi non arrivano piu' fin qui
## (GameManager.spunti_da_mostrare li scarta), quindi non c'e' piu' niente da distinguere.
func _cue(testo: String) -> Button:
	var accento := C_GOLD
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

## Un appiglio finisce nel campo e parte: si puo' anche solo leggerlo e scrivere altro.
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
		"prigionia":
			# L'isola che trattiene: stesso canale delle ammonizioni, perche' per chi gioca
			# e' la stessa specie di richiamo — «cosi' non torni piu'».
			return "[b][color=%s]%s[/color][/b]\n\n" % [chiaro, Testi.s("avvisi/prigionia")]
	return ""

## L'ULTIMA VOCE. Staccata, in corsivo, con del respiro attorno: e' un epitaffio, non
## l'ennesimo paragrafo del turno.
func _congedo(testo: String) -> void:
	if testo.strip_edges() == "":
		return
	_narrazione.append_text("\n[color=%s]· · ·[/color]\n\n[i][color=%s]%s[/color][/i]\n" % [
		C_GOLD.to_html(), C_BONE.to_html(), _fuori(testo.strip_edges())])

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

## La Vista Olimpo e' una CHAT in sola lettura, e SOLO quello: gli dei si parlano e il
## giocatore assiste. La traccia tecnica del turno (envelope, risvegli, delta) non e' una
## voce e non sta qui: va nel Log LLM, dove si guardano i numeri.
func _aggiorna_olimpo() -> void:
	if _pan_olimpo == null or GameManager.agora == null:
		return
	_pan_olimpo.imposta(GameManager.agora.trascrizione(Agora.VISTA_OLIMPO))

func _nome_tappa() -> String:
	var ep := GameManager.episodi.get_episodio(GameManager.stato.viaggio["corrente"])
	return ep.nome if ep else "?"

# --- toggle ---

func _aggiorna_ciurma() -> void:
	if _pan_ciurma == null or GameManager.agora == null:
		return
	_pan_ciurma.imposta(GameManager.agora.trascrizione(Agora.VISTA_CIURMA))

## Ulisse parla ai compagni: e' un BEAT, non un turno. Costa una chiamata sola invece di
## nove — gli dei non convocano l'assemblea per ogni frase detta a bordo. Le parole non
## si perdono: il prossimo turno vero le consegna all'Interprete, agli dei e a Omero.
func _on_ciurma_invio(testo: String) -> void:
	if _busy or _finita or _simulato_blocca():
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

func _on_toggle_reale(premuto: bool) -> void:
	if not premuto:
		LLMManager.mock_mode = true
		Impostazioni.scrivi("motore", FinestraImpostazioni.MOTORE_SIMULATO)
		_aggiorna_indicatore_motore()
		return
	if not LLMManager.c_e_un_provider():
		_chk_reale.set_pressed_no_signal(false)
		_guaio_motore(Testi.s("motore/nessun_profilo"))
		return
	if not LLMManager.chiave_presente():
		_chk_reale.set_pressed_no_signal(false)
		_guaio_motore(Testi.s("motore/manca_chiave", [LLMManager.nome_profilo_corrente()]))
		return
	Impostazioni.scrivi("motore", FinestraImpostazioni.MOTORE_REALE)
	await _attiva_reale()

## UN GUAIO COL MOTORE SI DICE IN UN POPUP, NON NELLA NARRAZIONE.
##
## Prima ogni esito — riuscita compresa — finiva in fondo al racconto di Omero, in rosso o in
## verde. Due difetti in uno. Il primo: «[modalità Mistral: dèi e narratore reali…]» compariva
## a ogni avvio, cioe' quasi sempre quando NON c'era niente da dire, e la prima riga del gioco
## era un rapporto tecnico dentro il testo del poema. Il secondo, peggiore: un errore VERO
## aveva lo stesso peso tipografico di una battuta, restava indietro appena la narrazione
## cresceva, e si poteva giocare per turni senza accorgersi che gli dei non stavano pensando.
##
## Ora la narrazione contiene solo la narrazione. Un problema ferma tutto con una finestra che
## dice cos'e' successo e porta dove si aggiusta — il bottone apre Settings, invece di
## suggerire di cercarlo.
func _guaio_motore(motivo: String) -> void:
	if _dlg_guaio == null:
		_dlg_guaio = AcceptDialog.new()
		_dlg_guaio.title = Testi.s("motore/guaio_titolo")
		_dlg_guaio.dialog_autowrap = true
		# «OK» davanti a un errore suona come un consenso. Qui non c'e' niente da approvare.
		_dlg_guaio.ok_button_text = Testi.s("finestre/chiudi")
		# Il bottone che RISOLVE, non un rimando. «Apri Settings» arriva al posto giusto in un
		# clic; «vai in Settings» va cercato.
		_dlg_guaio.add_button(Testi.s("motore/apri_settings"), true, "settings")
		_dlg_guaio.custom_action.connect(func(azione: StringName):
			if azione == &"settings":
				_dlg_guaio.hide()
				_apri_impostazioni())
		add_child(_dlg_guaio)
		_veste_dialogo(_dlg_guaio)   # dopo add_button: veste anche quello
	# Il testo del provider e' testo che arriva da fuori: le sue parentesi quadre non devono
	# poter diventare BBCode. `dialog_text` non lo interpreta, ma il giorno in cui questo
	# diventasse un RichTextLabel il difetto rinascerebbe silenzioso.
	_dlg_guaio.dialog_text = "%s\n\n%s" % [motivo, Testi.s("motore/guaio_dove_guardare")]
	# Un AcceptDialog e' una Window a se' e NON eredita content_scale_factor dal genitore, e
	# la dimensione va moltiplicata di conseguenza o il contenuto scalato non ci sta dentro.
	#
	# LA LARGHEZZA VA IMPOSTA. Con `popup_centered()` nudo e `dialog_autowrap` acceso il
	# dialogo prende la sua minima — misurato: 255 px di larghezza per 1212 di altezza, una
	# colonna di due parole per riga. Il testo era giusto e il bottone c'era: nessun test
	# poteva accorgersene, l'ha detto uno scatto (tools/foto_gioco.gd).
	var scala := get_window().content_scale_factor
	_dlg_guaio.content_scale_factor = scala
	_dlg_guaio.popup_centered(Vector2i(int(560 * scala), int(300 * scala)))

## Attiva il percorso reale sul provider scelto (Ollama locale o API esterna), verifica
## e popola il selettore dei modelli. Se non è pronto, torna ai dèi simulati e spiega.
func _attiva_reale() -> void:
	var chk := _chk_reale
	var dove := LLMManager.nome_profilo_corrente()
	# IL LOG NON SI APRE DA SOLO. Lo faceva qui, «cosi' si vede subito la verifica»: ma
	# attivare i dei veri e' cio' che succede a OGNI avvio con il motore reale salvato, e
	# quindi la finestra compariva sempre, non solo quando serviva. E non serve: ogni modo in
	# cui la verifica puo' fallire — provider muto, nessun modello, modello ritirato — e' gia'
	# scritto in rosso nella narrazione, dove il giocatore sta guardando. Il Log si apre da
	# View quando quelle righe non bastano.
	_chk_reale.disabled = true
	LLMManager.abilita_reale()
	var v: Dictionary = await LLMManager.verifica_provider()
	_chk_reale.disabled = false
	if not v["attivo"]:
		LLMManager.mock_mode = true
		chk.set_pressed_no_signal(false)
		# «Controlla la chiave API» e' un consiglio SBAGLIATO se si passa dal Gateway: li' la
		# chiave non la tiene il gioco, e cercarla in Settings non porta da nessuna parte.
		# Stessa correzione fatta in Impostazioni, sull'altra meta' della strada.
		var aiuto := Testi.s("motore/aiuto_ollama") if LLMManager.e_locale() \
			else Testi.s("motore/aiuto_gateway" if LLMManager.usa_gateway else "motore/aiuto_esterno")
		_guaio_motore(Testi.s("motore/non_risponde", [dove, String(v.get("errore", "?")), aiuto]))
		return
	if v["modelli"].is_empty():
		LLMManager.mock_mode = true
		chk.set_pressed_no_signal(false)
		_guaio_motore(Testi.s("motore/niente_modelli", [dove]))
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
		_guaio_motore(Testi.s("motore/non_genera", [scelto, dove, String(v.get("errore_genera", "?"))]))
		return
	# ELENCATO NO, MA GENERA: non e' un guaio, e non merita di fermare nessuno con una
	# finestra. Va nel Log, che e' il posto delle cose da sapere e non da fare. Se poi
	# smettesse davvero di rispondere, sarebbe il ramo qui sopra a farsi vivo.
	if not v["modello_presente"]:
		_on_llm_log("[color=%s]%s[/color]" % [
			C_OXBLOOD.to_html(), Bbcode.neutro(Testi.s("motore/modello_assente", [scelto]))])
	# NIENTE messaggio di riuscita. Il motore che funziona non e' una notizia: si vede dal
	# fatto che gli dei rispondono, e il provider in uso sta gia' scritto in Settings.
	if not _busy and not _finita:
		await _rigenera_spunti()  # spunti contestuali generati dal modello

