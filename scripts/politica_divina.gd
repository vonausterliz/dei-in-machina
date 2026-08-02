class_name PoliticaDivina
extends RefCounted

## La politica dell'Olimpo: coalizioni, strategie di lungo respiro (i piani), scavalcamenti
## di nascosto e la resa dei conti quando Zeus scopre chi ha disubbidito.
##
## Estratta da GameManager, che era diventato un contenitore di tutto: qui la regola sta
## in un posto solo, e il GameManager torna a fare l'orchestratore del turno.
## Tutto DETERMINISTICO: l'LLM sceglie il registro e la battuta, questi sono i pesi.

## Registri che "puniscono" vs quelli che "aiutano": il loro incontro definisce il conflitto.
const REGISTRI_PUNITIVI := ["castigo", "aiuto_negato", "trappola"]
const REGISTRI_BENIGNI := ["aiuto", "segno"]

var stato: StatoPartita
var agora: Agora
var _rng: RandomNumberGenerator

## Probabilita' sovrascrivibili dai test (0/1 per isolare un comportamento).
var prob_scavalcamento: float = Bilanciamento.num("politica_divina/prob_scavalcamento", 0.35)
var prob_coalizione: float = Bilanciamento.num("coalizioni/prob_coalizione", 0.4)

var _RATE_SOSPETTO: int = Bilanciamento.intero("politica_divina/rate_sospetto", 20)
var _IRA_ZEUS_SCOPERTA: int = Bilanciamento.intero("politica_divina/ira_zeus_scoperta", 15)
var _RIMBALZO_ULISSE: int = Bilanciamento.intero("politica_divina/rimbalzo_ulisse", 5)
var _SOGLIA_SCOPERTA: int = Bilanciamento.intero("politica_divina/soglia_scoperta", 60)
var _COESIONE_INIZIALE: int = Bilanciamento.intero("coalizioni/coesione_iniziale", 70)
var _COESIONE_DECADIMENTO: int = Bilanciamento.intero("coalizioni/coesione_decadimento", 15)
var _MAX_COALIZIONI: int = Bilanciamento.intero("coalizioni/massimo", 1)
var _PESO_COALIZIONE: int = Bilanciamento.intero("coalizioni/peso_intensita", 1)
var _SOGLIA_VULNERABILITA: int = Bilanciamento.intero("coalizioni/soglia_vulnerabilita", 40)
var _SOGLIA_HYBRIS: int = Bilanciamento.intero("ulisse/soglia_hybris", 50)

func _init(s: StatoPartita, a: Agora, rng: RandomNumberGenerator) -> void:
	stato = s
	agora = a
	_rng = rng

## Sfondo sulle proposte prima del verdetto: piano, tracotanza e peso di coalizione.
## Modulano l'intensita', non sostituiscono la scelta del registro fatta dall'LLM.
func prepara_per_arbitrato(proposte: Array) -> Array:
	return applica_peso_coalizioni(modula_per_hybris(modula_per_piano(proposte)))

## Un dio con un piano a orizzonte "lungo" (la pazienza di Poseidone) inclina la sua
## reazione: aspetta (intensita' giu') finche' Ulisse e' saldo, colpisce piu' forte
## (intensita' su) quando e' debole o vicino alla salvezza. Sfondo, non causa dominante.
func modula_per_piano(proposte: Array) -> Array:
	var vulnerabile := _ulisse_vulnerabile()
	var out: Array = []
	for p in proposte:
		var q: Dictionary = p.duplicate()
		var reg: Dictionary = stato.registro_divino.get(p.get("dio", ""), {})
		var piano = reg.get("piano", null)
		if typeof(piano) == TYPE_DICTIONARY and String(piano.get("orizzonte", "")) == "lungo":
			var delta_i := 1 if vulnerabile else -1
			q["intensita"] = clampi(int(q.get("intensita", 1)) + delta_i, 1, 3)
		out.append(q)
	return out

## Ulisse e' "debole": animo basso, oppure si trova in una tappa in cui e' allo stremo
## (il naufragio) o a un passo dalla salvezza (Scheria) — il momento in cui un dio
## paziente colpisce.
func _ulisse_vulnerabile() -> bool:
	var animo := int(stato.ulisse.get("stat", {}).get("animo", 100))
	var ep := String(stato.ulisse.get("episodio_corrente", ""))
	return animo <= _SOGLIA_VULNERABILITA or ep == "naufragio" or ep == "scheria"

## Peso di blocco: chi e' in una coalizione attiva spinge con piu' forza (intensita' +).
func applica_peso_coalizioni(proposte: Array) -> Array:
	var out: Array = []
	for p in proposte:
		var q: Dictionary = p.duplicate()
		if _in_coalizione(p.get("dio", "")):
			q["intensita"] = clampi(int(q.get("intensita", 1)) + _PESO_COALIZIONE, 1, 3)
		out.append(q)
	return out

func _in_coalizione(id: String) -> bool:
	for c in stato.coalizioni:
		if c.get("membri", []).has(id):
			return true
	return false

## Fine turno: le coalizioni attive perdono coesione (e si sciolgono a zero); poi, raro
## e col tetto, un blocco di dei punitivi della stessa fazione puo' formarne una nuova.

