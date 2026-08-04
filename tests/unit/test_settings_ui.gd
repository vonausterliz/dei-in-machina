extends GutTest

## LA FINESTRA DELLE IMPOSTAZIONI, guardata da vicino.
##
## Un pannello puo' costruirsi senza un errore ed essere inservibile: la scheda «Costi» e'
## arrivata a schermo cosi', e il giudizio e' stato «completamente incomprensibile». Questi
## test coprono cio' che si puo' provare senza occhi — che i comandi ci siano, che la
## cascata autore/modello si riempia, che il testo di aiuto esista per ogni manopola.
## Per l'impaginazione vera c'e' tools/foto_settings.gd, che ne fa il ritratto.

var _idx_prima := 0
var _modelli_prima: Array = []

func before_each():
	LLMManager.mock_mode = true
	LLMManager.usa_gateway = false
	_idx_prima = LLMManager.profilo_idx
	_modelli_prima = []
	for p in LLMManager.profili:
		_modelli_prima.append(String(p.get("model", "")))

func after_each():
	for i in LLMManager.profili.size():
		LLMManager.profili[i]["model"] = _modelli_prima[i]
	LLMManager.profilo_idx = _idx_prima

func _apri() -> Window:
	var f: Window = load("res://scenes/finestra_impostazioni.gd").new()
	add_child_autofree(f)
	await wait_frames(2)
	return f

func _scegli(f: Window, nome: String) -> void:
	var i := LLMManager.indice_profilo(nome)
	assert_gte(i, 0, "serve il provider «%s»" % nome)
	f._opt_provider.select(i)
	f._on_provider(i)

# --- La cascata autore → modello ---

## Con OpenRouter l'elenco e' di oltre trecento voci: un menu piatto e' un muro.
func test_con_openrouter_compare_l_autore():
	var f := await _apri()
	_scegli(f, "OpenRouter")
	assert_true(f._riga_autore.visible, "i nomi sono «autore/modello»: l'autore si sceglie")
	assert_gt(f._opt_autore.item_count, 0)
	assert_gt(f._opt_modello.item_count, 0)
	for i in f._opt_modello.item_count:
		assert_string_contains(f._opt_modello.get_item_text(i), f._autore_scelto() + "/")

## Su un provider a nome semplice la riga non deve comparire vuota o con un autore inventato.
func test_su_un_provider_a_nome_semplice_l_autore_sparisce():
	var f := await _apri()
	_scegli(f, "Mistral")
	assert_false(f._riga_autore.visible)
	assert_gt(f._opt_modello.item_count, 0)

func test_cambiare_autore_cambia_i_modelli_offerti():
	var f := await _apri()
	_scegli(f, "OpenRouter")
	if f._opt_autore.item_count < 2:
		fail_test("i modelli curati di OpenRouter devono coprire piu' di un autore")
		return
	# Un autore DIVERSO da quello gia' scelto: all'apertura il menu si posiziona sull'autore
	# del modello corrente, quindi «prendi l'indice 1» a volte non cambiava niente.
	var primo: String = f._opt_modello.get_item_text(0)
	var altro := 1 if f._opt_autore.selected == 0 else 0
	f._opt_autore.select(altro)
	f._on_autore(altro)
	assert_ne(f._opt_modello.get_item_text(0), primo)
	# E la scelta dev'essere ARRIVATA al gioco: un menu che mostra un modello mentre il
	# gioco ne usa un altro e' il difetto peggiore di tutti, perche' non si vede.
	assert_eq(LLMManager.modello_del_profilo(), f._opt_modello.get_item_text(f._opt_modello.selected))

## Il caso in cui la scelta «tornava indietro da sola»: a motore spento finiva nel profilo
## di Ollama, e il menu si risincronizzava da quello vero, rimasto invariato.
func test_scegliere_un_modello_resta_scelto_dopo_un_risincronismo():
	var f := await _apri()
	_scegli(f, "OpenRouter")
	var voluto: String = f._opt_modello.get_item_text(f._opt_modello.item_count - 1)
	LLMManager.ricorda_modello(voluto)
	f._sincronizza_modello()
	assert_eq(f._opt_modello.get_item_text(f._opt_modello.selected), voluto)

## Ollama e' un provider come gli altri: dev'essere nel menu, e senza chiedere chiavi.
func test_ollama_si_sceglie_dal_menu_dei_provider():
	var f := await _apri()
	var nomi: Array = []
	for i in f._opt_provider.item_count:
		nomi.append(f._opt_provider.get_item_text(i))
	assert_has(nomi, "Ollama locale")
	_scegli(f, "Ollama locale")
	assert_gt(f._opt_modello.item_count, 0, "i modelli locali devono essere scegliibili")
	assert_true(f._chk_gateway.disabled, "davanti a un server in casa la coda non serve")

func test_lo_stato_della_chiave_si_vede_accanto_al_provider():
	var f := await _apri()
	_scegli(f, "Ollama locale")
	var locale: String = f._stato_chiave.text
	_scegli(f, "Anthropic")
	assert_ne(f._stato_chiave.text, locale,
		"un provider che vuole una chiave non puo' dire la stessa cosa di uno che non la vuole")

