extends SceneTree

## Ricava le immagini fisse del marchio DALLO STESSO disegno della schermata d'apertura
## (scenes/splash.gd), invece di tenere in giro dei file da riallineare a mano:
##
##   assets/marchio.png -> immagine d'avvio del motore (al posto del logo di Godot)
##   assets/icona.png   -> icona dell'applicazione (la finestra e la barra di sistema)
##
## Il marchio vive in un posto solo. Se cambia il disegno, si rilancia questo e le
## immagini seguono.
##
## Serve uno schermo (il disegno va renderizzato davvero): NON usare --headless.
##   ./tools/godot/godot4 --path . --script res://tools/genera_marchio.gd

const CARTELLA := "res://assets"
## Istante in cui congelare l'animazione. 1.85s non e' casuale: nome e sottotitolo sono
## gia' comparsi del tutto, l'invito a premere un tasto non ancora — e in un'immagine
## d'avvio, dove non si preme nulla, quell'invito sarebbe una bugia.
const ISTANTE := 1.85

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARTELLA))
	await _scatta(Vector2i(1152, 648), false, "%s/marchio.png" % CARTELLA)
	await _scatta(Vector2i(512, 512), true, "%s/icona.png" % CARTELLA)   # senza scritte: l'istante non conta
	print("Marchio generato in %s" % CARTELLA)
	quit()

func _scatta(dim: Vector2i, solo_marchio: bool, dove: String) -> void:
	var vp := SubViewport.new()
	vp.size = dim
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)

	var s := Splash.new()
	s.solo_marchio = solo_marchio
	vp.add_child(s)
	await process_frame          # il layout si assesta
	s.fissa(ISTANTE)             # niente animazione: il marchio fermo, gia' comparso
	await process_frame
	await process_frame          # una seconda passata: il redraw dev'essere finito

	var img := vp.get_texture().get_image()
	var errore := img.save_png(ProjectSettings.globalize_path(dove))
	if errore != OK:
		push_error("Non riesco a scrivere %s (errore %d)" % [dove, errore])
	else:
		print("  %s  %dx%d" % [dove, dim.x, dim.y])
	vp.queue_free()