## Fine turno: le coalizioni attive perdono coesione (e si sciolgono a zero); poi, raro
## e col tetto, un blocco di dei punitivi della stessa fazione puo' formarne una nuova.
func aggiorna_coalizioni(proposte: Array) -> void:
	var vive: Array = []
	for c in stato.coalizioni:
		c["coesione"] = int(c.get("coesione", 0)) - _COESIONE_DECADIMENTO
		if int(c["coesione"]) > 0:
			vive.append(c)
		elif c.has("canale"):
			agora.chiudi_gruppo(String(c["canale"]), stato.turno)  # il gruppo si scioglie
	stato.coalizioni = vive

	if stato.coalizioni.size() >= _MAX_COALIZIONI or prob_coalizione <= 0.0:
		return
	var blocco := _blocco_punitivo_stessa_fazione(proposte)
	if blocco.size() < 2:
		return
	if prob_coalizione < 1.0 and _rng.randf() > prob_coalizione:
		return
	# Nasce l'intesa: e con lei un canale di gruppo, come una chat riservata.
	var nomi: Array = []
	for id in blocco:
		var d := PantheonManager.get_dio(id)
		nomi.append(d.nome if d else id)
	stato.coalizioni.append({
		"membri": blocco,
		"obiettivo": "negare il ritorno a Ulisse",
		"formata_al_turno": stato.turno,
		"coesione": _COESIONE_INIZIALE,
		"scadenza": "obiettivo_raggiunto_o_interessi_divergenti",
		"canale": agora.apri_gruppo(blocco, nomi, stato.turno),
	})

## Dei con proposta punitiva e stessa fazione contro-ritorno: la base di una coalizione.

## Dei con proposta punitiva e stessa fazione contro-ritorno: la base di una coalizione.
func _blocco_punitivo_stessa_fazione(proposte: Array) -> Array:
	var membri: Array = []
	for p in proposte:
		if REGISTRI_PUNITIVI.has(p.get("registro", "")):
			var d: Dio = PantheonManager.get_dio(p.get("dio", ""))
			if d != null and d.fazione == "contro-ritorno":
				membri.append(p.get("dio", ""))
	return membri

## SCAVALCAMENTO: se una proposta punitiva ha perso il verdetto, quel dio puo' (raro)
## fare di testa sua alle spalle di Zeus. Applica il suo delta e registra un pendente.
## Ritorna {} se nessuno scavalca, altrimenti {colpevole, delta, cosa}.
func tenta_scavalcamento(proposte: Array, verdetto: Dictionary) -> Dictionary:
	var perdente := _perdente_punitivo(proposte, verdetto)
	if perdente.is_empty() or prob_scavalcamento <= 0.0:
		return {}
	if prob_scavalcamento < 1.0 and _rng.randf() > prob_scavalcamento:
		return {}
	var d := Delta.da_reazione(perdente["dio"], perdente["registro"], int(perdente.get("intensita", 1)))
	var cosa := "Oltre al verdetto, ha agito di nascosto: %s con intensita' %d." % [perdente["registro"], int(perdente.get("intensita", 1))]
	stato.scavalcamenti_pendenti.append({
		"turno": stato.turno,
		"colpevole": perdente["dio"],
		"cosa": cosa,
		"sfrontatezza": int(perdente.get("intensita", 1)),
		"sospetto_zeus": 0,
		"soglia_scoperta": _SOGLIA_SCOPERTA,
		"rilevato": false,
	})
	return {"colpevole": perdente["dio"], "delta": d, "cosa": cosa}

## Una proposta con registro punitivo il cui dio NON e' l'attore del verdetto (ha perso).

## Una proposta con registro punitivo il cui dio NON e' l'attore del verdetto (ha perso).
func _perdente_punitivo(proposte: Array, verdetto: Dictionary) -> Dictionary:
	var vincitore: String = verdetto.get("attore", "")
	for p in proposte:
		if p.get("dio", "") != vincitore and REGISTRI_PUNITIVI.has(p.get("registro", "")):
			return p
	return {}

## RESA DEI CONTI (inizio turno): il sospetto di Zeus sale sui pendenti; alla soglia
## scopre il colpevole, cova ira (relazioni.zeus_verso) e il conto rimbalza su Ulisse.
## Ritorna {} o {scoperti: [id...], delta} (rimbalzo da applicare nel turno).

## RESA DEI CONTI (inizio turno): il sospetto di Zeus sale sui pendenti; alla soglia
## scopre il colpevole, cova ira (relazioni.zeus_verso) e il conto rimbalza su Ulisse.
## Ritorna {} o {scoperti: [id...], delta} (rimbalzo da applicare nel turno).
func resa_dei_conti() -> Dictionary:
	var scoperti: Array = []
	var delta: Dictionary = {}
	for sc in stato.scavalcamenti_pendenti:
		if sc.get("rilevato", false):
			continue
		sc["sospetto_zeus"] = int(sc.get("sospetto_zeus", 0)) + _RATE_SOSPETTO
		if int(sc["sospetto_zeus"]) >= int(sc.get("soglia_scoperta", _SOGLIA_SCOPERTA)):
			sc["rilevato"] = true
			var colpevole: String = sc.get("colpevole", "")
			var zv: Dictionary = stato.relazioni.get("zeus_verso", {})
			if zv.has(colpevole):
				zv[colpevole] = int(zv[colpevole]) + _IRA_ZEUS_SCOPERTA
			scoperti.append(colpevole)
			delta = Delta.unisci(delta, {"ulisse.animo": -_RIMBALZO_ULISSE})
	if scoperti.is_empty():
		return {}
	return {"scoperti": scoperti, "delta": delta}

func modula_per_hybris(proposte: Array) -> Array:
	if int(stato.ulisse.get("hybris", 0)) < _SOGLIA_HYBRIS:
		return proposte
	var out: Array = []
	for p in proposte:
		var q: Dictionary = p.duplicate()
		if REGISTRI_PUNITIVI.has(String(q.get("registro", ""))):
			q["intensita"] = clampi(int(q.get("intensita", 1)) + 1, 1, 3)
		out.append(q)
	return out

## Ogni dio in 'svegli' propone. 'altri' (opzionale) = proposte altrui da mostrargli (replica).
