extends GutTest

## LA COLONNA SONORA: un brano per momento del gioco, in data/musica.json.
##
## Il rischio qui non e' il codice, e' la TABELLA. Un momento scritto con un id che non
## corrisponde a nessun capitolo non fa rumore: semplicemente quel brano non suona mai, e
## chi l'ha configurato pensa che il file sia rotto. Questi test sorvegliano la
## corrispondenza fra i due elenchi, nei due sensi.

const SPECIALI := ["splash", "traversata", "fine_morte", "fine_prigionia_eterna", "fine_itaca"]

var _cs: ColonnaSonora

func before_each():
	_cs = ColonnaSonora.new()
	add_child_autofree(_cs)

# --- La tabella regge i due elenchi ---

## Un momento che non e' ne' un capitolo ne' un momento speciale non suonera' mai, e
## nessuno se ne accorgera'.
func test_ogni_momento_e_un_capitolo_o_uno_speciale():
	var capitoli: Array = GameManager.episodi.ordine()
	for m in _cs.momenti():
		if SPECIALI.has(m):
			continue
		assert_true(capitoli.has(m),
			"«%s» in musica.json non e' un capitolo: quel brano non suonera' mai" % m)

## E il contrario: un capitolo nuovo senza la sua riga resterebbe muto per sempre, e la
## mancanza non si vedrebbe da nessuna parte.
func test_ogni_capitolo_ha_il_suo_momento():
	var momenti := _cs.momenti()
	for id in GameManager.episodi.ordine():
		assert_true(momenti.has(id), "il capitolo «%s» non ha una riga in musica.json" % id)

## I finali dichiarati devono avere un momento: e' l'ultima cosa che si ascolta.
func test_i_finali_hanno_il_loro_momento():
	for m in SPECIALI:
		assert_true(_cs.momenti().has(m), "manca il momento «%s»" % m)

# --- La risoluzione dei file ---

## Il brano dell'apertura c'e' davvero, ed e' un percorso vero sul disco. Se `brano()`
## tornasse un percorso che non esiste, lo splash resterebbe muto in silenzio.
func test_lo_splash_ha_un_brano_esistente():
	var b := _cs.brano("splash")
	assert_ne(String(b["file"]), "", "lo splash deve avere un brano configurato")
	assert_true(FileAccess.file_exists(String(b["file"])), "il file dello splash non c'e'")

## Non cicla: la schermata si congeda tre secondi dopo l'ultima nota, e un brano che
## ricomincia la terrebbe li' per sempre.
func test_lo_splash_non_cicla():
	assert_false(bool(_cs.brano("splash")["ciclo"]))

## Un momento senza brano non e' un errore: deve dare "" senza lamentarsi.
##
## NON si nomina un capitolo preciso. La cartella `music/` e' di chi gioca e col tempo si
## riempira': un test scritto su «troia e' muto» diventerebbe rosso il giorno in cui qualcuno
## posa troia.mp3, e sarebbe il test a sbagliare, non lui. Si cerca un momento che sia muto
## adesso, qualunque esso sia.
func test_un_momento_senza_brano_da_stringa_vuota():
	var muto := ""
	for m in _cs.momenti():
		if String(_cs.brano(m)["file"]) == "":
			muto = m
			break
	if muto == "":
		pass_test("tutti i momenti hanno un brano: non c'e' niente da verificare qui")
		return
	assert_eq(String(_cs.brano(muto)["file"]), "")
	assert_false(_cs.suona(muto), "un momento muto non suona, e lo dice")

# --- La convenzione: il file che si chiama come il momento ---

## LA DOMANDA NATURALE di chi aggiunge una musica e' «basta metterla nella cartella?», e la
## risposta dev'essere si'. Un file chiamato come il momento si trova senza scrivere niente
## nella tabella. Il file di prova si crea e si cancella qui: la cartella `music/` e' di chi
## gioca, e un test non deve lasciarci dentro roba sua.
func test_un_file_chiamato_come_il_momento_si_trova():
	var dove := _cartella_music()
	var finto := dove.path_join("ciconi.mp3")
	_deposita(finto)
	var cs2 := ColonnaSonora.new()   # rilegge la cartella
	add_child_autofree(cs2)
	assert_eq(cs2.brano("ciconi")["file"], finto,
		"un file chiamato come il momento deve bastare")
	DirAccess.remove_absolute(finto)

