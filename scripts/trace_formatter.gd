class_name TraceFormatter
extends RefCounted

## Formattazione condivisa della "vista Olimpo" testuale (una voce di storico_olimpo).
## Usata sia dal dumper di uno stato salvato (dump_trace) sia dal driver che esegue
## N turni col mock (run_turns): un solo formato, un solo posto da mantenere.

static func intestazione(stato: StatoPartita) -> String:
	var righe: Array[String] = []
	righe.append("=== Vista Olimpo — %s (seed %d) ===" % [stato.run_id, stato.seed_partita])
	righe.append("Turno corrente: %d | stato: %s | esito: %s" % [stato.turno, stato.stato, str(stato.esito)])
	return "\n".join(righe)

static func turno(voce: Dictionary) -> String:
	var r: Array[String] = []
	r.append("--- Turno %s ---" % _numero(voce.get("turno", "?")))
	r.append("Input:      %s" % voce.get("input", ""))

	var envelope: Dictionary = voce.get("envelope", {})
	r.append("Envelope:   plausibilita=%s tipo=%s tag=%s tono=%s intensita=%s" % [
		envelope.get("plausibilita", "?"), envelope.get("tipo", "?"),
		envelope.get("tag", []), envelope.get("tono", "?"), _numero(envelope.get("intensita", "?")),
	])

	var svegli: Array = voce.get("svegli", [])
	r.append("Svegli:     %s" % (", ".join(svegli) if not svegli.is_empty() else "(nessuno)"))

	var eventi: Array = voce.get("eventi_emessi", [])
	if not eventi.is_empty():
		r.append("Eventi:     %s" % ", ".join(eventi))

	var delib: Array = voce.get("deliberazione", [])
	if not delib.is_empty():
		r.append("Deliberazione:")
		for battuta in delib:
			var chi: String = battuta.get("dio", "?")
			var testo: String = battuta.get("dice", "")
			var esito: String = battuta.get("registro", battuta.get("proposta", battuta.get("verdetto", "")))
			r.append("  %-12s %s  [%s]" % [chi + ":", testo, esito])

	var verdetto: Dictionary = voce.get("verdetto", {})
	if not verdetto.is_empty():
		r.append("Verdetto:   %s -> %s" % [verdetto.get("attore", "?"), verdetto.get("registro", "?")])

	var scav: Dictionary = voce.get("scavalcamento", {})
	if not scav.is_empty():
		r.append("Scavalcamento: %s — %s" % [scav.get("colpevole", "?"), scav.get("cosa", "")])

	var delta: Dictionary = voce.get("delta", {})
	if not delta.is_empty():
		r.append("Delta:      %s" % delta)

	var narrazione: String = voce.get("narrazione_omero", "")
	if narrazione != "":
		r.append("Omero:      \"%s\"" % narrazione)

	return "\n".join(r)

## JSON non distingue int/float: un intero "pulito" (12.0) si stampa come "12".
static func _numero(valore: Variant) -> String:
	if typeof(valore) == TYPE_FLOAT and float(valore) == floor(valore):
		return str(int(valore))
	return str(valore)
