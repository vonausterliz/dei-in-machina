extends SceneTree

## RITRAE LA SOGLIA — il dialogo fra il sipario e la prima mossa.
##
## E' testo dentro un riquadro a dimensione automatica, con un referto che cambia lunghezza
## a seconda di cosa c'e' da dire: o ci sta, o esce dal bordo. Un test che legge le stringhe
## direbbe di si' in entrambi i casi. Nella stessa settimana il dialogo dei guai e' uscito
## 255x1212 pixel e la pagina d'aiuto chiedeva 972 px su una finestra di 1033: sono difetti
## che si vedono solo guardando.
##
## Si ritraggono TRE casi, perche' sono tre impaginazioni diverse:
##   1. con una partita da riprendere e tutto a posto (il caso normale);
##   2. senza salvataggio (la voce «carica» c'e' lo stesso, spenta e col motivo: e' la riga
##      che cambia aspetto senza cambiare posto);
##   3. con audio muto e una chiave mancante (il referto si allunga, ed e' il caso in cui
##      serve di piu' che si legga).
##
## Uso:  tools/godot/godot4 --path . --script res://tools/foto_avvio.gd
##       (serve un DISPLAY: una Window headless non ha un viewport da cui leggere)

const DOVE := "user://scatti"

func _init() -> void:
	_scatta.call_deferred()

func _scatta() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOVE))
	Testi.usa()
	var serif: Font = load("res://fonts/Cardo-Regular.ttf")
	var grassetto: Font = load("res://fonts/Cardo-Bold.ttf")

	var casi := {
		"avvio_normale": {
			"ripresa": {"episodio": "L'isola del ciclope", "turno": 34, "quando": "2026-08-05 09:12"},
			"motore": "OpenRouter · deepseek/deepseek-v4-flash",
			"audio": "", "guai": [],
		},
		"avvio_prima_volta": {
			"ripresa": {},
			"motore": "Ollama locale · mistral-small3.2:latest",
			"audio": "", "guai": [],
		},
		"avvio_con_guai": {
			"ripresa": {"episodio": "Il paese dei Lotofagi", "turno": 7, "quando": "2026-08-04 22:40"},
			"motore": "Mistral · mistral-small-latest",
			"audio": Testi.s("avvio/audio_muto"),
			"guai": [Testi.s("motore/manca_chiave", ["Mistral"])],
		},
	}

	for nome in casi:
		var d := DialogoAvvio.new(casi[nome], serif, grassetto)
		root.add_child(d)
		d.popup_centered()
		for i in 20:
			await process_frame
		# QUANTO CHIEDE E QUANTO GLIENE DANNO. Se il minimo supera la finestra, qualcosa esce
		# dal bordo in basso — e in uno scatto si vede solo se lo si cerca. Meglio dirlo.
		var minimo := Vector2.ZERO
		for c in d.get_children():
			if c is Control:
				minimo = minimo.max((c as Control).get_combined_minimum_size())
		print("  %-20s finestra %dx%d · contenuto minimo %.0fx%.0f%s" % [
			nome, d.size.x, d.size.y, minimo.x, minimo.y,
			"   [!] IL CONTENUTO NON CI STA" if minimo.y > d.size.y else ""])
		_png(nome, d)
		d.hide()
		d.queue_free()
		await process_frame
	quit(0)

func _png(nome: String, w: Window) -> void:
	if w == null or not w.visible:
		printerr("[!] %s: finestra non visibile, salto" % nome)
		return
	var img := w.get_texture().get_image()
	img.save_png("%s/%s.png" % [DOVE, nome])
	print("     → %s/%s.png  (%dx%d)" % [DOVE, nome, img.get_width(), img.get_height()])
