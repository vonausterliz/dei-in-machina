extends GutTest

## I dati dipendenti dalla lingua stanno FUORI dal codice (data/lingua/*.json) e la
## logica deterministica li usa da lì: tradurre il gioco non deve rompere i controlli.

func test_dati_caricati_dal_json():
	Lingua.usa("it")
	assert_gt(Lingua.marcatori_anacronismo().size(), 50, "i marcatori vengono dal file")
	assert_gt(Lingua.cue_invocazione().size(), 10)
	# Gli spunti generici sono stati TOLTI: valevano ovunque e quindi non valevano da
	# nessuna parte. Ogni tappa ha i suoi (episodi.json -> spunti_di_riserva).
	assert_false(Lingua.ha("spunti_generici"), "niente appigli buoni per ogni occasione")

func test_la_regola_usa_i_dati_esterni():
	# Il backstop dell'anacronismo deve leggere la lista dal file, non da una costante.
	Lingua.usa("it")
	assert_true(Validazione.e_anacronistico("prendo il fucile"))
	assert_false(Validazione.e_anacronistico("offro vino allo straniero"))

func test_lingua_mancante_ricade_su_italiano():
	Lingua.usa("xx")  # non esiste
	assert_gt(Lingua.marcatori_anacronismo().size(), 0, "ripiega sulla lingua predefinita")
	Lingua.usa("it")
