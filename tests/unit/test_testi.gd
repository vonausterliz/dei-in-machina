extends GutTest

## Le stringhe mostrate all'utente stanno in data/testi/<lingua>.json, non nel codice.

func test_stringhe_dal_file():
	Testi.usa("it")
	assert_eq(Testi.s("gioco/agisci"), "Agisci")
	assert_string_contains(Testi.s("app/titolo"), "MACHINA")

func test_sostituzioni():
	assert_eq(Testi.s("pannelli/ciurma_conteggio", [12, 45]), "12 di 45")
	assert_string_contains(Testi.s("gioco/fine", ["follia"]), "follia")

func test_chiave_mancante_e_visibile():
	# Meglio vedere la chiave che una stringa vuota: si capisce subito cosa manca.
	assert_eq(Testi.s("non/esiste"), "non/esiste")

func test_lingua_mancante_ricade_su_italiano():
	Testi.usa("xx")
	assert_eq(Testi.s("gioco/agisci"), "Agisci")
	Testi.usa("it")
