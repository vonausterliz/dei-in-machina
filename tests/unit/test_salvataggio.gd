extends GutTest

## SALVARE E RIPRENDERE. Una partita dura ~76 turni e ~450 chiamate al modello: perderla
## chiudendo la finestra e' una perdita vera.
##
## `salva_partita` funzionava gia'. Era `carica_partita` a non reggere: rispetto a
## `nuova_partita` non ricostruiva `_politica` (crash alla PRIMA riga del turno dopo), ne'
## la ciurma, ne' i locali accesi della tappa. E due cose non erano nemmeno nel file: le
## chat dell'Agora e i compagni caduti — i morti sarebbero tornati in vita.
##
## Nessun test lo copriva: e' per questo che e' potuto marcire.

const PATH := "user://test_partita.json"

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(1234)

func after_each():
	# Un test non lascia tracce fuori da se'.
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

## Porta la partita a uno stato "vissuto": qualche turno, una chat, dei ricordi.
func _gioca_un_po() -> void:
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("Sono io, Odisseo, che t'ho accecato!")
	await GameManager.esegui_beat("Reggete i remi, e non fiatate.")

## Il caso che conta: si salva, si riprende, e si continua a giocare.
func test_ricaricare_e_proseguire_non_rompe_il_turno():
	await _gioca_un_po()
	assert_true(GameManager.salva_partita(PATH))
	var turno_salvato: int = GameManager.stato.turno

	GameManager.nuova_partita(999)          # un'altra partita, per sporcare tutto
	assert_true(GameManager.carica_partita(PATH))
	assert_eq(GameManager.stato.turno, turno_salvato)

	# Qui prima si schiantava: esegui_turno chiama _politica.resa_dei_conti() sulla prima
	# riga, e _politica era rimasta null.
	var esito := await GameManager.esegui_turno("Mi ritiro verso l'uscita dell'antro.")
	assert_eq(GameManager.stato.turno, turno_salvato + 1, "il gioco riparte da dov'era")
	assert_true(esito.has("voce"))

func test_i_moduli_ci_sono_tutti_dopo_il_caricamento():
	await _gioca_un_po()
	GameManager.salva_partita(PATH)
	GameManager.nuova_partita(999)
	GameManager.carica_partita(PATH)
	assert_not_null(GameManager.ciurma, "senza ciurma i compagni sparirebbero in silenzio")
	assert_not_null(GameManager.agora)
	assert_true(GameManager.agora.canali.has(Agora.CANALE_CIURMA),
		"il canale dei compagni deve esistere, o la chat sparisce")
	# PIU' INSIDIOSO DEL CRASH: i moduli sono oggetti che tengono un riferimento allo stato.
	# Se sopravvivono al caricamento continuano a lavorare sullo stato VECCHIO — niente
	# errore, e la politica divina scrive in una partita che non esiste piu'.
	assert_true(GameManager._politica.stato == GameManager.stato,
		"la politica divina deve lavorare sullo stato appena caricato")
	assert_true(GameManager._politica.agora == GameManager.agora,
		"…e scrivere nell'agora appena caricata")

## Le due chat sono meta' del gioco: riprendere con l'Olimpo vuoto sarebbe come riaprire
## un libro con le pagine bianche.
func test_le_chat_sopravvivono():
	await _gioca_un_po()
	var prima := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	var prima_ciurma := GameManager.agora.trascrizione(Agora.VISTA_CIURMA)
	GameManager.salva_partita(PATH)
	GameManager.nuova_partita(999)
	GameManager.carica_partita(PATH)
	assert_eq(GameManager.agora.trascrizione(Agora.VISTA_OLIMPO), prima)
	assert_eq(GameManager.agora.trascrizione(Agora.VISTA_CIURMA), prima_ciurma)

## JSON non ha chiavi intere: le intestazioni dei turni tornerebbero come "1", "2"… e
## nessuna combacerebbe piu' col numero del turno. Il collante fra le viste sparirebbe
## senza un errore.
func test_le_intestazioni_dei_turni_restano_interi():
	await _gioca_un_po()
	GameManager.salva_partita(PATH)
	GameManager.nuova_partita(999)
	GameManager.carica_partita(PATH)
	for k in GameManager.agora.intestazioni:
		assert_eq(typeof(k), TYPE_INT, "la chiave dell'intestazione dev'essere il turno")

func test_i_caduti_restano_caduti():
	GameManager.vai_a_tappa("ciclope")
	await GameManager.esegui_turno("fuggo dall'antro")   # chiude la tappa: Antifo cade
	assert_false(GameManager.ciurma.nomi_vivi().has("Antifo"))
	GameManager.salva_partita(PATH)
	GameManager.nuova_partita(999)
	GameManager.carica_partita(PATH)
	assert_false(GameManager.ciurma.nomi_vivi().has("Antifo"),
		"i morti non tornano in vita al caricamento")

## `attivo` sui locali e' un flag IN MEMORIA, non nel salvataggio: senza riaccenderlo,
## ricaricando dentro il Ciclope, Polifemo sarebbe spento e non reagirebbe piu'.
func test_i_locali_della_tappa_tornano_accesi():
	GameManager.vai_a_tappa("ciclope")
	GameManager.salva_partita(PATH)
	GameManager.nuova_partita(999)   # nuova_partita spegne tutti i locali
	GameManager.carica_partita(PATH)
	assert_true(PantheonManager.get_dio("polifemo").attivo,
		"il dio della tappa in cui si riprende dev'essere in ascolto")

## Riprendere non deve azzerare la tappa: i turni gia' spesi qui restano spesi (o a Ogigia
## si potrebbe restare per sempre salvando e ricaricando).
func test_il_conto_dei_turni_nella_tappa_non_si_azzera():
	GameManager.vai_a_tappa("ogigia")
	await GameManager.esegui_turno("Guardo il mare.")
	await GameManager.esegui_turno("Guardo il mare.")
	var spesi: int = int(GameManager.stato.viaggio["turni_in_episodio"])
	assert_gt(spesi, 0)
	GameManager.salva_partita(PATH)
	GameManager.nuova_partita(999)
	GameManager.carica_partita(PATH)
	assert_eq(int(GameManager.stato.viaggio["turni_in_episodio"]), spesi)

func test_la_voce_di_omero_prosegue():
	await _gioca_un_po()
	var ultima: String = GameManager._ultima_narrazione
	assert_false(ultima.is_empty())
	GameManager.salva_partita(PATH)
	GameManager.nuova_partita(999)
	GameManager.carica_partita(PATH)
	assert_eq(GameManager._ultima_narrazione, ultima,
		"Omero deve sapere cosa aveva appena raccontato")

func test_caricare_un_file_che_non_esiste_non_rompe_niente():
	assert_false(GameManager.carica_partita("user://non_esiste_proprio.json"))
	var esito := await GameManager.esegui_turno("Scendo a riva.")
	assert_true(esito.has("voce"), "la partita in corso resta giocabile")
