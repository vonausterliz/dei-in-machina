extends Node

## Autoload. Fase 0: solo caricamento e accesso al data layer statico.
## Il risveglio (fase 2) e il resto della logica arriveranno dopo.

const PANTHEON_PATH := "res://data/pantheon.json"

var pantheon: Pantheon = null

func _ready() -> void:
	pantheon = Pantheon.carica(PANTHEON_PATH)
	if pantheon == null or pantheon.numero_dei() == 0:
		push_error("PantheonManager: pantheon non caricato correttamente da %s" % PANTHEON_PATH)

func get_dio(id: String) -> Dio:
	return pantheon.get_dio(id) if pantheon else null

func dei_attivi() -> Array[Dio]:
	return pantheon.dei_attivi() if pantheon else []

## RISVEGLIO: quali dei si svegliano dato l'envelope + eventi di mondo (design:
## il ledger e il risveglio sono responsabilita' del PantheonManager). La regola
## deterministica vive su Pantheon (dato) per essere testabile in isolamento.
func risveglio(envelope: Dictionary, eventi: Array, episodio_corrente: String) -> Array[String]:
	return pantheon.risveglio(envelope, eventi, episodio_corrente) if pantheon else []

func eleggibili(episodio_corrente: String) -> Array[String]:
	return pantheon.eleggibili(episodio_corrente) if pantheon else []
