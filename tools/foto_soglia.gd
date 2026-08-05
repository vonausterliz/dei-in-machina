extends SceneTree

## RITRAE LA SOGLIA COM'E' DAVVERO — dentro il gioco, non in laboratorio.
##
## `tools/foto_avvio.gd` ritrae il dialogo da solo: dice se il riquadro e' impaginato bene.
## Non dice la cosa che e' andata storta, che riguardava tutto il resto della schermata:
## l'apertura sfumava, sotto compariva una partita GIA' COMINCIATA — la voce di Omero, i tre
## appigli — e sopra il dialogo chiedeva ancora cosa fare. Si vedeva il gioco rispondere a una
## domanda non ancora posta, e «Comincia da Troia» dopo aver letto l'inizio di Troia non
## voleva piu' dire niente.
##
## Un difetto che sta nella RELAZIONE fra due cose si vede solo ritraendole insieme. Qui si
## avvia il gioco vero, si aspetta che la soglia compaia, e si fotografa tutto lo schermo.
##
## Uso:  tools/godot/godot4 --path . --script res://tools/foto_soglia.gd

const DOVE := "user://scatti"
const SECONDI_MASSIMI := 90.0

var _t0 := 0.0

func _init() -> void:
	_scatta.call_deferred()

func _process(_d: float) -> bool:
	if _t0 > 0.0 and (Time.get_ticks_msec() / 1000.0) - _t0 > SECONDI_MASSIMI:
		printerr("[!] tempo scaduto: la soglia non e' comparsa")
		quit(1)
	return false

func _scatta() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOVE))
	root.get_node("LLMManager").mock_mode = true

	# NON tipizzato: Main ha un campo `_input` che collide col metodo virtuale `Control._input`
	# (vedi tools/foto_gioco.gd). E NON si tocca `_niente_dialoghi`: qui la soglia la vogliamo.
	var ui = load("res://scenes/Main.tscn").instantiate()
	root.add_child(ui)

	# L'apertura dura qualche secondo e la soglia arriva alla sua fine. Invece di indovinare
	# un'attesa, si CHIEDE allo splash di finire subito: `congeda()` su un sipario trattenuto
	# non lo fa sparire — annuncia «pronto», che e' esattamente l'istante da ritrarre.
	for i in 40:
		await process_frame
	for c in ui.get_children():
		if c is Splash:
			c.congeda()
	for i in 40:
		await process_frame

	if ui._dlg_avvio == null:
		printerr("[!] la soglia non e' comparsa: non c'e' niente da ritrarre")
		quit(1)
		return

	# LA PROVA VERA, prima ancora dello scatto: dietro il dialogo non dev'esserci una partita.
	# Si guarda il pannello della narrazione — se contiene la voce di Omero, il gioco e'
	# partito senza che nessuno gliel'abbia chiesto.
	var narrato: String = ui._narrazione.get_parsed_text().strip_edges()
	var appigli := 0
	for n in ui.find_children("*", "Button", true, false):
		if String((n as Button).text).begins_with("›"):
			appigli += 1
	print("  dietro la soglia: %d caratteri di narrazione · %d appigli" % [narrato.length(), appigli])
	var guai: Array[String] = []
	if narrato.length() > 0:
		guai.append("la narrazione e' gia' scritta dietro la soglia: «%s…»" % narrato.substr(0, 60))
	if appigli > 0:
		guai.append("ci sono gia' %d appigli proposti dietro la soglia" % appigli)
	# E il sipario dev'essere ancora alzato: e' lui a coprire la schermata vuota.
	var sipario := false
	for c in ui.get_children():
		if c is Splash:
			sipario = true
	if not sipario:
		guai.append("il sipario e' gia' calato: si vede la schermata vuota sotto la soglia")

	_png("soglia_intera", ui.get_window())
	_png("soglia_dialogo", ui._dlg_avvio)

	# E DOPO LA SCELTA: la partita comincia, il sipario cala, la scena c'e'.
	ui._su_scelta_avvio(DialogoAvvio.NUOVA)
	for i in 60:
		await process_frame
	var dopo: String = ui._narrazione.get_parsed_text().strip_edges()
	print("  dopo «nuova partita»: %d caratteri di narrazione" % dopo.length())
	if dopo.length() == 0:
		guai.append("scelta «nuova partita», ma la scena non si e' aperta: schermata muta")
	if ui._dlg_avvio != null:
		guai.append("la soglia e' rimasta aperta dopo la scelta")
	_png("soglia_dopo_la_scelta", ui.get_window())

	if guai.is_empty():
		print("\n✓ dietro la soglia non c'e' nessuna partita, e dopo la scelta c'e'.")
		quit(0)
		return
	for g in guai:
		printerr("[!] %s" % g)
	quit(1)

func _png(nome: String, w: Window) -> void:
	if w == null or not w.visible:
		printerr("[!] %s: finestra non visibile, salto" % nome)
		return
	var img := w.get_texture().get_image()
	img.save_png("%s/%s.png" % [DOVE, nome])
	print("     → %s/%s.png  (%dx%d)" % [DOVE, nome, img.get_width(), img.get_height()])
