class_name FinestraImpostazioni
extends Window

## Impostazioni (menu Settings): provider, modello, chiavi API e uso del Gateway.
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
## Il motore scelto: chi dà voce agli dèi. La GUI principale reagisce attivando il
## percorso giusto (mock / Ollama / API esterna) e mostrandone l'esito.
signal motore_scelto(modo: int)
## Dimensione dell'interfaccia scelta dall'utente (moltiplicatore sulla scala schermo).
signal zoom_scelto(fattore: float)

## Dimensione "logica" del contenuto. La finestra va poi moltiplicata per la scala:
## con content_scale_factor 2 (Retina) il contenuto occupa il doppio dei pixel.
const DIM_BASE := Vector2i(860, 760)

## Il simulato NON e' una scelta di gioco: esiste solo come stato tecnico di partenza e
## per i test/console headless. Non compare nel menu e nessuno puo' selezionarlo.
const MOTORE_MOCK := 0
const MOTORE_OLLAMA := 1
const MOTORE_ESTERNO := 2

var _campi_chiave: Dictionary = {}   # nome_variabile_env -> LineEdit
var _opt_motore: OptionButton
var _opt_provider: OptionButton
var _opt_modello: OptionButton
var _chk_gateway: CheckBox
var _btn_prova: Button
var _stato: Label
var _costi_box: VBoxContainer
var _dlg_nome: AcceptDialog
var _campo_nome: LineEdit

func _init() -> void:
	title = Testi.s("finestre/impostazioni_titolo")
	size = DIM_BASE
	min_size = Vector2i(640, 460)
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
	# Due schede: i modelli (chi parla) e i costi (quanto lo si fa parlare). Sono due
	# domande diverse, e mescolarle in un'unica colonna le rendeva entrambe piu' confuse.
	var schede := TabContainer.new()
	schede.set_anchors_preset(Control.PRESET_FULL_RECT)
	margine.add_child(schede)

	# Scorrevole: cosi' il contenuto resta raggiungibile anche a finestra piccola.
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
	v.add_child(_etichetta(Testi.s("impostazioni/motore"), 14, C_GOLD))
	var riga_motore := HBoxContainer.new()
	riga_motore.add_theme_constant_override("separation", 10)
	v.add_child(riga_motore)
	riga_motore.add_child(_etichetta(Testi.s("impostazioni/chi_parla"), 13, C_BONE_DIM))
	_opt_motore = OptionButton.new()
	# Il simulato (mock) resta solo come stato interno di partenza e per i test: non e'
	# una scelta di gioco, quindi non compare qui.
	_opt_motore.add_item(Testi.s("impostazioni/ollama_locale"), MOTORE_OLLAMA)
	_opt_motore.add_item(Testi.s("impostazioni/provider_esterno"), MOTORE_ESTERNO)
	var motore_salvato := int(Impostazioni.leggi("motore", MOTORE_ESTERNO))
	var idx_motore := _opt_motore.get_item_index(motore_salvato)
	_opt_motore.select(idx_motore if idx_motore >= 0 else 0)
	_opt_motore.item_selected.connect(func(i):
		var modo := _opt_motore.get_item_id(i)
		Impostazioni.scrivi("motore", modo)
		motore_scelto.emit(modo))
	riga_motore.add_child(_opt_motore)

	v.add_child(_separatore())
	v.add_child(_etichetta(Testi.s("impostazioni/provider_modello"), 14, C_GOLD))
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	v.add_child(riga)
	riga.add_child(_etichetta(Testi.s("impostazioni/provider"), 13, C_BONE_DIM))
	_opt_provider = OptionButton.new()
	for nome in LLMManager.nomi_profili_esterni():
		_opt_provider.add_item(String(nome))
	_opt_provider.item_selected.connect(_on_provider)
	riga.add_child(_opt_provider)
	riga.add_child(_etichetta(Testi.s("impostazioni/modello"), 13, C_BONE_DIM))
	_opt_modello = OptionButton.new()
	# Ricordato PER PROVIDER: un modello appartiene al suo provider.
	_opt_modello.item_selected.connect(func(i):
		LLMManager.ricorda_modello(_opt_modello.get_item_text(i))
		_sincronizza_modello())
	riga.add_child(_opt_modello)
	var btn_agg := Button.new()
	btn_agg.text = Testi.s("impostazioni/aggiorna_elenco")
	btn_agg.pressed.connect(_aggiorna_modelli)
	riga.add_child(btn_agg)
	_btn_prova = Button.new()
	_btn_prova.text = Testi.s("impostazioni/prova")
	_btn_prova.pressed.connect(_prova_modello)
	riga.add_child(_btn_prova)

	_chk_gateway = CheckBox.new()
	_chk_gateway.text = Testi.s("impostazioni/gateway")
	_chk_gateway.add_theme_color_override("font_color", C_BONE)
	_chk_gateway.toggled.connect(_on_gateway)
	v.add_child(_chk_gateway)

	v.add_child(_separatore())
	v.add_child(_etichetta(Testi.s("impostazioni/chiavi"), 14, C_GOLD))
	var nota := _etichetta(Testi.s("impostazioni/chiavi_nota"), 12, C_BONE_DIM)
	nota.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nota)

	var griglia := GridContainer.new()
	griglia.columns = 3
	griglia.add_theme_constant_override("h_separation", 10)
	griglia.add_theme_constant_override("v_separation", 8)
	v.add_child(griglia)
	for env in _variabili_chiave():
		griglia.add_child(_etichetta(env, 13, C_BONE))
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

	_scheda_costi(schede)
	_sincronizza()

