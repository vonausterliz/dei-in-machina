extends Node

## Autoload. Stato della partita corrente + FSM del turno (macchina_del_turno.mermaid).
##
## Fase 2: ciclo minimo fino a Omero. I dei vengono SELEZIONATI (risveglio) ma non
## ancora CHIAMATI: niente deliberazione/arbitrato/scavalcamento/applicazione delta
## (fasi 3-6). La resa dei conti iniziale (politica divina) e' fase 6.
## L'ammonizione piena (contatore/scala/follia) e' fase 5: qui la validazione fa solo
## da instradamento (in_mondo -> risveglio; fuori-mondo -> nessun dio + richiamo di Omero).

const SALVATAGGIO_DEFAULT := "user://partita.json"

## Fasi della macchina del turno attraversate in Fase 2 (le altre arrivano dopo).
enum Fase { INTERPRETAZIONE, VALIDAZIONE, RISVEGLIO, NARRAZIONE, ESITO, AVANZAMENTO }

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

## Esegue un turno completo (fino a Omero) sull'input libero di Ulisse.
## `eventi`: condizioni di mondo attive questo turno (di norma vuote finche' gli
## episodi non le generano, fase 7); passabili per test e per usi futuri.
## Ritorna un dizionario di esito: {voce, svegli, in_mondo, esito, fsm_path}.
## 'voce' e' anche appesa a stato.storico_olimpo (schema letto dal trace dumper).
func esegui_turno(input_testo: String, eventi: Array = []) -> Dictionary:
	if stato == null:
		push_error("GameManager: nessuna partita attiva.")
		return {}

	var percorso: Array[String] = []
	stato.turno += 1
	var turno := stato.turno

	# INTERPRETAZIONE — testo libero -> envelope (Interprete via LLMManager).
	percorso.append(Fase.keys()[Fase.INTERPRETAZIONE])
	var envelope: Dictionary = await LLMManager.interpreta(input_testo)

	# VALIDAZIONE — instradamento minimo (ammonizione piena = fase 5).
	percorso.append(Fase.keys()[Fase.VALIDAZIONE])
	var in_mondo: bool = envelope.get("plausibilita", "") == "in_mondo"

	# RISVEGLIO — solo selezione deterministica; i dei non vengono ancora chiamati.
	var svegli: Array[String] = []
	if in_mondo:
		percorso.append(Fase.keys()[Fase.RISVEGLIO])
		_risolvi_invocazione(envelope, input_testo)
		svegli = PantheonManager.risveglio(envelope, eventi, _episodio_corrente())
		_segna_in_gioco(svegli)

	# NARRAZIONE — Omero reticente, senza nomi di dei (invariante). Mock in fase 2.
	percorso.append(Fase.keys()[Fase.NARRAZIONE])
	var narrazione: String = await LLMManager.narrazione_omero({
		"sintesi": envelope.get("sintesi", ""),
		"in_mondo": in_mondo,
		"svegli": svegli,
	})

	# Registrazioni: storico_olimpo (vista Olimpo/debug) + diario (player-facing).
	var voce := {
		"turno": turno,
		"input": input_testo,
		"envelope": envelope,
		"svegli": svegli,
		"eventi_emessi": eventi,
		"narrazione_omero": narrazione,
	}
	stato.storico_olimpo.append(voce)
	stato.diario.append({
		"turno": turno,
		"voce": envelope.get("sintesi", input_testo),
		"esito": "neutro",  # marcatore d'esito vero = fase 3 (i dei applicano delta)
	})

	# ESITO — in fase 2 nessun delta divino, quindi di norma "continua".
	percorso.append(Fase.keys()[Fase.ESITO])
	var esito := _controlla_esito()

	percorso.append(Fase.keys()[Fase.AVANZAMENTO])
	return {
		"voce": voce,
		"svegli": svegli,
		"in_mondo": in_mondo,
		"esito": esito,
		"fsm_path": percorso,
	}

func _episodio_corrente() -> String:
	var ep: Variant = stato.ulisse.get("episodio_corrente", null)
	return String(ep) if ep != null else ""

## Riferimento allusivo a un dio: se Ulisse invoca/supplica (anche per epiteto:
## "il capo dell'olimpo") senza che l'envelope abbia gia' un dio_invocato valido,
## lo risolviamo deterministicamente dal testo. Gated sull'INTENTO di invocazione
## (preghiera/supplica): una menzione di passaggio non deve svegliare un dio.
func _risolvi_invocazione(envelope: Dictionary, input_testo: String) -> void:
	if not _ha_intento_invocazione(envelope):
		return
	var attuale: Variant = envelope.get("dio_invocato", null)
	if attuale != null and PantheonManager.pantheon.ha(String(attuale)):
		return  # l'Interprete/LLM ha gia' fornito un id valido
	var id := PantheonManager.risolvi_invocato(input_testo)
	if id != "":
		envelope["dio_invocato"] = id

func _ha_intento_invocazione(envelope: Dictionary) -> bool:
	if envelope.get("tipo", "") == "preghiera":
		return true
	var tag: Array = envelope.get("tag", [])
	return tag.has("preghiera") or tag.has("supplica")

## Un dio che si sveglia entra "in gioco" (utile per i locali; i persistenti lo sono gia').
func _segna_in_gioco(svegli: Array) -> void:
	for id in svegli:
		if stato.registro_divino.has(id):
			stato.registro_divino[id]["risvegliato"] = true

## Controllo d'esito. Fase 2: solo cio' che e' gia' derivabile senza delta divini.
## morte / follia / prigionia / itaca arrivano con le fasi che li generano.
func _controlla_esito() -> String:
	var ciurma: Dictionary = stato.ulisse.get("stat", {}).get("ciurma", {})
	if int(ciurma.get("vivi", 1)) <= 0:
		return "ciurma_perduta"
	return "continua"
