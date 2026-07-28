extends SceneTree

## Driver di traccia headless: esegue N turni col MOCK e stampa la vista Olimpo dal
## vivo (CLAUDE.md, mandato punto 4: "esegue N turni col mock e stampa lo storico").
## Deterministico (mock + seed): e' l'occhio per giudicare la macchina del turno,
## turno per turno, senza rete ne' token.
## Uso: tools/godot/godot4 --headless --path . --script res://tools/trace_dumper/run_turns.gd

const SEED := 4815162342

## Input scriptati scelti per esercitare risvegli diversi col mock deterministico.
const COPIONE := [
	"Sono io, Odisseo, che t'ho accecato!",         # vanto/tracotanza -> Poseidone
	"Dico al gigante che il mio nome e' Nessuno.",   # astuzia/inganno  -> Atena
	"Prendo un aereo e volo a Itaca.",               # anacronistico    -> nessun dio, richiamo
	"Riempio gli otri d'acqua alla sorgente.",       # neutro           -> nessun dio
	"Mi rivolgo al capo dell'olimpo e lo supplico.", # preghiera allusiva -> Zeus (via epiteto)
]

func _init() -> void:
	_avvia.call_deferred()

func _avvia() -> void:
	# In modalita' --script gli autoload sono nodi sotto /root ma non identificatori
	# globali a compile-time: li recuperiamo per nome.
	var llm: Node = root.get_node("LLMManager")
	var gm: Node = root.get_node("GameManager")

	# Determinismo: forza il mock a prescindere dalla config.
	llm.mock_mode = true
	gm.nuova_partita(SEED)

	print(TraceFormatter.intestazione(gm.stato))
	print("")

	for input in COPIONE:
		var esito: Dictionary = await gm.esegui_turno(input)
		print(TraceFormatter.turno(esito["voce"]))
		print("  FSM: %s" % " -> ".join(esito["fsm_path"]))
		print("  esito: %s" % esito["esito"])
		print("")

	print("=== Fine: %d turni eseguiti col mock ===" % COPIONE.size())
	quit(0)
