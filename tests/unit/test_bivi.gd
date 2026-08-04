extends GutTest

## I BIVI NON SI PROPONGONO PIU'.
##
## Storia in due tempi. Il design (sez. 4) voleva «scelte discrete per i bivi veri: Scilla o
## Cariddi? apri l'otre?». Costruirle davvero sarebbe una seconda macchina del turno, con
## rami scritti a mano tappa per tappa; cosi' si era usato il campo `rischio`, che esisteva
## gia' negli spunti: segno «‡», conferma obbligatoria, reazione degli dei amplificata di un
## grado in qualunque direzione.
##
## Alla prova del gioco quel surrogato non ha retto la lettura: fra tre frasi omeriche ne
## compariva una col simbolo strano che apriva una finestrella. Su richiesta esplicita
## dell'umano (v2.34) i bivi sono stati tolti DALLE PROPOSTE: `rischio: true` ora vuol dire
## una cosa sola, e piu' semplice — *questo non si propone*. Rischiare resta possibile
## scrivendolo nel campo libero, che e' il posto giusto per una cosa che nessuno ha
## suggerito.
##
## La REGOLA deterministica resta, e resta sorvegliata: `esegui_turno(..., rischio)` e
## `forza_con_rischio` sono l'unico punto in cui il rischio ha un effetto, e se un giorno
## tornassero i bivi veri e' li' che si attaccheranno.

const VANTO := "Sono io, Odisseo, che t'ho accecato!"

func before_each():
	LLMManager.mock_mode = true

func _turno(rischio: bool) -> Dictionary:
	GameManager.nuova_partita(555)
	GameManager.vai_a_tappa("ciclope")
	return await GameManager.esegui_turno(VANTO, [], rischio)

# --- Cio' che arriva a schermo: mai un bivio ---

## Il cuore della richiesta: uno spunto marcato rischioso non deve comparire fra le scelte.
func test_uno_spunto_rischioso_non_si_propone():
	GameManager.nuova_partita(1)
	var mostrati := GameManager.spunti_da_mostrare([
		{"testo": "Apri l'otre dei venti.", "rischio": true},
		{"testo": "Resta al timone.", "rischio": false},
	])
	for s in mostrati:
		assert_false(bool(s.get("rischio", false)), "un bivio e' arrivato a schermo")
		assert_ne(String(s["testo"]), "Apri l'otre dei venti.")

## Scartare senza rimpiazzare lascerebbe due appigli invece di tre, e il giocatore vedrebbe
## l'interfaccia assottigliarsi senza capire perche'. Il vuoto si ricuce con la tappa.
func test_il_posto_del_bivio_si_ricuce():
	GameManager.nuova_partita(1)
	GameManager.vai_a_tappa("ciclope")
	var mostrati := GameManager.spunti_da_mostrare([
		{"testo": "Sfida il gigante a voce alta.", "rischio": true},
		{"testo": "Conta i compagni rimasti.", "rischio": false},
	])
	assert_eq(mostrati.size(), GameManager.QUANTI_SPUNTI,
		"tolto il bivio, gli appigli della tappa completano i tre")

## Mai piu' di tre: il rammendo non deve trasformare l'elenco in un menu.
func test_non_piu_di_tre():
	GameManager.nuova_partita(1)
	GameManager.vai_a_tappa("ciclope")
	var molti: Array = []
	for i in 8:
		molti.append({"testo": "Azione plausibile numero %d." % i, "rischio": false})
	assert_eq(GameManager.spunti_da_mostrare(molti).size(), GameManager.QUANTI_SPUNTI)

## Il rammendo non deve poter ripetere una frase gia' presente.
func test_niente_doppioni():
	GameManager.nuova_partita(1)
	GameManager.vai_a_tappa("ciclope")
	var mostrati := GameManager.spunti_da_mostrare([
		{"testo": "Resta al timone.", "rischio": false},
		{"testo": "resta al timone.", "rischio": false},
	])
	var visti := {}
	for s in mostrati:
		var k := String(s["testo"]).to_lower()
		assert_false(visti.has(k), "appiglio ripetuto: %s" % k)
		visti[k] = true

## Nella GUI un appiglio finisce nel campo e parte, senza nessuna finestrella di mezzo.
func test_nella_gui_nessuna_conferma():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	LLMManager.mock_mode = true
	ui._scegli_spunto("Resta al timone.")
	for f in ui.get_children():
		assert_false(f is ConfirmationDialog and f.visible,
			"non deve aprirsi nessuna conferma: i bivi non arrivano piu' fin qui")

## Il segno «‡» era il marchio del bivio a schermo. Non deve piu' esistere da nessuna parte.
func test_il_segno_del_bivio_e_sparito():
	var src := FileAccess.get_file_as_string("res://scenes/main.gd")
	assert_false(src.contains("‡  "), "il segno del bivio e' ancora nel codice della GUI")

# --- La regola deterministica, che resta ---

func test_il_rischio_amplifica_la_reazione():
	var senza := await _turno(false)
	var d1: Dictionary = senza["voce"]["delta"]
	var con := await _turno(true)
	var d2: Dictionary = con["voce"]["delta"]
	assert_lt(int(d2.get("ulisse.animo", 0)), int(d1.get("ulisse.animo", 0)),
		"la stessa mossa, presa come rischio, deve pesare di piu'")

## Amplificare non vuol dire punire: se gli dei aiutano, il rischio fa valere di piu'
## l'aiuto. E' un bivio, non una penalita' mascherata.
func test_il_rischio_amplifica_anche_il_bene():
	var forte := Delta.da_reazione("atena", "aiuto", 2)
	var debole := Delta.da_reazione("atena", "aiuto", 1)
	assert_gt(int(forte.get("ulisse.animo", 0)), int(debole.get("ulisse.animo", 0)),
		"un grado in piu' di aiuto e' piu' aiuto")

## Resta leggibile nella traccia: guardando il Log si deve capire perche' quel turno ha
## pesato il doppio.
func test_il_rischio_resta_nella_traccia():
	var con := await _turno(true)
	assert_true(con["voce"].get("rischio", false))
	var senza := await _turno(false)
	assert_false(senza["voce"].get("rischio", false))

## Un turno normale non cambia di una virgola: il rischio e' l'eccezione.
func test_senza_rischio_niente_cambia():
	var a := await _turno(false)
	var b := await _turno(false)
	assert_eq(a["voce"]["delta"], b["voce"]["delta"], "stesso seme, stesso esito")

## L'intensita' non puo' sfondare il tetto: 3 e' il massimo, anche rischiando.
func test_il_rischio_non_sfonda_il_massimo():
	assert_eq(GameManager.forza_con_rischio(3, true), 3)
	assert_eq(GameManager.forza_con_rischio(2, true), 3)
	assert_eq(GameManager.forza_con_rischio(1, false), 1)

## Il marchio deve sopravvivere al FILTRO (che non lo guarda): e' `spunti_da_mostrare` a
## scartarlo, un passo dopo. Se il filtro lo perdesse, un bivio tornerebbe proponibile.
func test_il_filtro_non_perde_il_marchio_del_rischio():
	GameManager.nuova_partita(1)
	var filtrati := GameManager.filtra_spunti([
		{"testo": "Apri l'otre dei venti.", "rischio": true},
		{"testo": "Resta al timone.", "rischio": false},
	])
	assert_eq(filtrati.size(), 2)
	assert_true(bool(filtrati[0]["rischio"]))
	assert_false(bool(filtrati[1]["rischio"]))
