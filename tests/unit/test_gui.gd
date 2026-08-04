extends GutTest

## La GUI (scenes/Main.tscn) si istanzia e gioca un turno senza errori (headless).
## Non testa il rendering (serve un display), ma la costruzione e il wiring col motore.

func test_scena_si_istanzia_e_apre():
	LLMManager.mock_mode = true
	var scena: PackedScene = load("res://scenes/Main.tscn")
	assert_not_null(scena, "Main.tscn deve caricarsi")
	var ui = scena.instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	# La UI ha avviato una partita e mostrato l'intro della prima tappa.
	assert_not_null(GameManager.stato)
	assert_string_contains(ui._narrazione.get_parsed_text(), "Omero")

func test_gui_gioca_un_turno():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._input.text = "Sono io, Odisseo, che t'ho accecato!"
	await ui._on_agisci()
	# Dopo il turno la narrazione e' cresciuta e le stat (barre + valori) esistono.
	assert_string_contains(ui._narrazione.get_parsed_text().to_lower(), "un dio")
	assert_true(ui._stat_vals.has("animo"))
	assert_ne(ui._stat_vals["animo"].text, "—", "il valore dell'animo e' stato popolato")

## Regressione storica: la finestra della ciurma era dichiarata, aveva il pulsante, la voce
## di menu e le funzioni di aggiornamento — ma non veniva MAI creata, e nessun test
## headless guardava le viste. Ora le due chat sono PANNELLI nella pagina (v2.34): la
## guardia vale uguale, e anzi di piu' — se non si costruiscono, mezza colonna e' vuota.
func test_le_viste_esistono():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	for nome in ["_fin_log", "_pan_olimpo", "_pan_ciurma", "_lente", "_mappa"]:
		assert_not_null(ui.get(nome), "%s deve essere costruito, non solo dichiarato" % nome)

## Le chat sono INCASTRATE, non finestre: devono stare dentro l'albero della pagina.
## Il difetto che si vuole impedire e' il ritorno silenzioso a una finestra separata.
func test_le_chat_sono_dentro_la_pagina():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	for p in [ui._pan_olimpo, ui._pan_ciurma]:
		assert_false(p is Window, "una chat incastrata non e' una finestra")
		assert_true(ui.is_ancestor_of(p), "deve stare nella pagina")
		assert_true(p.visible, "e vedersi senza doverla aprire")

func test_la_chat_della_ciurma_e_interattiva_e_collegata():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_true(ui._pan_ciurma.interattiva, "dalla ciurma Ulisse deve poter scrivere")
	assert_not_null(ui._pan_ciurma.campo, "la barra d'invio dev'essere costruita")
	assert_true(ui._pan_ciurma.inviato.is_connected(ui._on_ciurma_invio),
		"cio' che Ulisse scrive ai compagni deve arrivare al gioco")

## L'Olimpo e' in SOLA LETTURA: il giocatore assiste, non parla con gli dei. Una barra
## d'invio li' dentro romperebbe il patto su cui regge tutto il gioco.
func test_la_chat_dell_olimpo_non_si_puo_scrivere():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_false(ui._pan_olimpo.interattiva)
	assert_null(ui._pan_olimpo.campo, "agli dei non si scrive")

## La lente apre e chiude senza errori, su tutti e tre i riquadri che ce l'hanno.
func test_la_lente_si_apre_e_si_chiude():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	for apri in [ui._ingrandisci_mappa, ui._ingrandisci_olimpo, ui._ingrandisci_ciurma]:
		apri.call()
		await wait_frames(1)
		assert_true(ui._lente.visible, "la lente deve aprirsi")
		ui._lente.chiudi()
		assert_false(ui._lente.visible, "e chiudersi")

## La Vista Olimpo e' una CHAT: niente traccia tecnica, niente voci della ciurma.
func test_la_vista_olimpo_resta_una_chat():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._input.text = "Sono io, Odisseo, che t'ho accecato!"
	await ui._on_agisci()
	var t: String = ui._pan_olimpo.testo.get_parsed_text()
	assert_false(t.contains("Envelope:"), "la traccia tecnica appartiene al Log LLM")
	assert_false(t.contains("# Ciurma"), "la ciurma ha il suo riquadro")

## Il bottone per provare il modello dev'essere costruito e collegato: e' l'unico modo
## per sapere se una configurazione funziona SENZA cominciare una partita.
func test_settings_ha_il_bottone_prova_collegato():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	var f = ui._fin_impostazioni
	assert_not_null(f._btn_prova, "il bottone dev'essere costruito, non solo dichiarato")
	assert_true(f._btn_prova.pressed.is_connected(f._prova_modello), "e collegato")

