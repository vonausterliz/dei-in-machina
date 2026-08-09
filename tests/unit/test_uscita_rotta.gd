extends GutTest

## R-14 — PARLARE DI ROTTA NON È SALPARE.
##
## `rotta` è il tag d'uscita di nove tappe su quindici: Troia, Eolo, Circe, l'Ade, le Sirene,
## Scilla, Trinacia, Ogigia, Scheria. Sono tappe che si chiudono quando Ulisse riprende il
## mare — e nel tracciato del 6 agosto 2026 Troia si è chiusa al TURNO 3 su
##
##     «ai remi dobbiamo arrivare ad itaca!»    tipo: azione, tag: [rotta]
##
## cioè su un incitamento ai rematori, gridato mentre la nave era ancora là. L'Interprete non
## aveva sbagliato: di rotta si parlava davvero. È il gioco che ha letto un tag come se fosse
## un movimento.
##
## Il tag dice DI COSA si parla; il campo `tipo` dell'envelope dice SE ci si muove. Per uscire
## servono tutti e due — e nient'altro cambia: nessun tag nuovo, nessun prompt riscritto.
## `fuga` non lo chiede: da un pericolo si scappa anche parlando (tipo `parola`) o con
## un'astuzia (tipo `azione`), ed è comunque un congedo.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(7)

func _envelope(tag: Array, tipo: String) -> Dictionary:
	return {"tag": tag, "tipo": tipo, "plausibilita": "in_mondo"}

## Il caso vero, con le parole vere.
func test_incitare_i_rematori_non_chiude_la_tappa():
	var a := GameManager.viaggio.avanza(_envelope(["rotta"], "azione"))
	assert_false(bool(a["avanzato"]),
		"«ai remi dobbiamo arrivare ad itaca!» ha chiuso Troia al turno 3")
	assert_eq(String(a.get("causa", "")), "", "una tappa che non cambia non ha causa")

## E la tappa resta quella: non si esce di lato.
func test_dopo_il_falso_congedo_si_e_ancora_li():
	GameManager.viaggio.avanza(_envelope(["rotta"], "azione"))
	assert_eq(GameManager.viaggio.corrente(), "troia")

## Salpare davvero, invece, chiude — ed è una partenza voluta.
func test_salpare_chiude_la_tappa():
	var a := GameManager.viaggio.avanza(_envelope(["rotta"], "movimento"))
	assert_true(bool(a["avanzato"]), "con `tipo: movimento` la tappa deve chiudersi")
	assert_eq(String(a["causa"]), "scelta")

## La fuga non chiede il movimento: si scappa anche con le parole, e resta una cacciata.
func test_la_fuga_non_chiede_il_movimento():
	GameManager.viaggio.entra("ciconi")   # i Ciconi escono su `fuga`
	var a := GameManager.viaggio.avanza(_envelope(["fuga"], "azione"))
	assert_true(bool(a["avanzato"]), "una fuga è un congedo, di qualunque tipo sia")
	assert_eq(String(a["causa"]), "cacciato")

## Un envelope senza `tipo` non è un movimento: nel dubbio si resta. Il campo esiste nel
## contratto ed è obbligatorio, ma un modello può ometterlo — e l'omissione non deve
## regalare un cambio di scena.
func test_senza_tipo_non_si_parte():
	var a := GameManager.viaggio.avanza({"tag": ["rotta"], "plausibilita": "in_mondo"})
	assert_false(bool(a["avanzato"]))

## OGIGIA. Chi è trattenuto da Calipso si libera SALPANDO, non parlandone: l'ammonizione di
## prigionia non deve azzerarsi perché Ulisse ha nominato la rotta guardando il mare.
func test_a_ogigia_parlare_di_rotta_non_scioglie_la_prigionia():
	GameManager.viaggio.entra("ogigia")
	GameManager.stato.viaggio["turni_in_episodio"] = 9
	GameManager.stato.ammonizioni["prigionia"] = 1
	var esito := GameManager.viaggio.trattiene(_envelope(["rotta"], "parola"), true)
	assert_eq(esito, "prigionia", "parlare di partire non è partire")
	assert_eq(int(GameManager.stato.ammonizioni["prigionia"]), 2)

func test_a_ogigia_salpare_scioglie_tutto():
	GameManager.viaggio.entra("ogigia")
	GameManager.stato.viaggio["turni_in_episodio"] = 9
	GameManager.stato.ammonizioni["prigionia"] = 1
	var esito := GameManager.viaggio.trattiene(_envelope(["rotta"], "movimento"), true)
	assert_eq(esito, "", "chi riparte non è prigioniero")
	assert_eq(int(GameManager.stato.ammonizioni["prigionia"]), 0)
