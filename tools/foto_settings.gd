extends SceneTree

## RITRAE LE DUE SCHEDE DI IMPOSTAZIONI, e i dialoghi, in PNG.
##
## Serve perche' l'impaginazione non si giudica da un test: un pannello puo' costruirsi
## senza errori ed essere illeggibile. Era gia' successo — la scheda «Costi» e' arrivata a
## schermo senza che nessuno l'avesse guardata, e il giudizio di chi ci ha provato e'
## stato «completamente incomprensibile».
##
## Un tentativo precedente si piantava: girava con --headless, dove le Window non hanno un
## viewport da cui leggere. Qui si apre una finestra vera (serve un DISPLAY) e c'e' un
## contasecondi che chiude comunque, cosi' al peggio si perde uno scatto, non la sessione.
##
## Uso:  tools/godot/godot4 --path . --script res://tools/foto_settings.gd
##       (le immagini finiscono nella cartella dati utente, il percorso e' stampato)

const DOVE := "user://scatti"
const SECONDI_MASSIMI := 40.0

var _fin: Window
var _t0 := 0.0

func _init() -> void:
	_scatta.call_deferred()

func _process(_d: float) -> bool:
	# Rete di sicurezza: qualunque cosa succeda, non si resta appesi.
	if _t0 > 0.0 and (Time.get_ticks_msec() / 1000.0) - _t0 > SECONDI_MASSIMI:
		printerr("[!] tempo scaduto: chiudo")
		quit(1)
	return false

func _scatta() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOVE))

	# load() a runtime, non `FinestraImpostazioni.new()`: in modalita' --script gli autoload
	# non esistono ancora quando Godot compila le dipendenze dello script, e la finestra ne
	# nomina uno (LLMManager). Riferirla per nome la farebbe compilare troppo presto.
	var scena: GDScript = load("res://scenes/finestra_impostazioni.gd")
	_fin = scena.new()
	root.add_child(_fin)
	_fin.adegua_a_scala(1.0)
	_fin.popup_centered()
	await _riposa(8)

	var schede: TabContainer = _trova_tab(_fin)
	if schede == null:
		printerr("[!] nessun TabContainer: la finestra non si e' costruita")
		quit(1)
		return

	for i in schede.get_tab_count():
		schede.current_tab = i
		await _riposa(6)
		_png("scheda_%d_%s" % [i, schede.get_tab_title(i).to_lower()], _fin)

	# OpenRouter e' il caso che conta: e' il solo con la riga «Autore», ed e' quello con
	# oltre trecento modelli — cioe' quello in cui l'impaginazione poteva sfasciarsi.
	schede.current_tab = 0
	var llm := root.get_node("LLMManager")
	var idx: int = llm.indice_profilo("OpenRouter")
	if idx >= 0:
		_fin._opt_provider.select(idx)
		_fin._on_provider(idx)
		await _riposa(6)
		_png("scheda_0_openrouter", _fin)

	# Il «?» di una manopola: e' il dialogo che porta la spiegazione lunga.
	var chiave: String = Costi.descrittori().keys()[0]
	var d: Dictionary = Costi.descrittori()[chiave]
	_fin.mostra_aiuto(String(d.get("etichetta", chiave)), String(d.get("aiuto_lungo", "")))
	await _riposa(8)
	_png("dialogo_aiuto", _fin._dlg_aiuto)

	_fin._dlg_aiuto.hide()
	await _riposa(4)
	_fin._chiedi_nome_profilo()
	await _riposa(8)
	_png("dialogo_nuovo_profilo", _fin._dlg_nome)

	print("scatti in: ", ProjectSettings.globalize_path(DOVE))
	quit(0)

func _riposa(n: int) -> void:
	for i in n:
		await process_frame

## Una Window E' un viewport: si ritrae da se'. E' il motivo per cui headless non poteva
## funzionare — li' la Window non ne ha uno.
func _png(nome: String, w: Window) -> void:
	if w == null or not w.visible:
		printerr("[!] %s: finestra non visibile, salto" % nome)
		return
	var img := w.get_texture().get_image()
	var percorso := "%s/%s.png" % [DOVE, nome]
	img.save_png(percorso)
	print("  %s  (%dx%d)" % [percorso, img.get_width(), img.get_height()])

func _trova_tab(n: Node) -> TabContainer:
	for c in n.get_children():
		if c is TabContainer:
			return c
		var giu := _trova_tab(c)
		if giu != null:
			return giu
	return null