## La prova deve guardare il profilo SCELTO, non quello che sta girando: si configura
## Gemini mentre il gioco e' ancora sul simulato, e provare "l'attivo" proverebbe Ollama.
func test_la_prova_guarda_il_profilo_scelto_non_quello_attivo():
	var quanti: int = LLMManager.profili.size()
	if quanti == 0:
		pending("nessun provider configurato"); return
	var locale := LLMManager.indice_profilo("Ollama locale")
	LLMManager.profilo_idx = quanti - 1
	var cfg := LLMManager.config_del_profilo()
	assert_eq(String(cfg["model"]), String(LLMManager.profili[quanti - 1]["model"]))
	assert_ne(String(cfg["base_url"]), String(LLMManager.profili[locale]["base_url"]),
		"non deve cadere sul provider locale")

## L'AVVISO SCRITTO NON C'E' PIU', il presidio si'.
##
## Nell'intestazione c'era «⚠ SIMULATO — gli dèi non pensano», messo li' dopo che si erano
## giocati quattro turni con dei finti credendo fossero veri. Su richiesta esplicita
## (v2.34) l'indicazione del motore e' uscita dall'interfaccia. Il guaio pero' non lo
## impediva l'etichetta: lo impedisce il BLOCCO — col simulato il campo e' spento e il
## bottone disabilitato. Quella e' la cosa da sorvegliare, e vale piu' di una scritta.
func test_col_simulato_non_si_puo_agire():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	# In headless il blocco non scatta (o i test si bloccherebbero da soli): si prova la
	# regola, che e' il punto unico in cui la decisione vive.
	assert_true(Main.blocca_simulato(true, true), "motore finto + schermo = non si gioca")
	assert_false(ui._narrazione.get_parsed_text().to_lower().contains("simulato"),
		"l'avviso scritto e' stato tolto dall'interfaccia")

# --- Il simulato non e' uno stato in cui si possa GIOCARE ---

## Il mock resta (ci girano i test e la console headless), ma con una finestra aperta non
## dev'essere una partita: si sono giocati quattro turni con dèi finti credendo fossero
## veri. Meglio un gioco che si ferma e spiega, di uno che finge.
func test_col_simulato_e_una_finestra_aperta_il_gioco_si_ferma():
	assert_true(Main.blocca_simulato(true, true), "motore finto + schermo = non si gioca")

func test_senza_schermo_il_simulato_resta_permesso():
	assert_false(Main.blocca_simulato(true, false), "headless: test e console devono girare")

func test_col_motore_vero_non_si_blocca_nulla():
	assert_false(Main.blocca_simulato(false, true))
	assert_false(Main.blocca_simulato(false, false))

## Guardia effettiva: in headless (dove girano i test) non deve MAI scattare, altrimenti
## si bloccherebbero da soli.
func test_la_guardia_non_scatta_nei_test():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_false(ui._simulato_blocca(), "i test girano sul mock: non devono autobloccarsi")

## Salvare e riprendere dall'interfaccia. Il codice per farlo esisteva da sempre in
## GameManager e non era collegato a niente: una partita dura ~76 turni, e perderla
## chiudendo la finestra e' una perdita vera.
func test_la_partita_si_salva_e_si_riprende_dalla_gui():
	LLMManager.mock_mode = true
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	GameManager.vai_a_tappa("ciclope")
	ui._input.text = "Sono io, Odisseo, che t'ho accecato!"
	await ui._on_agisci()
	var turno: int = GameManager.stato.turno

	ui._on_menu_partita(Main.VOCE_SALVA)
	assert_string_contains(ui._narrazione.get_parsed_text(), "salvata")

	GameManager.nuova_partita(1)          # si perde tutto…
	await ui._on_menu_partita(Main.VOCE_CARICA)   # …e si riprende
	assert_eq(GameManager.stato.turno, turno, "si riparte da dove si era")
	assert_string_contains(ui._narrazione.get_parsed_text(), "ripresa")
	# Il diario di bordo non e' piu' a schermo (v2.34), ma i DATI restano: li usa il
	# salvataggio, e Omero per ricordare cos'e' successo. Sparire dall'interfaccia non
	# vuol dire sparire dallo stato.
	assert_gt(GameManager.stato.diario.size(), 0, "il diario resta nello stato salvato")

