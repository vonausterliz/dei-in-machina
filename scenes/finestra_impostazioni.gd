class_name FinestraImpostazioni
extends Window

## Impostazioni (menu Settings). Due schede, due domande diverse:
##  - «Modelli»: CHI da' voce agli dei — provider, modello, chiavi API, Gateway.
##  - «Costi»:   QUANTO lo si fa parlare — i limiti nati per risparmiare chiamate.
##
## Le chiavi NON stanno nel repo: si salvano in user://impostazioni.json (cartella dati
## dell'utente, fuori dal progetto). Restano valide le variabili d'ambiente: se una chiave
## è già nell'ambiente, quella ha la precedenza e qui appare come "già presente".

const C_SEA := Color("0e0b16")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")
const C_VERDIGRIS := Color("4e9a8e")
const C_OXBLOOD := Color("b04a34")

signal applicate
## Accendi (o spegni) i dèi veri sul provider selezionato. La GUI principale reagisce
## attivando il percorso reale e mostrandone l'esito.
signal motore_scelto(reale: bool)
## Dimensione dell'interfaccia scelta dall'utente (moltiplicatore sulla scala schermo).
signal zoom_scelto(fattore: float)

## Dimensione "logica" del contenuto. La finestra va poi moltiplicata per la scala:
## con content_scale_factor 2 (Retina) il contenuto occupa il doppio dei pixel.
const DIM_BASE := Vector2i(900, 780)

## IL MOTORE ORA HA DUE STATI, NON TRE.
##
## Prima erano «simulato / Ollama / provider esterno», e le ultime due erano in realta' la
## stessa cosa detta due volte: quale provider usare. Da quando Ollama e' un provider come
## gli altri resta la sola domanda vera — dei finti o dei veri.
const MOTORE_SIMULATO := 0
const MOTORE_REALE := 1

## Il valore salvato, tradotto dai tre stati vecchi ai due nuovi: 1 era «Ollama» e 2 era
## «esterno», e in entrambi i casi si voleva un motore vero.
static func motore_salvato() -> int:
	var v := int(Impostazioni.leggi("motore", MOTORE_REALE))
	return MOTORE_SIMULATO if v == MOTORE_SIMULATO else MOTORE_REALE

var _campi_chiave: Dictionary = {}   # nome_variabile_env -> LineEdit
var _opt_provider: OptionButton
var _opt_autore: OptionButton
var _riga_autore: HBoxContainer
var _opt_modello: OptionButton
var _chk_gateway: CheckBox
var _btn_prova: Button
var _btn_aggiorna: Button
var _stato: Label
var _stato_chiave: Label
var _costi_box: VBoxContainer
var _dlg_nome: ConfirmationDialog
var _campo_nome: LineEdit
var _dlg_aiuto: AcceptDialog
var _testo_aiuto: Label
var _scala := 1.0

## L'elenco dei modelli attualmente in mano: all'inizio quelli curati nel file del provider,
## dopo «Aggiorna» quelli che il provider ha appena elencato.
var _modelli: Array = []

func _init() -> void:
	title = Testi.s("finestre/impostazioni_titolo")
	size = DIM_BASE
	min_size = Vector2i(680, 500)
	visible = false

func _ready() -> void:
	if not close_requested.is_connected(hide):
		close_requested.connect(hide)
	var sfondo := ColorRect.new()
	sfondo.color = C_SEA
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sfondo)
	var margine := MarginContainer.new()
	margine.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lato in ["left", "top", "right", "bottom"]:
		margine.add_theme_constant_override("margin_" + lato, 18)
	add_child(margine)
	var schede := TabContainer.new()
	schede.set_anchors_preset(Control.PRESET_FULL_RECT)
	margine.add_child(schede)
	_scheda_modelli(schede)
	_scheda_costi(schede)
	_sincronizza()

# --- Scheda «Modelli» ---

