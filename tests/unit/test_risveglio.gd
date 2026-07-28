extends GutTest

var _p: Pantheon

func before_each():
	_p = Pantheon.carica("res://data/pantheon.json")

func _env(tag: Array, dio_invocato = null) -> Dictionary:
	return {"plausibilita": "in_mondo", "tipo": "parola", "tag": tag, "dio_invocato": dio_invocato}

# --- eleggibilita' ---

func test_eleggibili_stadio_1_solo_persistenti():
	var e := _p.eleggibili("ciclope")
	assert_eq(e.size(), 3)
	for id in ["atena", "poseidone", "zeus"]:
		assert_has(e, id)

func test_locale_eleggibile_solo_nel_suo_episodio():
	# Simula lo stadio 3: accendo un locale e controllo l'eleggibilita' per episodio.
	_p.get_dio("polifemo").attivo = true
	assert_has(_p.eleggibili("ciclope"), "polifemo", "nel suo episodio e' eleggibile")
	assert_does_not_have(_p.eleggibili("eolo"), "polifemo", "fuori dal suo episodio no")

# --- risveglio per trigger_azione ---

func test_vanto_sveglia_solo_poseidone():
	var svegli := _p.risveglio(_env(["vanto", "tracotanza"]), [], "")
	assert_eq(svegli, ["poseidone"], "vanto/tracotanza inneschano solo Poseidone tra i persistenti")

func test_astuzia_sveglia_solo_atena():
	assert_eq(_p.risveglio(_env(["astuzia"]), [], ""), ["atena"])

func test_xenia_sveglia_solo_zeus():
	assert_eq(_p.risveglio(_env(["xenia"]), [], ""), ["zeus"])

func test_empieta_sveglia_zeus_e_poseidone():
	# empieta e' trigger sia di Zeus sia di Poseidone: entrambi, in ordine di pantheon.
	assert_eq(_p.risveglio(_env(["empieta"]), [], ""), ["poseidone", "zeus"])

func test_nessun_tag_nessun_risveglio():
	assert_eq(_p.risveglio(_env([]), [], ""), [])

func test_tag_senza_trigger_nessun_risveglio():
	# 'nostalgia' non e' trigger di alcun persistente.
	assert_eq(_p.risveglio(_env(["nostalgia"]), [], ""), [])

# --- risveglio per trigger_evento ---

func test_evento_maledizione_sveglia_poseidone():
	var svegli := _p.risveglio(_env([]), ["maledizione_di_polifemo"], "")
	assert_eq(svegli, ["poseidone"])

# --- risveglio per invocazione esplicita ---

func test_dio_invocato_sveglia_anche_senza_tag():
	# Ulisse prega Atena per nome: si sveglia anche se nessun tag combacia.
	var svegli := _p.risveglio(_env([], "atena"), [], "")
	assert_has(svegli, "atena")

func test_dio_invocato_non_eleggibile_non_si_sveglia():
	# Invocare un locale spento non lo sveglia (Ulisse prega alla cieca).
	assert_does_not_have(_p.risveglio(_env([], "circe"), [], ""), "circe")

func test_ordine_risveglio_segue_il_pantheon():
	# Determinismo dell'ordine: atena prima di poseidone prima di zeus.
	var svegli := _p.risveglio(_env(["astuzia", "empieta"]), [], "")
	assert_eq(svegli, ["atena", "poseidone", "zeus"])
