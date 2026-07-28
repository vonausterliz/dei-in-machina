extends SceneTree

## Dumper di traccia headless — "vista Olimpo" da riga di comando (CLAUDE.md, punto 4).
## Stampa in forma leggibile lo storico_olimpo di uno stato di partita ESISTENTE
## (default: l'esempio in data/stato_partita.json). Per eseguire turni dal vivo col
## mock e vederli stampati, usa invece tools/trace_dumper/run_turns.gd.
## Uso: tools/godot/godot4 --headless --path . --script res://tools/trace_dumper/dump_trace.gd [-- percorso_stato]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://data/stato_partita.json"
	var stato := StatoPartita.carica(path)
	if stato == null:
		printerr("dump_trace: impossibile caricare lo stato da %s" % path)
		quit(1)
		return
	print(TraceFormatter.intestazione(stato))
	print("")
	if stato.storico_olimpo.is_empty():
		print("(storico_olimpo vuoto: nessun turno da mostrare)")
	else:
		for voce in stato.storico_olimpo:
			print(TraceFormatter.turno(voce))
			print("")
	quit(0)
