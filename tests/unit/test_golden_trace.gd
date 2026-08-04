extends GutTest

## IL GOLDEN TRACE DENTRO LA SUITE.
##
## Lo strumento a riga di comando (tools/golden_trace/) serve a LEGGERE la differenza; questo
## test serve a non poterla ignorare. Stessa logica per entrambi — scripts/traccia_canonica.gd —
## cosi' non c'e' modo che uno passi e l'altro no.
##
## Un test normale verifica cio' che qualcuno ha pensato di verificare. Questo confronta
## TUTTO cio' che sei turni canonici producono con cio' che producevano prima: un'assenza si
## vede come una rottura. E' l'unica rete che copre i guasti di questo progetto — due finali
## irraggiungibili, un caricamento che ometteva un modulo, la terraferma non disegnata:
## nessuno di loro faceva fallire qualcosa, perche' nessuno di loro sbagliava. Mancavano.

var _costi_prima := ""

func before_each():
	# La traccia e' stata registrata col profilo di costo tarato. Con un altro profilo
	# cambiano quanti compagni parlano e ogni quanto si aggiorna la cronaca: la traccia
	# risulterebbe diversa per una ragione che non c'entra niente col codice.
	_costi_prima = Costi.attivo()
	Costi.usa(Costi.PREDEFINITO)

func after_each():
	Costi.usa(_costi_prima)

func test_la_traccia_canonica_non_e_cambiata():
	var attesa := TracciaCanonica.attesa()
	assert_false(attesa.is_empty(),
		"manca %s — registrala con tools/golden_trace/golden_trace.gd -- aggiorna" % TracciaCanonica.PERCORSO)
	if attesa.is_empty():
		return
	var ottenuta: Dictionary = await TracciaCanonica.registra(GameManager, LLMManager)
	var differenze := TracciaCanonica.confronta(attesa, ottenuta)
	assert_eq(differenze, [], "\n  ".join(PackedStringArray(
		["la traccia canonica e' cambiata. Se e' voluto, rileggila e rigenerala:"] + differenze)))

## UNA TRACCIA CHE NON TOCCA NIENTE RESTA VERDE PER SEMPRE.
##
## E' il modo in cui un golden trace muore senza che nessuno se ne accorga: il copione
## smette di svegliare dei, di far avanzare tappe, di produrre narrazione, e il confronto
## continua a riuscire — su niente. Qui si pretende che eserciti ancora qualcosa.
func test_la_traccia_esercita_ancora_le_parti_che_contano():
	var t := TracciaCanonica.attesa()
	if t.is_empty():
		fail_test("nessuna traccia registrata")
		return
	var turni: Array = t["turni"]
	assert_gte(turni.size(), 5, "meno di cinque turni non attraversano abbastanza macchina")

	var con_dei := 0
	var narrati := 0
	var fuori_mondo := 0
	var avanzamenti := 0
	var con_delta := 0
	var con_ciurma := 0
	for u in turni:
		if not (u["svegliati"] as Array).is_empty():
			con_dei += 1
		if String(u["narrazione"]).strip_edges() != "":
			narrati += 1
		if not bool(u["in_mondo"]):
			fuori_mondo += 1
		if bool(u["avanzato"]):
			avanzamenti += 1
		if not (u["delta"] as Dictionary).is_empty():
			con_delta += 1
		if not (u["ciurma_parla"] as Array).is_empty():
			con_ciurma += 1

	assert_gt(con_dei, 0, "nessun dio si sveglia: il cuore del gioco non e' coperto")
	assert_gt(narrati, 0, "nessun turno narrato: Omero non e' coperto")
	assert_gt(fuori_mondo, 0, "nessun anacronismo: l'ammonizione non e' coperta")
	assert_gt(avanzamenti, 0, "nessun avanzamento di tappa: il viaggio non e' coperto")
	assert_gt(con_delta, 0, "nessun delta applicato: le conseguenze non sono coperte")
	assert_gt(con_ciurma, 0, "nessuna voce di ciurma: il ritmo dei compagni non e' coperto")

## L'invariante piu' importante del design, verificata sul testo REGISTRATO: se un giorno
## Omero cominciasse a nominare gli dei, la traccia lo conserverebbe nero su bianco.
func test_nella_traccia_omero_non_nomina_mai_un_dio():
	var t := TracciaCanonica.attesa()
	if t.is_empty():
		fail_test("nessuna traccia registrata")
		return
	var nomi: Array = []
	for d in PantheonManager.pantheon.tutti():
		nomi.append(String(d.nome).to_lower())
	for u in t["turni"]:
		var testo := (String(u["narrazione"]) + " " + String(u["congedo"])).to_lower()
		for n in nomi:
			assert_false(testo.contains(n),
				"turno %d: la narrazione nomina «%s»" % [int(u["n"]), n])
