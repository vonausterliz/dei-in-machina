extends GutTest

## CHI VA NASCOSTO, E CHI NO.
##
## L'invariante «la narrazione rivolta al giocatore non nomina MAI un dio» è il pilastro del
## gioco: gli dèi muovono i fili dall'Olimpo e non si devono vedere. Ma valeva su tutte e
## tredici le voci del pantheon, comprese quelle che il giocatore ha DAVANTI.
##
## Il conto, dal tracciato del 6 agosto 2026: **10 ritentativi di Omero su 43 chiamate**, e
## in tutti e dieci il nome vietato era il personaggio in scena — Eolo alle sue isole (turni
## 15-19), Circe a casa sua (23-28). Mai un olimpio. Il ritentativo fallisce quasi sempre
## (come si fa a narrare l'isola di Eolo senza dire Eolo?), quindi interviene `redigi()`, e a
## schermo è arrivato «Chiedi a **un dio** il nome dell'aroma» mentre Circe versava il vino.
##
## Non è un dettaglio di prompt: l'invariante serve a non svelare CHI MUOVE I FILI
## dall'Olimpo, non a cancellare i personaggi che si incontrano. Il poema li nomina tutti.
##
## Da qui il campo `nascosto` in `pantheon.json`, dichiarato voce per voce. Dedurlo dalla
## tappa corrente sarebbe costato meno, ma avrebbe reso nominabile **Ermes** durante la tappa
## di Circe: Ermes ha `episodio: circe` perché è lì che interviene, e la sua è
## un'intromissione olimpia — esattamente ciò che va tenuto celato.

var _pantheon: Pantheon

func before_all():
	_pantheon = PantheonManager.pantheon

## Il campo è obbligatorio e dichiarato: chi non lo dichiara non è «probabilmente visibile»,
## è un buco nel contratto. (Il validatore lo pretende; qui si guarda il dato vero.)
func test_ogni_voce_del_pantheon_dichiara_se_e_nascosta():
	var grezzo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/pantheon.json"))
	for voce in grezzo["dei"]:
		assert_true(voce.has("nascosto"), "%s non dichiara `nascosto`" % voce.get("id", "?"))

## I FILI DELL'OLIMPO. Sono quelli per cui l'invariante esiste.
func test_i_fili_dell_olimpo_sono_nascosti():
	for id in ["atena", "poseidone", "zeus", "ermes"]:
		assert_true(_pantheon.get_dio(id).nascosto, "%s deve restare invisibile" % id)

## CHI SI INCONTRA. Il giocatore li ha davanti: negarne il nome non nasconde niente, confonde
## e basta.
func test_chi_si_incontra_ha_un_nome():
	for id in ["polifemo", "eolo", "circe", "tiresia", "sirene", "scilla", "elio", "calipso",
			"ino_leucotea"]:
		assert_false(_pantheon.get_dio(id).nascosto, "%s si incontra: si può nominare" % id)

## Nel dubbio si nasconde: una voce nuova che si dimentichi il campo non deve sbucare nella
## narrazione. Il default sbagliato, qui, rompe il pilastro del gioco.
func test_nel_dubbio_si_nasconde():
	assert_true(Dio.from_dict({"id": "nuovo", "nome": "Nuovo"}).nascosto,
		"un dio che non dichiara niente resta un segreto")

## La lista che il Narratore sorveglia è fatta di soli nascosti.
func test_il_narratore_sorveglia_solo_i_nascosti():
	var nomi := _pantheon.nomi_nascosti()
	assert_eq(nomi.size(), 4, "i fili dell'Olimpo sono quattro: %s" % [nomi])
	var n := Narratore.new(nomi)
	assert_true(n.nomina_un_dio("Atena scese come un'ombra sulla nave."),
		"un olimpio nominato è una falla")
	assert_false(n.nomina_un_dio("Circe versò il vino e sorrise."),
		"Circe è lì, davanti al giocatore")
	assert_false(n.nomina_un_dio("Eolo consegnò l'otre dei venti."),
		"Eolo è l'ospite di quella tappa")
	assert_true(n.nomina_un_dio("Ermes gli mise in mano l'erba moly."),
		"l'intervento di Ermes è un filo dell'Olimpo, non un incontro")

## IL DATO E IL PROMPT DEVONO DIRE LA STESSA COSA.
##
## Il codice ora *permette* di nominare Circe, ma se il prompt continua a vietarlo Omero la
## eviterà lo stesso — e il difetto sopravvive alla correzione, in silenzio. `mondo.txt` è
## incluso da tutti e sette gli agenti: è lì che la distinzione va detta una volta sola.
func test_il_prompt_condiviso_divide_i_due_elenchi_come_il_pantheon():
	var mondo := FileAccess.get_file_as_string("res://prompts/mondo.txt")
	var taglio := mondo.find("Chi Ulisse INCONTRA")
	assert_gt(taglio, 0, "manca la sezione «chi non si nomina, e chi sì» in mondo.txt")
	var segreti := mondo.substr(0, taglio)
	var in_scena := mondo.substr(taglio)
	for dio in _pantheon.tutti():
		if dio.nascosto:
			assert_true(segreti.contains(dio.nome),
				"%s è nascosto nel pantheon ma non è fra i fili dell'Olimpo nel prompt" % dio.nome)
		else:
			assert_true(in_scena.contains(dio.nome),
				"%s si incontra, ma il prompt non dice che si può nominare" % dio.nome)

## E `redigi()` non deve più cancellare chi è in scena: è il caso letto a schermo.
func test_redigi_non_cancella_piu_chi_e_in_scena():
	var n := Narratore.new(_pantheon.nomi_nascosti())
	assert_eq(n.redigi("Chiedi a Circe il nome dell'aroma."),
		"Chiedi a Circe il nome dell'aroma.")
	assert_ne(n.redigi("Chiedi ad Atena il nome dell'aroma."),
		"Chiedi ad Atena il nome dell'aroma.", "un olimpio va ancora oscurato")
