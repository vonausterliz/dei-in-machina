# Dei in machina — gioco narrativo agentico sull'Odissea.
# Copyright (C) 2026 vonausterliz
#
# Programma libero: puoi ridistribuirlo e modificarlo secondo i termini della GNU Affero
# General Public License, versione 3, pubblicata dalla Free Software Foundation. Distribuito
# nella speranza che sia utile, ma SENZA ALCUNA GARANZIA. Il testo completo e' in LICENSE.

extends Node

## Avanzamento effimero del turno per la UI. Non entra nello stato, in Agora o nei
## salvataggi: serve soltanto a far vedere la conversazione mentre il motore lavora.
## `trascrizione` e' una fotografia del canale al momento del segnale, cosi' la GUI puo'
## riprodurre anche il mock senza cambiare l'ordine logico del turno.
signal progresso_turno(fase: String, dati: Dictionary)

## Autoload. Stato della partita corrente + FSM del turno (macchina_del_turno.mermaid).
##
## Fase 2: ciclo minimo fino a Omero. I dei vengono SELEZIONATI (risveglio) ma non
## ancora CHIAMATI: niente deliberazione/arbitrato/scavalcamento/applicazione delta
## (fasi 3-6). La resa dei conti iniziale (politica divina) e' fase 6.
## L'ammonizione piena (contatore/scala/follia) e' fase 5: qui la validazione fa solo
## da instradamento (in_mondo -> risveglio; fuori-mondo -> nessun dio + richiamo di Omero).

const SALVATAGGIO_DEFAULT := "user://partita.json"
const EPISODI_PATH := "res://data/episodi.json"

var episodi: Episodi = null
## Le tappe: dove siamo, quando si chiude, cosa quella tappa consente. Estratto perche'
## la regola del viaggio stava sparsa in tredici metodi in mezzo alla macchina del turno.
var viaggio: Viaggio = null
## Il taccuino privato degli dei: cosa ognuno ha voluto e come e' finita.
var taccuino: Taccuino = null

## Fasi della macchina del turno (macchina_del_turno.mermaid).
enum Fase {
	RESA_DEI_CONTI,
	INTERPRETAZIONE, VALIDAZIONE, RISVEGLIO,
	DELIBERAZIONE, ARBITRATO, APPLICAZIONE, SCAVALCAMENTO,
	ESITO, AVANZAMENTO, NARRAZIONE,
}

## Valori-seme: NON piu' costanti nel codice ma voci di data/bilanciamento.json, cosi' la
## taratura si fa sul file (design sez. 12). Il secondo argomento e' solo il ripiego.
@onready var _PROB_SCAVALCAMENTO_DEFAULT: float = Bilanciamento.num("politica_divina/prob_scavalcamento", 0.35)
@onready var _RATE_SOSPETTO: int = Bilanciamento.intero("politica_divina/rate_sospetto", 20)
@onready var _IRA_ZEUS_SCOPERTA: int = Bilanciamento.intero("politica_divina/ira_zeus_scoperta", 15)
@onready var _RIMBALZO_ULISSE: int = Bilanciamento.intero("politica_divina/rimbalzo_ulisse", 5)
@onready var _SOGLIA_SCOPERTA: int = Bilanciamento.intero("politica_divina/soglia_scoperta", 60)

## Probabilita' che un dio bocciato scavalchi Zeus. Sovrascrivibile nei test (0/1).
## Le probabilita' vivono nel modulo; questi restano come comodita' per i test, che le
## impostano su GameManager. Il setter le inoltra dove servono davvero.
var prob_scavalcamento := 0.35:
	set(v):
		prob_scavalcamento = v
		if _politica: _politica.prob_scavalcamento = v
var _rng := RandomNumberGenerator.new()

## Coalizioni & strategie (fase 6-bis), valori-seme. Rare e bounded per non annegare
## il segnale deducibile: restano modulazione di sfondo, mai la causa dominante.
@onready var _PROB_COALIZIONE_DEFAULT: float = Bilanciamento.num("coalizioni/prob_coalizione", 0.4)
@onready var _COESIONE_INIZIALE: int = Bilanciamento.intero("coalizioni/coesione_iniziale", 70)
@onready var _COESIONE_DECADIMENTO: int = Bilanciamento.intero("coalizioni/coesione_decadimento", 15)
@onready var _MAX_COALIZIONI: int = Bilanciamento.intero("coalizioni/massimo", 1)
@onready var _PESO_COALIZIONE: int = Bilanciamento.intero("coalizioni/peso_intensita", 1)
@onready var _SOGLIA_VULNERABILITA: int = Bilanciamento.intero("coalizioni/soglia_vulnerabilita", 40)
var prob_coalizione := 0.4:
	set(v):
		prob_coalizione = v
		if _politica: _politica.prob_coalizione = v

var stato: StatoPartita = null

## Moduli estratti: la regola vive nel suo file, GameManager orchestra il turno.
var _validazione: Validazione = null
## Le conversazioni (vista Olimpo come chat, e in seguito la ciurma).
var agora: Agora = null
## I compagni: hanno voce propria e possono morire (allora tacciono).
var ciurma: Ciurma = null
## Coalizioni, piani, scavalcamenti e resa dei conti: la politica dell'Olimpo.
var _politica: PoliticaDivina = null

## Ultima narrazione di Omero: la ripassiamo al turno dopo per la continuità del discorso.
var _ultima_narrazione: String = ""

## Strangler flag del solo slice Ismaro. Nei test legacy a mock resta spento finche'
## il test d integrazione non lo abilita esplicitamente; nel gioco reale e attivo.
var ciconi_world_poc_enabled := true
var _ciconi_world_poc_in_mock := false

func _ready() -> void:
	episodi = Episodi.carica(EPISODI_PATH)
	prob_scavalcamento = _PROB_SCAVALCAMENTO_DEFAULT
	prob_coalizione = _PROB_COALIZIONE_DEFAULT

func nuova_partita(seed_partita: int = 0) -> void:
	var s := seed_partita if seed_partita != 0 else randi()
	stato = StatoPartita.nuova(PantheonManager.pantheon, s)
	_validazione = Validazione.new(stato)
	viaggio = Viaggio.new(episodi, stato)
	taccuino = Taccuino.new(stato)
	agora = Agora.new()
	agora.canale(Agora.CANALE_OLIMPO, "Olimpo")
	ciurma = Ciurma.carica()
	agora.canale(Agora.CANALE_CIURMA, "Ciurma")
	_politica = PoliticaDivina.new(stato, agora, _rng)
	_ultima_narrazione = ""
	_rng.seed = s  # riproducibilita': stessa run, stessi scavalcamenti
	prob_scavalcamento = _PROB_SCAVALCAMENTO_DEFAULT
	prob_coalizione = _PROB_COALIZIONE_DEFAULT
	# Viaggio: i locali ripartono spenti; si entra nella prima tappa (accende i suoi locali).
	PantheonManager.pantheon.spegni_locali()
	# NB: l'ordine delle tappe e' quello del poema, fisso, e vive in data/episodi.json.
	# Il design v0.1 lo voleva rimescolato dal seme; deciso di no (design sez. 7): l'ordine
	# dell'Odissea e' la causalita' della storia, non un contenitore di tappe.
	_entra_in_episodio(episodi.primo())

## Entra in una tappa. La regola sta in Viaggio; qui resta la continuita' del racconto:
## il primo turno della tappa prosegue dalla sua intro.
func _entra_in_episodio(id: String) -> String:
	var intro := viaggio.entra(id)
	if id == "ciconi" and stato != null and stato.ciconi_run.is_empty():
		var initial := CiconiWorld.initial_state()
		stato.ciconi_run = CiconiWorldStore.new_record(CiconiWorldStore.seed_id_for_path(), initial)
	_ultima_narrazione = intro
	return intro

## Il momento del giorno, che avanza di uno a ogni turno e ricomincia. Deterministico:
## dipende solo dal numero del turno, quindi due partite con lo stesso seme scandiscono il
## tempo allo stesso modo. E' il battito che tiene insieme le tre viste da quando non si
## scrive piu' «turno N» — scandisce senza numerare.
func momento_corrente() -> String:
	var m: Array = Lingua.momenti_del_giorno()
	if m.is_empty() or stato == null:
		return ""
	return String(m[maxi(0, stato.turno) % m.size()])

## Intro e ancora di scena della tappa corrente (per aprire la scena e per gli agenti).
func intro_corrente() -> String:
	return viaggio.intro_corrente() if viaggio else ""

func scena_corrente() -> String:
	return viaggio.scena_corrente() if viaggio else ""

func _nome_tappa_corrente() -> String:
	return viaggio.nome_corrente() if viaggio else ""

## Ogni quanti turni si aggiorna il riassunto rotolante. Non a ogni turno: sarebbe una
## chiamata LLM in piu' sempre. Cosi' la memoria costa poco e resta a dimensione costante.
## Dal profilo di costo (era in bilanciamento.json, che pero' e' la taratura di GIOCO).
func _cronaca_ogni() -> int:
	return maxi(1, Costi.limite("cronaca_ogni", 4))

## Aggiorna la cronaca (memoria della vicenda) se sono passati abbastanza turni. Prende i
## fatti NON ancora riassunti da storico_olimpo (azione + cosa e' seguito).
func _aggiorna_cronaca_se_serve() -> void:
	if stato.turno - stato.cronaca_turno < _cronaca_ogni():
		return
	var fatti: Array = []
	for v in stato.storico_olimpo:
		if int(v.get("turno", 0)) <= stato.cronaca_turno:
			continue
		var narr := String(v.get("narrazione_omero", ""))
		if narr == "":
			continue  # turni fuori-mondo: non fanno storia
		fatti.append("- Ulisse: «%s» → %s" % [String(v.get("input", "")), narr])
	if fatti.is_empty():
		stato.cronaca_turno = stato.turno
		return
	var nuova_cronaca: String = await LLMManager.aggiorna_cronaca({
		"precedente": stato.cronaca,
		"fatti": fatti,
		"luogo": _nome_tappa_corrente(),
	})
	if nuova_cronaca != "":
		stato.cronaca = nuova_cronaca
	stato.cronaca_turno = stato.turno

