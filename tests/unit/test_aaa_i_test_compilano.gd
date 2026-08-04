extends GutTest

## LA GUARDIA CONTRO IL SILENZIO DI GUT.
##
## Un file di test che non compila GUT non lo esegue e non lo dice: sparisce dal conteggio
## e la suite resta verde. È successo QUATTRO volte in questo progetto — un `await`
## dimenticato, una firma cambiata prima della sua implementazione, un `var x :=` su un
## valore senza tipo — e ogni volta se n'è accorto solo chi guardava il TOTALE dei test,
## non chi guardava i fallimenti. È il modo peggiore di rompere una suite: silenzioso, e
## indistinguibile dal successo.
##
## Il numero dei test cambia a ogni commit e non si può fissare. I FILE invece si possono
## contare: se un .gd sta in tests/ dev'essere caricabile, e qui la cosa diventa un
## fallimento col nome del file dentro.
##
## ⚠️ LA GUARDIA HA MANCATO LA QUINTA VOLTA, e per una ragione che vale la pena scrivere:
## si reggeva su «`load()` di uno script che non compila torna null». **Non è vero.** In
## Godot 4.7 `load()` stampa l'errore di parsing sulla console e restituisce comunque
## l'oggetto GDScript — non nullo, solo inservibile. Il controllo passava sempre, per
## qualunque file, e la guardia era decorativa: sorvegliava una cosa che non poteva
## succedere. Se n'è accorto di nuovo il TOTALE dei test (43 file, 42 script eseguiti),
## cioè esattamente il riflesso che questo file doveva rendere inutile.
##
## Quello che discrimina davvero è `can_instantiate()`: false su uno script che non compila.
## (Anche `reload()` funziona — torna 43, ERR_PARSE_ERROR — ma ri-analizza il file per
## niente.)
##
## Si chiama «aaa» perché GUT esegue in ordine alfabetico: se qualcosa è rotto lo si legge
## in cima all'output, non dopo trecento righe verdi.

const CARTELLE := ["res://tests/unit", "res://tests/integration"]

## Erano 39 il 3 agosto 2026, 43 il 4 agosto. Il numero sale quando si aggiungono test; se
## scende, qualcuno ha cancellato un file — e va detto, non scoperto.
const QUANTI_ALMENO := 44

func test_ogni_file_di_test_compila():
	var rotti: Array = []
	var visti := 0
	for cartella in CARTELLE:
		var dir := DirAccess.open(cartella)
		if dir == null:
			continue
		for nome in dir.get_files():
			if not nome.ends_with(".gd"):
				continue
			visti += 1
			var s: Variant = load(cartella + "/" + nome)
			# NON `s == null`: vedi sopra, non succede mai. Uno script che non compila si
			# carica benissimo e poi non si può istanziare — ed è li' che GUT lo perde.
			if s == null or not (s is GDScript) or not s.can_instantiate():
				rotti.append(nome)
	assert_gt(visti, 30, "lo scandaglio deve trovare i file, o non sta guardando niente")
	assert_eq(rotti, [], "NON COMPILANO: GUT li salterebbe in silenzio, e la suite resterebbe verde")

## La guardia deve poter fallire. Un file rotto per finta, caricato dalla stessa strada dei
## veri: se questo test passasse anche con lo script guasto, la guardia sarebbe di nuovo
## decorativa e nessuno lo saprebbe.
func test_la_guardia_riconosce_uno_script_guasto():
	var percorso := "user://prova_script_guasto.gd"
	var f := FileAccess.open(percorso, FileAccess.WRITE)
	f.store_string("extends GutTest\nfunc x():\n\tvar a := Questo.Non.Esiste.Proprio\n")
	f.close()
	var s: Variant = load(percorso)
	# Gli errori di parsing che escono da qui sono il RISULTATO ATTESO, non un guasto: senza
	# dichiararli gestiti GUT fa fallire il test proprio per gli errori che gli ho chiesto.
	for e in gut.error_tracker.get_errors_for_test():
		e.handled = true
	assert_false(s != null and s is GDScript and s.can_instantiate(),
		"uno script che non compila deve risultare guasto al controllo")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(percorso))

func test_i_file_di_test_non_sono_spariti():
	var quanti := 0
	for cartella in CARTELLE:
		var dir := DirAccess.open(cartella)
		if dir != null:
			for nome in dir.get_files():
				if nome.ends_with(".gd"):
					quanti += 1
	assert_gte(quanti, QUANTI_ALMENO,
		"erano %d: se ne mancano, dirlo invece di lasciarlo dedurre dal totale" % QUANTI_ALMENO)
