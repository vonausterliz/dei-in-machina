extends Node

## Autoload. Stato della partita corrente + FSM del turno (macchina_del_turno.mermaid).
##
## Fase 2: ciclo minimo fino a Omero. I dei vengono SELEZIONATI (risveglio) ma non
## ancora CHIAMATI: niente deliberazione/arbitrato/scavalcamento/applicazione delta
## (fasi 3-6). La resa dei conti iniziale (politica divina) e' fase 6.
## L'ammonizione piena (contatore/scala/follia) e' fase 5: qui la validazione fa solo
## da instradamento (in_mondo -> risveglio; fuori-mondo -> nessun dio + richiamo di Omero).

const SALVATAGGIO_DEFAULT := "user://partita.json"

## Fasi della macchina del turno (macchina_del_turno.mermaid). RESA_DEI_CONTI e
## SCAVALCAMENTO (politica divina) sono fase 6; la DELIBERAZIONE in fase 3 e' solo
## raccolta di proposte, non ancora dialogo tra dei in conflitto (quello e' fase 4).
enum Fase {
	INTERPRETAZIONE, VALIDAZIONE, RISVEGLIO,
	DELIBERAZIONE, ARBITRATO, APPLICAZIONE,
	NARRAZIONE, ESITO, AVANZAMENTO,
}

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

	# RISVEGLIO — selezione deterministica dei dei che reagiscono.
	var svegli: Array[String] = []
	var proposte: Array = []
	var verdetto: Dictionary = {}
	var delta: Dictionary = {}
	var conflitto := false
	if in_mondo:
		percorso.append(Fase.keys()[Fase.RISVEGLIO])
		_risolvi_invocazione(envelope, input_testo)
		svegli = PantheonManager.risveglio(envelope, eventi, _episodio_corrente())
		_segna_in_gioco(svegli)

		# L'azione cambia Ulisse comunque (hybris/metis), anche se nessun dio reagisce.
		delta = Delta.da_azione(envelope)

		if not svegli.is_empty():
			# DELIBERAZIONE — ogni dio sveglio propone; se le proposte confliggono
			# (chi punisce vs chi aiuta) i dei si ribattono (round 2) e Zeus arbitra.
			percorso.append(Fase.keys()[Fase.DELIBERAZIONE])
			var esito_delib := await _delibera(svegli, envelope)
			proposte = esito_delib["proposte"]
			conflitto = esito_delib["conflitto"]

			# ARBITRATO — verdetto: Zeus se c'e' conflitto, altrimenti deterministico.
			percorso.append(Fase.keys()[Fase.ARBITRATO])
			verdetto = esito_delib["verdetto"]

			# APPLICAZIONE — delta della reazione (numeri = regola, non LLM).
			if verdetto.get("attore", "") != "" and verdetto.get("registro", "silenzio") != "silenzio":
				percorso.append(Fase.keys()[Fase.APPLICAZIONE])
				delta = Delta.unisci(delta, Delta.da_reazione(
					verdetto["attore"], verdetto["registro"], int(verdetto["intensita"])))

		Delta.applica(stato, delta)

	# NARRAZIONE — Omero reticente, senza nomi di dei (invariante).
	percorso.append(Fase.keys()[Fase.NARRAZIONE])
	var impronta := ""
	if not verdetto.is_empty():
		var attore: Dio = PantheonManager.get_dio(verdetto["attore"])
		if attore != null:
			impronta = attore.impronta
	var narrazione: String = await LLMManager.narrazione_omero({
		"sintesi": envelope.get("sintesi", ""),
		"in_mondo": in_mondo,
		"svegli": svegli,
		"verdetto": verdetto,
		"delta": delta,
		"impronta": impronta,
		"esito_segno": _segno_esito(delta),
	})

	# Registrazioni: storico_olimpo (vista Olimpo/debug) + diario (player-facing).
	var voce := {
		"turno": turno,
		"input": input_testo,
		"envelope": envelope,
		"svegli": svegli,
		"eventi_emessi": eventi,
		"conflitto": conflitto if in_mondo else false,
		"deliberazione": proposte,
		"verdetto": verdetto,
		"delta": delta,
		"narrazione_omero": narrazione,
	}
	stato.storico_olimpo.append(voce)
	stato.diario.append({
		"turno": turno,
		"voce": envelope.get("sintesi", input_testo),
		"esito": Delta.marcatore_diario(delta) if in_mondo else "neutro",
	})

	# ESITO — ora le stat cambiano: controllo reale (ciurma; gli altri esiti con le loro fasi).
	percorso.append(Fase.keys()[Fase.ESITO])
	var esito := _controlla_esito()
	if esito != "continua":
		stato.stato = "finita"
		stato.esito = esito

	percorso.append(Fase.keys()[Fase.AVANZAMENTO])
	return {
		"voce": voce,
		"svegli": svegli,
		"in_mondo": in_mondo,
		"esito": esito,
		"fsm_path": percorso,
	}

