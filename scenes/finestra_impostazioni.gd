class_name FinestraImpostazioni
extends Window

## Impostazioni (menu Settings): provider, modello, chiavi API e uso del Gateway.
##
## Le chiavi NON stanno nel repo: si salvano in user://impostazioni.json (cartella dati
## dell'utente, fuori dal progetto). Restano valide le variabili d'ambiente: se una chiave
## è già nell'ambiente, quella ha la precedenza e qui appare come "già presente".

const PERCORSO := "user://impostazioni.json"

const C_SEA := Color("0e0b16")
const C_BONE := Color("eadfc7")
const C_BONE_DIM := Color("b4a98d")
const C_GOLD := Color("cba24b")
const C_VERDIGRIS := Color("4e9a8e")

signal applicate
## Il motore scelto: chi dà voce agli dèi. La GUI principale reagisce attivando il
## percorso giusto (mock / Ollama / API esterna) e mostrandone l'esito.
signal motore_scelto(modo: int)
## Dimensione dell'interfaccia scelta dall'utente (moltiplicatore sulla scala schermo).
signal zoom_scelto(fattore: float)

const MOTORE_MOCK := 0
const MOTORE_OLLAMA := 1
const MOTORE_ESTERNO := 2

var _campi_chiave: Dictionary = {}   # nome_variabile_env -> LineEdit
var _opt_motore: OptionButton
var _opt_provider: OptionButton
var _opt_modello: OptionButton
var _chk_gateway: CheckBox
var _stato: Label

func _init() -> void:
	title = "Impostazioni · modelli e chiavi API"
	size = Vector2i(680, 560)
	visible = false
	close_requested.connect(hide)

func _ready() -> void:
	var sfondo := ColorRect.new()
	sfondo.color = C_SEA
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sfondo)
	var margine := MarginContainer.new()
	margine.set_anchors_preset(Control.PRESET_FULL_RECT)
	for lato in ["left", "top", "right", "bottom"]:
		margine.add_theme_constant_override("margin_" + lato, 18)
	add_child(margine)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	margine.add_child(v)

	v.add_child(_etichetta("ASPETTO", 14, C_GOLD))
	var riga_zoom := HBoxContainer.new()
	riga_zoom.add_theme_constant_override("separation", 10)
	v.add_child(riga_zoom)
	riga_zoom.add_child(_etichetta("Dimensione interfaccia:", 13, C_BONE_DIM))
	var opt_zoom := OptionButton.new()
	for etichetta in ["100%", "115%", "130%", "150%", "175%"]:
		opt_zoom.add_item(etichetta)
	opt_zoom.select(0)
	opt_zoom.item_selected.connect(func(i):
		zoom_scelto.emit([1.0, 1.15, 1.30, 1.50, 1.75][i]))
	riga_zoom.add_child(opt_zoom)
	riga_zoom.add_child(_etichetta("(vale per il gioco e per le finestre di servizio)", 12, C_BONE_DIM))

	v.add_child(_separatore())
	v.add_child(_etichetta("MOTORE", 14, C_GOLD))
	var riga_motore := HBoxContainer.new()
	riga_motore.add_theme_constant_override("separation", 10)
	v.add_child(riga_motore)
	riga_motore.add_child(_etichetta("Chi dà voce agli dèi:", 13, C_BONE_DIM))
	_opt_motore = OptionButton.new()
	_opt_motore.add_item("Simulato (senza LLM, istantaneo)", MOTORE_MOCK)
	_opt_motore.add_item("Ollama locale", MOTORE_OLLAMA)
	_opt_motore.add_item("Provider esterno (API)", MOTORE_ESTERNO)
	_opt_motore.item_selected.connect(func(i): motore_scelto.emit(_opt_motore.get_item_id(i)))
	riga_motore.add_child(_opt_motore)

	v.add_child(_separatore())
	v.add_child(_etichetta("PROVIDER E MODELLO", 14, C_GOLD))
	var riga := HBoxContainer.new()
	riga.add_theme_constant_override("separation", 10)
	v.add_child(riga)
	riga.add_child(_etichetta("Provider:", 13, C_BONE_DIM))
	_opt_provider = OptionButton.new()
	for nome in LLMManager.nomi_profili_esterni():
		_opt_provider.add_item(String(nome))
	_opt_provider.item_selected.connect(_on_provider)
	riga.add_child(_opt_provider)
	riga.add_child(_etichetta("Modello:", 13, C_BONE_DIM))
	_opt_modello = OptionButton.new()
	_opt_modello.item_selected.connect(func(i): LLMManager.imposta_modello(_opt_modello.get_item_text(i)))
	riga.add_child(_opt_modello)
	var btn_agg := Button.new()
	btn_agg.text = "Aggiorna elenco"
	btn_agg.pressed.connect(_aggiorna_modelli)
	riga.add_child(btn_agg)

	_chk_gateway = CheckBox.new()
	_chk_gateway.text = "Passa dal Gateway locale (limiti del piano gratuito: coda, throttling, cache)"
	_chk_gateway.add_theme_color_override("font_color", C_BONE)
	_chk_gateway.toggled.connect(_on_gateway)
	v.add_child(_chk_gateway)

	v.add_child(_separatore())
	v.add_child(_etichetta("CHIAVI API", 14, C_GOLD))
	var nota := _etichetta("Salvate nella cartella dati dell'utente, mai nel progetto. Una chiave già presente nell'ambiente ha la precedenza.", 12, C_BONE_DIM)
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
		campo.placeholder_text = "incolla qui la chiave"
		campo.custom_minimum_size = Vector2(340, 0)
		campo.text = _chiavi_salvate().get(env, "")
		_campi_chiave[env] = campo
		griglia.add_child(campo)
		var da_env := OS.has_environment(env) and OS.get_environment(env) != ""
		griglia.add_child(_etichetta("già nell'ambiente" if da_env else "", 12, C_VERDIGRIS))

	v.add_child(_separatore())
	_stato = _etichetta("", 13, C_VERDIGRIS)
	_stato.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stato)

	var azioni := HBoxContainer.new()
	azioni.add_theme_constant_override("separation", 10)
	v.add_child(azioni)
	var salva := Button.new()
	salva.text = "Salva e applica"
	salva.pressed.connect(_salva)
	azioni.add_child(salva)
	var chiudi := Button.new()
	chiudi.text = "Chiudi"
	chiudi.pressed.connect(hide)
	azioni.add_child(chiudi)

	_sincronizza()

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
	if not FileAccess.file_exists(PERCORSO):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var c: Variant = parsed.get("chiavi", {})
	return c if typeof(c) == TYPE_DICTIONARY else {}