# --- costruzione minuta ---

## LA SCHEDA DEI COSTI. Il pannello si costruisce dai DESCRITTORI dichiarati in
## data/profili_costo.json: aggiungere un limite non richiede di toccare l'interfaccia.
func _scheda_costi(schede: TabContainer) -> void:
	var scorri := ScrollContainer.new()
	scorri.name = Testi.s("impostazioni/tab_costi")
	scorri.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	schede.add_child(scorri)
	_costi_box = VBoxContainer.new()
	_costi_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_costi_box.add_theme_constant_override("separation", 12)
	scorri.add_child(_costi_box)
	_ridisegna_costi()

func _ridisegna_costi() -> void:
	for c in _costi_box.get_children():
		_costi_box.remove_child(c)
		c.queue_free()

	_costi_box.add_child(_etichetta(Testi.s("impostazioni/profilo_nota"), 12, C_BONE_DIM))
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	_costi_box.add_child(riga)
	riga.add_child(_etichetta(Testi.s("impostazioni/profilo"), 13, C_BONE_DIM))

	var profili := Costi.profili()
	var opt := OptionButton.new()
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
	crea.pressed.connect(_chiedi_nome_profilo)
	riga.add_child(crea)

	if not bloccato:
		var togli := Button.new()
		togli.text = Testi.s("impostazioni/cancella_profilo")
		togli.add_theme_color_override("font_color", C_OXBLOOD)
		togli.pressed.connect(func():
			Costi.cancella(String(attivo["id"]))
			_ridisegna_costi())
		riga.add_child(togli)

	var descr := String(attivo.get("descrizione", ""))
	if descr != "":
		var d := _etichetta(descr, 12, C_BONE_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(560, 0)
		_costi_box.add_child(d)
	if bloccato:
		_costi_box.add_child(_etichetta(Testi.s("impostazioni/profilo_bloccato"), 12, C_GOLD))
	_costi_box.add_child(_separatore())

	for chiave in Costi.descrittori():
		_costi_box.add_child(_riga_limite(String(chiave), Costi.descrittori()[chiave], bloccato))

func _riga_limite(chiave: String, d: Dictionary, bloccato: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	box.add_child(riga)
	var id_profilo := Costi.attivo()

	if String(d.get("tipo", "")) == "booleano":
		var chk := CheckBox.new()
		chk.text = String(d.get("etichetta", chiave))
		chk.button_pressed = Costi.acceso(chiave)
		chk.disabled = bloccato
		chk.toggled.connect(func(premuto):
			Costi.imposta(id_profilo, chiave, premuto))
		riga.add_child(chk)
	else:
		riga.add_child(_etichetta(String(d.get("etichetta", chiave)), 13, C_BONE))
		var sp := SpinBox.new()
		sp.min_value = int(d.get("min", 0))
		sp.max_value = int(d.get("max", 99))
		sp.value = Costi.limite(chiave)
		sp.editable = not bloccato
		sp.value_changed.connect(func(val):
			Costi.imposta(id_profilo, chiave, int(val)))
		riga.add_child(sp)

	var aiuto := String(d.get("aiuto", ""))
	if aiuto != "":
		var a := _etichetta(aiuto, 11, C_BONE_DIM)
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		a.custom_minimum_size = Vector2(560, 0)
		box.add_child(a)
	return box

## Creare un profilo parte SEMPRE da uno esistente: si modifica, non si compila da zero.
func _chiedi_nome_profilo() -> void:
	if _dlg_nome == null:
		_dlg_nome = AcceptDialog.new()
		_dlg_nome.title = Testi.s("impostazioni/nome_nuovo_profilo")
		_campo_nome = LineEdit.new()
		_campo_nome.custom_minimum_size = Vector2(280, 0)
		_dlg_nome.add_child(_campo_nome)
		_dlg_nome.confirmed.connect(func():
			var id := Costi.crea(_campo_nome.text, Costi.attivo())
			if id != "":
				Costi.usa(id)
			_ridisegna_costi())
		add_child(_dlg_nome)
	_campo_nome.text = ""
	_dlg_nome.popup_centered()

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

## Le variabili d'ambiente dichiarate dai profili (così l'elenco segue i profili, non è fisso).
func _variabili_chiave() -> Array:
	var out: Array = []
	for p in LLMManager.profili_esterni:
		var env := String(p.get("api_key_env", ""))
		if env != "" and not out.has(env):
			out.append(env)
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
	applicate.emit()

# --- reazioni ---

func _on_provider(idx: int) -> void:
	# Salvato per NOME: aggiungere o togliere un file in config/providers/ non deve far
	# scivolare la scelta su un altro provider.
	Impostazioni.scrivi("provider_nome", LLMManager.nomi_profili_esterni()[idx] if idx < LLMManager.nomi_profili_esterni().size() else "")
	LLMManager.imposta_profilo_esterno(idx)
	_sincronizza_modello()

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
	content_scale_factor = clampf(f, 1.0, 3.0)
	var schermo := DisplayServer.screen_get_size()
	size = Vector2i(
		mini(int(DIM_BASE.x * content_scale_factor), schermo.x - 60),
		mini(int(DIM_BASE.y * content_scale_factor), schermo.y - 80))

func _sincronizza() -> void:
	if LLMManager.profili_esterni.is_empty():
		return
	_opt_provider.select(LLMManager.provider_esterno_idx)
	_chk_gateway.set_pressed_no_signal(LLMManager.usa_gateway)
	_chk_gateway.disabled = not LLMManager.gateway_disponibile()
	_sincronizza_modello()

func _sincronizza_modello() -> void:
	_opt_modello.clear()
	_opt_modello.add_item(LLMManager.modello_del_profilo())
	_opt_modello.select(0)

## Chiede al provider l'elenco dei modelli disponibili.
func _aggiorna_modelli() -> void:
	_stato.text = Testi.s("impostazioni/interrogo")
	var v: Dictionary = await LLMManager.verifica_ollama()
	if not v["attivo"]:
		_stato.text = Testi.s("impostazioni/non_raggiungibile", [v.get("errore", "?")])
		return
	_riempi_modelli(v["modelli"])
	var atteso: String = v["atteso"]
	for i in _opt_modello.item_count:
		if _opt_modello.get_item_text(i) == atteso:
			_opt_modello.select(i)
	_stato.text = Testi.s("impostazioni/modelli_trovati", [v["modelli"].size()])


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
		_riempi_modelli(v["modelli"])
		for i in _opt_modello.item_count:
			if _opt_modello.get_item_text(i) == String(v["atteso"]):
				_opt_modello.select(i)

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
	var modo := _opt_motore.get_item_id(_opt_motore.selected)
	Impostazioni.scrivi("motore", modo)
	motore_scelto.emit(modo)
	_stato.text += "\n" + Testi.s("impostazioni/motore_acceso")

## Riempie il menu coi soli modelli che sanno scrivere testo: l'endpoint dei provider
## restituisce tutto il catalogo (voce, immagini, video, embedding) e offrirlo intero
## significa proporre scelte che non possono funzionare.
func _riempi_modelli(modelli: Array) -> void:
	_opt_modello.clear()
	var pieno := LLMManager.nome_pieno()
	var utili := LLMManager.solo_modelli_testuali(modelli, LLMManager.filtro_modelli(), pieno)
	for m in utili:
		_opt_modello.add_item(LLMManager.nome_nudo(String(m), pieno))

func _verdetto(testo: String, buono: bool) -> void:
	_stato.text = testo
	_stato.add_theme_color_override("font_color", C_VERDIGRIS if buono else C_OXBLOOD)
