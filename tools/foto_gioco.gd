extends SceneTree

## Ritrae la schermata di gioco, per guardarla senza doverci giocare (col motore simulato
## il gioco si blocca apposta). Compagno di tools/foto_settings.gd.
##
## Uso:  tools/godot/godot4 --path . --script res://tools/foto_gioco.gd
##       (serve un DISPLAY: una Window headless non ha un viewport da cui leggere)

const DOVE := "user://scatti"
const SECONDI_MASSIMI := 120.0

var _t0 := 0.0

func _init() -> void:
	_scatta.call_deferred()

func _process(_d: float) -> bool:
	if _t0 > 0.0 and (Time.get_ticks_msec() / 1000.0) - _t0 > SECONDI_MASSIMI:
		printerr("[!] tempo scaduto")
		quit(1)
	return false

func _scatta() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOVE))
	root.get_node("LLMManager").mock_mode = true

	# NON tipizzato `: Node`. Main ha un campo `_input` (la riga di comando del giocatore) che
	# ha lo stesso nome del metodo virtuale `Control._input`: con la variabile tipizzata il
	# compilatore risolve il METODO e lo script non compila. Senza tipo la risoluzione avviene
	# a runtime e trova il campo. (Il nome andrebbe cambiato, ma non da qui.)
	var ui = load("res://scenes/Main.tscn").instantiate()
	root.add_child(ui)
	for i in 30:
		await process_frame

	# Lo splash aspetta un tasto: senza questo si ritrae il frontespizio, non il gioco.
	var tasto := InputEventKey.new()
	tasto.keycode = KEY_SPACE
	tasto.pressed = true
	Input.parse_input_event(tasto)
	for i in 40:
		await process_frame

	_png("gioco", root)

	# LA VISTA OLIMPO, DOPO QUALCHE TURNO. Vuota non dice niente, ed e' vuota all'avvio:
	# per settimane e' rimasta a schermo una riga di servizio («Nessuno si oppone: la
	# volonta' di X passa») che nessuno strumento guardava, perche' nessuno strumento
	# arrivava fin qui. Si gioca qualche turno col mock e si ritrae la chat che ne esce.
	# Il mock si riafferma QUI: la scena, avviandosi, rilegge le impostazioni dell'utente e
	# se trovasse il motore vero acceso partirebbe a chiamare la rete — e uno scatto
	# diventerebbe un'attesa di minuti a ogni turno.
	var llm: Node = root.get_node("LLMManager")
	llm.mock_mode = true
	var gm: Node = root.get_node("GameManager")
	# I turni si giocano su GameManager e POI si aggiorna la vista. Non da `_on_agisci`:
	# col motore simulato e una finestra aperta il gioco si blocca apposta (e ha ragione —
	# lo scatto precedente mostrava proprio l'avviso «nessun motore attivo»). Lo strumento
	# non deve scavalcare quella guardia: la aggira dal modello, che e' dove sta la verita'.
	gm.vai_a_tappa("ciclope")   # dove gli dei hanno qualcosa da dirsi
	for battuta in COPIONE:
		# Il mock si riafferma a OGNI giro: la scena, avviandosi, riaccende il motore vero
		# salvato nelle preferenze, e lo fa in una coroutine che finisce quando le pare. Senza
		# questa riga i turni partivano verso Ollama e la chat restava vuota nello scatto.
		llm.mock_mode = true
		print("  … turno: %s" % battuta)
		await gm.esegui_turno(battuta)
	print("  olimpo: %d caratteri di conversazione" %
		gm.agora.trascrizione(Agora.VISTA_OLIMPO).length())
	ui._aggiorna_olimpo()
	ui._aggiorna_ciurma()
	ui._aggiorna_stats()
	ui._aggiorna_mappa()
	# Le chat ora sono NELLA pagina: lo scatto del gioco le contiene gia'. Resta da guardare
	# la lente, che e' l'unica parte che non si vede senza premere qualcosa.
	# Quanto chiede la pagina e quanto ce n'e': se il primo supera il secondo qualcosa esce
	# dal bordo in basso, e in uno scatto si vede solo se lo si cerca.
	# Il viewport si ritrae com'era all'ULTIMO frame disegnato: senza aspettare, lo scatto
	# mostra la pagina di prima degli aggiornamenti. E' costato tre scatti in cui la chat
	# risultava vuota mentre Agora aveva gia' duemila caratteri dentro.
	for i in 20:
		await process_frame

	var pagina: Control = null
	for c in ui.get_children():
		if c is MarginContainer:
			pagina = c.get_child(0)
			break
	print("  pagina: minimo %.0f · finestra %.0f (scala %.2f)" % [
		pagina.get_combined_minimum_size().y, ui.size.y, ui.get_window().content_scale_factor])
	for c in pagina.get_children():
		print("     %-18s min %.0f  alto %.0f" % [c.get_class(),
			c.get_combined_minimum_size().y, c.size.y])
		if c is HBoxContainer and c.get_child_count() == 2:
			for col in c.get_children():
				print("        colonna %-16s min %.0f" % [col.get_class(),
					col.get_combined_minimum_size().y])
				for r in col.get_children():
					print("           %-22s min %.0f" % [r.get_class(),
						r.get_combined_minimum_size().y])
	# MESSA IN POSA per lo scatto del README. Col motore simulato il gioco si blocca apposta
	# e il campo d'azione mostra una barra rossa: e' il comportamento giusto, ma in una
	# vetrina racconta una bugia — chi gioca davvero ha un motore acceso. Qui si rimette
	# l'aspetto del caso normale, senza toccare la regola (che resta quella di sempre).
	ui._input.editable = true
	ui._input.placeholder_text = Testi.s("gioco/placeholder")
	ui._btn_agisci.disabled = false
	for i in 6:
		await process_frame
	_png("gioco_giocato", root)
	ui._ingrandisci_olimpo()
	for i in 20:
		await process_frame
	_png("lente_olimpo", root)
	ui._lente.chiudi()
	ui._ingrandisci_mappa()
	for i in 20:
		await process_frame
	_png("lente_mappa", root)
	ui._lente.chiudi()

	# LA FINESTRA DEL GUAIO. E' l'unica cosa che interrompe il gioco, e da quando i problemi
	# del motore non si scrivono piu' in narrazione e' anche l'unico posto in cui si vedono:
	# se esce storta, il giocatore resta senza spiegazione. Un test puo' dire che il testo e'
	# quello giusto e che il bottone c'e'; non puo' dire se si legge.
	ui._guaio_motore(Testi.s("motore/non_risponde", [
		"Mistral", "HTTP 401 · no api key provided", Testi.s("motore/aiuto_esterno")]))
	for i in 20:
		await process_frame
	_png("guaio_motore", ui._dlg_guaio)
	ui._dlg_guaio.hide()

	# LE PAGINE D'AIUTO. Sono testo lungo dentro un riquadro a dimensione fissa: o ci sta, o
	# esce dal bordo — e un test che legge `dialog_text` direbbe di si' in entrambi i casi.
	#
	# Le costanti si leggono DALL'ISTANZA (`ui.VOCE_REGOLE`), mai da `Main.VOCE_REGOLE`.
	# Nominare la classe qui e' una dipendenza di COMPILAZIONE: obbliga `main.gd` a compilare
	# quando questo file viene caricato, e in modalita' `--script` gli autoload non sono
	# ancora identificatori globali — `LLMManager` non esiste, main.gd non compila, e lo
	# strumento prosegue su una scena a meta' facendo scatti di una partita mai iniziata.
	# E' la stessa ragione per cui `ui` qui sopra non e' tipizzato.
	for voce in [ui.VOCE_REGOLE, ui.VOCE_FAQ]:
		ui._on_menu_aiuto(voce)
		for i in 20:
			await process_frame
		_png("aiuto_%d" % voce, ui._dlg_aiuto)
	ui._dlg_aiuto.hide()
	quit(0)

## Input scelti per SVEGLIARE qualcuno: una chat degli dei senza dei e' una finestra vuota.
## Il vanto al ciclope tira in ballo Poseidone, l'astuzia Atena, la supplica Zeus.
const COPIONE := [
	"Dico al gigante che il mio nome e' Nessuno.",
	"Sono io, Odisseo, che t'ho accecato!",
	"Mi rivolgo al capo dell'olimpo e lo supplico.",
	"Offro una libagione e chiedo perdono al mare.",
]

func _png(nome: String, w: Window) -> void:
	if w == null or not w.visible:
		printerr("[!] %s: finestra non visibile, salto" % nome)
		return
	var img := w.get_texture().get_image()
	var percorso := "%s/%s.png" % [DOVE, nome]
	img.save_png(percorso)
	print("  %s  (%dx%d)" % [percorso, img.get_width(), img.get_height()])
