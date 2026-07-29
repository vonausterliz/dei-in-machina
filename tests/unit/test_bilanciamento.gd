extends GutTest

## I valori-seme stanno in data/bilanciamento.json, non nel codice: tarare il gioco non
## deve richiedere di toccare GDScript.

func test_valori_letti_dal_file():
	assert_eq(Bilanciamento.num("coalizioni/prob_coalizione", -1.0), 0.4)
	assert_eq(Bilanciamento.intero("ulisse/soglia_hybris", -1), 50)
	assert_eq(Bilanciamento.intero("delta/castigo/animo", 99), -2)

func test_ripiego_se_la_voce_non_c_e():
	assert_eq(Bilanciamento.intero("sezione/inesistente", 7), 7, "mai rompersi per una voce assente")

func test_il_delta_usa_i_valori_del_file():
	# castigo intensita' 3: animo -2*3, ira +2*3, ciurma -2 (tutti dal file)
	var d := Delta.da_reazione("poseidone", "castigo", 3)
	assert_eq(d["ulisse.animo"], -6)
	assert_eq(d["poseidone.ira"], 6)
	assert_eq(d["ulisse.ciurma.vivi"], -2)
