extends SceneTree

## Dumper di traccia headless — "vista Olimpo" da riga di comando (CLAUDE.md, punto 4).
## Fase 0: scheletro. Stampa in forma leggibile lo storico_olimpo di uno stato di
## partita esistente (default: l'esempio in data/stato_partita.json). Quando la
## macchina del turno (fase 2+) esistera' davvero, questo stesso formattatore
## rendera' leggibili N turni giocati col mock — e' il primo occhio sul sistema.
## Uso: tools/godot/godot4 --headless --script res://tools/trace_dumper/dump_trace.gd [-- percorso_stato]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://data/stato_partita.json"
	var stato := StatoPartita.carica(path)
	if stato == null:
		printerr("dump_trace: impossibile caricare lo stato da %s" % path)
		quit(1)
		return
	_stampa_intestazione(stato)
	if stato.storico_olimpo.is_empty():
		print("(storico_olimpo vuoto: nessun turno da mostrare)")
	else:
		for voce in stato.storico_olimpo:
			_stampa_turno(voce)
	quit(0)

func _stampa_intestazione(stato: StatoPartita) -> void:
	print("=== Vista Olimpo — %s (seed %d) ===" % [stato.run_id, stato.seed_partita])
	print("Turno corrente: %d | stato: %s | esito: %s" % [stato.turno, stato.stato, str(stato.esito)])
	print("")

func _stampa_turno(voce: Dictionary) -> void:
	var turno := _numero_leggibile(voce.get("turno", "?"))
	print("--- Turno %s ---" % turno)
	print("Input:      %s" % voce.get("input", ""))

	var envelope: Dictionary = voce.get("envelope", {})
	var intensita := _numero_leggibile(envelope.get("intensita", "?"))
	print("Envelope:   plausibilita=%s tipo=%s tag=%s tono=%s intensita=%s" % [
		envelope.get("plausibilita", "?"), envelope.get("tipo", "?"),
		envelope.get("tag", []), envelope.get("tono", "?"), intensita,
	])

	var svegli: Array = voce.get("svegli", [])
	if not svegli.is_empty():
		print("Svegli:     %s" % ", ".join(svegli))

	var eventi: Array = voce.get("eventi_emessi", [])
	if not eventi.is_empty():
		print("Eventi:     %s" % ", ".join(eventi))

	var delib: Array = voce.get("deliberazione", [])
	if not delib.is_empty():
		print("Deliberazione:")
		for battuta in delib:
			var chi: String = battuta.get("dio", "?")
			var testo: String = battuta.get("dice", "")
			var esito: String = battuta.get("proposta", battuta.get("verdetto", ""))
			print("  %-12s %s  [%s]" % [chi + ":", testo, esito])

	var scav: Dictionary = voce.get("scavalcamento", {})
	if not scav.is_empty():
		print("Scavalcamento: %s — %s" % [scav.get("colpevole", "?"), scav.get("cosa", "")])

	var delta: Dictionary = voce.get("delta", {})
	if not delta.is_empty():
		print("Delta:      %s" % delta)

	var narrazione: String = voce.get("narrazione_omero", "")
	if narrazione != "":
		print("Omero:      \"%s\"" % narrazione)

	print("")

## JSON non distingue int/float: un intero "pulito" (12.0) si stampa come "12".
func _numero_leggibile(valore) -> String:
	if typeof(valore) == TYPE_FLOAT and float(valore) == floor(valore):
		return str(int(valore))
	return str(valore)