## La scheda dei COSTI in Settings. I limiti nati per risparmiare chiamate ora si vedono e
## si scelgono: prima erano costanti sparse nel codice, e chi giocava con un piano a
## pagamento li subiva senza modo di accorgersene.
func test_settings_ha_la_scheda_dei_costi():
	var f := FinestraImpostazioni.new()
	add_child_autofree(f)
	await wait_frames(2)
	var schede: TabContainer = null
	for n in f.find_children("*", "TabContainer", true, false):
		schede = n
	assert_not_null(schede, "Settings dev'essere a schede")
	assert_eq(schede.get_tab_count(), 2, "modelli e costi")
	assert_not_null(f._costi_box, "il pannello dei costi dev'essere costruito")
	# Un controllo per ogni limite dichiarato: se un limite si aggiunge ai dati, il pannello
	# lo mostra da solo — non c'e' un elenco da tenere allineato a mano.
	assert_gte(f._costi_box.get_child_count(), Costi.descrittori().size())

# --- Il Log LLM: uno strumento di diagnosi, non una vista di gioco ---

## IL LOG NASCE CHIUSO, sempre. Si apriva da solo in due modi: se era aperto all'ultima
## uscita (geometria salvata) e ogni volta che si attivavano i dei veri — cioe' a ogni avvio
## con il motore reale in preferenza. La prima cosa che si vedeva del gioco era una finestra
## di traffico HTTP davanti alla narrazione.
func test_il_log_llm_nasce_chiuso():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	assert_false(ui._fin_log.visible, "il Log e' uno strumento: si apre quando serve")
	assert_false(ui._btn_log.button_pressed, "e la spunta di View deve dirlo")

## L'altra meta' della stessa decisione, nel posto dove si puo' verificare senza schermo: la
## geometria ricorda DOVE era la finestra, non SE era aperta. Finche' quel dato esisteva,
## bastava che qualcuno tornasse a leggerlo perche' il difetto rinascesse.
func test_la_geometria_ricorda_dove_non_se():
	var prima: Variant = Impostazioni.leggi("finestre", null)
	Impostazioni.salva_geometria("prova_test", Vector2i(11, 22), Vector2i(640, 480))
	var g := Impostazioni.geometria("prova_test")
	assert_eq(g["pos"], Vector2i(11, 22), "la posizione si ricorda")
	assert_eq(g["dim"], Vector2i(640, 480), "e la dimensione")
	assert_false(g.has("aperta"), "se fosse aperta non e' un dato che qualcuno deve poter leggere")
	if prima == null:
		Impostazioni.dimentica("finestre")
	else:
		Impostazioni.scrivi("finestre", prima)

# --- Un guaio col motore: una finestra, non una riga in fondo al racconto ---

## LA NARRAZIONE CONTIENE SOLO LA NARRAZIONE. Ogni esito del motore — riuscita compresa —
## finiva in coda al testo di Omero: «[modalità Mistral: dèi e narratore reali…]» compariva a
## ogni avvio, cioe' quasi sempre quando non c'era niente da dire, e la prima riga del gioco
## era un rapporto tecnico dentro il poema.
func test_la_narrazione_non_annuncia_il_motore():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	var t: String = ui._narrazione.get_parsed_text().to_lower()
	for parola in ["modalità", "modalita", "narratore reali", "guarda il log"]:
		assert_false(t.contains(parola),
			"«%s» e' un rapporto tecnico: non appartiene al racconto" % parola)

## E il messaggio non esiste piu' nemmeno nei testi: finche' la chiave resta, basta che
## qualcuno torni a usarla.
## Si chiede a `Testi.ha()`, non a `Testi.s()`: quello ritorna il PERCORSO quando la voce
## manca, ed e' esattamente l'errore contro cui la sua docstring mette in guardia.
func test_il_messaggio_di_riuscita_non_esiste_piu():
	assert_false(Testi.ha("motore/attivo"),
		"la voce e' stata tolta: un motore che funziona non e' una notizia")

## Il guaio ferma il giocatore con una finestra, e la finestra porta dove si aggiusta.
func test_un_guaio_apre_un_popup_col_bottone_per_settings():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._guaio_motore("Il provider non risponde.")
	assert_not_null(ui._dlg_guaio, "dev'esserci una finestra, non una riga di testo")
	assert_string_contains(ui._dlg_guaio.dialog_text, "Il provider non risponde.")
	# Il «dove guardare» e' comune a tutti i guai e non si ripete nei singoli messaggi.
	assert_string_contains(ui._dlg_guaio.dialog_text, "Settings")
	var etichette: Array = []
	for b in ui._dlg_guaio.get_ok_button().get_parent().get_children():
		if b is Button:
			etichette.append(b.text)
	assert_true(etichette.has(Testi.s("motore/apri_settings")),
		"un bottone che APRE Settings, non un consiglio di cercarlo (trovati: %s)" % str(etichette))

