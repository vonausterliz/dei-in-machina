extends Node

## Autoload. Fase 0: contenitore dello StatoPartita corrente + load/save.
## La FSM del turno (macchina_del_turno.mermaid) arriva dalla fase 2 in poi.

const SALVATAGGIO_DEFAULT := "user://partita.json"

var stato: StatoPartita = null

func nuova_partita(seed_partita: int = 0) -> void:
	var s := seed_partita if seed_partita != 0 else randi()
	stato = StatoPartita.nuova(PantheonManager.pantheon, s)

func carica_partita(path: String = SALVATAGGIO_DEFAULT) -> bool:
	var s := StatoPartita.carica(path)
	if s == null:
		return false
	stato = s
	return true

func salva_partita(path: String = SALVATAGGIO_DEFAULT) -> bool:
	if stato == null:
		push_error("GameManager: nessuna partita attiva da salvare.")
		return false
	return stato.salva(path)