## Gli ultimi beat del diario (cosa ha fatto Ulisse, di recente): la "storia finora"
## compatta per la continuita' del discorso di Omero. Niente chiamata LLM: e' gia' pronta.
func _storia_recente(quanti: int = 5) -> Array:
	var out: Array = []
	var d: Array = stato.diario
	var da := maxi(0, d.size() - quanti)
	for i in range(da, d.size()):
		out.append(String(d[i].get("voce", "")))
	return out

## A che punto e' il ritorno: inizio / mezzo / vicino (per l'orientamento discreto).
func _progresso_viaggio() -> String:
	return viaggio.progresso() if viaggio else "inizio"

## Come stanno andando le cose, dagli ultimi esiti del diario: duro / bene / incerto.
func _morale_recente(quanti: int = 4) -> String:
	var d: Array = stato.diario
	var mal := 0
	var ben := 0
	for i in range(maxi(0, d.size() - quanti), d.size()):
		match String(d[i].get("esito", "")):
			"ill": mal += 1
			"fair": ben += 1
	if mal > ben:
		return "duro"
	elif ben > mal:
		return "bene"
	return "incerto"

## Salta direttamente a una tappa (test/strumenti/debug). Accende i suoi locali.
func vai_a_tappa(id: String) -> void:
	_entra_in_episodio(id)

## RIPRENDERE UNA PARTITA dev'essere simmetrico a cominciarne una.
##
## Prima non lo era, e i modi di sbagliare erano tutti silenziosi: `_politica` non veniva
## ricostruita (col gioco appena avviato: crash alla prima riga del turno dopo; con una
## partita gia' in corso, peggio — continuava a scrivere nello stato VECCHIO); la ciurma
## restava null e i compagni sparivano senza un errore; i locali della tappa, che sono un
## flag in memoria e non nel file, restavano spenti.
##
## Regola: tutto cio' che `nuova_partita` costruisce, `carica_partita` lo ricostruisce.
func _replay_ciconi_salvato(candidate: StatoPartita) -> Dictionary:
	if candidate.ciconi_run.is_empty():
		return {"ok": true, "state": {}}
	var checked := CiconiWorldStore.validate_record(candidate.ciconi_run)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "reason": checked.get("reason", "invalid_ciconi_run")}
	return CiconiWorldStore.replay(candidate.ciconi_run)


func carica_partita(path: String = SALVATAGGIO_DEFAULT) -> bool:
	var s := StatoPartita.carica(path)
	if s == null:
		return false
	var replayed := _replay_ciconi_salvato(s)
	if not bool(replayed.get("ok", false)):
		var backup := StatoPartita.carica(path + ".bak")
		var backup_replayed := _replay_ciconi_salvato(backup) if backup != null else {"ok": false, "reason": "backup_missing"}
		if not bool(backup_replayed.get("ok", false)):
			push_error("GameManager: salvataggio Ciconi non valido: %s; backup: %s" % [replayed.get("reason", "errore"), backup_replayed.get("reason", "errore")])
			return false
		s = backup
		replayed = backup_replayed
	if not s.ciconi_run.is_empty():
		s.ciconi_run["snapshot"] = replayed["state"]
	stato = s
	_validazione = Validazione.new(stato)
	viaggio = Viaggio.new(episodi, stato)
	taccuino = Taccuino.new(stato)
	# Le conversazioni tornano com'erano; se il salvataggio e' anteriore a questa versione
	# si riparte da chat vuote, ma con i canali al loro posto.
	agora = Agora.from_dict(stato.agora) if not stato.agora.is_empty() else Agora.new()
	agora.canale(Agora.CANALE_OLIMPO, "Olimpo")
	agora.canale(Agora.CANALE_CIURMA, "Ciurma")
	ciurma = Ciurma.carica()
	ciurma.riprendi_caduti(stato.ciurma_caduti)
	_politica = PoliticaDivina.new(stato, agora, _rng)
	_ultima_narrazione = stato.ultima_narrazione
	_rng.seed = stato.seed_partita
	prob_scavalcamento = _PROB_SCAVALCAMENTO_DEFAULT
	prob_coalizione = _PROB_COALIZIONE_DEFAULT
	# I locali sono spenti di default e si accendono entrando in una tappa: qui non si
	# "entra" (azzererebbe i turni gia' spesi), si riaccende soltanto chi e' di scena.
	PantheonManager.pantheon.spegni_locali()
	viaggio.accendi_locali(viaggio.corrente())
	return true

func salva_partita(path: String = SALVATAGGIO_DEFAULT) -> bool:
	if stato == null:
		push_error("GameManager: nessuna partita attiva da salvare.")
		return false
	# Cio' che vive fuori dallo stato viene allineato adesso: le chat, i caduti e l'ultima
	# voce di Omero sono parte della partita quanto le statistiche.
	stato.agora = agora.to_dict() if agora else {}
	stato.ciurma_caduti = []
	if ciurma:
		for id in ciurma.caduti:
			stato.ciurma_caduti.append(String(id))
	stato.ultima_narrazione = _ultima_narrazione
	var fatto := stato.salva(path)
	# UN SALVATAGGIO FALLITO NON DEVE ESSERE SILENZIOSO. Ritornava `false` e basta, e chi
	# chiama spesso non lo guarda: il disco pieno o i permessi sbagliati si scoprivano al
	# riavvio, trovando una partita vecchia di ore.
	if fatto:
		Registro.info("partita", "salvata: turno %d · %s" % [stato.turno, path])
	else:
		Registro.errore("partita", "SALVATAGGIO FALLITO su %s — la partita non e' su disco" % path)
	return fatto

## Esegue un turno completo (fino a Omero) sull'input libero di Ulisse.
## `eventi`: condizioni di mondo attive questo turno (di norma vuote finche' gli
## episodi non le generano, fase 7); passabili per test e per usi futuri.
## Le parole scambiate coi compagni NON passano di qui: sono beat (vedi esegui_beat).
## Ritorna un dizionario di esito: {voce, svegli, in_mondo, esito, fsm_path}.
## 'voce' e' anche appesa a stato.storico_olimpo (schema letto dal trace dumper).
## `rischio`: Ulisse ha preso un BIVIO, non un suggerimento. Vedi forza_con_rischio.
func abilita_ciconi_world_poc(attivo: bool, anche_in_mock: bool = false) -> void:
	ciconi_world_poc_enabled = attivo
	_ciconi_world_poc_in_mock = attivo and anche_in_mock

func _usa_ciconi_world_poc() -> bool:
	return ciconi_world_poc_enabled and stato != null and _episodio_corrente() == "ciconi" and (not LLMManager.mock_mode or _ciconi_world_poc_in_mock)

func esegui_turno(input_testo: String, eventi: Array = [], rischio: bool = false) -> Dictionary:
	if _usa_ciconi_world_poc():
		return await _esegui_turno_ciconi(input_testo, rischio)
	return await _esegui_turno_legacy(input_testo, eventi, rischio)

