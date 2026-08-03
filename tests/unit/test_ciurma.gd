extends GutTest

## La ciurma: compagni con voce propria, interpellabili da Ulisse, che TACCIONO se muoiono.

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(77)

func test_roster_caricato_dal_file():
	assert_gte(GameManager.ciurma.compagni.size(), 6, "i compagni vengono da data/ciurma.json")
	assert_eq(GameManager.ciurma.get_compagno("euriloco")["nome"], "Euriloco")

func test_un_compagno_commenta_ogni_turno():
	await GameManager.esegui_turno("Sciolgo le vele.")
	var c: Dictionary = GameManager.agora.canali[Agora.CANALE_CIURMA]
	assert_gt(c["messaggi"].size(), 0, "qualcuno commenta")

func test_ulisse_puo_rivolgersi_a_uno_per_nome():
	await GameManager.esegui_turno("Euriloco, prepara i remi.")
	var messaggi: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"]
	var autori: Array = messaggi.map(func(m): return m["autore"])
	assert_has(autori, "Ulisse", "quando parla ai suoi, Ulisse compare in chat")
	assert_has(autori, "Euriloco", "risponde chi e' stato chiamato")

## Scrivere NELLA chat della ciurma significa gia' rivolgersi ai propri uomini: il canale
## e' il destinatario. Non serve chiamare qualcuno per nome perche' Ulisse si veda parlare.
func test_cio_che_ulisse_scrive_nella_chat_si_vede_sempre():
	await GameManager.esegui_beat("Coraggio, teniamo la rotta.")
	var autori: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"].map(
		func(m): return m["autore"])
	assert_has(autori, "Ulisse", "cio' che scrive nella chat della ciurma deve comparire")

## Un gesto compiuto nel gioco, invece, non e' una frase detta agli uomini: non va messo
## in bocca a Ulisse nella chat (li' commenta la ciurma, semmai).
func test_un_gesto_nel_gioco_non_diventa_una_battuta_di_ulisse():
	await GameManager.esegui_turno("Sguaino la spada e avanzo nell'antro.")
	var autori: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"].map(
		func(m): return m["autore"])
	assert_does_not_have(autori, "Ulisse", "un'azione non e' una battuta rivolta ai compagni")

func test_chi_muore_tace():
	# Antifo muore nel Ciclope: chiusa la tappa, la sua voce sparisce.
	assert_true(GameManager.ciurma.nomi_vivi().has("Antifo"))
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("fuggo dall'antro")   # tag fuga: chiude la tappa
	assert_false(GameManager.ciurma.nomi_vivi().has("Antifo"), "Antifo non parla piu'")
	assert_string_contains(GameManager.agora.trascrizione(Agora.VISTA_CIURMA), "non risponde")

func test_destinatari_riconosciuti_con_chiocciola():
	assert_eq(GameManager.ciurma.risolvi_destinatario("@euriloco"), "euriloco")
	assert_eq(GameManager.ciurma.risolvi_destinatario("Perimede"), "perimede")
	assert_eq(GameManager.ciurma.risolvi_destinatario("Zeus"), "", "non e' un compagno")

# --- BEAT: parlare ai compagni non fa girare il mondo ---

## Il punto del beat: costa una chiamata, non un turno. Se il turno avanzasse, tornerebbe
## tutta la macchina divina (nove chiamate) per ogni frase detta a bordo.
func test_il_beat_non_fa_avanzare_il_turno():
	var prima: int = GameManager.stato.turno
	await GameManager.esegui_beat("Coraggio, teniamo la rotta.")
	await GameManager.esegui_beat("Reggete i remi.")
	assert_eq(GameManager.stato.turno, prima, "il mondo non gira per due parole a bordo")

## ...ma le parole non si perdono: restano in sospeso per il prossimo turno vero.
func test_le_parole_restano_in_sospeso_e_poi_si_consegnano():
	await GameManager.esegui_beat("Domani mangeremo le vacche del Sole.")
	assert_eq(GameManager.stato.parole_ai_compagni.size(), 1, "in attesa del turno vero")
	await GameManager.esegui_turno("Scendo a riva.")
	assert_eq(GameManager.stato.parole_ai_compagni.size(), 0, "consegnate: il conto e' saldato")

## Il proposito detto a voce arriva all'Interprete insieme all'azione: cosi' i trigger
## scattano lo stesso e un dio puo' destarsi per cio' che Ulisse ha DETTO, non solo fatto.
func test_le_parole_arrivano_all_interprete_col_gesto():
	await GameManager.esegui_beat("Domani mangeremo le vacche del Sole.")
	var t: String = GameManager._testo_per_interprete("Scendo a riva.")
	assert_string_contains(t, "vacche del Sole", "il proposito viaggia con l'azione")
	assert_string_contains(t, "Scendo a riva.", "e l'azione resta")

## Due beat di fila non hanno lo stesso interlocutore: il giro di parola avanza.
func test_due_beat_di_fila_cambiano_interlocutore():
	await GameManager.esegui_beat("Chi di voi tiene il timone?")
	await GameManager.esegui_beat("E chi veglia a prua?")
	var messaggi: Array = GameManager.agora.canali[Agora.CANALE_CIURMA]["messaggi"]
	var voci: Array = messaggi.filter(func(m): return String(m["autore"]) != "Ulisse")
	assert_eq(voci.size(), 2, "hanno risposto in due")
	assert_ne(voci[0]["autore"], voci[1]["autore"], "non risponde sempre lo stesso")

## Ogni compagno deve avere il suo DIVIETO, come ce l'hanno gli dèi. E' la leva piu' forte
## per tenere una voce in carattere: senza, Perimede — che «esegue senza discutere» — si e'
## trovato a proporre alternative da consiglio di guerra.
func test_ogni_compagno_ha_il_suo_anti_pattern():
	for c in GameManager.ciurma.compagni:
		assert_false(String(c.get("anti_pattern", "")).is_empty(),
			"%s deve sapere cosa non direbbe mai" % c.get("nome", "?"))

func test_l_anti_pattern_entra_nel_prompt_del_compagno():
	var c: Dictionary = GameManager.ciurma.get_compagno("perimede")
	var sp := Compagno.new().system_prompt(c)
	assert_string_contains(sp, String(c["anti_pattern"]))
	assert_false(sp.contains("{{ANTI_PATTERN}}"), "il segnaposto va sostituito")
