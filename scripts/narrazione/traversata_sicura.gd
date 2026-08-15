class_name TraversataSicura
extends RefCounted

## Fallback deterministico per un passaggio respinto dal validatore narrativo.
##
## Non avanza la partita e non sceglie la prossima tappa: rende soltanto in prosa la rotta
## gia' fissata nel quadro. In questo modo `Viaggio` resta l'unica autorita' sull'ordine,
## sulla pressione e sulla causa (`scelta`, `cacciato`, `prodigio`). Il risultato conserva
## tali metadati per una futura integrazione nell'orchestratore.


static func scegli(testo: String, quadro: Dictionary, esito: Dictionary,
		validatore: ValidatoreNarrativo = null) -> Dictionary:
	if bool(esito.get("ok", false)):
		return _risultato(testo.strip_edges(), quadro, false)
	var fallback := genera(quadro, validatore)
	fallback["violazioni_originali"] = esito.get("violazioni", []).duplicate(true)
	return fallback


static func genera(quadro: Dictionary, validatore: ValidatoreNarrativo = null) -> Dictionary:
	var origine := _nome_sicuro(String(quadro.get("origine", quadro.get("da", ""))), "la terra alle spalle")
	var destinazione := _nome_sicuro(String(quadro.get("destinazione", quadro.get("a", ""))), "la riva assegnata")
	if not bool(quadro.get("passaggio_avvenuto", true)):
		var testo_fermo := "Il gesto non li porto altrove; Ulisse e i compagni rimasero dove erano."
		var out_fermo := _risultato(testo_fermo, quadro, true)
		var guardia_ferma := validatore if validatore != null else ValidatoreNarrativo.new()
		out_fermo["validazione"] = guardia_ferma.valida(testo_fermo, quadro)
		return out_fermo
	var causa := String(quadro.get("causa", ""))
	var testo := ""
	match causa:
		"scelta":
			testo = "La tappa «%s» rimase alle spalle per ordine di Ulisse. Le navi tennero la rotta fissata; la tappa «%s» apparve davanti alle prue." % [origine, destinazione]
		"cacciato":
			testo = "Respinti dalla tappa «%s», presero il mare. Senza mutare rotta videro la tappa «%s» apparire davanti alle prue." % [origine, destinazione]
		"prodigio":
			testo = "Dalla tappa «%s» una forza piu' grande li sospinse sul mare. Senza mutare rotta videro la tappa «%s» apparire davanti alle prue." % [origine, destinazione]
		_:
			testo = "La tappa «%s» rimase alle spalle. Le navi tennero la rotta fissata; la tappa «%s» apparve davanti alle prue." % [origine, destinazione]

	var out := _risultato(testo, quadro, true)
	var guardia := validatore if validatore != null else ValidatoreNarrativo.new()
	var verifica := guardia.valida(testo, quadro)
	# Un quadro puo' vietare anche parole usate dal modello di fallback. In tal caso si
	# riduce alla sola relazione causale fra i due estremi, senza inventare altri fatti.
	if not bool(verifica.get("ok", false)):
		out["testo"] = "La traversata condusse Ulisse dalla tappa «%s» alla tappa «%s»." % [origine, destinazione]
		verifica = guardia.valida(String(out["testo"]), quadro)
	out["validazione"] = verifica
	return out


static func _risultato(testo: String, quadro: Dictionary, fallback: bool) -> Dictionary:
	var origine := String(quadro.get("origine", quadro.get("da", "")))
	var destinazione := String(quadro.get("destinazione", quadro.get("a", "")))
	var passaggio_avvenuto := bool(quadro.get("passaggio_avvenuto", true))
	return {
		"testo": testo,
		"fallback": fallback,
		"deterministico": fallback,
		"origine": origine,
		"destinazione": destinazione,
		"rotta_fissa": [origine, destinazione] if passaggio_avvenuto else [origine],
		"passaggio_avvenuto": passaggio_avvenuto,
		"causa": String(quadro.get("causa", "")),
		"pressione": quadro.get("pressione", quadro.get("evento_pressione", "")),
	}


static func _nome_sicuro(nome: String, predefinito: String) -> String:
	var out := nome.replace("\n", " ").replace("\r", " ").replace("«", "").replace("»", "").strip_edges()
	return out if out != "" else predefinito