## Turno verticale del POC. Il solo swap di `stato.ciconi_run` e il commit logico;
## ogni consumer LLM parte dopo e riceve copie/proiezioni della stessa world version.
func _esegui_turno_ciconi(input_testo: String, rischio: bool = false) -> Dictionary:
	if stato == null or stato.stato != "in_corso":
		return {}
	if stato.ciconi_run.is_empty():
		var initial := CiconiWorld.initial_state()
		stato.ciconi_run = CiconiWorldStore.new_record(CiconiWorldStore.seed_id_for_path(), initial)

	LLMManager.tracciato.apre_turno(stato.turno + 1, input_testo)
	LLMManager.tracciato.entra("azione del giocatore", input_testo)
	stato.turno += 1
	var turno := stato.turno
	agora.segna_turno(turno, input_testo, momento_corrente())
	var percorso: Array[String] = ["INTERPRETAZIONE"]
	var envelope: Dictionary = await LLMManager.interpreta(_testo_per_interprete(input_testo))
	var val := _valida(envelope, input_testo)
	percorso.append("VALIDAZIONE")

	var before_state: Dictionary = stato.ciconi_run.get("snapshot", {}).duplicate(true)
	var raw_action: Variant = envelope.get("world_action", null)
	var action: Dictionary = raw_action.duplicate(true) if raw_action is Dictionary else {}
	action["schema"] = CiconiContracts.ACTION_SCHEMA
	action["action_id"] = "%s:ciconi:%d" % [stato.run_id, turno]
	action["expected_world_version"] = int(before_state.get("world_version", 0))
	action["actor_id"] = "odysseus"  # Player turns never delegate actor authority to the LLM.

	var outcome: Dictionary
	if not bool(val.get("in_mondo", false)):
		outcome = {"schema": CiconiContracts.OUTCOME_SCHEMA, "status": "REJECTED", "reason": "outside_world", "attempt": action.duplicate(true), "events": [], "applied_facts": [], "event_batch": {}, "committed": false, "idempotent": false, "state": before_state.duplicate(true)}
	else:
		percorso.append("RULE_RESOLUTION")
		outcome = CiconiWorld.resolve(before_state, action)

	var committed_state: Dictionary = before_state
	if bool(outcome.get("committed", false)):
		percorso.append("INVARIANT_VALIDATION")
		var stored := CiconiWorldStore.append_outcome(stato.ciconi_run, outcome)
		if not bool(stored.get("ok", false)):
			push_error("GameManager: commit Ciconi rifiutato: %s" % stored.get("reason", "errore"))
			outcome = {"schema": CiconiContracts.OUTCOME_SCHEMA, "status": "REJECTED", "reason": "commit_failed", "attempt": action.duplicate(true), "events": [], "applied_facts": [], "event_batch": {}, "committed": false, "idempotent": false, "state": before_state.duplicate(true)}
		else:
			stato.ciconi_run = stored["record"]
			committed_state = stato.ciconi_run["snapshot"]
			percorso.append("COMMIT")

	var authoritative_copy := committed_state.duplicate(true)
	var world_hash_before_presentation := CiconiWorld.state_hash(authoritative_copy)
	var outcome_for_brief := outcome.duplicate(true)
	outcome_for_brief.erase("state")
	var brief := CiconiNarrative.brief(committed_state, outcome_for_brief, outcome.get("event_batch", {}), action)
	var views := {
		"narrator": CiconiNarrative.audience_view(brief, committed_state, "player"),
		"crew": CiconiNarrative.audience_view(brief, committed_state, "crew"),
		"olympus": CiconiNarrative.audience_view(brief, committed_state, "olympus"),
	}
	var narrator_brief := CiconiNarrative.brief_for_audience(brief, views["narrator"])
	percorso.append("NARRAZIONE")
	var rendered := await LLMManager.narrazione_ciconi(narrator_brief)
	var narrazione := String(rendered.get("text", ""))
	if CiconiWorld.state_hash(stato.ciconi_run.get("snapshot", {})) != world_hash_before_presentation:
		push_error("GameManager: un consumer narrativo ha mutato il Ciconi WorldState")
		stato.ciconi_run["snapshot"] = authoritative_copy.duplicate(true)

	var factual := CiconiNarrative.factual_memory(committed_state, outcome.get("event_batch", {}))
	var crew_factual := CiconiNarrative.factual_memory(committed_state, outcome.get("event_batch", {}), "crew")
	stato.cronaca = CiconiNarrative.factual_memory_text(committed_state)
	stato.cronaca_turno = turno
	_ultima_narrazione = narrazione
	stato.parole_ai_compagni.clear()
	var public_outcome := outcome.duplicate(true)
	public_outcome.erase("state")
	var quadro := {"schema": "ciconi-turn-view/1", "world_version": committed_state.get("world_version", 0), "narrative_brief": brief, "audiences": views}
	var voce := {"turno": turno, "input": input_testo, "envelope": envelope, "svegli": [], "episodio": "ciconi", "eventi_emessi": outcome.get("events", []).duplicate(true), "conflitto": false, "deliberazione": [], "verdetto": {}, "scavalcamento": {}, "resa_dei_conti": {}, "coalizioni": stato.coalizioni.duplicate(true), "delta": {}, "ammonizione": val.get("classe", "nessuna"), "narrazione_omero": narrazione, "world_outcome": public_outcome, "world_version": committed_state.get("world_version", 0), "factual_memory": factual, "quadro_narrativo": quadro, "rischio": rischio}
	stato.storico_olimpo.append(voce)
	stato.diario.append({"turno": turno, "voce": envelope.get("sintesi", input_testo), "esito": String(outcome.get("status", "REJECTED")).to_lower(), "world_version": committed_state.get("world_version", 0)})
	if not LLMManager.mock_mode and bool(outcome.get("committed", false)):
		call_deferred("_post_commit_ciconi_crew", input_testo, views["crew"].duplicate(true), crew_factual.duplicate(true))

	var spunti := _spunti_ciconi(committed_state)
	ricorda_spunti(spunti)
	LLMManager.tracciato.esce("ciconi world", "v%s · %s" % [committed_state.get("world_version", 0), outcome.get("status", "REJECTED")])
	LLMManager.tracciato.chiude_turno()
	return {"voce": voce, "svegli": [], "in_mondo": bool(val.get("in_mondo", false)), "esito": "continua", "congedo": "", "episodio": "ciconi", "avanzato": false, "causa": "", "intro": "", "transizione": "", "quadro_narrativo": quadro, "spunti": spunti, "fsm_path": percorso, "world_outcome": public_outcome, "audience_views": views}

func _post_commit_ciconi_crew(_input_testo: String, crew_view: Dictionary, factual: Dictionary) -> void:
	await _fa_parlare_la_ciurma("", "", false, -1, {"audience_view": crew_view, "factual_memory": factual})

func _spunti_ciconi(world_state: Dictionary) -> Array:
	for agreement in world_state.get("agreements", {}).values():
		if bool(agreement.get("active", false)) and String(agreement.get("kind", "")) == "ALLIANCE":
			return [{"testo": "Consolida i termini dell alleanza.", "rischio": false}, {"testo": "Chiedi viveri per il viaggio.", "rischio": false}, {"testo": "Torna alle navi senza rompere il patto.", "rischio": false}]
	return [{"testo": "Chiedi di negoziare con il capo.", "rischio": false}, {"testo": "Proponi uno scambio di vino e viveri.", "rischio": false}, {"testo": "Osserva le difese prima di agire.", "rischio": false}]

