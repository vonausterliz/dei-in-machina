extends GutTest

## Le stringhe mostrate all'utente stanno in data/testi/<lingua>.json, non nel codice.

func test_stringhe_dal_file():
	Testi.usa("it")
	assert_eq(Testi.s("gioco/agisci"), "Agisci")
	assert_string_contains(Testi.s("app/titolo"), "MACHINA")

func test_sostituzioni():
	assert_eq(Testi.s("pannelli/ciurma_conteggio", [12, 45]), "12 di 45")
	assert_string_contains(Testi.s("gioco/fine", ["follia"]), "follia")

func test_chiave_mancante_e_visibile():
	# Meglio vedere la chiave che una stringa vuota: si capisce subito cosa manca.
	assert_eq(Testi.s("non/esiste"), "non/esiste")

func test_lingua_mancante_ricade_su_italiano():
	Testi.usa("xx")
	assert_eq(Testi.s("gioco/agisci"), "Agisci")
	Testi.usa("it")

## OGNI CHIAVE CITATA NEL CODICE DEVE ESISTERE.
##
## `Testi.s()` ritorna il PERCORSO quando la voce manca: ottimo per accorgersene a schermo,
## pessimo per accorgersene prima. Un refuso in `Testi.s("impostazioni/aiut")` non fa
## fallire niente — stampa «impostazioni/aiut» in mezzo alla finestra e buonanotte.
## Qui si scandagliano tutti i .gd e si pretende che ogni chiave scritta a mano ci sia.
func test_nessuna_chiave_citata_nel_codice_e_mancante():
	Testi.usa("it")
	var mancanti: Array = []
	var cercate := 0
	for f in _tutti_gli_script("res://"):
		var testo := FileAccess.get_file_as_string(f)
		for m in RegEx.create_from_string('Testi\\.s\\(\\s*"([^"]+)"').search_all(testo):
			cercate += 1
			var chiave := m.get_string(1)
			if not Testi.ha(chiave) and not mancanti.has(chiave):
				mancanti.append("%s  (in %s)" % [chiave, f.get_file()])
	assert_gt(cercate, 50, "lo scandaglio deve trovare le chiamate, o non sta guardando niente")
	assert_eq(mancanti, [], "chiavi citate nel codice ma assenti da data/testi/it.json")

## Le chiavi composte a runtime («gioco/epitaffio_%s») non si possono scandagliare: per
## quelle c'e' Testi.ha() ai punti di chiamata. Qui si guardano solo le letterali.
func _tutti_gli_script(percorso: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(percorso)
	if dir == null:
		return out
	dir.list_dir_begin()
	var nome := dir.get_next()
	while nome != "":
		var pieno := percorso.path_join(nome)
		if dir.current_is_dir():
			if not nome.begins_with(".") and nome not in ["addons", "tests", "tools"]:
				out.append_array(_tutti_gli_script(pieno))
		elif nome.ends_with(".gd"):
			out.append(pieno)
		nome = dir.get_next()
	dir.list_dir_end()
	return out