## Su macOS il disco non distingue le maiuscole, su Linux si'. Un brano che suona su una
## macchina e tace sull'altra e' il genere di differenza che fa perdere un pomeriggio.
func test_la_convenzione_ignora_le_maiuscole():
	var dove := _cartella_music()
	var finto := dove.path_join("Lotofagi.MP3")
	_deposita(finto)
	var cs2 := ColonnaSonora.new()
	add_child_autofree(cs2)
	assert_eq(cs2.brano("lotofagi")["file"], finto)
	DirAccess.remove_absolute(finto)

## La tabella VINCE: lo splash ha un file suo (Intro.mp3) e non deve farsi scavalcare da un
## `splash.mp3` posato li' per caso.
func test_la_tabella_vince_sulla_convenzione():
	var dove := _cartella_music()
	var finto := dove.path_join("splash.mp3")
	_deposita(finto)
	var cs2 := ColonnaSonora.new()
	add_child_autofree(cs2)
	assert_ne(cs2.brano("splash")["file"], finto, "il nome scritto nella tabella comanda")
	assert_true(String(cs2.brano("splash")["file"]).ends_with("Intro.mp3"))
	DirAccess.remove_absolute(finto)

## La convenzione vale solo per i momenti DICHIARATI: la tabella resta l'elenco di cosa
## esiste, altrimenti un file con un nome sbagliato sembrerebbe funzionare.
func test_la_convenzione_non_inventa_momenti():
	var dove := _cartella_music()
	var finto := dove.path_join("momento_inventato.mp3")
	_deposita(finto)
	var cs2 := ColonnaSonora.new()
	add_child_autofree(cs2)
	assert_eq(String(cs2.brano("momento_inventato")["file"]), "")
	DirAccess.remove_absolute(finto)

func _cartella_music() -> String:
	return ProjectSettings.globalize_path("res://music")

## Un file minimo: al controllo serve che ESISTA, non che sia un brano vero.
func _deposita(percorso: String) -> void:
	var f := FileAccess.open(percorso, FileAccess.WRITE)
	f.store_string("non e' musica")
	f.close()

## Un momento inventato non deve far esplodere niente: la musica e' un ornamento.
func test_un_momento_inesistente_e_muto():
	assert_eq(String(_cs.brano("non_esiste_questo")["file"]), "")
	assert_false(_cs.suona("non_esiste_questo"))

## Il volume del momento si somma a quello generale: la manopola grossa resta una sola.
func test_il_volume_si_somma():
	var generale := float(JSON.parse_string(
		FileAccess.get_file_as_string(ColonnaSonora.CONFIG)).get("volume_db", 0.0))
	assert_almost_eq(float(_cs.brano("splash")["volume_db"]), generale, 0.001)

## Un file nominato e MANCANTE deve risolversi a "", non a un percorso che non esiste:
## e' la differenza fra «muto» e «rotto piu' tardi, dentro il caricatore».
func test_un_file_mancante_si_risolve_a_vuoto():
	assert_eq(_cs._percorso("questo_brano_non_esiste.mp3"), "")

## Il caricamento avviene dal DISCO, senza importatore: e' cio' che permette di posare un
## mp3 in music/ e sentirlo senza riaprire l'editor. Se un giorno smettesse di funzionare,
## la musica sparirebbe senza un errore.
func test_il_brano_si_carica_dal_disco():
	var s := ColonnaSonora._carica(String(_cs.brano("splash")["file"]))
	assert_not_null(s, "AudioStreamMP3.load_from_file non ha caricato il brano")
	assert_gt(s.get_length(), 1.0, "un brano di durata nulla e' un file non letto")