## Registri che "puniscono" vs "aiutano": il loro incontro definisce il conflitto.
const _REGISTRI_PUNITIVI := ["castigo", "aiuto_negato", "trappola"]
const _REGISTRI_BENIGNI := ["aiuto", "segno"]

## Deliberazione. Ritorna {proposte, conflitto, verdetto}.
## - proposte aperte (round 1); si scartano i 'silenzio'.
## - se le proposte attive confliggono: round 2 di repliche (i dei si sentono tra loro)
##   e verdetto di Zeus (Arbitro LLM). Altrimenti verdetto deterministico.
func _delibera(svegli: Array, envelope: Dictionary) -> Dictionary:
	var proposte := await _raccogli_proposte(svegli, envelope, [])
	var attive := _attive(proposte)
	if attive.is_empty():
		return {"proposte": proposte, "conflitto": false, "verdetto": {}}
	if attive.size() == 1 or not _in_conflitto(attive):
		return {"proposte": attive, "conflitto": false, "verdetto": _arbitra(attive)}

	# CONFLITTO: i dei si ribattono, poi Zeus chiude.
	var repliche := await _repliche(attive, envelope)
	var verdetto: Dictionary = await LLMManager.verdetto_arbitro(repliche)
	return {"proposte": repliche, "conflitto": true, "verdetto": verdetto}

## Ogni dio in 'svegli' propone. 'altri' (opzionale) = proposte altrui da mostrargli (replica).
func _raccogli_proposte(svegli: Array, envelope: Dictionary, altri: Array) -> Array:
	var out: Array = []
	for id in svegli:
		out.append(await LLMManager.proposta_dio(PantheonManager.get_dio(id), _contesto_dio(id, envelope, altri)))
	return out

## Round 2: ogni dio ribatte vedendo le proposte degli ALTRI.
func _repliche(attive: Array, envelope: Dictionary) -> Array:
	var out: Array = []
	for p in attive:
		var id: String = p.get("dio", "")
		var altri := _altri_dei(attive, id)
		out.append(await LLMManager.proposta_dio(PantheonManager.get_dio(id), _contesto_dio(id, envelope, altri)))
	return out

func _contesto_dio(id: String, envelope: Dictionary, altri: Array) -> Dictionary:
	var reg: Dictionary = stato.registro_divino.get(id, {})
	return {
		"favore": reg.get("favore", 0),
		"ira": reg.get("ira", 0),
		"umore": reg.get("umore", ""),
		"envelope": envelope,
		"altri_dei": altri,
	}

## Le proposte degli altri dei (nome + registro + battuta), per la replica.
func _altri_dei(proposte: Array, escluso: String) -> Array:
	var out: Array = []
	for p in proposte:
		if p.get("dio", "") != escluso:
			var d: Dio = PantheonManager.get_dio(p.get("dio", ""))
			out.append({"nome": d.nome if d else p.get("dio", "?"), "registro": p.get("registro", "?"), "dice": p.get("dice", "")})
	return out

func _attive(proposte: Array) -> Array:
	var out: Array = []
	for p in proposte:
		if p.get("registro", "silenzio") != "silenzio":
			out.append(p)
	return out

func _in_conflitto(attive: Array) -> bool:
	var punisce := false
	var aiuta := false
	for p in attive:
		var r: String = p.get("registro", "")
		if _REGISTRI_PUNITIVI.has(r):
			punisce = true
		elif _REGISTRI_BENIGNI.has(r):
			aiuta = true
	return punisce and aiuta

## Verdetto deterministico (no conflitto): vince la proposta piu' intensa; a parita', l'ordine.
func _arbitra(proposte: Array) -> Dictionary:
	var best: Dictionary = proposte[0]
	for p in proposte:
		if int(p.get("intensita", 1)) > int(best.get("intensita", 1)):
			best = p
	return {
		"attore": best.get("dio", ""),
		"registro": best.get("registro", "silenzio"),
		"intensita": int(best.get("intensita", 1)),
		"dice": best.get("dice", ""),
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

## Segno d'esito per il narratore (senza numeri): peggiorato / parve giovare / neutro.
func _segno_esito(delta: Dictionary) -> String:
	var animo: int = int(delta.get("ulisse.animo", 0))
	if animo < 0 or int(delta.get("ulisse.ciurma.vivi", 0)) < 0:
		return "le cose hanno preso una brutta piega"
	if animo > 0 or int(delta.get("ulisse.metis", 0)) > 0:
		return "qualcosa e' parso giovare"
	return ""
