extends GutTest

## Poseidone DORME finche' non gli accecano il figlio (`dio.dorme_finche`): fra i Ciconi
## si destava a punire un saccheggio con cui non c'entra nulla. Questi test verificano i
## TRIGGER, non il sonno, quindi gli passano l'evento gia' accaduto. Che prima dorma e'
## verificato in test_dei_che_dormono.gd.
const ACCADUTI := ["maledizione_di_polifemo"]

var _p: Pantheon

func before_each():
	_p = Pantheon.carica("res://data/pantheon.json")

func _env(tag: Array, dio_invocato = null) -> Dictionary:
	return {"plausibilita": "in_mondo", "tipo": "parola", "tag": tag, "dio_invocato": dio_invocato}

# --- eleggibilita' ---

func test_eleggibili_stadio_1_solo_persistenti():
	var e := _p.eleggibili("ciclope", ACCADUTI)
	assert_eq(e.size(), 3)
	for id in ["atena", "poseidone", "zeus"]:
		assert_has(e, id)

func test_locale_eleggibile_solo_nel_suo_episodio():
	# Simula lo stadio 3: accendo un locale e controllo l'eleggibilita' per episodio.
	_p.get_dio("polifemo").attivo = true
	assert_has(_p.eleggibili("ciclope", ACCADUTI), "polifemo", "nel suo episodio e' eleggibile")
	assert_does_not_have(_p.eleggibili("eolo", ACCADUTI), "polifemo", "fuori dal suo episodio no")

# --- risveglio per trigger_azione ---

func test_vanto_sveglia_solo_poseidone():
	var svegli := _p.risveglio(_env(["vanto", "tracotanza"]), [], "", ACCADUTI)
	assert_eq(svegli, ["poseidone"], "vanto/tracotanza inneschano solo Poseidone tra i persistenti")

func test_astuzia_sveglia_solo_atena():
	assert_eq(_p.risveglio(_env(["astuzia"]), [], "", ACCADUTI), ["atena"])

func test_xenia_sveglia_solo_zeus():
	assert_eq(_p.risveglio(_env(["xenia"]), [], "", ACCADUTI), ["zeus"])

func test_empieta_sveglia_zeus_e_poseidone():
	# empieta e' trigger sia di Zeus sia di Poseidone: entrambi, in ordine di pantheon.
	assert_eq(_p.risveglio(_env(["empieta"]), [], "", ACCADUTI), ["poseidone", "zeus"])

func test_nessun_tag_nessun_risveglio():
	assert_eq(_p.risveglio(_env([]), [], "", ACCADUTI), [])

func test_tag_senza_trigger_nessun_risveglio():
	# 'nostalgia' non e' trigger di alcun persistente.
	assert_eq(_p.risveglio(_env(["nostalgia"]), [], "", ACCADUTI), [])

# --- risveglio per trigger_evento ---

func test_evento_maledizione_sveglia_poseidone():
	var svegli := _p.risveglio(_env([]), ["maledizione_di_polifemo"], "", ACCADUTI)
	assert_eq(svegli, ["poseidone"])

# --- risveglio per invocazione esplicita ---

func test_dio_invocato_sveglia_anche_senza_tag():
	# Ulisse prega Atena per nome: si sveglia anche se nessun tag combacia.
	var svegli := _p.risveglio(_env([], "atena"), [], "", ACCADUTI)
	assert_has(svegli, "atena")

func test_dio_invocato_non_eleggibile_non_si_sveglia():
	# Invocare un locale spento non lo sveglia (Ulisse prega alla cieca).
	assert_does_not_have(_p.risveglio(_env([], "circe"), [], "", ACCADUTI), "circe")

func test_ordine_risveglio_segue_il_pantheon():
	# Determinismo dell'ordine: atena prima di poseidone prima di zeus.
	var svegli := _p.risveglio(_env(["astuzia", "empieta"]), [], "", ACCADUTI)
	assert_eq(svegli, ["atena", "poseidone", "zeus"])
