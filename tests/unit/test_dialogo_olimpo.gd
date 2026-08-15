extends GutTest

## GLI DEI DEVONO PARLARSI, non deporre uno dopo l'altro.
##
## Nella Vista Olimpo si leggeva una fila di dichiarazioni e poi «prevale Atena: aiuto» —
## un verbale, non una conversazione. Due difetti distinti:
##
##  1. il round di REPLICHE partiva solo in caso di conflitto: se due dèi la pensavano
##     uguale, o se uno solo si destava con un altro presente, nessuno ribatteva;
##  2. Zeus PRODUCE GIA' una battuta da sovrano che chiude la contesa («dice» nel suo
##     verdetto) e il codice la buttava via per scrivere «prevale X: Y».

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(2024)
	GameManager.stato.eventi_accaduti.append("maledizione_di_polifemo")

# --- 1. Si ribatte anche senza litigare ---

## Il dialogo si misura nella CHAT, non nell'array delle posizioni finali: `deliberazione`
## registra dove ognuno e' arrivato, mentre la conversazione e' la sequenza di battute.
func test_due_dei_desti_si_ribattono_anche_se_d_accordo():
	GameManager.vai_a_tappa("ciclope")
	var esito: Dictionary = await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	assert_gte(esito["svegli"].size(), 2, "servono due dèi in campo")
	assert_gt(_battute_di_dei(), esito["svegli"].size(),
		"oltre alla prima presa di posizione ci devono essere le repliche: e' quello il dialogo")

## Con un dio solo non c'e' con chi parlare: nessuna replica, nessuna chiamata sprecata.
## «nessuno» e' la mossa dell'astuzia: a Troia sveglia la sola Atena.
func test_un_dio_solo_non_parla_da_solo():
	var esito: Dictionary = await GameManager.esegui_turno("Dico di chiamarmi Nessuno.")
	assert_eq(esito["svegli"].size(), 1, "qui si desta solo Atena")
	assert_eq(_battute_di_dei(), 1, "senza interlocutore non si replica")

## Quante battute («voce») hanno detto gli dèi nell'Olimpo, escluse le righe di servizio.
func _battute_di_dei() -> int:
	var n := 0
	for m in GameManager.agora.canali[Agora.CANALE_OLIMPO]["messaggi"]:
		if String(m["tipo"]) == "voce":
			n += 1
	return n

## Il costo e' limitato: le repliche non possono moltiplicarsi con gli dèi in campo.
func test_le_repliche_hanno_un_tetto():
	assert_lte(GameManager.MAX_REPLICHE, 2,
		"ogni replica e' una chiamata: il dialogo non puo' costare quanto vuole")

# --- 2. Il verdetto e' romanzato ---

func test_il_verdetto_arbitrato_usa_le_parole_di_zeus():
	GameManager.vai_a_tappa("ciclope")
	GameManager.prob_coalizione = 0.0
	await GameManager.esegui_turno("Mi vanto della mia astuzia davanti a tutti")
	var t := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	assert_false(t.contains("prevale "), "niente verbale: la contesa la chiude una voce")

func test_il_verdetto_non_arbitrato_non_e_un_referto():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	var t := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	assert_false(t.contains(": castigo"), "il registro e' roba da traccia tecnica, non da chat")

## Ma la traccia tecnica deve continuare a dirlo, senza giri di parole: e' lo strumento.
func test_la_traccia_tecnica_resta_esplicita():
	GameManager.vai_a_tappa("ciclope")
	var esito: Dictionary = await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	assert_string_contains(TraceFormatter.turno(esito["voce"]), "Verdetto:")

## Il motore segnala gli stati intermedi senza mutare la chat persistente.
func test_il_progresso_olimpo_arriva_prima_di_omero_e_non_si_salva():
	GameManager.vai_a_tappa("ciclope")
	var fasi: Array[String] = []
	var fotografie: Array[String] = []
	var ascolta := func(fase: String, dati: Dictionary):
		fasi.append(fase)
		fotografie.append(String(dati.get("trascrizione", "")))
	GameManager.progresso_turno.connect(ascolta)
	await GameManager.esegui_turno("Sono io, Odisseo, che tho accecato!")
	GameManager.progresso_turno.disconnect(ascolta)
	assert_ne(fasi.find("risvegli"), -1, "il risveglio deve avere un suo stato intermedio")
	assert_ne(fasi.find("narrazione"), -1, "Omero resta lultimo passaggio visuale")
	assert_lt(fasi.find("risvegli"), fasi.find("narrazione"),
		"la Vista Olimpo si aggiorna prima della narrazione")
	assert_lt(fasi.find("attesa"), fasi.find("battuta"),
		"ogni risposta e preceduta dallautore che sta rispondendo")
	for foto in fotografie:
		assert_false(foto.contains("sta rispondendo"),
			"lindicatore e della GUI, non della trascrizione persistente")
	assert_false(JSON.stringify(GameManager.agora.to_dict()).contains("sta rispondendo"),
		"Agora non conserva indicatori fra i dati della partita")
