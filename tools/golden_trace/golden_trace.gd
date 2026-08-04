extends SceneTree

## IL GOLDEN TRACE, da riga di comando (CLAUDE.md, mandato punto 5).
##
## Esegue il copione canonico col mock e confronta tutto cio' che ne esce con la traccia
## registrata. Serve a vedere le ASSENZE: una riga che non c'e' piu' non fa fallire nessun
## test, ma qui salta fuori come «SPARITO».
##
## Uso:
##   …--script res://tools/golden_trace/golden_trace.gd              confronta (esce 1 se cambia)
##   …--script res://tools/golden_trace/golden_trace.gd -- aggiorna  ri-registra la traccia
##
## La logica sta in scripts/traccia_canonica.gd, cosi' questo strumento e il test della
## suite guardano esattamente la stessa cosa.

func _init() -> void:
	_esegui.call_deferred()

func _esegui() -> void:
	var aggiorna := OS.get_cmdline_user_args().has("aggiorna")
	var gm: Node = root.get_node("GameManager")
	var llm: Node = root.get_node("LLMManager")

	print("\n=== Golden trace — %d turni canonici, mock, seed %d ===\n" % [
		TracciaCanonica.COPIONE.size(), TracciaCanonica.SEED])
	var ottenuta: Dictionary = await TracciaCanonica.registra(gm, llm)

	if aggiorna:
		if not TracciaCanonica.salva(ottenuta):
			printerr("[!] non riesco a scrivere %s" % TracciaCanonica.PERCORSO)
			quit(2)
			return
		print("Traccia registrata in %s (%d turni)." % [
			TracciaCanonica.PERCORSO, ottenuta["turni"].size()])
		print("Rileggi la differenza in git PRIMA di committarla: e' l'unico momento in cui")
		print("un cambiamento involontario si puo' ancora vedere.")
		quit(0)
		return

	var attesa := TracciaCanonica.attesa()
	if attesa.is_empty():
		printerr("[!] nessuna traccia registrata in %s." % TracciaCanonica.PERCORSO)
		printerr("    Registrala con:  … --script res://tools/golden_trace/golden_trace.gd -- aggiorna")
		quit(2)
		return

	var differenze := TracciaCanonica.confronta(attesa, ottenuta)
	if differenze.is_empty():
		print("Identica alla traccia registrata: %d turni, nessuna differenza." % ottenuta["turni"].size())
		_riassunto(ottenuta)
		quit(0)
		return

	printerr("[!] LA TRACCIA E' CAMBIATA — %d differenze:\n" % differenze.size())
	for d in differenze:
		printerr("  · %s" % d)
	printerr("\nSe il cambiamento e' voluto, rileggilo riga per riga e poi:")
	printerr("  … --script res://tools/golden_trace/golden_trace.gd -- aggiorna")
	quit(1)

## Due righe per capire che la traccia esercita ancora qualcosa, invece di essere diventata
## una fila di turni vuoti tutti uguali — un golden trace che non tocca niente resta verde
## per sempre e non protegge piu' nulla.
func _riassunto(t: Dictionary) -> void:
	var con_dei := 0
	var narrate := 0
	for turno in t["turni"]:
		if not (turno["svegliati"] as Array).is_empty():
			con_dei += 1
		if String(turno["narrazione"]).strip_edges() != "":
			narrate += 1
	print("  turni con almeno un dio sveglio: %d/%d · turni narrati: %d/%d · esito: %s" % [
		con_dei, t["turni"].size(), narrate, t["turni"].size(),
		String(t["finale"]["stato_partita"])])