func _esegui_turno_legacy(input_testo: String, eventi: Array = [], rischio: bool = false) -> Dictionary:
	if stato == null:
		push_error("GameManager: nessuna partita attiva.")
		return {}
	if stato.stato != "in_corso":
		push_warning("GameManager: partita gia' conclusa (%s)." % str(stato.esito))
		return {}

	# Il confine fra un turno e l'altro nel tracciato. Senza, un file di mille righe e' una
	# colata continua: con questo, si scorre fino al turno che interessa e si legge da li'.
	LLMManager.tracciato.apre_turno(stato.turno + 1, input_testo)
	# COSA ENTRA. Un tracciato di sole chiamate HTTP racconta come ha risposto il modello, non
	# che cosa il gioco gli ha chiesto ne' con quale stato in mano — e fra le due cose c'e'
	# tutto il codice che abbiamo scritto noi, che e' anche quello che sbaglia piu' spesso.
	LLMManager.tracciato.entra("azione del giocatore", input_testo)
	var _stat: Dictionary = stato.ulisse.get("stat", {})
	LLMManager.tracciato.entra("scena", "%s · turno %d · stat %s" % [
		_episodio_corrente(), stato.turno + 1, str(_stat)])

	var percorso: Array[String] = []
	stato.turno += 1
	var turno := stato.turno
	# La fotografia PRECEDE ogni conseguenza del turno. E' player-facing: niente registro
	# divino o identita' nascoste. Anche se piu' avanti Viaggio entra nella tappa nuova,
	# questa copia resta l'origine autorevole della narrazione atomica.
	var episodio_prima := _episodio_corrente()
	var stato_narrativo_prima := _stato_narrativo(episodio_prima)
	var momento_turno := momento_corrente()

	# RESA DEI CONTI — Zeus verifica gli scavalcamenti pendenti: il sospetto sale, e
	# alla soglia scopre il colpevole (cova ira, e il conto rimbalza su Ulisse).
	percorso.append(Fase.keys()[Fase.RESA_DEI_CONTI])
	var resa := _politica.resa_dei_conti()

	# Il collante fra le viste: cosa e' successo, e quando. Va segnato PRIMA che chiunque
	# scriva in chat, o le prime battute del turno resterebbero senza intestazione.
	agora.segna_turno(turno, input_testo, momento_turno)

	# INTERPRETAZIONE — testo libero -> envelope (Interprete via LLMManager).
	percorso.append(Fase.keys()[Fase.INTERPRETAZIONE])
	var envelope: Dictionary = await LLMManager.interpreta(_testo_per_interprete(input_testo))

	# VAGLIO — secondo parere dedicato sulla plausibilita' (vedi _vaglia_plausibilita).
	await _vaglia_plausibilita(envelope, input_testo)

	# VALIDAZIONE — scala diegetica dell'ammonizione (design sez. 6). Un input
	# fuori dal mondo non e' un errore: e' richiamo, poi smarrimento, poi follia.
	percorso.append(Fase.keys()[Fase.VALIDAZIONE])
	var val := _valida(envelope, input_testo)
	var in_mondo: bool = val["in_mondo"]

	# RISVEGLIO — selezione deterministica dei dei che reagiscono.
	var svegli: Array[String] = []
	var proposte: Array = []
	var verdetto: Dictionary = {}
	var scavalcamento: Dictionary = {}
	var delta: Dictionary = val["delta"]  # fuori-mondo: smarrimento/follia (vuoto se in_mondo)
	var conflitto := false
	# Eventi di mondo attivi in questa tappa (es. 'passaggio' nello stretto), uniti a
	# quelli passati dall'esterno: li legge il risveglio.
	var eventi_turno := _eventi_del_turno(eventi)
	_registra_eventi_accaduti(envelope, eventi_turno)
	if in_mondo:
		percorso.append(Fase.keys()[Fase.RISVEGLIO])
		await _risolvi_invocazione(envelope, input_testo)
		svegli = PantheonManager.risveglio(envelope, eventi_turno, _episodio_corrente(),
			stato.eventi_accaduti)
		_segna_in_gioco(svegli)
		_annuncia_risvegli(svegli)
		if not svegli.is_empty():
			_progresso_olimpo("risvegli")

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
					verdetto["attore"], verdetto["registro"],
					forza_con_rischio(int(verdetto["intensita"]), rischio)))

			# SCAVALCAMENTO — un dio punitivo bocciato puo' agire di nascosto (raro):
			# applica il suo delta all'insaputa di Zeus e lascia una traccia (pendente).
			scavalcamento = _politica.tenta_scavalcamento(proposte, verdetto)
			if not scavalcamento.is_empty():
				percorso.append(Fase.keys()[Fase.SCAVALCAMENTO])
				delta = Delta.unisci(delta, scavalcamento["delta"])

			# Ogni dio che ha agito se ne fa un ricordo. Va scritto QUI, quando il verdetto
			# e' noto e l'eventuale scavalcamento e' avvenuto: prima non si saprebbe com'e'
			# andata, e "come e' andata" e' meta' del ricordo.
			_annota_nella_memoria(proposte, verdetto, scavalcamento, envelope)

	# Coalizioni (fase 6-bis): decadono ogni turno e, raramente, se ne formano di nuove
	# dal blocco di dei punitivi della stessa fazione (proposte vuote se nessuno ha reagito).
	_politica.aggiorna_coalizioni(proposte)

	# La ripercussione della resa dei conti (rimbalzo su Ulisse) confluisce nel turno.
	delta = Delta.unisci(delta, resa.get("delta", {}))

	# APPLICAZIONE del delta (reazione divina in_mondo, smarrimento/follia, resa, scavalcamento).
	Delta.applica(stato, delta)

	# PRIGIONIA / ESITO appartengono ancora alla tappa PRIMA. Vanno risolti prima che
	# Viaggio possa mutarla, altrimenti indugiare a Ogigia verrebbe giudicato dalla scena
	# successiva. Omero ricevera' il risultato, non lo decidera'.
	var prigionia := _trattiene(envelope, in_mondo)
	if prigionia == "prigionia":
		val["classe"] = "prigionia"
	percorso.append(Fase.keys()[Fase.ESITO])
	var esito: String = val["esito"] if val["esito"] != "continua" else _controlla_esito()
	if esito == "continua" and prigionia == "prigionia_eterna":
		esito = prigionia

	# AVANZAMENTO PRIMA DELLA PROSA. `Viaggio` resta l'unica autorita': incrementa il
	# contatore, decide l'unica tappa successiva e applica il cambio. Non c'e' piu' una
	# seconda chiamata `_passaggio`; da/a/causa entreranno nello stesso quadro del turno.
	percorso.append(Fase.keys()[Fase.AVANZAMENTO])
	var grado_pressione := viaggio.grado_pressione()
	var avanzamento := {"avanzato": false, "intro": "", "episodio": episodio_prima,
		"esito": "continua", "causa": "", "da": "", "a": "", "chiude": ""}
	if esito == "continua" and in_mondo:
		avanzamento = _avanza_episodio(envelope)
		esito = avanzamento["esito"]
	if bool(avanzamento.get("avanzato", false)) and String(avanzamento.get("causa", "")) == "prodigio":
		grado_pressione = Viaggio.GRADO_SPINTA

	# Il quadro vede lo stato DOPO realmente applicato. Itaca e' un caso speciale di
	# Viaggio: il risultato dice `itaca` senza chiamare entra(), quindi l'id viene dal
	# risultato e non dal solo `stato.viaggio.corrente`.
	var episodio_dopo := String(avanzamento.get("episodio", episodio_prima))
	var stato_narrativo_dopo := _stato_narrativo(episodio_dopo)
	var passaggio := _passaggio_narrativo(avanzamento, episodio_prima)
	var quadro_narrativo: Dictionary = {}

	# NARRAZIONE — una sola chiamata contiene azione, conseguenze e traversata eventuale.
	# Fuori-mondo Omero continua a tacere: al giocatore va il richiamo diegetico.
	percorso.append(Fase.keys()[Fase.NARRAZIONE])
	var impronta := ""
	if not verdetto.is_empty():
		var attore: Dio = PantheonManager.get_dio(verdetto["attore"])
		if attore != null:
			impronta = attore.impronta
	var narrazione := ""
	var spunti: Array = []
	if in_mondo:
		quadro_narrativo = _quadro_del_turno(stato_narrativo_prima, stato_narrativo_dopo,
			envelope, input_testo, delta, eventi_turno, esito, grado_pressione,
			bool(avanzamento.get("avanzato", false)) and String(avanzamento.get("causa", "")) == "prodigio",
			passaggio, momento_turno, impronta)
		var controllo_quadro := QuadroNarrativo.valida(quadro_narrativo)
		if not bool(controllo_quadro["ok"]):
			push_error("GameManager: quadro narrativo non valido: %s" % "; ".join(controllo_quadro["errori"]))
		else:
			# La Vista Olimpo ha gia' ricevuto risvegli e battute prima che Omero parli.
			_progresso_olimpo("narrazione")
			var ctx := _contesto_omero_da_quadro(quadro_narrativo, delta, impronta)
			var r: Dictionary = await LLMManager.narrazione_e_spunti(ctx)
			narrazione = String(r.get("narrazione", ""))
			spunti = r.get("spunti", []) if esito == "continua" else []
			_ultima_narrazione = narrazione
			# Il profilo dedicato resta compatibile: legge i campi legacy player-facing
			# affiancati al quadro e parte comunque dallo stato dopo.
			if esito == "continua" and Costi.acceso("spunti_separati"):
				ctx["narrazione"] = narrazione
				var sp: Array = await LLMManager.suggerisci(ctx)
				if not sp.is_empty():
					spunti = sp
	# Gli appigli appartengono alla tappa DOPO, perche' Viaggio ha gia' applicato il cambio.
	ricorda_spunti(spunti)

	# LA CIURMA commenta la sola voce atomica. Le parole sospese sono state consegnate e
	# possono essere cancellate soltanto dopo che anche Omero le ha ricevute.
	await _fa_parlare_la_ciurma(input_testo, narrazione)
	stato.parole_ai_compagni.clear()

	# La voce resta attribuita all'episodio prima anche se lo stato e' gia' nella tappa
	# nuova. Il quadro completo resta nella traccia per rendere osservabile il contratto.
	var voce := _registra(turno, input_testo, envelope, svegli, eventi_turno, conflitto,
		proposte, verdetto, scavalcamento, resa, delta, val, narrazione, in_mondo,
		episodio_prima, quadro_narrativo)
	voce["rischio"] = rischio

	var congedo := ""
	if esito != "continua":
		stato.stato = "finita"
		stato.esito = esito
		# L'arrivo a Itaca e' gia' dentro la singola voce atomica. Gli altri finali
		# conservano il loro epitaffio dedicato (fuori-mondo compreso).
		if not bool(avanzamento.get("avanzato", false)):
			congedo = await _congedo(esito)
	else:
		await _aggiorna_cronaca_se_serve()

	# COSA ESCE. Il risultato che il giocatore vede, e il segno lasciato sugli dei: e' il
	# lato del confine che nessuna riga HTTP racconta. Poi il consuntivo — quanto e' durato
	# il turno e chi se l'e' preso — che e' la riga per cui il tracciato esiste.
	var t := LLMManager.tracciato
	t.esce("narrazione", "%d caratteri" % narrazione.length() if narrazione != "" else "(nessuna)")
	t.esce("spunti", "%d" % spunti.size())
	t.esce("dei svegliati", ", ".join(svegli) if not svegli.is_empty() else "(nessuno)")
	if not delta.is_empty():
		t.esce("delta", str(delta))
	if not verdetto.is_empty():
		t.esce("verdetto", "%s → %s" % [verdetto.get("attore", "?"), verdetto.get("registro", "?")])
	if esito != "continua":
		t.esce("esito", esito)
	t.chiude_turno()

	return {
		"voce": voce,
		"svegli": svegli,
		"in_mondo": in_mondo,
		"esito": esito,
		"congedo": congedo,   # l'ultima voce di Omero, se la partita e' finita
		"episodio": avanzamento["episodio"],
		"avanzato": avanzamento["avanzato"],
		# PERCHE' si e' cambiata scena (R-12): senza questo la causa resterebbe dentro il
		# motore, e chi guarda il turno da fuori — la UI, i test, il golden trace — non
		# potrebbe accorgersi di un cambio di scena rimasto senza spiegazione.
		"causa": avanzamento.get("causa", ""),
		"intro": avanzamento["intro"],
		"transizione": "",  # la traversata e' gia' nella voce atomica di Omero
		"quadro_narrativo": quadro_narrativo.duplicate(true),
		"spunti": spunti,   # gia' pronti: nessuna seconda chiamata dopo la narrazione
		"fsm_path": percorso,
	}

## Registri che "puniscono" vs "aiutano": il loro incontro definisce il conflitto.
const _REGISTRI_PUNITIVI := ["castigo", "aiuto_negato", "trappola"]
const _REGISTRI_BENIGNI := ["aiuto", "segno"]

## Deliberazione. Ritorna {proposte, conflitto, verdetto}.
## - proposte aperte (round 1); si scartano i 'silenzio'.
## - se le proposte attive confliggono: round 2 di repliche (i dei si sentono tra loro)
##   e verdetto di Zeus (Arbitro LLM). Altrimenti verdetto deterministico.
## Quanti dèi possono ribattere in un turno. Ogni replica e' una chiamata: il dialogo
## dev'essere una conversazione, non un costo che cresce con gli dèi in campo.
## Il tetto vive nel PROFILO DI COSTO, non piu' come costante: chi gioca su un piano a
## pagamento non ha ragione di subirlo. Resta una costante come ripiego e come riferimento
## del valore con cui il gioco e' stato tarato.
const MAX_REPLICHE := 2

func max_repliche() -> int:
	return Costi.limite("max_repliche", MAX_REPLICHE)

