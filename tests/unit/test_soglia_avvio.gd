extends GutTest

## LA SOGLIA — e il difetto di ordine che l'aveva resa inutile.
##
## Segnalazione: «come vedi dal file screenshot_avvio.jpg c'è già l'inizio della partita, sono
## state scritte frasi di omero e ci sono già delle risposte proposte».
##
## Aveva ragione. La partita si avviava SOTTO la schermata d'apertura — un'ottimizzazione
## nata buona, per non far aspettare nessuno — e con l'arrivo della soglia e' diventata
## sbagliata: si vedeva il gioco rispondere a una domanda non ancora posta, e «Comincia da
## Troia» dopo aver letto l'inizio di Troia non voleva piu' dire niente.
##
## La parte visiva la prova `tools/foto_soglia.gd`, che avvia il gioco vero e conta i
## caratteri di narrazione dietro il dialogo. Qui si presidia cio' che si puo' provare senza
## occhi: la forma del referto, e che i tre casi producano tre dialoghi diversi.

var _serif: Font
var _grassetto: Font

func before_all():
	_serif = load("res://fonts/Cardo-Regular.ttf")
	_grassetto = load("res://fonts/Cardo-Bold.ttf")

func _dialogo(stato: Dictionary) -> DialogoAvvio:
	var d := DialogoAvvio.new(stato, _serif, _grassetto)
	autofree(d)
	return d

const SANO := {"ripresa": {}, "motore": "Ollama locale · mistral-small3.2", "audio": "", "guai": []}

## Il bottone «Riprendi» esiste SOLO se c'e' qualcosa da riprendere. Offrirlo sempre
## vorrebbe dire un bottone che a volte non fa niente, e un bottone che a volte non fa
## niente insegna a non fidarsi degli altri due.
func test_senza_salvataggio_non_si_offre_di_riprendere():
	var d := _dialogo(SANO)
	assert_false(_testo_bottoni(d).contains(Testi.s("avvio/riprendi")),
		"offre di riprendere una partita che non c'e'")
	assert_true(_testo_bottoni(d).contains(Testi.s("avvio/nuova")))
	assert_true(_testo_bottoni(d).contains(Testi.s("avvio/impostazioni")))

## …e quando c'e', porta con se' i DETTAGLI. «Riprendi la partita» da solo obbliga a
## fidarsi: quale partita, di quando? Con capitolo, turno e data la scelta si fa guardando.
func test_riprendere_dice_quale_partita():
	var d := _dialogo({"ripresa": {"episodio": "L'isola del ciclope", "turno": 34,
		"quando": "2026-08-05 09:12"}, "motore": "x", "audio": "", "guai": []})
	var t := _testo_bottoni(d)
	assert_true(t.contains(Testi.s("avvio/riprendi")))
	assert_true(t.contains("L'isola del ciclope"), "non dice a che punto si era")
	assert_true(t.contains("34"), "non dice il turno")

func test_il_referto_dice_motore_e_audio():
	var d := _dialogo(SANO)
	var t := _referto(d)
	assert_true(t.contains("Ollama locale"), "non dice con cosa si sta per giocare")
	assert_true(t.contains(Testi.s("avvio/audio_ok")))
	assert_true(t.contains(Testi.s("avvio/pronto")), "tutto a posto e non lo dice")

func test_un_audio_muto_si_vede():
	var d := _dialogo({"ripresa": {}, "motore": "x",
		"audio": Testi.s("avvio/audio_muto"), "guai": []})
	assert_true(_referto(d).contains("MUTO"),
		"l'audio non parte e la soglia non lo dice: il silenzio sembra una scelta")

func test_i_guai_si_elencano_e_si_dice_dove_andare():
	var d := _dialogo({"ripresa": {}, "motore": "x", "audio": "",
		"guai": ["Manca la chiave API per «Mistral»."]})
	var t := _referto(d)
	assert_true(t.contains(Testi.s("avvio/da_sistemare")))
	assert_true(t.contains("Manca la chiave API"))
	assert_false(t.contains(Testi.s("avvio/pronto")), "dice «tutto pronto» con un guaio aperto")

## UN GUAIO ARRIVATO DOPO finisce nel referto, non in un secondo dialogo.
##
## Godot non permette due finestre esclusive figlie dello stesso genitore: l'avviso del
## motore veniva INGHIOTTITO con un errore in console, e al primo avvio con una chiave
## sbagliata non compariva niente. L'ha trovato lo strumento di scatto, non un test — è un
## errore del motore grafico, non un'asserzione — e per questo adesso un test c'è.
func test_un_guaio_che_arriva_dopo_entra_nel_referto():
	var d := _dialogo(SANO)
	assert_true(_referto(d).contains(Testi.s("avvio/pronto")))
	d.aggiungi_guaio("Mistral non risponde.\nHTTP 401 · no api key provided")
	var t := _referto(d)
	assert_true(t.contains("Mistral non risponde"), "il guaio non e' arrivato nel referto")
	assert_false(t.contains(Testi.s("avvio/pronto")), "dice ancora «tutto pronto»")
	# Su una riga sola: gli a capo di un messaggio d'errore spezzerebbero l'elenco.
	assert_false(t.contains("risponde.\nHTTP"), "gli a capo non sono stati appianati")

## Lo stesso guaio due volte resta uno: la verifica del motore può ripetersi.
func test_lo_stesso_guaio_non_si_accumula():
	var d := _dialogo(SANO)
	for i in 3:
		d.aggiungi_guaio("sempre lo stesso")
	assert_eq(_referto(d).count("sempre lo stesso"), 1, "il referto si è riempito di doppioni")

# --- lettura ---

func _testo_bottoni(d: DialogoAvvio) -> String:
	var fuori: Array[String] = []
	for n in d.find_children("*", "Button", true, false):
		fuori.append(String((n as Button).text))
	# I bottoni col sottotitolo hanno il testo in due Label figlie, non in `text`.
	for n in d.find_children("*", "Label", true, false):
		fuori.append(String((n as Label).text))
	return "\n".join(fuori)

func _referto(d: DialogoAvvio) -> String:
	for n in d.find_children("*", "RichTextLabel", true, false):
		return String((n as RichTextLabel).text)
	return ""