## Premere Agisci senza motore e' il momento in cui il guaio si sente: hai scritto, e non
## succede niente. Li' la finestra serve piu' che mai — e la narrazione resta pulita.
func test_agire_senza_motore_apre_il_popup_e_non_sporca_la_narrazione():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	var prima: String = ui._narrazione.get_parsed_text()
	# _simulato_blocca() e' falso in headless (o i test si bloccherebbero da soli): si prova
	# la strada, non l'interruttore.
	ui._guaio_motore(Testi.s("motore/serve_un_motore"))
	assert_true(ui._dlg_guaio.visible, "la finestra si apre")
	assert_eq(ui._narrazione.get_parsed_text(), prima, "e il racconto non cresce di una riga")

# --- Il menu Aiuto ---

## Le regole del gioco erano solo nei documenti: chi apre il gioco e non il repository non
## aveva modo di sapere che gli dei dormono, che i tre appigli non sono le uniche mosse, che
## parlare alla ciurma non fa avanzare il turno. Sono le REGOLE — non appartengono a un file.
func test_c_e_un_menu_aiuto_con_regole_e_faq():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	var barra: MenuBar = null
	for n in ui.find_children("*", "MenuBar", true, false):
		barra = n
	assert_not_null(barra, "la barra dei menu dev'esserci")
	var menu: PopupMenu = null
	for i in barra.get_child_count():
		var p := barra.get_child(i)
		if p is PopupMenu and p.name == Testi.s("menu/aiuto"):
			menu = p
	assert_not_null(menu, "dev'esserci un menu «%s»" % Testi.s("menu/aiuto"))
	var voci: Array = []
	for i in menu.item_count:
		voci.append(menu.get_item_id(i))
	for atteso in [Main.VOCE_REGOLE, Main.VOCE_FAQ, Main.VOCE_REPO]:
		assert_true(voci.has(atteso), "manca la voce %d in Aiuto" % atteso)

## Una pagina d'aiuto: il testo c'e', e finisce col rimando ai documenti veri.
func test_una_pagina_di_aiuto_si_apre_e_rimanda_ai_documenti():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._on_menu_aiuto(Main.VOCE_REGOLE)
	assert_not_null(ui._dlg_aiuto)
	assert_true(ui._dlg_aiuto.visible)
	assert_string_contains(ui._testo_aiuto.text, "Ulisse")
	assert_string_contains(ui._testo_aiuto.text, "COME_GIOCARE.md",
		"il gioco non contiene il manuale: lo indica")

## La stessa finestra serve tutte le voci: due finestre gemelle divergono su cio' che si
## dimentica di copiare.
func test_le_pagine_di_aiuto_condividono_una_finestra_sola():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._on_menu_aiuto(Main.VOCE_REGOLE)
	var prima = ui._dlg_aiuto
	var testo_regole: String = ui._testo_aiuto.text
	ui._on_menu_aiuto(Main.VOCE_FAQ)
	assert_eq(ui._dlg_aiuto, prima, "una finestra sola, riempita di volta in volta")
	assert_ne(ui._testo_aiuto.text, testo_regole, "e il contenuto cambia davvero")

## IL TESTO DEVE SCORRERE. Con il testo dentro `dialog_text` il riquadro cresce quanto serve
## e non guarda lo schermo: le regole chiedevano 972 px su una finestra di 1033, e su un
## portatile piu' corto i bottoni sarebbero finiti sotto il bordo — senza modo di chiudere.
func test_la_pagina_di_aiuto_scorre_invece_di_crescere():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._on_menu_aiuto(Main.VOCE_REGOLE)
	var scorre := false
	for n in ui._dlg_aiuto.find_children("*", "ScrollContainer", true, false):
		scorre = true
	assert_true(scorre, "il testo lungo sta in un ScrollContainer, non nel dialogo nudo")
	assert_eq(ui._dlg_aiuto.dialog_text, "",
		"il testo NON e' in dialog_text: sarebbe quello a far crescere la finestra")

## L'unico indirizzo che il gioco apra e' una COSTANTE. Il giorno in cui lo si componesse da
## un dato — peggio, da cio' che dice un modello — OS.shell_open diventerebbe un modo per
## far aprire al giocatore qualcosa che non ha scelto.
func test_l_indirizzo_del_repository_e_una_costante_https():
	assert_true(Main.REPOSITORY.begins_with("https://github.com/"),
		"un solo indirizzo, fisso e in chiaro: %s" % Main.REPOSITORY)
