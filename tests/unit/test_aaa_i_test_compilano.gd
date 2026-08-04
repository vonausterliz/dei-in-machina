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
## contare: se un .gd sta in tests/ dev'essere caricabile. `load()` su uno script che non
## compila torna null, e qui diventa un fallimento col nome del file dentro.
##
## Si chiama «aaa» perché GUT esegue in ordine alfabetico: se qualcosa è rotto lo si legge
## in cima all'output, non dopo trecento righe verdi.

const CARTELLE := ["res://tests/unit", "res://tests/integration"]

## Erano 39 il 3 agosto 2026. Il numero sale quando si aggiungono test; se scende, qualcuno
## ha cancellato un file — e va detto, non scoperto.
const QUANTI_ALMENO := 39

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
			if load(cartella + "/" + nome) == null:
				rotti.append(nome)
	assert_gt(visti, 30, "lo scandaglio deve trovare i file, o non sta guardando niente")
	assert_eq(rotti, [], "NON COMPILANO: GUT li salterebbe in silenzio, e la suite resterebbe verde")

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