func _delibera(svegli: Array, envelope: Dictionary) -> Dictionary:
	var proposte := await _raccogli_proposte(svegli, envelope, [])
	var attive := _attive(proposte)
	if attive.is_empty():
		return {"proposte": proposte, "conflitto": false, "verdetto": {}}

	# SI RIBATTE APPENA C'E' QUALCUNO A CUI RIBATTERE, non solo quando si litiga.
	# Prima le repliche partivano soltanto in caso di conflitto: due dèi d'accordo
	# deponevano uno dopo l'altro e la Vista Olimpo restava un verbale. La contesa e' una
	# delle cose che si dicono, non la sola.
	var conflitto := attive.size() > 1 and _in_conflitto(attive)
	if attive.size() > 1:
		attive = await _repliche(attive, envelope)

	if not conflitto:
		var prep := _prepara_per_arbitrato(attive)
		var v := _arbitra(prep)
		var id_vincitore := String(v.get("attore", ""))
		var vincitore: Dio = PantheonManager.get_dio(id_vincitore)
		_progresso_olimpo("attesa", vincitore.nome if vincitore else id_vincitore)
		_verdetto_in_chat(v, false, prep)
		return {"proposte": prep, "conflitto": false, "verdetto": v}

	# CONFLITTO: dopo il botta e risposta, Zeus chiude.
	var prep_c := _prepara_per_arbitrato(attive)
	_progresso_olimpo("attesa", "Zeus")
	var verdetto: Dictionary = await LLMManager.verdetto_arbitro(prep_c)
	_verdetto_in_chat(verdetto, true, prep_c)
	return {"proposte": prep_c, "conflitto": true, "verdetto": verdetto}

## Sfondo (fase 6-bis) sulle proposte prima del verdetto: strategie (piano) e peso di
## coalizione. Modulano l'intensita', non sostituiscono la scelta LLM del registro.
func _prepara_per_arbitrato(proposte: Array) -> Array:
	return _politica.prepara_per_arbitrato(proposte)

## La TRACOTANZA si paga: oltre la soglia, chi punisce colpisce piu' forte. Prima la
## hybris saliva senza mai avere conseguenze — era un numero decorativo.
@onready var _SOGLIA_HYBRIS: int = Bilanciamento.intero("ulisse/soglia_hybris", 50)

func _raccogli_proposte(svegli: Array, envelope: Dictionary, altri: Array) -> Array:
	var out: Array = []
	for id in svegli:
		var dio: Dio = PantheonManager.get_dio(id)
		_progresso_olimpo("attesa", dio.nome if dio else id)
		var p: Dictionary = await LLMManager.proposta_dio(dio, _contesto_dio(id, envelope, altri))
		out.append(p)
		_in_chat(p)
	return out

## Round 2: ogni dio ribatte vedendo le proposte degli ALTRI.
## Il botta e risposta: ogni dio rilegge cio' che hanno detto gli ALTRI e ribatte.
## Al massimo MAX_REPLICHE voci — ogni replica e' una chiamata, e una conversazione a
## cinque non e' piu' una conversazione. Chi replica sono i primi in ordine di pantheon,
## quindi in modo deterministico e riproducibile.
## Chi non replica tiene la sua proposta: non sparisce dal campo.
func _repliche(attive: Array, envelope: Dictionary) -> Array:
	var out: Array = []
	for i in attive.size():
		var p: Dictionary = attive[i]
		if i >= max_repliche():
			out.append(p)
			continue
		var id: String = p.get("dio", "")
		var altri := _altri_dei(attive, id)
		var dio: Dio = PantheonManager.get_dio(id)
		_progresso_olimpo("attesa", dio.nome if dio else id)
		var r: Dictionary = await LLMManager.proposta_dio(dio, _contesto_dio(id, envelope, altri))
		# Se il modello non produce nulla di nuovo, resta valida la prima proposta: meglio
		# una voce sola che una voce persa.
		if String(r.get("dice", "")).strip_edges() == "":
			out.append(p)
			continue
		out.append(r)
		_in_chat(r)
	return out

func _contesto_dio(id: String, envelope: Dictionary, altri: Array) -> Dictionary:
	var reg: Dictionary = stato.registro_divino.get(id, {})
	return {
		"favore": reg.get("favore", 0),
		"ira": reg.get("ira", 0),
		"umore": reg.get("umore", ""),
		"envelope": envelope,
		"altri_dei": altri,
		"cronaca": stato.cronaca,  # anche i dei sanno cos'e' accaduto finora
		"detto_ai_compagni": _parole_in_sospeso(),  # cio' che ha mormorato a bordo
		# Il suo taccuino: i recenti per esteso, il resto condensato in una frase.
		"memoria": ricordi_recenti(id),
		"memoria_riassunto": riassunto_memoria(id),
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

# --- Fase 6-bis: strategie (piano) ---

# --- Fase 6-bis: coalizioni ---

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
		"gesto": best.get("gesto", ""),
	}

## IL BIVIO, senza una seconda macchina del turno.
##
## Il design (sez. 4) voleva «scelte discrete per i bivi veri: Scilla o Cariddi? apri
## l'otre?». Costruirle davvero significherebbe un secondo tipo di turno, con rami scritti
## a mano tappa per tappa. Ma il campo `rischio` esiste gia' negli spunti — Omero marca col
## «!» quelli pericolosi — e finora serviva solo a colorare un bottone.
##
## Prendere un appiglio rischioso e' un IMPEGNO: la GUI chiede conferma e non lascia
## correggere la frase, e la reazione degli dei sale di un grado — in QUALUNQUE direzione
## abbiano scelto. Chi rischia rischia davvero: il castigo morde di piu', ma anche l'aiuto
## vale di piu'. E' un bivio, non una penalita' mascherata.
##
## Questa e' la parte deterministica, cioe' la garanzia: il resto (la conferma) e' forma.
static func forza_con_rischio(intensita: int, rischio: bool) -> int:
	return clampi(intensita + (1 if rischio else 0), 1, 3)

## Validazione/ammonizione e vaglio della plausibilita' vivono in Validazione (scripts/).
## Qui restano solo i due punti di ingresso, per non spargere la regola in due posti.
## IL GIOCO NON PUO' RIFIUTARE CIO' CHE HA APPENA PROPOSTO.
##
## Successo sul campo: fra i tre spunti c'era «Sguaina il bronzo e rispondi all'affronto
## con il ferro che i Ciconi rispettano» — perfettamente omerica — e cliccarla dava «Quel
## gesto non appartiene a questo mondo». Il vaglio passa da un LLM, quindi sbaglia: e'
## inevitabile. Ma su un testo che ha scritto Omero non c'e' niente da vagliare, e' in
## mondo per costruzione. Saltarlo toglie la contraddizione E una chiamata.
##
## La salvaguardia deterministica (i marcatori) NON si scavalca: se qualcuno mettesse un
## anacronismo vero fra gli spunti, quello resta fuori.
##
## LA PROMESSA NON HA CLAUSOLE. Fino al 9 agosto 2026 ne aveva una — `and not
## Costi.acceso("vaglia_sempre")` — e col profilo «Senza vincoli di costo» il gioco tornava a
## bocciare i propri suggerimenti: tre appigli generati dal gioco, cliccati, respinti come
## anacronismi. Un'impostazione di costo puo' decidere quanto il gioco SPENDE, mai se il
## gioco si CONTRADDICE: il vaglio degli appigli resta, ma solo per guardare.
func _vaglia_plausibilita(envelope: Dictionary, input_testo: String) -> void:
	if gia_proposto(input_testo):
		if not _validazione.e_anacronistico(input_testo):
			envelope["plausibilita"] = "in_mondo"
			if Costi.acceso("vaglia_sempre"):
				await _sorveglia_appiglio(input_testo)
			return
	await _validazione.vaglia(envelope, input_testo)

## Il vaglio sugli appigli offerti, col profilo che lo chiede: PARTE, e non decide niente.
## Se il Vaglio boccia un testo che ha scritto Omero, il difetto sta nel prompt di Omero —
## e questa riga e' l'unica cosa che quella spesa deve comprare. Chi tara i prompt la trova
## in `app-*.log`; il giocatore non se ne accorge, ed e' giusto cosi'.
func _sorveglia_appiglio(input_testo: String) -> void:
	var classe: String = await LLMManager.verifica_plausibilita(input_testo)
	if classe != "" and classe != "in_mondo":
		Registro.avviso("spunti", "il Vaglio boccia un appiglio offerto dal gioco (%s): «%s» — la promessa tiene, il prompt di Omero e' da rivedere" % [classe, input_testo])

## GLI SPUNTI SONO UNA PROMESSA: cio' che il gioco offre, il gioco lo accetta e lo sa
## rendere. Sul campo la promessa si e' rotta in tre modi, tutti qui:
##  - fra le frasi e' comparso «---SPUNTI», cioe' l'impalcatura del prompt;
##  - sono arrivati anacronismi, che poi il gioco stesso avrebbe respinto;
##  - all'isola di Eolo veniva proposto «apri l'otre», e Eolo l'otre non l'ha ancora dato.
## Il prompt puo' chiedere tutto questo, ma resta una preghiera: questa e' la garanzia.
func filtra_spunti(spunti: Array) -> Array:
	return viaggio.filtra_spunti(spunti) if viaggio else []

## Quanti appigli si offrono. Tre e' il numero con cui il gioco e' stato scritto: due sono
## un aut-aut, quattro sono un menu.
const QUANTI_SPUNTI := 3

