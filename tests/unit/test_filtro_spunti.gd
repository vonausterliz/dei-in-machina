extends GutTest

## GLI SPUNTI SONO UNA PROMESSA: cio' che il gioco offre, il gioco lo accetta e lo sa
## rendere. Tre modi in cui la promessa si e' rotta sul campo, tutti nello stesso punto:
##
##  1. fra le frasi e' comparso «---SPUNTI», cioe' l'impalcatura del prompt;
##  2. sono arrivati anacronismi, che poi il gioco stesso avrebbe respinto;
##  3. all'isola di Eolo veniva proposto «apri l'otre» — e Eolo l'otre non l'ha ancora dato.
##
## Il prompt puo' chiedere tutto questo, ma resta una preghiera: qui c'e' la garanzia.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(31)

func test_l_impalcatura_del_prompt_non_diventa_uno_spunto():
	var puliti := GameManager.filtra_spunti([
		{"testo": "---SPUNTI", "rischio": false},
		{"testo": "SPUNTI", "rischio": false},
		{"testo": "ORIENTAMENTO", "rischio": false},
		{"testo": "Piega ai remi.", "rischio": false},
	])
	assert_eq(puliti.size(), 1)
	assert_eq(String(puliti[0]["testo"]), "Piega ai remi.")

func test_un_anacronismo_non_viene_mai_proposto():
	var puliti := GameManager.filtra_spunti([
		{"testo": "Spara ai Ciconi col fucile.", "rischio": true},
		{"testo": "Offri vino al re.", "rischio": false},
	])
	assert_eq(puliti.size(), 1, "il gioco non puo' offrire cio' che poi respinge")
	assert_eq(String(puliti[0]["testo"]), "Offri vino al re.")

## Il caso di Eolo: la tappa dichiara cosa NON e' ancora accaduto, e quelle parole non
## possono comparire in uno spunto finche' non accade.
func test_non_si_propone_cio_che_non_e_ancora_accaduto():
	GameManager.vai_a_tappa("eolo")
	var puliti := GameManager.filtra_spunti([
		{"testo": "Apri l'otre dei venti mentre i compagni dormono.", "rischio": true},
		{"testo": "Racconta a Eolo la caduta di Troia.", "rischio": false},
	])
	assert_eq(puliti.size(), 1, "l'otre non c'e' ancora: non si puo' aprire")
	assert_string_contains(String(puliti[0]["testo"]), "Racconta")

func test_altrove_lo_stesso_spunto_e_ammesso():
	GameManager.vai_a_tappa("ciclope")
	var puliti := GameManager.filtra_spunti([{"testo": "Apri l'otre.", "rischio": false}])
	assert_eq(puliti.size(), 1, "il vincolo vale nella sua tappa, non ovunque")

## NIENTE APPIGLI GENERICI. Prima esistevano tre frasi buone per ogni occasione, e
## proprio per questo non erano buone per nessuna: «piega ai remi e prosegui la rotta»
## compariva anche chiusi nell'antro del Ciclope. Un appiglio che non sa cosa sta
## succedendo e' peggio di nessun appiglio — il campo libero c'e' sempre.
func test_il_ripiego_e_sempre_legato_alla_tappa():
	for id in GameManager.episodi.ordine():
		GameManager.vai_a_tappa(id)
		var r := GameManager.spunti_di_riserva()
		assert_gt(r.size(), 0, "la tappa «%s» deve avere i suoi appigli" % id)

func test_se_non_resta_niente_si_ripiega_su_quelli_della_tappa():
	GameManager.vai_a_tappa("ciclope")
	var puliti := GameManager.filtra_spunti([{"testo": "---SPUNTI", "rischio": false}])
	assert_eq(puliti.size(), 0)
	var riserva := GameManager.spunti_di_riserva()
	assert_gt(riserva.size(), 0)
	assert_false(String(riserva[0]["testo"]).to_lower().contains("remi"),
		"nell'antro non si rema")

## E cio' che passa il filtro e' anche cio' che il gioco si impegna a non rifiutare.
func test_solo_gli_spunti_filtrati_diventano_una_promessa():
	GameManager.ricorda_spunti([
		{"testo": "Spara ai Ciconi col fucile.", "rischio": true},
		{"testo": "Offri vino al re.", "rischio": false},
	])
	assert_false(GameManager.gia_proposto("Spara ai Ciconi col fucile."),
		"non si promette cio' che non si e' offerto")
	assert_true(GameManager.gia_proposto("Offri vino al re."))

## Gli appigli della tappa passano dallo STESSO filtro: anche loro possono nominare cose
## non ancora accadute (a Trinacia il ripiego non deve proporre di macellare le vacche).
func test_anche_il_ripiego_passa_dal_filtro():
	for id in GameManager.episodi.ordine():
		GameManager.vai_a_tappa(id)
		var riserva := GameManager.spunti_di_riserva()
		assert_eq(GameManager.filtra_spunti(riserva).size(), riserva.size(),
			"gli appigli di «%s» devono superare il proprio filtro" % id)
