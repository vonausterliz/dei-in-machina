extends GutTest

## LA SEQUENZA D'AVVIO, nell'ordine chiesto:
##
##   1. la schermata d'apertura;
##   2. si dissolve — perche' e' finita la musica, o perche' e' stato premuto un tasto;
##   3. quando si e' dissolta compare SOLO il popup delle tre scelte;
##   4. scelto, compare la schermata principale.
##
## Il passo 2 non avveniva. Con `trattieni` acceso — che e' sempre, quando c'e' la soglia —
## `congeda()` usciva subito senza avviare nessuna sfumatura: la schermata d'apertura restava
## intera, marchio e «un tasto, e il viaggio comincia» compresi, e il popup ci compariva
## sopra. Nel referto del gioco tutto tornava; a schermo era un'altra cosa. Si vede nello
## screenshot dell'umano, non lo vedeva nessun test.
##
## Adesso l'uscita e' in due tempi — il velo (l'emblema) e il sipario (il fondale scuro) —
## e questi test presidiano il confine fra i due, che e' l'istante in cui il popup nasce.

const PASSO := 1.0 / 60.0

var _splash: Splash
var _pronto := 0
var _finito := 0

func before_each():
	_pronto = 0
	_finito = 0
	_splash = Splash.new()
	# Niente musica: qui si misura il sipario, non la colonna sonora. Senza brano la
	# schermata si regge sul tempo (`DURATA`), che e' esattamente il caso da provare.
	_splash.pronto.connect(func(): _pronto += 1)
	_splash.finito.connect(func(): _finito += 1)
	add_child_autofree(_splash)
	await wait_frames(1)

## Fa scorrere il tempo del sipario senza aspettarlo davvero: `_process` e' pubblico quanto
## basta, e un test che dorme 0,7 secondi per ogni caso e' un test che si smette di eseguire.
func _scorri(secondi: float) -> void:
	var quanti := int(ceil(secondi / PASSO))
	for i in quanti:
		if is_instance_valid(_splash) and _splash.is_processing():
			_splash._process(PASSO)

func _velo() -> float:
	return _splash._tela.modulate.a

func _fondale() -> float:
	return _splash._fondale.modulate.a

## IL VELO PARTE ANCHE SE IL SIPARIO E' TRATTENUTO. E' il difetto dello screenshot.
func test_trattenuto_lemblema_sfuma_lo_stesso():
	_splash.trattieni = true
	assert_almost_eq(_velo(), 1.0, 0.01, "l'emblema non si vede prima ancora di cominciare")
	_splash.congeda()
	_scorri(Splash.DISSOLVENZA + 0.05)
	assert_almost_eq(_velo(), 0.0, 0.01,
		"la schermata d'apertura NON si e' dissolta: il popup comparira' sopra il marchio")

## …ma il fondale resta. E' cio' che sta dietro il popup: buio, non mezza partita.
func test_trattenuto_il_fondale_resta():
	_splash.trattieni = true
	_splash.congeda()
	_scorri(Splash.DISSOLVENZA * 3.0)
	assert_almost_eq(_fondale(), 1.0, 0.01,
		"il fondale se n'e' andato senza permesso: dietro il popup si vedrebbe il gioco")
	assert_eq(_finito, 0, "la schermata d'apertura si e' congedata mentre era trattenuta")

## IL POPUP NASCE QUANDO IL VELO E' FINITO, non un istante prima. Prima `pronto` partiva
## nello stesso istante di `congeda()`, ed e' il motivo per cui i due si sovrapponevano.
func test_il_popup_si_chiede_a_dissolvenza_finita():
	_splash.trattieni = true
	_splash.congeda()
	assert_eq(_pronto, 0, "il popup e' stato chiesto prima che l'apertura si dissolvesse")
	_scorri(Splash.DISSOLVENZA * 0.5)
	assert_eq(_pronto, 0, "il popup e' stato chiesto a meta' dissolvenza")
	_scorri(Splash.DISSOLVENZA * 0.6)
	assert_eq(_pronto, 1, "l'apertura si e' dissolta e il popup non e' stato chiesto")
	_scorri(Splash.DISSOLVENZA * 2.0)
	assert_eq(_pronto, 1, "il popup e' stato chiesto piu' di una volta")

## Scelto: il fondale sfuma e sotto c'e' il gioco. Solo allora la schermata d'apertura ha
## finito davvero.
func test_lascia_andare_cala_il_fondale_e_poi_finisce():
	_splash.trattieni = true
	_splash.congeda()
	_scorri(Splash.DISSOLVENZA + 0.05)
	_splash.lascia_andare()
	_scorri(Splash.DISSOLVENZA * 0.5)
	assert_between(_fondale(), 0.05, 0.95, "il fondale non sta sfumando: sparisce di colpo")
	assert_eq(_finito, 0, "ha annunciato la fine col fondale ancora a mezz'aria")
	_scorri(Splash.DISSOLVENZA)
	assert_eq(_finito, 1, "il sipario e' calato e non l'ha detto a nessuno")

## Senza nessuno che trattenga — il vecchio comportamento, e quello del generatore d'icona —
## le due sfumature partono insieme e la schermata se ne va da sola.
func test_senza_soglia_se_ne_va_tutta_insieme():
	_splash.congeda()
	_scorri(Splash.DISSOLVENZA + 0.05)
	assert_eq(_pronto, 0, "ha chiesto un popup che nessuno aveva chiesto")
	assert_eq(_finito, 1, "senza soglia la schermata d'apertura non se n'e' andata")

## Un tasto premuto vale la fine della musica: sono le due strade descritte, e devono
## portare allo stesso posto.
func test_un_tasto_dissolve_come_la_musica():
	_splash.trattieni = true
	var tasto := InputEventKey.new()
	tasto.keycode = KEY_SPACE
	tasto.pressed = true
	_splash._input(tasto)
	_scorri(Splash.DISSOLVENZA + 0.05)
	assert_almost_eq(_velo(), 0.0, 0.01, "premere un tasto non dissolve l'apertura")
	assert_eq(_pronto, 1, "premere un tasto non porta al popup delle scelte")