## CIO' CHE ARRIVA A SCHERMO, deciso in un posto solo.
##
## Oltre al filtro (la promessa: cio' che offro, lo accetto) qui cade una seconda scure:
## NIENTE BIVI FRA GLI APPIGLI. Il campo `rischio` era nato per marcarli — segno «‡»,
## conferma obbligatoria, reazione degli dei amplificata — e all'atto pratico spezzava la
## lettura: fra tre frasi omeriche ne compariva una con un simbolo strano che apriva una
## finestrella. Ora `rischio: true` vuol dire una cosa sola, e piu' semplice: *questo non si
## propone*. Rischiare resta possibile — si scrive nel campo libero, che e' il posto giusto
## per una cosa che nessuno ti ha suggerito.
##
## Scartare senza rimpiazzare darebbe due appigli nei turni in cui il modello ne marca uno,
## e il giocatore vedrebbe l'interfaccia assottigliarsi senza capire perche'. Il vuoto si
## ricuce con gli appigli della tappa, che sanno dove ti trovi.
func spunti_da_mostrare(spunti: Array) -> Array:
	var out: Array = []
	var visti := {}
	for fonte in [spunti, spunti_di_riserva()]:
		for s in filtra_spunti(fonte):
			if out.size() >= QUANTI_SPUNTI:
				break
			if bool(s.get("rischio", false)):
				continue
			var t := String(s.get("testo", "")).strip_edges()
			var chiave := t.to_lower()
			if t == "" or visti.has(chiave):
				continue
			visti[chiave] = true
			out.append(s)
	return out

## Gli appigli quando quelli generati non reggono: SOLO quelli della tappa, che sanno dove
## ti trovi e cosa sta succedendo li'. Gli appigli generici sono stati tolti — tre frasi
## buone per ogni occasione non erano buone per nessuna: «piega ai remi e prosegui la
## rotta» compariva anche mentre Ulisse era chiuso nell'antro del Ciclope.
## Se una tappa non ne dichiara, non si inventa niente: il campo libero c'e' sempre.
func spunti_di_riserva() -> Array:
	return viaggio.spunti_di_riserva() if viaggio else []

## Pubblica: anche la schermata iniziale genera spunti (fuori da un turno), e anche quelli
## il gioco non deve poterli rifiutare. Si ricorda solo cio' che ha superato il filtro.
func ricorda_spunti(spunti: Array) -> void:
	stato.spunti_proposti.clear()
	for s in filtra_spunti(spunti):
		var t := String(s.get("testo", "")).strip_edges()
		if t != "":
			stato.spunti_proposti.append(t)

## Vero se il testo e' uno degli spunti che il gioco sta mostrando adesso. Confronto
## tollerante su spazi e maiuscole: il bottone incolla il testo nel campo, e da li' puo'
## passare di tutto.
func gia_proposto(testo: String) -> bool:
	var t := testo.strip_edges().to_lower()
	if t == "":
		return false
	for s in stato.spunti_proposti:
		if String(s).strip_edges().to_lower() == t:
			return true
	return false

func _valida(envelope: Dictionary, input_testo: String) -> Dictionary:
	return _validazione.valida(envelope, input_testo)

func _episodio_corrente() -> String:
	return viaggio.corrente() if viaggio else ""

## Fotografia player-facing usata dal quadro. Non contiene registro divino, memorie,
## coalizioni o altre cause nascoste: Omero vede soltanto cio' che il mondo ha gia' reso
## vero per Ulisse. L'id esplicito serve anche a Itaca, che conclude il viaggio senza
## dover aprire un ulteriore turno nella nuova tappa.
func _stato_narrativo(episodio_id: String) -> Dictionary:
	var ep: Episodio = episodi.get_episodio(episodio_id) if episodi else null
	var turno_nella_tappa := int(stato.viaggio.get("turni_in_episodio", 0))
	if episodio_id != _episodio_corrente():
		turno_nella_tappa = 0
	var caduti: Array = []
	if ciurma:
		caduti = ciurma.caduti.duplicate(true)
	return {
		"episodio": {
			"id": episodio_id,
			"nome": ep.nome if ep else episodio_id,
			"scena": ep.scena if ep else "",
		},
		"ulisse": {
			"stat": stato.ulisse.get("stat", {}).duplicate(true),
			"hybris": int(stato.ulisse.get("hybris", 0)),
			"cimeli": stato.ulisse.get("cimeli", []).duplicate(true),
		},
		"viaggio": {
			"turni_in_episodio": turno_nella_tappa,
			"completati": stato.viaggio.get("completati", []).duplicate(true),
		},
		"eventi_accaduti": stato.eventi_accaduti.duplicate(true),
		"ciurma_caduti": caduti,
	}

## La rotta viene sempre dai dati degli episodi: nessuna copia del poema nel codice del
## quadro e nessun ramo che il modello possa scegliere.
func _politica_narrativa() -> Dictionary:
	var ordine: Array = episodi.ordine() if episodi else []
	var nomi := {}
	for id in ordine:
		var ep: Episodio = episodi.get_episodio(String(id))
		nomi[String(id)] = ep.nome if ep else String(id)
	return QuadroNarrativo.politica_rotta_fissa(ordine, nomi)

## `Viaggio` decide il cambio; questo helper gli da' soltanto la forma del contratto.
func _passaggio_narrativo(avanzamento: Dictionary, episodio_prima: String) -> Dictionary:
	if not bool(avanzamento.get("avanzato", false)):
		return {}
	var episodio_dopo := String(avanzamento.get("episodio", ""))
	var ep_prima: Episodio = episodi.get_episodio(episodio_prima) if episodi else null
	var ep_dopo: Episodio = episodi.get_episodio(episodio_dopo) if episodi else null
	return {
		"avvenuto": true,
		"da": {"id": episodio_prima, "nome": ep_prima.nome if ep_prima else String(avanzamento.get("da", episodio_prima))},
		"a": {"id": episodio_dopo, "nome": ep_dopo.nome if ep_dopo else String(avanzamento.get("a", episodio_dopo))},
		"causa": String(avanzamento.get("causa", "")),
	}

## Dal delta completo cade ogni path privato di un dio. Il cambiamento numerico di Ulisse
## resta invece autorevole e rende impossibile alla prosa aumentare perdite o benefici.
func _delta_visibile(delta: Dictionary) -> Dictionary:
	var out := {}
	for path in delta:
		if String(path).begins_with("ulisse."):
			out[path] = delta[path]
	return out

func _fatti_del_turno(delta: Dictionary, eventi_turno: Array, impronta: String) -> Array:
	var fatti: Array = []
	var segno := _segno_esito(delta)
	if segno != "":
		fatti.append(segno)
	for evento in eventi_turno:
		var leggibile := String(evento).replace("_", " ").strip_edges()
		if leggibile != "":
			fatti.append(leggibile)
	if impronta.strip_edges() != "":
		fatti.append(impronta.strip_edges())
	return fatti

func _quadro_del_turno(stato_prima: Dictionary, stato_dopo: Dictionary,
		envelope: Dictionary, input_testo: String, delta: Dictionary, eventi_turno: Array,
		esito: String, grado_pressione: int, pressione_spinge: bool, passaggio: Dictionary,
		momento: String, impronta: String) -> Dictionary:
	var fatti := _fatti_del_turno(delta, eventi_turno, impronta)
	var conseguenze := {
		"delta": _delta_visibile(delta),
		"eventi": eventi_turno.duplicate(true),
		"fatti": fatti.duplicate(true),
		"esito": esito,
		"pressione": {"grado": grado_pressione, "spinge": pressione_spinge},
	}
	var vietati: Array = [
		{"id": "nave_perduta", "descrizione": "la perdita permanente di una nave",
			"marcatori": ["una nave affondo'", "perdettero una nave", "una nave ando' perduta"]},
		{"id": "nuova_perdita", "descrizione": "una perdita permanente non decisa dal motore",
			"marcatori": ["morirono altri compagni", "un altro compagno mori'"]},
	]
	return QuadroNarrativo.crea(stato_prima, {
		"testo": input_testo,
		"sintesi": String(envelope.get("sintesi", input_testo)),
		"tipo": String(envelope.get("tipo", "azione")),
		"tag": envelope.get("tag", []).duplicate(true),
	}, conseguenze, stato_dopo, momento, fatti, vietati, passaggio,
		_politica_narrativa())

## Il Narratore privilegia il quadro; i campi affiancati mantengono compatibili il mock e
## il Suggeritore separato, ma sono anch'essi player-facing e descrivono lo stato dopo.
func _contesto_omero_da_quadro(quadro: Dictionary, delta: Dictionary,
		impronta: String) -> Dictionary:
	var ctx := QuadroNarrativo.come_contesto_omero(quadro)
	var dopo: Dictionary = quadro.get("stato_dopo", {})
	var ep: Dictionary = dopo.get("episodio", {})
	ctx.merge({
		"scena": String(ep.get("scena", "")),
		"cronaca": stato.cronaca,
		"storia": _storia_recente(),
		"ultima_narrazione": _ultima_narrazione,
		"luogo": String(ep.get("nome", "")),
		"progresso": _progresso_viaggio(),
		"morale": _morale_recente(),
		"delta": _delta_visibile(delta),
		"impronta": impronta,
		"esito_segno": _segno_esito(delta),
		"detto_ai_compagni": _parole_in_sospeso(),
		"momento": String(quadro.get("momento", "")),
	}, true)
	return ctx

## Quel che ACCADE resta accaduto. Una tappa puo' dichiarare che un certo tag dell'azione
## fa succedere un evento (nell'antro, il vanto di Ulisse chiama la maledizione di
## Polifemo): da li' in poi chi dormeva in attesa di quell'evento e' sveglio per sempre.
func _registra_eventi_accaduti(envelope: Dictionary, eventi_turno: Array) -> void:
	viaggio.registra_eventi_accaduti(envelope, eventi_turno)

## Eventi di mondo del turno: quelli della tappa corrente + quelli passati dall'esterno.
func _eventi_del_turno(eventi: Array) -> Array:
	return viaggio.eventi_del_turno(eventi)

