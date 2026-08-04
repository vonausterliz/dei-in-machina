extends GutTest

## «QUESTO MODELLO GIRA SU QUESTA MACCHINA?»
##
## Il verdetto accanto a ogni modello di Ollama. La regola è una funzione pura, così si può
## provare su un hardware che non ho davanti: 12 GB di scheda e 60 di RAM sono i numeri del
## PC su cui è nata, ma i test devono valere anche per un portatile da 8.

const GB := 1_073_741_824

# I numeri veri della macchina in cui è nata la funzione.
const VRAM := 12.0
const RAM := 60.0

func _giudica(gb: float, fallimento := "") -> Dictionary:
	return VerdettoModello.giudica(int(gb * GB), VRAM, RAM, fallimento)

# --- Le tre fasce ---

## deepseek-r1 è 4,7 GB: con il margine servono ~5,9 GB, e la scheda ne ha 12.
func test_un_modello_che_sta_nella_scheda_e_verde():
	var v := _giudica(4.7)
	assert_eq(v["segno"], VerdettoModello.OK)
	assert_string_contains(String(v["motivo"]), "bene")

## mixtral è 26,4 GB: fuori dalla scheda, dentro la RAM. Parte, ma diviso con la CPU.
func test_un_modello_che_sta_solo_in_ram_e_arancione():
	var v := _giudica(26.4)
	assert_eq(v["segno"], VerdettoModello.LIMITE)
	assert_string_contains(String(v["motivo"]), "lento")

## Oltre la RAM il sistema andrebbe in swap: non è lentezza, è un blocco.
func test_un_modello_piu_grosso_della_ram_e_rosso():
	var v := _giudica(80.0)
	assert_eq(v["segno"], VerdettoModello.NO)

## Il margine conta: un modello che «ci sta al pelo» non ci sta. Con 12 GB di scheda, il
## limite verde è a 12 × 0,92 / 1,25 ≈ 8,8 GB di file.
func test_il_margine_per_il_contesto_e_dentro_il_conto():
	assert_eq(_giudica(8.0)["segno"], VerdettoModello.OK, "8 GB stanno")
	assert_eq(_giudica(11.5)["segno"], VerdettoModello.LIMITE,
		"11,5 GB di file ne vogliono 14 con il contesto: nella scheda non ci stanno")

func test_il_verdetto_dice_quanti_gb_servono():
	var v := _giudica(10.0)
	assert_almost_eq(float(v["gb_servono"]), 12.5, 0.1, "10 GB di file + un quarto")

# --- Il fatto batte la previsione ---

## IL CASO CHE HA FATTO NASCERE TUTTO QUESTO. Su questa macchina mistral-small3.2 occupa
## 15 GB su 60 di RAM: in memoria ci starebbe comodo, e la stima direbbe «arancione, lento».
## Ma NON parte, perché Ollama 0.5.11 non lo conosce. Una spunta verde — o anche solo un
## giallo — su un modello che non si avvia è peggio di nessun segno.
func test_un_fallimento_gia_misurato_vince_sulla_stima():
	var senza := _giudica(15.0)
	assert_eq(senza["segno"], VerdettoModello.LIMITE, "la sola stima direbbe: ci sta, lento")
	var con := _giudica(15.0, "this model is not supported by your version of Ollama")
	assert_eq(con["segno"], VerdettoModello.NO, "ma è stato provato, e non parte")
	assert_string_contains(String(con["motivo"]), "version of Ollama",
		"il motivo vero dev'essere sotto gli occhi, non riassunto")

## E vale anche per un modello piccolissimo: la memoria non c'entra niente.
func test_il_fallimento_vince_anche_su_un_modello_minuscolo():
	assert_eq(_giudica(0.5, "404 model not found")["segno"], VerdettoModello.NO)

# --- Quello che non si sa ---

## Un modello non installato non ha una dimensione: non si giudica, si dice che manca.
func test_un_modello_non_installato_non_si_giudica():
	var v := _giudica(0.0)
	assert_eq(v["segno"], VerdettoModello.IGNOTO)
	assert_string_contains(String(v["motivo"]), "ollama pull")

## Senza sapere quanta memoria ha la scheda non si può promettere che vada veloce, ma
## nemmeno accusare la VRAM: si dice quello che si sa e si tace il resto.
func test_senza_vram_nota_si_giudica_sulla_sola_ram_dicendolo():
	var v := VerdettoModello.giudica(int(20.0 * GB), 0.0, RAM)
	assert_eq(v["segno"], VerdettoModello.LIMITE)
	assert_string_contains(String(v["motivo"]), "scheda video")
	assert_eq(VerdettoModello.giudica(int(80.0 * GB), 0.0, RAM)["segno"], VerdettoModello.NO,
		"la RAM basta da sola a dire di no")

# --- Il segno ---

## Il colore non basta: chi non distingue il verde dal rosso deve leggere lo stesso il
## verdetto. Per questo il simbolo sta nel testo e il colore nell'icona.
func test_ogni_segno_ha_un_simbolo_e_un_colore_suoi():
	var simboli: Array = []
	var colori: Array = []
	for s in [VerdettoModello.OK, VerdettoModello.LIMITE, VerdettoModello.NO, VerdettoModello.IGNOTO]:
		var sim := VerdettoModello.simbolo(s)
		assert_false(simboli.has(sim), "«%s» ripete un simbolo già usato" % s)
		simboli.append(sim)
		colori.append(VerdettoModello.colore(s).to_html())
	assert_eq(colori.size(), 4)
	for c in colori:
		assert_eq(colori.count(c), 1, "due segni con lo stesso colore non si distinguono")

# --- L'hardware vero ---

## Non si verifica QUANTA memoria ha questa macchina (cambia da macchina a macchina): si
## verifica che il gioco riesca a leggerla, perché senza quel numero il verdetto non esiste.
func test_la_ram_si_riesce_sempre_a_leggere():
	Hardware.dimentica()
	assert_gt(Hardware.ram_gb(), 0.5, "OS.get_memory_info() deve dare i byte fisici")

## La VRAM può non esserci (nessuna scheda, nessun nvidia-smi): l'importante è che la
## risposta sia onesta invece di una cifra inventata.
func test_la_vram_o_si_sa_o_si_dice_che_non_si_sa():
	Hardware.dimentica()
	var v := Hardware.vram_gb()
	assert_true(v == 0.0 or v > 0.5, "o zero (ignota) o un numero sensato, mai una via di mezzo")
	assert_eq(Hardware.vram_nota(), v > 0.0)

func test_la_descrizione_dice_i_numeri_che_ha():
	Hardware.dimentica(60.0, 12.0)
	assert_string_contains(Hardware.descrizione(), "12")
	assert_string_contains(Hardware.descrizione(), "60")
	Hardware.dimentica(60.0, 0.0)
	assert_string_contains(Hardware.descrizione().to_lower(), "scheda")
	Hardware.dimentica()   # rimettere la misura vera: è stato globale
