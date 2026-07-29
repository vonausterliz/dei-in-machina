extends GutTest

## I dati dipendenti dalla lingua stanno FUORI dal codice (data/lingua/*.json) e la
## logica deterministica li usa da lì: tradurre il gioco non deve rompere i controlli.

func test_dati_caricati_dal_json():
	Lingua.usa("it")
	assert_gt(Lingua.marcatori_anacronismo().size(), 50, "i marcatori vengono dal file")
	assert_gt(Lingua.cue_invocazione().size(), 10)
	assert_eq(Lingua.spunti_generici().size(), 3)

func test_la_regola_usa_i_dati_esterni():
	# Il backstop dell'anacronismo deve leggere la lista dal file, non da una costante.
	Lingua.usa("it")
	assert_true(Validazione.e_anacronistico("prendo il fucile"))
	assert_false(Validazione.e_anacronistico("offro vino allo straniero"))

func test_lingua_mancante_ricade_su_italiano():
	Lingua.usa("xx")  # non esiste
	assert_gt(Lingua.marcatori_anacronismo().size(), 0, "ripiega sulla lingua predefinita")
	Lingua.usa("it")
