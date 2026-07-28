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
