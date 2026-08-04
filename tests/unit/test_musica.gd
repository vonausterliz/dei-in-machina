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

## Un momento muto (oggi: tutti i capitoli) non e' un errore. Deve dare "" senza lamentarsi.
func test_un_momento_muto_da_stringa_vuota():
	assert_eq(String(_cs.brano("troia")["file"]), "")
	assert_false(_cs.suona("troia"), "un momento muto non suona, e lo dice")

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
