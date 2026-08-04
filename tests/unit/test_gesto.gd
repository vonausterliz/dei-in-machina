extends GutTest

## IL GESTO: cio' che un dio FA quando la sua volonta' passa.
##
## Nasce da un difetto visto giocando: la Vista Olimpo scriveva «Nessuno si oppone: la
## volonta' di Atena passa» — un narratore dentro una chat, che per giunta non diceva
## QUALE fosse la volonta'. Il registro (castigo, aiuto, segno, trappola) e' cio' che
## muove i numeri, e non arrivava mai a schermo.

const REGISTRI := ["castigo", "aiuto", "aiuto_negato", "segno", "trappola"]

# --- Il ripiego: c'e' per OGNI registro che produce un delta ---

## Se manca anche un solo ripiego, quel registro esce dalla chat in silenzio: il dio
## parla, agisce nei numeri, e a schermo non e' successo nulla.
func test_ogni_registro_attivo_ha_un_ripiego():
	for r in REGISTRI:
		for i in [1, 2, 3]:
			assert_ne(Gesto.ripiego(r, i), "", "manca il gesto %s/%d" % [r, i])

## Tre intensita' diverse sono tre atti diversi: se fossero la stessa frase, tanto varrebbe
## non avere l'intensita'.
func test_le_intensita_non_si_ripetono():
	for r in REGISTRI:
		var viste := {}
		for i in [1, 2, 3]:
			var g := Gesto.ripiego(r, i)
			assert_false(viste.has(g), "%s: intensita' diverse, stessa frase" % r)
			viste[g] = true

## Silenzio e arbitrato non sono atti: il primo e' il contrario di un atto, il secondo e'
## la parola di Zeus, che ha gia' la sua riga.
func test_senza_atto_nessun_gesto():
	assert_eq(Gesto.ripiego("silenzio", 1), "")
	assert_eq(Gesto.ripiego("arbitrato", 2), "")
	assert_eq(Gesto.ripiego("registro_inventato", 1), "")

## Intensita' fuori scala non deve svuotare la riga: si arrotonda agli estremi.
func test_intensita_fuori_scala():
	assert_eq(Gesto.ripiego("castigo", 0), Gesto.ripiego("castigo", 1))
	assert_eq(Gesto.ripiego("castigo", 9), Gesto.ripiego("castigo", 3))

# --- La pulizia dell'output del modello ---

## Il modello mette il nome in testa perche' glielo abbiamo chiesto in terza persona.
## Senza toglierlo la chat scrive «Atena Atena stende la mano».
func test_ripulisci_toglie_il_nome_in_testa():
	assert_eq(Gesto.ripulisci("Atena stende la mano su di lui.", "Atena"),
		"stende la mano su di lui.")
	assert_eq(Gesto.ripulisci("*alza la mano*", "Poseidone"), "alza la mano")

## Un gesto lungo un paragrafo sfonda la riga della chat.
func test_ripulisci_taglia_il_paragrafo():
	var lungo := "alza la mano ".repeat(30)
	var g := Gesto.ripulisci(lungo, "Zeus")
	assert_lt(g.length(), Gesto.MASSIMO + 2)
	assert_true(g.ends_with("…"))

## Il nome si toglie solo se e' davvero in testa: «Atenaide» non e' «Atena».
func test_ripulisci_non_mangia_parole_che_iniziano_uguale():
	assert_eq(Gesto.ripulisci("volta il capo", "Poseidone"), "volta il capo")

# --- Da dove viene il gesto ---

## Se il dio l'ha detto, vince il suo: e' la sua voce, il ripiego e' una toppa.
func test_il_gesto_del_dio_batte_il_ripiego():
	var p := {"registro": "castigo", "intensita": 1, "gesto": "gli spegne il fuoco sotto le mani"}
	assert_eq(Gesto.da_proposta(p), "gli spegne il fuoco sotto le mani")

## Il modello dimentichera' il campo: succede, e non deve lasciare la riga vuota.
func test_senza_gesto_si_usa_il_ripiego():
	var p := {"registro": "castigo", "intensita": 3}
	assert_eq(Gesto.da_proposta(p), Gesto.ripiego("castigo", 3))

# --- Il percorso vero: dal JSON del modello alla proposta ---

## Con chat_fn finto si prova il ramo LLM, che il mock non tocca mai.
func test_il_dio_agente_legge_il_gesto():
	var dio := PantheonManager.get_dio("poseidone")
	var agente := DioAgente.new()
	var finto := func(_m, _o):
		return {"ok": true, "content": '{"registro":"castigo","intensita":2,' \
			+ '"dice":"Non e\' finita.","gesto":"Poseidone *gonfia il mare sotto la chiglia*"}'}
	var p: Dictionary = await agente.proponi(dio, {"envelope": {}}, finto)
	assert_eq(p["gesto"], "gonfia il mare sotto la chiglia", "nome e asterischi via")

## Chi tace non muove un dito: un modello che sceglie "silenzio" e poi descrive un atto
## sta contraddicendo se stesso, e in chat si vedrebbe agire un dio inerte.
func test_col_silenzio_il_gesto_si_butta():
	var dio := PantheonManager.get_dio("poseidone")
	var agente := DioAgente.new()
	var finto := func(_m, _o):
		return {"ok": true, "content": '{"registro":"silenzio","intensita":1,' \
			+ '"dice":"Mi annoia.","gesto":"solleva un\'onda"}'}
	var p: Dictionary = await agente.proponi(dio, {"envelope": {}}, finto)
	assert_eq(p["gesto"], "")
