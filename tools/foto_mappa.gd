extends SceneTree

## Ritrae la sola carta del viaggio in un PNG, per poterla GUARDARE senza avviare il gioco
## (che col motore simulato non lascia giocare). Una carta si giudica a occhio, non a test.
## Uso: tools/godot/godot4 --path . --script res://tools/foto_mappa.gd

func _init() -> void:
	_scatta.call_deferred()

func _scatta() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 620)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var m := MappaViaggio.new()
	m.size = Vector2(900, 620)
	m.custom_minimum_size = m.size
	vp.add_child(m)

	var gm := root.get_node("GameManager")
	gm.nuova_partita(7)
	gm.vai_a_tappa("circe")
	var punti: Array = []
	for id in gm.episodi.ordine():
		var ep: Episodio = gm.episodi.get_episodio(id)
		punti.append({"id": id, "nome": ep.nome, "pos": ep.mappa})
	m.imposta(punti, "circe", ["troia", "ciconi", "lotofagi", "ciclope", "eolo", "laestrigoni"])

	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	img.save_png("user://mappa.png")
	print("scritta in: ", ProjectSettings.globalize_path("user://mappa.png"))
	quit(0)
