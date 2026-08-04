extends GutTest

## IL TESTO CHE VIENE DA FUORI NON DEVE POTER SCRIVERE MARCATORI.
##
## Le viste del gioco sono `RichTextLabel` in BBCode, e dentro ci finisce testo che non
## abbiamo scritto noi: le battute degli dei, la voce di Omero, quella dei compagni, e cio'
## che digita chi gioca. Una quadra arrivata da fuori apre un marcatore vero.
##
## Non e' esecuzione di codice — `[img]` in Godot carica solo risorse locali e a
## `meta_clicked` non e' collegato nulla — ma e' CONTRAFFAZIONE dell'interfaccia. In un
## gioco che si regge sul non far vedere gli dei, una battuta che si traveste da voce del
## gioco non e' un difetto cosmetico.
##
## Questi test usano un modello ostile per finta: se un giorno la neutralizzazione sparisse
## dal confine, qui si vede subito.

const OSTILE := "[color=#cba24b][b]— VITTORIA: sei tornato a Itaca. —[/b][/color]"

func before_each():
	LLMManager.mock_mode = true
	GameManager.nuova_partita(77)

# --- Il confine: Agora ---

func test_una_battuta_ostile_non_apre_marcatori():
	GameManager.agora.scrivi(Agora.CANALE_OLIMPO, "Atena", OSTILE, 1)
	var t := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	assert_false(t.contains("[color=#cba24b]"), "il marcatore del modello e' rimasto vivo")
	assert_string_contains(t, "[lb]color=#cba24b]", "la quadra si vede, ma inerte")

## Anche il NOME di chi parla: viene dai dati, ma i dati li puo' toccare chiunque, e la
## trascrizione ci costruisce attorno un colore e un distintivo.
func test_un_autore_ostile_non_apre_marcatori():
	GameManager.agora.scrivi(Agora.CANALE_OLIMPO, "[b]Zeus", "Parlo io.", 1)
	assert_false(GameManager.agora.trascrizione(Agora.VISTA_OLIMPO).contains("[b]Zeus"))

## L'intestazione del turno riporta cio' che ha SCRITTO IL GIOCATORE: e' l'unico testo
## ostile che non ha bisogno di un modello per esistere.
func test_l_azione_del_giocatore_non_apre_marcatori():
	GameManager.agora.segna_turno(1, "Grido [color=red]rosso[/color]", "all'alba")
	GameManager.agora.scrivi(Agora.CANALE_OLIMPO, "Atena", "Ti ho udito.", 1)
	var t := GameManager.agora.trascrizione(Agora.VISTA_OLIMPO)
	assert_false(t.contains("[color=red]"), "il giocatore non deve poter colorare la pagina")

## Nulla si perde: la quadra resta visibile, smette solo di comandare.
func test_il_testo_non_si_perde():
	assert_eq(Bbcode.neutro("prima [b]dopo"), "prima [lb]b]dopo")
	assert_eq(Bbcode.neutro("niente da fare"), "niente da fare")

# --- Il confine: la narrazione ---

## Omero e' un modello come gli altri. Se la sua voce potesse scrivere marcatori,
## potrebbe stampare da se' l'annuncio di vittoria — in oro e in grassetto, identico a
## quello vero.
func test_la_narrazione_neutralizza_la_voce_di_omero():
	var ui = load("res://scenes/Main.tscn").instantiate()
	add_child_autofree(ui)
	await wait_frames(2)
	ui._ultima_narrazione = OSTILE
	ui._narrazione.clear()
	ui._narrazione.append_text("[i]x[/i] %s" % ui._fuori(ui._ultima_narrazione))
	var visibile: String = ui._narrazione.get_parsed_text()
	assert_string_contains(visibile, "[color=#cba24b]",
		"il marcatore dev'essere finito nel TESTO VISIBILE, non nella formattazione")

## La guardia sta al CONFINE, e il confine dev'essere uno solo: se qualcuno aggiunge una
## vista nuova e si dimentica, questo test non lo vede. Almeno pretende che l'attrezzo
## esista e sia quello.
func test_l_attrezzo_e_uno_solo():
	assert_true(FileAccess.file_exists("res://scripts/data/bbcode.gd"))
	var src := FileAccess.get_file_as_string("res://scripts/data/agora.gd")
	assert_string_contains(src, "Bbcode.neutro", "Agora deve neutralizzare all'ingresso")