func _scheda_modelli(schede: TabContainer) -> void:
	# Scorrevole: così il contenuto resta raggiungibile anche a finestra piccola.
	var scorri := ScrollContainer.new()
	scorri.name = Testi.s("impostazioni/tab_modelli")
	scorri.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	schede.add_child(scorri)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	scorri.add_child(v)

	v.add_child(_etichetta(Testi.s("impostazioni/aspetto"), 14, C_GOLD))
	var riga_zoom := HBoxContainer.new()
	riga_zoom.add_theme_constant_override("separation", 10)
	v.add_child(riga_zoom)
	riga_zoom.add_child(_etichetta(Testi.s("impostazioni/dimensione"), 13, C_BONE_DIM))
	var opt_zoom := OptionButton.new()
	for etichetta in ["100%", "115%", "130%", "150%", "175%"]:
		opt_zoom.add_item(etichetta)
	var zoom_valori := [1.0, 1.15, 1.30, 1.50, 1.75]
	opt_zoom.select(maxi(0, zoom_valori.find(float(Impostazioni.leggi("zoom", 1.0)))))
	opt_zoom.item_selected.connect(func(i):
		Impostazioni.scrivi("zoom", zoom_valori[i])
		zoom_scelto.emit(zoom_valori[i]))
	riga_zoom.add_child(opt_zoom)
	riga_zoom.add_child(_etichetta(Testi.s("impostazioni/dimensione_nota"), 12, C_BONE_DIM))

	v.add_child(_separatore())
	v.add_child(_etichetta(Testi.s("impostazioni/provider_modello"), 14, C_GOLD))
	var nota_p := _etichetta(Testi.s("impostazioni/provider_nota"), 12, C_BONE_DIM)
	nota_p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nota_p.custom_minimum_size = Vector2(600, 0)
	v.add_child(nota_p)

	var riga_p := HBoxContainer.new()
	riga_p.add_theme_constant_override("separation", 10)
	v.add_child(riga_p)
	riga_p.add_child(_etichetta(Testi.s("impostazioni/provider"), 13, C_BONE_DIM))
	_opt_provider = OptionButton.new()
	for nome in LLMManager.nomi_profili():
		_opt_provider.add_item(String(nome))
	_opt_provider.item_selected.connect(_on_provider)
	riga_p.add_child(_opt_provider)
	_stato_chiave = _etichetta("", 12, C_BONE_DIM)
	riga_p.add_child(_stato_chiave)

	# L'AUTORE. OpenRouter offre oltre trecento modelli: un menu piatto con dentro
	# trecento voci non e' un elenco fra cui scegliere, e' un muro. La riga compare solo
	# per i provider che usano nomi «autore/modello» — altrove non ci sarebbe niente dentro.
	_riga_autore = HBoxContainer.new()
	_riga_autore.add_theme_constant_override("separation", 10)
	v.add_child(_riga_autore)
	_riga_autore.add_child(_etichetta(Testi.s("impostazioni/autore"), 13, C_BONE_DIM))
	_opt_autore = OptionButton.new()
	_opt_autore.custom_minimum_size = Vector2(200, 0)
	_opt_autore.item_selected.connect(_on_autore)
	_riga_autore.add_child(_opt_autore)
	_riga_autore.add_child(_etichetta(Testi.s("impostazioni/autore_nota"), 11, C_BONE_DIM))

	var riga_m := HBoxContainer.new()
	riga_m.add_theme_constant_override("separation", 10)
	v.add_child(riga_m)
	riga_m.add_child(_etichetta(Testi.s("impostazioni/modello"), 13, C_BONE_DIM))
	_opt_modello = OptionButton.new()
	_opt_modello.custom_minimum_size = Vector2(300, 0)
	# Ricordato PER PROVIDER: un modello appartiene al suo provider.
	_opt_modello.item_selected.connect(func(i):
		LLMManager.ricorda_modello(_opt_modello.get_item_text(i)))
	riga_m.add_child(_opt_modello)
	_btn_aggiorna = Button.new()
	_btn_aggiorna.text = Testi.s("impostazioni/aggiorna_elenco")
	_btn_aggiorna.tooltip_text = Testi.s("impostazioni/tooltip_aggiorna")
	_btn_aggiorna.pressed.connect(_aggiorna_modelli)
	riga_m.add_child(_btn_aggiorna)
	_btn_prova = Button.new()
	_btn_prova.text = Testi.s("impostazioni/prova")
	_btn_prova.tooltip_text = Testi.s("impostazioni/tooltip_prova")
	_btn_prova.pressed.connect(_prova_modello)
	riga_m.add_child(_btn_prova)

	_chk_gateway = CheckBox.new()
	_chk_gateway.text = Testi.s("impostazioni/gateway")
	_chk_gateway.add_theme_color_override("font_color", C_BONE)
	_chk_gateway.toggled.connect(_on_gateway)
	v.add_child(_chk_gateway)

	v.add_child(_separatore())
	v.add_child(_etichetta(Testi.s("impostazioni/chiavi"), 14, C_GOLD))
	var nota := _etichetta(Testi.s("impostazioni/chiavi_nota"), 12, C_BONE_DIM)
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nota.custom_minimum_size = Vector2(600, 0)
	v.add_child(nota)

	var griglia := GridContainer.new()
	griglia.columns = 3
	griglia.add_theme_constant_override("h_separation", 10)
	griglia.add_theme_constant_override("v_separation", 8)
	v.add_child(griglia)
	for riga in _variabili_chiave():
		var env := String(riga[0])
		griglia.add_child(_etichetta("%s  ·  %s" % [String(riga[1]), env], 13, C_BONE))
		var campo := LineEdit.new()
		campo.secret = true
		campo.placeholder_text = Testi.s("impostazioni/chiave_placeholder")
		campo.custom_minimum_size = Vector2(340, 0)
		campo.text = _chiavi_salvate().get(env, "")
		_campi_chiave[env] = campo
		griglia.add_child(campo)
		var da_env := OS.has_environment(env) and OS.get_environment(env) != ""
		griglia.add_child(_etichetta(Testi.s("impostazioni/gia_ambiente") if da_env else "", 12, C_VERDIGRIS))

	v.add_child(_separatore())
	_stato = _etichetta("", 13, C_VERDIGRIS)
	_stato.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stato.custom_minimum_size = Vector2(600, 0)
	v.add_child(_stato)

	var azioni := HBoxContainer.new()
	azioni.add_theme_constant_override("separation", 10)
	v.add_child(azioni)
	var salva := Button.new()
	salva.text = Testi.s("impostazioni/salva")
	salva.pressed.connect(_salva)
	azioni.add_child(salva)
	var chiudi := Button.new()
	chiudi.text = Testi.s("impostazioni/chiudi")
	chiudi.pressed.connect(hide)
	azioni.add_child(chiudi)

