extends GutTest

## PERCHÉ SI CAMBIA SCENA — R-09.
##
## «Un cambio di scena deve avere una causa, e il giocatore deve leggerla. Le cause legittime
## sono tre: me ne sono andato io, mi hanno cacciato, è successo qualcosa di sovrannaturale.
## Un cambio senza causa non deve esistere.»
##
## Nasce da una partita vera (tracciato del 6 agosto 2026, 00:45): «non posso trovarmi a
## combattere coi Ciconi e poi al turno dopo trovarmi dai Lotofagi». Contati i turni, era
## proprio così — Ciconi e Lotofagi chiusi tutti e due da un contatore scaduto.
##
## E Omero non poteva farci niente: `_passaggio(da, a)` gli passava due nomi e basta. Con due
## nomi si scrive una cosa sola, il mare che si allarga — la stessa prosa per una fuga e per
## un commiato. Non era il narratore a sbagliare: non aveva l'informazione.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(7)

func _avanza_con(tag: Array) -> Dictionary:
	return GameManager.viaggio.avanza({"tag": tag, "plausibilita": "in_mondo"})

## Ogni avanzamento porta una causa, e la causa è una delle tre. Mai vuota, mai altro.
func test_ogni_avanzamento_ha_una_causa_fra_le_tre():
	var a := _avanza_con(["rotta"])   # Troia esce su `rotta`
	assert_true(bool(a["avanzato"]), "la tappa non è avanzata: il caso non prova niente")
	assert_true(Viaggio.CAUSE.has(String(a.get("causa", ""))),
		"avanzamento senza causa, o con una causa fuori elenco: «%s»" % a.get("causa", ""))

## Scappare è andarsene sotto la spinta di qualcuno: vale «cacciato», non «scelta».
func test_la_fuga_e_una_cacciata():
	GameManager.viaggio.entra("ciconi")    # i Ciconi escono su `fuga`
	var a := _avanza_con(["fuga"])
	assert_true(bool(a["avanzato"]))
	assert_eq(String(a["causa"]), "cacciato",
		"una fuga è stata registrata come partenza voluta")

## Un tag d'uscita che non è fuga è una partenza decisa da lui.
func test_un_congedo_e_una_scelta():
	assert_eq(String(_avanza_con(["rotta"])["causa"]), "scelta")

## Restare non produce nessuna causa: la causa esiste solo se qualcosa è cambiato.
func test_chi_resta_non_ha_causa():
	var a := _avanza_con(["curiosita"])
	assert_false(bool(a["avanzato"]))
	assert_eq(String(a.get("causa", "")), "", "una tappa che non cambia ha prodotto una causa")

## E LA CAUSA DEVE ARRIVARE A OMERO, che è tutto il punto: se resta dentro il motore, il
## giocatore continua a leggere la stessa traversata generica di prima.
func test_la_causa_arriva_nel_prompt_del_passaggio():
	var n := Narratore.new(["atena", "poseidone"])
	var detto := {}
	for causa in Viaggio.CAUSE:
		var m: Array = n.costruisci_messaggi({"passaggio":
			{"da": "I Ciconi di Ismaro", "a": "La terra dei Lotofagi", "causa": causa}})
		var testo := String(m[1]["content"])
		assert_true(testo.contains("MOTIVO"), "il prompt del passaggio non dice il motivo (%s)" % causa)
		detto[causa] = testo
	# …e le tre cause devono dare tre istruzioni DIVERSE. Un motivo uguale per tutte sarebbe
	# un campo che c'è e non serve: la fuga e il commiato tornerebbero a somigliarsi.
	assert_ne(detto["scelta"], detto["cacciato"], "partire e essere cacciati danno lo stesso prompt")
	assert_ne(detto["cacciato"], detto["prodigio"], "cacciata e prodigio danno lo stesso prompt")

## Senza causa il prompt resta quello di prima: nessuna riga MOTIVO inventata dal nulla.
func test_senza_causa_non_si_inventa_un_motivo():
	var n := Narratore.new([])
	var m: Array = n.costruisci_messaggi({"passaggio": {"da": "A", "a": "B"}})
	assert_false(String(m[1]["content"]).contains("MOTIVO"))
