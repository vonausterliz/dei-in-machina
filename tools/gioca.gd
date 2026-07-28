extends SceneTree

## Console interattiva — la prima forma GIOCABILE di Dei in machina.
## Scrivi cosa fa e dice Ulisse; Omero narra le conseguenze. Gli dei restano nascosti:
## per sbirciare dietro le quinte c'e' il comando :olimpo (la vista da sviluppatore).
##
## Uso:
##   mock (istantaneo, deterministico):  tools/godot/godot4 --headless --path . --script res://tools/gioca.gd
##   Ollama (dei e narratore reali):     ... --script res://tools/gioca.gd -- ollama
##
## Comandi durante il gioco:
##   :olimpo   mostra/nasconde la vista Olimpo (debug: envelope, dei svegli, delta)
##   :stato    stat correnti di Ulisse
##   :esci     termina

const SEED := 4815162342

var _gm: Node
var _llm: Node
var _mostra_olimpo := false

func _init() -> void:
	_gioca.call_deferred()

func _gioca() -> void:
	_llm = root.get_node("LLMManager")
	_gm = root.get_node("GameManager")

	var args := OS.get_cmdline_user_args()
	var usa_ollama := args.has("ollama")
	if usa_ollama:
		_llm.abilita_reale()
		# Override opzionale del modello: "-- ollama <model>".
		for a in args:
			if a != "ollama":
				_llm._client.model = a
		print("[modalita' Ollama (%s): dei e narratore reali — puo' essere lento]" % _llm._client.model)
		if not await _llm._client.disponibile():
			printerr("Ollama non raggiungibile. Avvia `ollama serve` o usa la modalita' mock.")
			quit(1)
			return
	else:
		_llm.mock_mode = true
		print("[modalita' mock: deterministica e istantanea]")

	_gm.nuova_partita(SEED)
	_intro()

	while true:
		printraw("\n> ")
		var riga := OS.read_string_from_stdin().strip_edges()
		if riga == "":
			continue
		if riga == ":esci" or riga == ":quit":
			break
		if riga == ":olimpo":
			_mostra_olimpo = not _mostra_olimpo
			print("[vista Olimpo: %s]" % ("ON" if _mostra_olimpo else "OFF"))
			continue
		if riga == ":stato":
			_stampa_stato()
			continue

		var esito: Dictionary = await _gm.esegui_turno(riga)
		_stampa_turno(esito)
		if esito.get("avanzato", false) and esito["esito"] == "continua":
			print("\n~ %s ~\nOmero: %s" % [_gm.stato.viaggio["corrente"], esito.get("intro", "")])
		if esito["esito"] != "continua":
			if esito["esito"] == "itaca":
				print("\n=== VITTORIA: sei tornato a Itaca. ===")
			else:
				print("\n=== FINE: %s ===" % esito["esito"])
			break

	print("\nAddio, Ulisse.")
	quit(0)

func _intro() -> void:
	print("\n============================================================")
	print(" DEI IN MACHINA — sei Ulisse. Scrivi cosa fai e dici.")
	print(" Gli dei ti osservano, ma non li vedrai. Deducili.")
	print(" Comandi: :olimpo  :stato  :esci")
	print("============================================================")
	print("\nOmero: %s\nCosa fai?" % _gm.intro_corrente())

func _stampa_turno(esito: Dictionary) -> void:
	var voce: Dictionary = esito["voce"]
	# Parte rivolta al giocatore: solo Omero. Gli dei restano nascosti.
	print("\nOmero: %s" % voce.get("narrazione_omero", ""))
	# Vista Olimpo (debug), solo se richiesta.
	if _mostra_olimpo:
		print("\n" + TraceFormatter.turno(voce))

func _stampa_stato() -> void:
	var st: Dictionary = _gm.stato.ulisse["stat"]
	print("[Ulisse] animo=%d  metis=%d  hybris=%d  ciurma=%d/%d" % [
		st["animo"], st["metis"], _gm.stato.ulisse["hybris"],
		st["ciurma"]["vivi"], st["ciurma"]["iniziali"]])
