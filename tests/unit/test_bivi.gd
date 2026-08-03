extends GutTest

## I BIVI, senza un secondo tipo di turno.
##
## Il design (sez. 4) vuole «scelte discrete per i bivi veri: Scilla o Cariddi? apri
## l'otre?». Oggi gli appigli sono prefill di testo: si cliccano, finiscono nel campo, e da
## li' si possono modificare o ignorare. Non e' una scelta, e' un suggerimento.
##
## Un bivio vero, come lo descriveva il design, sarebbe una seconda macchina del turno con
## rami scritti a mano tappa per tappa. Ma il campo `rischio` ESISTE GIA' negli spunti
## (Omero marca col «!» quelli pericolosi) e finora serviva solo a colorare il bottone.
## Trattarlo come IMPEGNO da' il peso della scelta senza un meccanismo nuovo:
##
##  1. si conferma prima di agire (nella GUI), e non si puo' modificare la frase;
##  2. la reazione degli dei e' amplificata di un grado — in QUALUNQUE direzione abbiano
##     scelto. Chi rischia rischia davvero: il castigo morde di piu', ma anche l'aiuto vale
##     di piu'. Questa e' la parte deterministica, ed e' la garanzia.

const VANTO := "Sono io, Odisseo, che t'ho accecato!"

func before_each():
	LLMManager.mock_mode = true

func _turno(rischio: bool) -> Dictionary:
	GameManager.nuova_partita(555)
	GameManager.vai_a_tappa("ciclope")
	return await GameManager.esegui_turno(VANTO, [], rischio)

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

## Gli spunti pericolosi arrivano gia' marcati da Omero (il «!»), e il marchio deve
## sopravvivere al filtro: se si perdesse, i bivi tornerebbero suggerimenti qualunque.
func test_il_filtro_non_perde_il_marchio_del_rischio():
	GameManager.nuova_partita(1)
	var filtrati := GameManager.filtra_spunti([
		{"testo": "Apri l'otre dei venti.", "rischio": true},
		{"testo": "Resta al timone.", "rischio": false},
	])
	assert_eq(filtrati.size(), 2)
	assert_true(bool(filtrati[0]["rischio"]))
	assert_false(bool(filtrati[1]["rischio"]))

## Nella GUI un bivio non si puo' correggere: cliccarlo NON riempie il campo (da dove si
## potrebbe modificare o ignorare), chiede conferma. E' la differenza fra un suggerimento
## e una scelta.
func test_nella_gui_un_bivio_chiede_conferma_e_non_riempie_il_campo():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._scegli_spunto("Apri l'otre dei venti.", true)
	assert_eq(ui._input.text, "", "un bivio non finisce nel campo modificabile")
	assert_not_null(ui._conferma, "dev'esserci la richiesta di conferma")
	assert_true(ui._conferma.visible)

func test_nella_gui_uno_spunto_normale_riempie_il_campo_come_sempre():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	LLMManager.mock_mode = true
	ui._scegli_spunto("Resta al timone.", false)
	# Con lo spunto normale il turno parte subito (comportamento di sempre): il campo viene
	# riempito e poi svuotato dall'azione. L'importante e' che NON si chieda conferma.
	assert_true(ui._conferma == null or not ui._conferma.visible)