## Le chiavi API si chiedono solo a chi ne ha una, e col nome del provider accanto:
## «OPENROUTER_API_KEY» da solo non dice a chi serve.
func test_i_campi_chiave_sono_uno_per_provider_remoto():
	var f := await _apri()
	var attesi: Array = []
	for p in LLMManager.profili:
		var env := String(p.get("api_key_env", ""))
		if env != "" and not attesi.has(env):
			attesi.append(env)
	assert_eq(f._campi_chiave.keys().size(), attesi.size())
	for env in attesi:
		assert_true(f._campi_chiave.has(env), "manca il campo per %s" % env)

# --- La scheda dei costi ---

## Se una spiegazione non sta in una riga non si accorcia: si mette nel «?». Ma allora il
## «?» dev'esserci per tutti, o l'utente impara a non cercarlo.
func test_ogni_manopola_ha_etichetta_riga_di_aiuto_e_spiegazione_lunga():
	for chiave in Costi.descrittori():
		var d: Dictionary = Costi.descrittori()[chiave]
		for campo in ["etichetta", "aiuto", "aiuto_lungo"]:
			assert_false(String(d.get(campo, "")).strip_edges().is_empty(),
				"%s non ha «%s»" % [chiave, campo])
		assert_gt(String(d["aiuto_lungo"]).length(), 200,
			"«%s»: se la spiegazione lunga e' corta come quella corta, non serve" % chiave)

## I testi rivolti a chi gioca vanno in italiano vero. Nei commenti del codice si scrive
## «e'» per non litigare con gli editor; a schermo e' una crepa piccola e visibilissima.
func test_i_testi_dei_costi_usano_gli_accenti_veri():
	var sbagliati: Array = []
	for chiave in Costi.descrittori():
		var d: Dictionary = Costi.descrittori()[chiave]
		for campo in ["etichetta", "aiuto", "aiuto_lungo"]:
			for brutto in [" e' ", "piu'", "puo'", "perche'", "cosi'", "gia'", "c'e'"]:
				if String(d[campo]).contains(brutto):
					sbagliati.append("%s/%s: «%s»" % [chiave, campo, brutto])
	assert_eq(sbagliati, [])

func test_il_pannello_costruisce_una_riga_per_ogni_manopola():
	var f := await _apri()
	var trovate := 0
	for c in f._costi_box.get_children():
		if c is VBoxContainer:
			trovate += 1
	assert_eq(trovate, Costi.descrittori().size())

## Cancellare: si deve poter fare su un profilo proprio, mai sui due predefiniti.
func test_il_bottone_cancella_e_spento_sui_predefiniti_e_acceso_sui_propri():
	var attivo_prima := Costi.attivo()
	var f := await _apri()
	Costi.usa("frugale")
	f._ridisegna_costi()
	assert_true(_bottone(f, Testi.s("impostazioni/cancella_profilo")).disabled,
		"il Frugale e' il riferimento della taratura: non si cancella")

	var id := Costi.crea("Provvisorio", "frugale")
	Costi.usa(id)
	f._ridisegna_costi()
	var togli := _bottone(f, Testi.s("impostazioni/cancella_profilo"))
	assert_false(togli.disabled, "un profilo mio devo poterlo cancellare")

	Costi.cancella(id)
	f._ridisegna_costi()
	assert_eq(Costi.attivo(), "frugale", "cancellato l'attivo si torna al prudente")
	Costi.usa(attivo_prima)

func _bottone(n: Node, testo: String) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).text == testo:
			return c
		var giu := _bottone(c, testo)
		if giu != null:
			return giu
	return null

# --- I dialoghi ---

## Un AcceptDialog e' una FINESTRA A SE': non eredita il content_scale_factor del genitore.
## Con l'interfaccia al 150% usciva grande come un francobollo, col bottone OK illeggibile.
func test_i_dialoghi_prendono_la_scala_della_finestra():
	var f := await _apri()
	f.adegua_a_scala(1.5)
	f.mostra_aiuto("Titolo", "Un testo di prova abbastanza lungo da riempire il riquadro.")
	assert_almost_eq(f._dlg_aiuto.content_scale_factor, 1.5, 0.01)
	assert_gt(f._dlg_aiuto.size.x, 700, "la finestra va ingrandita quanto il suo contenuto")
	f._dlg_aiuto.hide()

func test_il_dialogo_del_nuovo_profilo_ha_i_bottoni_in_italiano():
	var f := await _apri()
	f._chiedi_nome_profilo()
	assert_eq(f._dlg_nome.cancel_button_text, Testi.s("finestre/annulla"))
	assert_eq(f._dlg_nome.ok_button_text, Testi.s("finestre/crea"))
	assert_gt(f._dlg_nome.size.y, 180, "ci devono stare la spiegazione, il campo e i bottoni")
	f._dlg_nome.hide()