## AVANZAMENTO della tappa. Ritorna {esito, avanzato, intro, episodio, da, a, causa}.
## Si avanza se compare l'azione di progresso (avanza_su_tag) o si tocca il tetto turni.
## Entrare in Itaca = vittoria (esito "itaca").
## AVANZAMENTO. La DECISIONE (si chiude? qual e' la prossima?) sta in Viaggio, che non
## chiama mai l'LLM; qui resta soltanto la conseguenza deterministica sui compagni. La
## traversata entra poi nel quadro e viene narrata insieme al resto del turno.
func _avanza_episodio(envelope: Dictionary) -> Dictionary:
	var a := viaggio.avanza(envelope)
	if String(a["chiude"]) != "":
		_fai_cadere_i_destinati(String(a["chiude"]))
	if not a["avanzato"]:
		return {"esito": "continua", "avanzato": false, "intro": "",
			"episodio": a["episodio"], "causa": "", "da": "", "a": "",
			"chiude": "", "transizione": ""}
	return {
		"esito": a["esito"], "avanzato": true, "intro": a["intro"], "episodio": a["episodio"],
		"causa": a.get("causa", ""), "da": a.get("da", ""), "a": a.get("a", ""),
		"chiude": a.get("chiude", ""), "transizione": "",
	}

## Una tappa che TRATTIENE (Ogigia) ammonisce chi indugia, e alla terza volta lo tiene per
## sempre. La regola sta in Viaggio: e' una proprieta' della tappa, non del turno.
func _trattiene(envelope: Dictionary, in_mondo: bool) -> String:
	return viaggio.trattiene(envelope, in_mondo)

## IL CONGEDO: l'ultima voce di Omero, quando la partita finisce.
##
## Prima si chiudeva con «— FINE: follia —»: una riga di verbale in fondo a un poema. Un
## gioco che per venti turni ti ha parlato con la voce di un aedo non puo' congedarti come
## un modulo che si chiude — e l'ultima cosa che si legge e' quella che resta.
##
## Lo scrive Omero (UNA chiamata, e solo a partita finita: non pesa sul turno). Il testo di
## ripiego pero' non e' un ripiego qualunque: e' cio' che si legge col motore simulato, nei
## test, e ogni volta che il modello non risponde. Sta nei dati, ed e' gia' epico di suo.
## Vale l'invariante: nemmeno qui si nomina un dio.
func _congedo(esito: String) -> String:
	var chiave := "gioco/epitaffio_%s" % esito
	if not Testi.ha(chiave):
		return ""   # questo finale non ha (ancora) un commiato suo: meglio niente
	var ripiego := Testi.s(chiave)
	var scritto: String = await LLMManager.narrazione_omero({
		"congedo": {
			"esito": esito,
			"luogo": _nome_tappa_corrente(),
			"cronaca": stato.cronaca,
			"modello": ripiego,   # il tono da tenere, non un testo da copiare
		},
	})
	return scritto.strip_edges() if scritto.strip_edges() != "" else ripiego

## Riferimento allusivo a un dio: se Ulisse invoca/supplica (anche per epiteto:
## "il capo dell'olimpo") senza che l'envelope abbia gia' un dio_invocato valido,
## lo risolviamo deterministicamente dal testo. Gated sull'INTENTO di invocazione
## (preghiera/supplica): una menzione di passaggio non deve svegliare un dio.
func _risolvi_invocazione(envelope: Dictionary, input_testo: String) -> void:
	var attuale: Variant = envelope.get("dio_invocato", null)
	if attuale != null and PantheonManager.pantheon.ha(String(attuale)):
		return  # l'Interprete/LLM ha gia' fornito un id valido
	var dett := PantheonManager.risolvi_invocato_dett(input_testo)
	var id: String = dett["id"]
	if id != "":
		# Nominare un dio per NOME PROPRIO ("Atena, portami a casa") e' invocazione diretta:
		# sveglia comunque, anche se l'LLM ha classificato l'input come semplice azione.
		# L'epiteto ALLUSIVO ("il capo dell'olimpo"), piu' ambiguo, richiede invece l'intento
		# di preghiera/supplica, per non svegliare un dio a ogni menzione di passaggio.
		if dett["per_nome"] or _ha_intento_invocazione(envelope):
			envelope["dio_invocato"] = id
		return
	# IBRIDO: il deterministico non ha trovato nulla. Se c'e' un indizio di invocazione,
	# chiedo all'LLM di riconoscere un riferimento anche PARAFRASATO (output vincolato agli
	# id del pantheon). In mock ritorna "": i test restano deterministici.
	if _indizio_invocazione(envelope, input_testo):
		var llm_id: String = await LLMManager.identifica_dio(input_testo)
		if llm_id != "" and PantheonManager.pantheon.ha(llm_id):
			envelope["dio_invocato"] = llm_id

## Parole che segnalano un'invocazione/preghiera: delimitano quando vale la pena spendere


## Vero se c'e' motivo di sospettare un'invocazione (per gate della chiamata LLM ibrida).
func _indizio_invocazione(envelope: Dictionary, input_testo: String) -> bool:
	if Costi.acceso("ricognizione_sempre"):
		return true   # profilo senza vincoli: si cerca comunque, anche senza indizi
	if _ha_intento_invocazione(envelope):
		return true
	if envelope.get("tipo", "") == "rituale":
		return true
	var t := input_testo.to_lower()
	for cue in Lingua.cue_invocazione():
		if t.find(cue) != -1:
			return true
	return false

func _ha_intento_invocazione(envelope: Dictionary) -> bool:
	if envelope.get("tipo", "") == "preghiera":
		return true
	var tag: Array = envelope.get("tag", [])
	return tag.has("preghiera") or tag.has("supplica")

## Un dio che si sveglia entra "in gioco" (utile per i locali; i persistenti lo sono gia').
## Chi si desta lo mostra nel canale: e' il momento in cui un dio "entra in chat".
func _annuncia_risvegli(svegli: Array) -> void:
	for id in svegli:
		var dio := PantheonManager.get_dio(id)
		if dio:
			agora.scrivi(Agora.CANALE_OLIMPO, dio.nome, "si desta.", stato.turno, "azione", dio.simbolo)

## Una fotografia effimera della chat per la GUI. Agora resta la fonte persistente;
## questo segnale non scrive nello stato e permette di rendere il turno a scatti.
func _progresso_olimpo(fase: String, autore: String = "") -> void:
	if agora == null:
		return
	progresso_turno.emit(fase, {
		"turno": stato.turno,
		"autore": autore,
		"trascrizione": agora.trascrizione(Agora.VISTA_OLIMPO),
	})

## Porta una proposta divina nel canale giusto: se il dio e' in coalizione parla anche
## nel gruppo, come si fa in una chat quando si ha un tavolo riservato.
func _in_chat(p: Dictionary) -> void:
	var battuta := String(p.get("dice", "")).strip_edges()
	if battuta == "":
		return
	var dio := PantheonManager.get_dio(String(p.get("dio", "")))
	if dio == null:
		return
	agora.scrivi(Agora.CANALE_OLIMPO, dio.nome, battuta, stato.turno, "voce", dio.simbolo)
	for c in stato.coalizioni:
		if c.get("membri", []).has(dio.id) and c.has("canale"):
			agora.scrivi(String(c["canale"]), dio.nome, battuta, stato.turno, "voce", dio.simbolo)
	_progresso_olimpo("battuta")

## Come si chiude la discussione, in chat.
##
## LA VOLONTA' CHE PASSA NON SI ANNUNCIA: SI VEDE. Prima qui usciva una riga di servizio,
## «Nessuno si oppone: la volonta' di Atena passa» — un narratore che parla dentro una
## chat, e per giunta senza dire QUALE fosse quella volonta': il registro (castigo, aiuto,
## segno, trappola) e' cio' che muove i numeri e non arrivava mai a schermo. Ora chi la
## spunta AGISCE, e l'atto e' un suo messaggio. Chi perde ha parlato e basta: non serve
## dire chi ha vinto, si vede chi ha mosso la mano.
##
## Con la contesa Zeus parla comunque: li' c'e' una sentenza, e la sentenza ha una voce.
## Ma anche dopo la sua parola il gesto lo fa il dio, non lui.
func _verdetto_in_chat(verdetto: Dictionary, arbitrato: bool, proposte: Array = []) -> void:
	var attore := String(verdetto.get("attore", ""))
	if attore == "":
		return
	var dio := PantheonManager.get_dio(attore)
	var nome: String = dio.nome if dio else attore

	# LE PAROLE DI ZEUS, non un referto. L'Arbitro produce gia' una battuta da sovrano che
	# chiude la contesa («dice»), e il codice la buttava via per scrivere «prevale X: Y».
	if arbitrato:
		var testo := String(verdetto.get("dice", "")).strip_edges()
		if testo == "":
			testo = Testi.s("olimpo/zeus_chiude", [nome])
		var zeus: Dio = PantheonManager.get_dio("zeus")
		agora.scrivi(Agora.CANALE_OLIMPO, "Zeus", testo, stato.turno, "verdetto",
			zeus.simbolo if zeus else "")
		_progresso_olimpo("verdetto")

	# Il gesto lo propone il dio stesso; il verdetto dell'Arbitro pero' e' un dizionario a
	# se' e non porta quel campo, quindi si va a riprenderlo dalla sua proposta.
	var g := Gesto.da_proposta(_proposta_di(attore, proposte, verdetto), nome)
	if g != "":
		# Dopo la sentenza, chi compie il gesto prende visivamente la parola.
		_progresso_olimpo("attesa", nome)
		agora.scrivi(Agora.CANALE_OLIMPO, nome, g, stato.turno, "azione",
			dio.simbolo if dio else "")
		_progresso_olimpo("azione")