# --- Scheda «Costi» ---

## Il pannello si costruisce dai DESCRITTORI dichiarati in data/profili_costo.json:
## aggiungere un limite non richiede di toccare l'interfaccia.
func _scheda_costi(schede: TabContainer) -> void:
	var scorri := ScrollContainer.new()
	scorri.name = Testi.s("impostazioni/tab_costi")
	scorri.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	schede.add_child(scorri)
	_costi_box = VBoxContainer.new()
	_costi_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_costi_box.add_theme_constant_override("separation", 10)
	scorri.add_child(_costi_box)
	_ridisegna_costi()

func _ridisegna_costi() -> void:
	# remove_child PRIMA di queue_free: queue_free e' differito a fine frame, e senza
	# toglierli subito le righe vecchie restano accanto alle nuove per un fotogramma.
	for c in _costi_box.get_children():
		_costi_box.remove_child(c)
		c.queue_free()

	_costi_box.add_child(_etichetta(Testi.s("impostazioni/costi_titolo"), 14, C_GOLD))
	var intro := _etichetta(Testi.s("impostazioni/profilo_nota"), 12, C_BONE_DIM)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(620, 0)
	_costi_box.add_child(intro)

	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	_costi_box.add_child(riga)
	riga.add_child(_etichetta(Testi.s("impostazioni/profilo"), 13, C_BONE))

	var profili := Costi.profili()
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(260, 0)
	for i in profili.size():
		opt.add_item(String(profili[i]["nome"]), i)
		if String(profili[i]["id"]) == Costi.attivo():
			opt.select(i)
	opt.item_selected.connect(func(i):
		Costi.usa(String(profili[i]["id"]))
		_ridisegna_costi())
	riga.add_child(opt)

	var attivo := Costi.get_profilo(Costi.attivo())
	var bloccato := bool(attivo.get("predefinito", true))

	var crea := Button.new()
	crea.text = Testi.s("impostazioni/nuovo_profilo")
	crea.tooltip_text = Testi.s("impostazioni/tooltip_nuovo_profilo")
	crea.pressed.connect(_chiedi_nome_profilo)
	riga.add_child(crea)

	# Cancellare: si puo' su tutti tranne i due predefiniti, che sono il riferimento con
	# cui il gioco e' stato tarato. Sui predefiniti il bottone c'e' lo stesso ma spento,
	# con la ragione nel tooltip: un comando che appare e sparisce si direbbe un difetto.
	var togli := Button.new()
	togli.text = Testi.s("impostazioni/cancella_profilo")
	togli.disabled = bloccato
	togli.tooltip_text = Testi.s("impostazioni/profilo_bloccato" if bloccato else "impostazioni/tooltip_cancella")
	if not bloccato:
		togli.add_theme_color_override("font_color", C_OXBLOOD)
		togli.pressed.connect(func(): _chiedi_conferma_cancella(String(attivo["id"]), String(attivo["nome"])))
	riga.add_child(togli)

	var descr := String(attivo.get("descrizione", ""))
	if descr != "":
		var d := _etichetta(descr, 12, C_BONE_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(620, 0)
		_costi_box.add_child(d)
	if bloccato:
		_costi_box.add_child(_etichetta(Testi.s("impostazioni/profilo_bloccato"), 12, C_GOLD))
	_costi_box.add_child(_separatore())

	for chiave in Costi.descrittori():
		_costi_box.add_child(_riga_limite(String(chiave), Costi.descrittori()[chiave], bloccato))

## Una manopola: etichetta senza gergo, il comando, il «?», e sotto una riga che dice cosa
## cambia davvero. Se la spiegazione non sta in una riga NON si accorcia — sta nel «?».
func _riga_limite(chiave: String, d: Dictionary, bloccato: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	box.add_child(riga)
	var id_profilo := Costi.attivo()
	var etichetta := String(d.get("etichetta", chiave))

	if String(d.get("tipo", "")) == "booleano":
		var chk := CheckBox.new()
		chk.text = etichetta
		chk.add_theme_color_override("font_color", C_BONE)
		chk.button_pressed = Costi.acceso(chiave)
		chk.disabled = bloccato
		chk.toggled.connect(func(premuto):
			Costi.imposta(id_profilo, chiave, premuto))
		riga.add_child(chk)
	else:
		var l := _etichetta(etichetta, 13, C_BONE)
		l.custom_minimum_size = Vector2(430, 0)
		riga.add_child(l)
		var sp := SpinBox.new()
		sp.min_value = int(d.get("min", 0))
		sp.max_value = int(d.get("max", 99))
		sp.value = Costi.limite(chiave)
		sp.editable = not bloccato
		sp.value_changed.connect(func(val):
			Costi.imposta(id_profilo, chiave, int(val)))
		riga.add_child(sp)

	var lungo := String(d.get("aiuto_lungo", ""))
	if lungo != "":
		riga.add_child(_bottone_aiuto(etichetta, lungo))

	var aiuto := String(d.get("aiuto", ""))
	if aiuto != "":
		var a := _etichetta(aiuto, 11, C_BONE_DIM)
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		a.custom_minimum_size = Vector2(620, 0)
		box.add_child(a)
	box.add_child(_separatore())
	return box

func _bottone_aiuto(titolo: String, testo: String) -> Button:
	var b := Button.new()
	b.text = "?"
	b.custom_minimum_size = Vector2(30, 0)
	b.tooltip_text = Testi.s("impostazioni/tooltip_aiuto")
	b.add_theme_color_override("font_color", C_GOLD)
	b.pressed.connect(func(): mostra_aiuto(titolo, testo))
	return b

func mostra_aiuto(titolo: String, testo: String) -> void:
	if _dlg_aiuto == null:
		_dlg_aiuto = AcceptDialog.new()
		_dlg_aiuto.min_size = Vector2i(560, 320)
		var m := MarginContainer.new()
		for lato in ["left", "top", "right", "bottom"]:
			m.add_theme_constant_override("margin_" + lato, 8)
		_testo_aiuto = Label.new()
		_testo_aiuto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_testo_aiuto.custom_minimum_size = Vector2(520, 0)
		m.add_child(_testo_aiuto)
		_dlg_aiuto.add_child(m)
		add_child(_dlg_aiuto)
	_dlg_aiuto.title = titolo
	_testo_aiuto.text = testo
	_apri(_dlg_aiuto, Vector2i(580, 340))

## Creare un profilo parte SEMPRE da uno esistente: si modifica, non si compila da zero.
func _chiedi_nome_profilo() -> void:
	if _dlg_nome == null:
		_dlg_nome = ConfirmationDialog.new()
		_dlg_nome.title = Testi.s("impostazioni/nome_nuovo_profilo")
		_dlg_nome.min_size = Vector2i(460, 210)
		var m := MarginContainer.new()
		for lato in ["left", "top", "right", "bottom"]:
			m.add_theme_constant_override("margin_" + lato, 10)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		var spiega := Label.new()
		spiega.text = Testi.s("impostazioni/nuovo_profilo_nota")
		spiega.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		spiega.custom_minimum_size = Vector2(400, 0)
		v.add_child(spiega)
		_campo_nome = LineEdit.new()
		_campo_nome.custom_minimum_size = Vector2(400, 34)
		_campo_nome.placeholder_text = Testi.s("impostazioni/nome_placeholder")
		v.add_child(_campo_nome)
		m.add_child(v)
		_dlg_nome.add_child(m)
		# I bottoni dei dialoghi di Godot nascono in inglese: «Cancel» in mezzo a una
		# finestra italiana e' una crepa piccola e visibilissima.
		_dlg_nome.ok_button_text = Testi.s("finestre/crea")
		_dlg_nome.cancel_button_text = Testi.s("finestre/annulla")
		# Invio = conferma: in un dialogo con un campo solo, dover andare col mouse fino a
		# OK e' un passaggio che nessuno si aspetta.
		_dlg_nome.register_text_enter(_campo_nome)
		_dlg_nome.confirmed.connect(func():
			var id := Costi.crea(_campo_nome.text, Costi.attivo())
			if id != "":
				Costi.usa(id)
			_ridisegna_costi())
		add_child(_dlg_nome)
	_campo_nome.text = ""
	_apri(_dlg_nome, Vector2i(480, 230))
	_campo_nome.grab_focus()

func _chiedi_conferma_cancella(id: String, nome: String) -> void:
	var d := ConfirmationDialog.new()
	d.title = Testi.s("impostazioni/cancella_profilo")
	d.dialog_text = Testi.s("impostazioni/cancella_conferma", [nome])
	d.ok_button_text = Testi.s("impostazioni/cancella_profilo")
	d.cancel_button_text = Testi.s("finestre/annulla")
	d.min_size = Vector2i(420, 170)
	d.confirmed.connect(func():
		Costi.cancella(id)
		_ridisegna_costi())
	d.visibility_changed.connect(func():
		if not d.visible:
			d.queue_free())
	add_child(d)
	_apri(d, Vector2i(440, 190))

## I DIALOGHI SONO FINESTRE A SE': non ereditano il content_scale_factor del genitore.
## Con l'interfaccia al 150% la finestra scalava e il dialogo no — usciva grande come un
## francobollo, col bottone OK illeggibile. La scala va data anche a loro, e la dimensione
## moltiplicata di conseguenza, o il contenuto scalato non ci sta dentro.
func _apri(d: Window, dim: Vector2i) -> void:
	d.content_scale_factor = _scala
	d.popup_centered(Vector2i(int(dim.x * _scala), int(dim.y * _scala)))

# --- costruzione minuta ---

func _etichetta(testo: String, dim: int, col: Color) -> Label:
	var l := Label.new()
	l.text = testo
	l.add_theme_font_size_override("font_size", dim)
	l.add_theme_color_override("font_color", col)
	return l

func _separatore() -> Control:
	var r := ColorRect.new()
	r.color = Color(C_GOLD, 0.20)
	r.custom_minimum_size = Vector2(0, 1)
	return r

## Le variabili d'ambiente dichiarate dai provider, con accanto il provider che le usa —
## «OPENROUTER_API_KEY» da solo non dice a chi serve. I provider locali non compaiono:
## non hanno chiavi da chiedere.
func _variabili_chiave() -> Array:
	var out: Array = []
	var visti: Dictionary = {}
	for p in LLMManager.profili:
		var env := String(p.get("api_key_env", ""))
		if env == "" or visti.has(env):
			continue
		visti[env] = true
		out.append([env, String(p.get("nome", "?"))])
	return out

# --- persistenza ---

static func _chiavi_salvate() -> Dictionary:
	return Impostazioni.chiavi()

## Compatibilita': l'avvio chiama questa; la sostanza sta in Impostazioni.
static func applica_chiavi_salvate() -> void:
	Impostazioni.applica_chiavi_all_ambiente()

func _salva() -> void:
	var chiavi: Dictionary = {}
	for env in _campi_chiave:
		var v: String = _campi_chiave[env].text.strip_edges()
		if v != "":
			chiavi[env] = v
			if not (OS.has_environment(env) and OS.get_environment(env) != ""):
				OS.set_environment(env, v)
	Impostazioni.scrivi("chiavi", chiavi)
	_stato.text = Testi.s("impostazioni/salvato")
	_aggiorna_stato_chiave()
	applicate.emit()

# --- reazioni ---

func _on_provider(idx: int) -> void:
	# Salvato per NOME: aggiungere o togliere un file in config/providers/ non deve far
	# scivolare la scelta su un altro provider.
	var nomi: Array = LLMManager.nomi_profili()
	Impostazioni.scrivi("provider_nome", String(nomi[idx]) if idx < nomi.size() else "")
	LLMManager.imposta_profilo(idx)
	_sincronizza_modello()

func _on_autore(_i: int) -> void:
	_riempi_modelli(_autore_scelto(), LLMManager.modello_del_profilo())
	# Cambiare autore cambia il modello mostrato: se non lo si registra, il gioco resta
	# su quello di prima mentre il menu ne mostra un altro.
	if _opt_modello.item_count > 0:
		LLMManager.ricorda_modello(_opt_modello.get_item_text(maxi(0, _opt_modello.selected)))

## La spunta e' ORTOGONALE al provider: dice solo se passare dalla coda locale. Prima
## selezionava il "profilo gateway", e quindi accenderla voleva dire perdere il provider
## scelto — si poteva avere il throttling del piano gratuito oppure Gemini, non entrambi.
func _on_gateway(premuto: bool) -> void:
	LLMManager.imposta_gateway(premuto)
	Impostazioni.scrivi("usa_gateway", premuto)
	_sincronizza_modello()
	_stato.text = Testi.s("impostazioni/gateway_scelto" if premuto else "impostazioni/gateway_spento")

## Adegua la finestra alla scala, senza uscire dallo schermo.
func adegua_a_scala(f: float) -> void:
	_scala = clampf(f, 1.0, 3.0)
	content_scale_factor = _scala
	var schermo := DisplayServer.screen_get_size()
	size = Vector2i(
		mini(int(DIM_BASE.x * content_scale_factor), schermo.x - 60),
		mini(int(DIM_BASE.y * content_scale_factor), schermo.y - 80))

func _sincronizza() -> void:
	if LLMManager.profili.is_empty():
		return
	_opt_provider.select(LLMManager.profilo_idx)
	_chk_gateway.set_pressed_no_signal(LLMManager.usa_gateway)
	_sincronizza_modello()

## Rimette il menu dei modelli su cio' che il provider selezionato offre: i modelli curati
## nel suo file, piu' quello scelto se non fosse gia' fra loro.
func _sincronizza_modello() -> void:
	var elenco: Array = LLMManager.modelli_noti().duplicate()
	var attuale := LLMManager.modello_del_profilo()
	if attuale != "" and attuale != "?" and not elenco.has(attuale):
		elenco.append(attuale)
	_usa_elenco(elenco, attuale)
	_aggiorna_stato_chiave()

## Un provider locale non vuole chiavi; uno remoto senza chiave non puo' funzionare, e
## dirlo qui evita di scoprirlo a partita iniziata con gli dei muti.
func _aggiorna_stato_chiave() -> void:
	if LLMManager.e_locale():
		_stato_chiave.text = Testi.s("impostazioni/provider_locale")
		_stato_chiave.add_theme_color_override("font_color", C_VERDIGRIS)
	elif LLMManager.chiave_presente():
		_stato_chiave.text = Testi.s("impostazioni/chiave_ok")
		_stato_chiave.add_theme_color_override("font_color", C_VERDIGRIS)
	else:
		_stato_chiave.text = Testi.s("impostazioni/chiave_manca")
		_stato_chiave.add_theme_color_override("font_color", C_OXBLOOD)
	# Davanti a un provider locale il Gateway non ha senso: non c'e' nessun piano gratuito
	# da rispettare, e la coda aggiungerebbe attesa senza proteggere da niente.
	_chk_gateway.disabled = not LLMManager.gateway_disponibile() or LLMManager.e_locale()

## Riempie i due menu — autore e modello — a partire dall'elenco in mano.
func _usa_elenco(modelli: Array, selezionato: String) -> void:
	_modelli = LLMManager.solo_modelli_testuali(
		modelli, LLMManager.filtro_modelli(), LLMManager.nome_pieno())
	var elenco_autori := LLMManager.autori(_modelli)
	_riga_autore.visible = not elenco_autori.is_empty()
	_opt_autore.clear()
	if elenco_autori.is_empty():
		_riempi_modelli("", selezionato)
		return
	var mio := LLMManager.autore_di(selezionato)
	for i in elenco_autori.size():
		_opt_autore.add_item(String(elenco_autori[i]))
		if String(elenco_autori[i]) == mio:
			_opt_autore.select(i)
	if _opt_autore.selected < 0:
		_opt_autore.select(0)
	_riempi_modelli(_autore_scelto(), selezionato)

func _autore_scelto() -> String:
	if not _riga_autore.visible or _opt_autore.selected < 0:
		return ""
	return _opt_autore.get_item_text(_opt_autore.selected)

func _riempi_modelli(autore: String, selezionato: String) -> void:
	_opt_modello.clear()
	var suoi := LLMManager.modelli_di(autore, _modelli)
	for i in suoi.size():
		_opt_modello.add_item(String(suoi[i]))
		if String(suoi[i]) == selezionato:
			_opt_modello.select(i)
	if _opt_modello.item_count > 0 and _opt_modello.selected < 0:
		_opt_modello.select(0)
	_opt_modello.disabled = _opt_modello.item_count == 0

## CHIEDE L'ELENCO AL PROVIDER SELEZIONATO NEL MENU.
##
## Prima chiamava verifica_provider(), che interroga il MOTORE ACCESO: con Ollama in
## esecuzione e OpenRouter scelto qui sopra, il gioco chiedeva la lista a Ollama e la
## mostrava come se fosse di OpenRouter. Nessun errore, nessuna spia: la risposta di un
## altro. Il bottone «Prova il modello», accanto, faceva gia' la cosa giusta.
func _aggiorna_modelli() -> void:
	_btn_aggiorna.disabled = true
	_stato.add_theme_color_override("font_color", C_BONE_DIM)
	_stato.text = Testi.s("impostazioni/interrogo", [LLMManager.nome_profilo_corrente()])
	var r: Dictionary = await LLMManager.elenca_modelli_del_profilo()
	_btn_aggiorna.disabled = false
	if not r["ok"]:
		_verdetto(Testi.s("impostazioni/non_raggiungibile", [String(r["dove"]), String(r["errore"])]), false)
		return
	var modelli: Array = r["modelli"]
	if modelli.is_empty():
		_verdetto(Testi.s("impostazioni/elenco_vuoto", [LLMManager.nome_profilo_corrente()]), false)
		return
	_usa_elenco(modelli, LLMManager.modello_del_profilo())
	_verdetto(Testi.s("impostazioni/modelli_trovati",
		[_modelli.size(), LLMManager.nome_profilo_corrente(), modelli.size()]), true)

## Prova il modello configurato QUI, non quello che sta girando: si sta configurando
## Gemini mentre il gioco e' ancora sul motore simulato, e provare "il provider attivo"
## proverebbe Ollama. Verdetto in chiaro, coi colori: verde funziona, rosso no.
func _prova_modello() -> void:
	_btn_prova.disabled = true
	_stato.text = Testi.s("impostazioni/provo", [LLMManager.modello_del_profilo()])
	_stato.add_theme_color_override("font_color", C_BONE_DIM)
	var v: Dictionary = await LLMManager.prova_profilo()
	_btn_prova.disabled = false

	# L'elenco appena arrivato dal provider: se qualcosa non va, le alternative sono li'.
	if not v["modelli"].is_empty():
		_usa_elenco(v["modelli"], String(v["atteso"]))

	if not v["raggiungibile"]:
		_verdetto(Testi.s("impostazioni/prova_irraggiungibile", [v["dove"], v["errore"]]), false)
	elif not v["genera"]:
		_verdetto(Testi.s("impostazioni/prova_non_genera", [v["atteso"], v["errore"]]), false)
	elif not v["elencato"]:
		# Genera ma non compare in elenco: funziona, quindi va bene — capita con gli alias.
		_verdetto(Testi.s("impostazioni/prova_ok_non_elencato", [v["atteso"], v["ms"]]), true)
		_accendi_se_spento()
	else:
		_verdetto(Testi.s("impostazioni/prova_ok", [v["atteso"], v["ms"]]), true)
		_accendi_se_spento()

## Una prova riuscita mentre il gioco e' rimasto sul simulato lascia l'utente in trappola:
## il motore funziona, ma nessuno l'ha acceso — e la partita continua con dèi finti senza
## che si veda. E' successo davvero. Un bottone "prova" senza effetti collaterali e' pulito
## in teoria; qui la cosa giusta e' accendere, e dirlo.
func _accendi_se_spento() -> void:
	if not LLMManager.mock_mode:
		return
	Impostazioni.scrivi("motore", MOTORE_REALE)
	motore_scelto.emit(true)
	_stato.text += "\n" + Testi.s("impostazioni/motore_acceso")

func _verdetto(testo: String, buono: bool) -> void:
	_stato.text = testo
	_stato.add_theme_color_override("font_color", C_VERDIGRIS if buono else C_OXBLOOD)