## Carica le chiavi salvate nell'ambiente del processo (all'avvio del gioco), così il
## resto del codice continua a leggerle come sempre da OS.get_environment.
static func applica_chiavi_salvate() -> void:
	for env in _chiavi_salvate():
		var valore := String(_chiavi_salvate()[env])
		# L'ambiente vero ha la precedenza: non lo sovrascrivo.
		if valore != "" and not (OS.has_environment(env) and OS.get_environment(env) != ""):
			OS.set_environment(env, valore)

func _salva() -> void:
	var chiavi: Dictionary = {}
	for env in _campi_chiave:
		var v: String = _campi_chiave[env].text.strip_edges()
		if v != "":
			chiavi[env] = v
			if not (OS.has_environment(env) and OS.get_environment(env) != ""):
				OS.set_environment(env, v)
	var f := FileAccess.open(PERCORSO, FileAccess.WRITE)
	if f == null:
		_stato.text = "Impossibile salvare le impostazioni."
		return
	f.store_string(JSON.stringify({"chiavi": chiavi}, "  "))
	f.close()
	_stato.text = "Salvato. Le chiavi valgono da subito (le nuove chiamate le useranno)."
	applicate.emit()

# --- reazioni ---

func _on_provider(idx: int) -> void:
	LLMManager.imposta_profilo_esterno(idx)
	_sincronizza_modello()

func _on_gateway(premuto: bool) -> void:
	# Il Gateway è semplicemente uno dei profili: selezionarlo è "passare dal gateway".
	var idx := _indice_gateway()
	if premuto and idx >= 0:
		_opt_provider.select(idx)
		LLMManager.imposta_profilo_esterno(idx)
		_sincronizza_modello()
		_stato.text = "Gateway selezionato. Ricorda di avviarlo: llm_gateway/gateway.sh start"
	elif not premuto and _indice_gateway() == _opt_provider.selected:
		var alt := 1 if LLMManager.profili_esterni.size() > 1 else 0
		_opt_provider.select(alt)
		LLMManager.imposta_profilo_esterno(alt)
		_sincronizza_modello()

func _indice_gateway() -> int:
	var nomi: Array = LLMManager.nomi_profili_esterni()
	for i in nomi.size():
		if String(nomi[i]).to_lower().find("gateway") != -1:
			return i
	return -1

func _sincronizza() -> void:
	if LLMManager.profili_esterni.is_empty():
		return
	_opt_provider.select(LLMManager.provider_esterno_idx)
	_chk_gateway.set_pressed_no_signal(LLMManager.provider_esterno_idx == _indice_gateway())
	_sincronizza_modello()

func _sincronizza_modello() -> void:
	_opt_modello.clear()
	_opt_modello.add_item(LLMManager.modello_atteso())
	_opt_modello.select(0)

## Chiede al provider l'elenco dei modelli disponibili.
func _aggiorna_modelli() -> void:
	_stato.text = "Interrogo il provider…"
	var v: Dictionary = await LLMManager.verifica_ollama()
	if not v["attivo"]:
		_stato.text = "Provider non raggiungibile: %s" % v.get("errore", "?")
		return
	_opt_modello.clear()
	for m in v["modelli"]:
		_opt_modello.add_item(String(m))
	var atteso: String = v["atteso"]
	for i in _opt_modello.item_count:
		if _opt_modello.get_item_text(i) == atteso:
			_opt_modello.select(i)
	_stato.text = "%d modelli disponibili." % v["modelli"].size()
