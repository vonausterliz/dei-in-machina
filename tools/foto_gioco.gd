extends SceneTree

## Ritrae la schermata di gioco, per guardarla senza doverci giocare (col motore simulato
## il gioco si blocca apposta). Compagno di tools/foto_settings.gd.
##
## Uso:  tools/godot/godot4 --path . --script res://tools/foto_gioco.gd
##       (serve un DISPLAY: una Window headless non ha un viewport da cui leggere)

const DOVE := "user://scatti"
const SECONDI_MASSIMI := 40.0

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

	var ui: Node = load("res://scenes/Main.tscn").instantiate()
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

	var img := root.get_texture().get_image()
	var percorso := "%s/gioco.png" % DOVE
	img.save_png(percorso)
	print("  %s  (%dx%d)" % [percorso, img.get_width(), img.get_height()])
	quit(0)
