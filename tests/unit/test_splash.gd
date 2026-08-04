extends GutTest

## LA SCHERMATA D'APERTURA, e quando se ne va.
##
## Prima spariva dopo 3,4 secondi fissi. Con trenta secondi di musica sopra, sparire a 3,4
## vuol dire tagliare la frase a metà — e lasciare la musica a suonare su una schermata che
## non c'è più. La regola nuova: al primo tasto, oppure tre secondi dopo l'ultima nota.
##
## In headless non c'è audio (e non c'è nessuno a guardare): lì vale il tempo fisso, ed è
## importante che valga, o i test resterebbero appesi ad aspettare una musica che non parte.

func _splash() -> Splash:
	var s := Splash.new()
	add_child_autofree(s)
	await wait_frames(2)
	return s

func test_il_file_della_musica_c_e_ed_e_lungo_quanto_serve():
	assert_true(ResourceLoader.exists(Splash.MUSICA),
		"%s deve esistere: si rigenera con ./avvia.sh musica" % Splash.MUSICA)
	var flusso: AudioStream = load(Splash.MUSICA)
	assert_not_null(flusso)
	assert_almost_eq(flusso.get_length(), 30.0, 1.0, "circa trenta secondi, come chiesto")

## Senza audio la schermata non può restare in attesa di un `finished` che non arriverà mai.
func test_senza_musica_vale_il_tempo_fisso():
	var s := await _splash()
	assert_null(s._suono, "in headless non si suona niente")
	assert_almost_eq(s._quando_congedarsi(0.0), Splash.DURATA, 0.01)

## Mentre la musica suona non c'è nessun traguardo: la schermata aspetta.
func test_con_la_musica_in_corso_non_ci_si_congeda():
	var s := await _splash()
	s._suono = AudioStreamPlayer.new()   # basta che ci sia: qui non deve suonare
	s.add_child(s._suono)
	s._muto_da = -1.0
	assert_eq(s._quando_congedarsi(0.0), INF, "finché suona, si resta")

## Finita la musica parte il conto alla rovescia dei tre secondi.
func test_finita_la_musica_si_aspettano_tre_secondi():
	var s := await _splash()
	s._suono = AudioStreamPlayer.new()
	s.add_child(s._suono)
	s._t = 30.0
	s._muto_da = 0.0
	assert_almost_eq(s._quando_congedarsi(0.0), 30.0 + Splash.ATTESA_DOPO_MUSICA, 0.01)
	# Due secondi dopo ne manca ancora uno.
	s._muto_da = 0.0
	assert_almost_eq(s._quando_congedarsi(2.0), 31.0, 0.01)

## Un tasto congeda subito, musica o non musica: un'apertura che non si può saltare è un
## pedaggio, ed è la ragione per cui esisteva il tempo fisso.
func test_un_tasto_congeda_subito():
	var s := await _splash()
	var tasto := InputEventKey.new()
	tasto.keycode = KEY_SPACE
	tasto.pressed = true
	s._input(tasto)
	assert_gte(s._uscita, 0.0, "l'uscita è cominciata")

func test_congedarsi_due_volte_non_ricomincia_la_dissolvenza():
	var s := await _splash()
	s.congeda()
	s._uscita = 0.4
	s.congeda()
	assert_almost_eq(s._uscita, 0.4, 0.01, "idempotente")