## La proposta di quel dio fra quelle in campo; in mancanza, il verdetto stesso (che ha
## comunque registro e intensita': basta al ripiego).
func _proposta_di(id: String, proposte: Array, verdetto: Dictionary) -> Dictionary:
	for p in proposte:
		if String(p.get("dio", "")) == id:
			return p
	return verdetto

## Registra il turno nei due archivi: storico_olimpo (tutto, per la vista dietro le quinte)
## e diario (reticente, per il giocatore). Ritorna la voce appena scritta.
func _registra(turno: int, input_testo: String, envelope: Dictionary, svegli: Array,
		eventi_turno: Array, conflitto: bool, proposte: Array, verdetto: Dictionary,
		scavalcamento: Dictionary, resa: Dictionary, delta: Dictionary, val: Dictionary,
		narrazione: String, in_mondo: bool, episodio_turno: String = "",
		quadro_narrativo: Dictionary = {}) -> Dictionary:
	var voce := {
		"turno": turno,
		"input": input_testo,
		"envelope": envelope,
		"svegli": svegli,
		"episodio": episodio_turno if episodio_turno != "" else _episodio_corrente(),
		"eventi_emessi": eventi_turno,
		"conflitto": conflitto if in_mondo else false,
		"deliberazione": proposte,
		"verdetto": verdetto,
		"scavalcamento": scavalcamento,
		"resa_dei_conti": resa,
		"coalizioni": stato.coalizioni.duplicate(true),
		"delta": delta,
		"ammonizione": val["classe"],
		"narrazione_omero": narrazione,
	}
	if not quadro_narrativo.is_empty():
		voce["quadro_narrativo"] = quadro_narrativo.duplicate(true)
	stato.storico_olimpo.append(voce)
	stato.diario.append({
		"turno": turno,
		"voce": envelope.get("sintesi", input_testo),
		"esito": Delta.marcatore_diario(delta) if in_mondo else "ill",
	})
	return voce

## Tutto cio' che Omero deve sapere per narrare un turno: l'azione, l'ancora di scena, la
## memoria del discorso e i segnali d'orientamento. Raccolto qui perche' esegui_turno resti
## leggibile come sequenza di fasi, invece di un muro di dizionario in mezzo.
func _contesto_omero(envelope: Dictionary, input_testo: String, svegli: Array,
		verdetto: Dictionary, delta: Dictionary, impronta: String) -> Dictionary:
	return {
		"sintesi": envelope.get("sintesi", ""),
		"azione": input_testo,      # le parole/gesto esatti: Omero deve rispondere a QUESTO
		"scena": scena_corrente(),  # ancora: dove si trova Ulisse e chi c'e' (coerenza)
		"cronaca": stato.cronaca,                # memoria della vicenda finora
		"storia": _storia_recente(),             # i beat precedenti (continuita' del discorso)
		"ultima_narrazione": _ultima_narrazione, # l'ultima voce di Omero (continuita' immediata)
		"luogo": _nome_tappa_corrente(),         # per l'orientamento discreto
		"progresso": _progresso_viaggio(),       # inizio / mezzo / vicino a Itaca
		"morale": _morale_recente(),             # duro / bene / incerto (come sta andando)
		"svegli": svegli,
		"verdetto": verdetto,
		"delta": delta,
		"impronta": impronta,
		"esito_segno": _segno_esito(delta),
		"detto_ai_compagni": _parole_in_sospeso(),
		"momento": momento_corrente(),   # «il sole gia' calava»: la prosa se ne serve
	}

## Un BEAT: Ulisse scambia due parole coi suoi senza che il mondo giri.
##
## Costa UNA chiamata (la risposta di un compagno) invece delle nove di un turno pieno:
## gli dei non convocano l'assemblea per ogni frase detta a bordo. Le parole pero' non si
## perdono — restano in sospeso e il prossimo turno vero le consegna all'Interprete
## (perche' i trigger scattino lo stesso), agli dei e a Omero.
func esegui_beat(testo: String) -> Dictionary:
	if stato == null or stato.stato != "in_corso":
		return {"ok": false}
	var pulito := testo.strip_edges()
	if pulito == "":
		return {"ok": false}
	# Il giro di parola avanza a ogni beat: due frasi di fila non hanno lo stesso
	# interlocutore. Deterministico, come tutto il resto.
	var giro := stato.turno + stato.parole_ai_compagni.size()
	stato.parole_ai_compagni.append(pulito)
	await _fa_parlare_la_ciurma(pulito, "", true, giro)
	return {"ok": true}

## Cio' che Ulisse ha detto ai compagni dall'ultimo turno pieno, in una riga.
func _parole_in_sospeso() -> String:
	if stato == null or stato.parole_ai_compagni.is_empty():
		return ""
	return " ".join(stato.parole_ai_compagni)

## Il testo che vede l'Interprete: l'azione, preceduta da cio' che Ulisse ha detto ai suoi.
## Cosi' un proposito espresso a voce ("mangiamo le vacche del Sole") produce comunque i
## suoi tag e sveglia chi di dovere — senza costare una seconda chiamata.
func _testo_per_interprete(input_testo: String) -> String:
	var parole := _parole_in_sospeso()
	if parole == "":
		return input_testo
	return "Poco fa ha detto ai compagni: «%s». Adesso: «%s»" % [parole, input_testo]

## Il taccuino privato di ogni dio (scripts/taccuino.gd): qui restano solo le deleghe,
## perche' i test e il contesto degli agenti le chiamano su GameManager.
func _annota_nella_memoria(proposte: Array, verdetto: Dictionary, scavalcamento: Dictionary,
		envelope: Dictionary) -> void:
	taccuino.annota(proposte, verdetto, scavalcamento, envelope,
		_nome_tappa_corrente(), _nome_dio(String(verdetto.get("attore", ""))))

func riassunto_memoria(id: String) -> String:
	return taccuino.riassunto_memoria(id) if taccuino else ""

func ricordi_recenti(id: String) -> Array:
	return taccuino.ricordi_recenti(id) if taccuino else []

func _nome_dio(id: String) -> String:
	var d: Dio = PantheonManager.get_dio(id)
	return d.nome if d != null else id

## Chi risponde: i compagni interpellati per nome, oppure (a rotazione) uno solo.
## Deterministico: niente casualita' non seminata, e la chat non si affolla.
## `alla_ciurma`: Ulisse ha scritto NELLA chat dei compagni. Allora sta parlando a loro
## anche se non nomina nessuno — il canale e' il destinatario.
## `giro`: chi tocca nella rotazione (i beat avanzano anche a turno fermo).
func _fa_parlare_la_ciurma(input_testo: String, narrazione: String, alla_ciurma: bool = false, giro: int = -1, committed_view: Dictionary = {}) -> void:
	if ciurma == null:
		return
	var vivi: Array = ciurma.vivi()
	if vivi.is_empty():
		return
	var interpellati: Array = ciurma.destinatari_in(input_testo)
	var parlanti: Array = []
	if not interpellati.is_empty():
		for id in interpellati:
			parlanti.append(ciurma.get_compagno(id))
	else:
		# Quanti parlano SPONTANEAMENTE: dal profilo di costo. Chi viene chiamato per nome
		# risponde comunque, sempre — quella valvola e' in mano al giocatore.
		var quanti := clampi(Costi.limite("compagni_per_turno", 1), 1, vivi.size())
		var da := (giro if giro >= 0 else stato.turno)
		for k in quanti:
			parlanti.append(vivi[(da + k) % vivi.size()])
	var contesto := {
		"scena": scena_corrente(),
		"cronaca": stato.cronaca,
		"accaduto": narrazione,
		"ulisse_dice": input_testo,
	}
	if not committed_view.is_empty():
		var memory: Dictionary = committed_view.get("factual_memory", {})
		contesto["scena"] = JSON.stringify(committed_view.get("audience_view", {}))
		contesto["cronaca"] = "\n".join(PackedStringArray(memory.get("entries", [])))
		contesto["accaduto"] = contesto["cronaca"]
		contesto["ulisse_dice"] = ""  # Raw player text may describe facts this audience did not observe.
		contesto["world_version"] = committed_view.get("audience_view", {}).get("world_version", 0)
	# Ulisse compare in chat quando sta PARLANDO ai suoi: o perche' ha scritto nella loro
	# chat, o perche' ne ha nominato uno. Un gesto compiuto nel campo di gioco ("sguaino
	# la spada") non e' una frase detta a qualcuno e non gli va messo in bocca.
	var parla_ai_suoi := alla_ciurma or not interpellati.is_empty()
	if parla_ai_suoi:
		agora.scrivi(Agora.CANALE_CIURMA, "Ulisse", input_testo, stato.turno, "voce", "ΟΔ")
	for c in parlanti:
		var ctx := contesto.duplicate()
		ctx["interpellato"] = parla_ai_suoi
		var battuta: String = await LLMManager.parla_compagno(c, ctx)
		if battuta != "":
			agora.scrivi(Agora.CANALE_CIURMA, String(c.get("nome", "")), battuta, stato.turno,
				"voce", String(c.get("simbolo", "")))

## Chi muore secondo il poema esce di scena quando la tappa si chiude: la sua voce tace.
func _fai_cadere_i_destinati(episodio: String) -> void:
	if ciurma == null:
		return
	for id in ciurma.destinati_a_cadere(episodio):
		var nome := ciurma.fai_cadere(id)
		if nome != "":
			agora.scrivi(Agora.CANALE_CIURMA, "", "%s non risponde piu'." % nome, stato.turno, "sistema")

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
