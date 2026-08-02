extends Node

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

## Fasi della macchina del turno (macchina_del_turno.mermaid).
enum Fase {
	RESA_DEI_CONTI,
	INTERPRETAZIONE, VALIDAZIONE, RISVEGLIO,
	DELIBERAZIONE, ARBITRATO, APPLICAZIONE, SCAVALCAMENTO,
	NARRAZIONE, ESITO, AVANZAMENTO,
}

## Valori-seme: NON piu' costanti nel codice ma voci di data/bilanciamento.json, cosi' la
## taratura si fa sul file (design sez. 12). Il secondo argomento e' solo il ripiego.
@onready var _PROB_SCAVALCAMENTO_DEFAULT: float = Bilanciamento.num("politica_divina/prob_scavalcamento", 0.35)
@onready var _RATE_SOSPETTO: int = Bilanciamento.intero("politica_divina/rate_sospetto", 20)
@onready var _IRA_ZEUS_SCOPERTA: int = Bilanciamento.intero("politica_divina/ira_zeus_scoperta", 15)
@onready var _RIMBALZO_ULISSE: int = Bilanciamento.intero("politica_divina/rimbalzo_ulisse", 5)
@onready var _SOGLIA_SCOPERTA: int = Bilanciamento.intero("politica_divina/soglia_scoperta", 60)

## Probabilita' che un dio bocciato scavalchi Zeus. Sovrascrivibile nei test (0/1).
var prob_scavalcamento := 0.35
var _rng := RandomNumberGenerator.new()

## Coalizioni & strategie (fase 6-bis), valori-seme. Rare e bounded per non annegare
## il segnale deducibile: restano modulazione di sfondo, mai la causa dominante.
@onready var _PROB_COALIZIONE_DEFAULT: float = Bilanciamento.num("coalizioni/prob_coalizione", 0.4)
@onready var _COESIONE_INIZIALE: int = Bilanciamento.intero("coalizioni/coesione_iniziale", 70)
@onready var _COESIONE_DECADIMENTO: int = Bilanciamento.intero("coalizioni/coesione_decadimento", 15)
@onready var _MAX_COALIZIONI: int = Bilanciamento.intero("coalizioni/massimo", 1)
@onready var _PESO_COALIZIONE: int = Bilanciamento.intero("coalizioni/peso_intensita", 1)
@onready var _SOGLIA_VULNERABILITA: int = Bilanciamento.intero("coalizioni/soglia_vulnerabilita", 40)
var prob_coalizione := 0.4

var stato: StatoPartita = null

## Moduli estratti: la regola vive nel suo file, GameManager orchestra il turno.
var _validazione: Validazione = null
## Le conversazioni (vista Olimpo come chat, e in seguito la ciurma).
var agora: Agora = null
## I compagni: hanno voce propria e possono morire (allora tacciono).
var ciurma: Ciurma = null

## Ultima narrazione di Omero: la ripassiamo al turno dopo per la continuità del discorso.
var _ultima_narrazione: String = ""

func _ready() -> void:
	episodi = Episodi.carica(EPISODI_PATH)
	prob_scavalcamento = _PROB_SCAVALCAMENTO_DEFAULT
	prob_coalizione = _PROB_COALIZIONE_DEFAULT

func nuova_partita(seed_partita: int = 0) -> void:
	var s := seed_partita if seed_partita != 0 else randi()
	stato = StatoPartita.nuova(PantheonManager.pantheon, s)
	_validazione = Validazione.new(stato)
	agora = Agora.new()
	agora.canale(Agora.CANALE_OLIMPO, "Olimpo")
	ciurma = Ciurma.carica()
	agora.canale(Agora.CANALE_CIURMA, "Ciurma")
	_ultima_narrazione = ""
	_rng.seed = s  # riproducibilita': stessa run, stessi scavalcamenti
	prob_scavalcamento = _PROB_SCAVALCAMENTO_DEFAULT
	prob_coalizione = _PROB_COALIZIONE_DEFAULT
	# Viaggio: i locali ripartono spenti; si entra nella prima tappa (accende i suoi locali).
	PantheonManager.pantheon.spegni_locali()
	stato.viaggio["ordine_episodi"] = episodi.ordine()
	_entra_in_episodio(episodi.primo())

## Entra in una tappa: la rende corrente, azzera i turni-in-tappa e ACCENDE i suoi
## dei locali (attivo + in gioco). Ritorna l'intro della tappa (per il narratore/console).
func _entra_in_episodio(id: String) -> String:
	stato.viaggio["corrente"] = id
	stato.viaggio["turni_in_episodio"] = 0
	stato.ulisse["episodio_corrente"] = id
	for dio in PantheonManager.pantheon.locali_di_episodio(id):
		dio.attivo = true
		if stato.registro_divino.has(dio.id):
			stato.registro_divino[dio.id]["risvegliato"] = true
	var ep := episodi.get_episodio(id)
	var intro := ep.intro if ep else ""
	_ultima_narrazione = intro  # continuita': il primo turno prosegue dall'intro della tappa
	return intro

## Intro della tappa corrente (per aprire la scena).
func intro_corrente() -> String:
	var ep := episodi.get_episodio(_episodio_corrente())
	return ep.intro if ep else ""

## Ancora di scena della tappa corrente (luogo + chi e' presente + vincoli): serve a
## Omero e al Suggeritore per restare coerenti e non inventare luoghi/personaggi assenti.
func scena_corrente() -> String:
	var ep := episodi.get_episodio(_episodio_corrente())
	return ep.scena if ep else ""

func _nome_tappa_corrente() -> String:
	var ep := episodi.get_episodio(_episodio_corrente())
	return ep.nome if ep else ""

## Ogni quanti turni si aggiorna il riassunto rotolante. Non a ogni turno: sarebbe una
## chiamata LLM in piu' sempre. Cosi' la memoria costa poco e resta a dimensione costante.
@onready var _CRONACA_OGNI: int = Bilanciamento.intero("memoria/cronaca_ogni", 4)

## Aggiorna la cronaca (memoria della vicenda) se sono passati abbastanza turni. Prende i
## fatti NON ancora riassunti da storico_olimpo (azione + cosa e' seguito).
func _aggiorna_cronaca_se_serve() -> void:
	if stato.turno - stato.cronaca_turno < _CRONACA_OGNI:
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
	var ord: Array = episodi.ordine()
	var i := ord.find(_episodio_corrente())
	if i < 0 or ord.size() <= 1:
		return "inizio"
	var f := float(i) / float(ord.size() - 1)
	if f < 0.34:
		return "inizio"
	elif f < 0.72:
		return "mezzo"
	return "vicino"

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

func carica_partita(path: String = SALVATAGGIO_DEFAULT) -> bool:
	var s := StatoPartita.carica(path)
	if s == null:
		return false
	stato = s
	_validazione = Validazione.new(stato)  # i moduli lavorano sullo stato caricato
	agora = Agora.new()
	agora.canale(Agora.CANALE_OLIMPO, "Olimpo")
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
	if stato.stato != "in_corso":
		push_warning("GameManager: partita gia' conclusa (%s)." % str(stato.esito))
		return {}

	var percorso: Array[String] = []
	stato.turno += 1
	var turno := stato.turno

	# RESA DEI CONTI — Zeus verifica gli scavalcamenti pendenti: il sospetto sale, e
	# alla soglia scopre il colpevole (cova ira, e il conto rimbalza su Ulisse).
	percorso.append(Fase.keys()[Fase.RESA_DEI_CONTI])
	var resa := _resa_dei_conti()

	# INTERPRETAZIONE — testo libero -> envelope (Interprete via LLMManager).
	percorso.append(Fase.keys()[Fase.INTERPRETAZIONE])
	var envelope: Dictionary = await LLMManager.interpreta(input_testo)

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
	if in_mondo:
		percorso.append(Fase.keys()[Fase.RISVEGLIO])
		await _risolvi_invocazione(envelope, input_testo)
		svegli = PantheonManager.risveglio(envelope, eventi_turno, _episodio_corrente())
		_segna_in_gioco(svegli)
		_annuncia_risvegli(svegli)

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

			# SCAVALCAMENTO — un dio punitivo bocciato puo' agire di nascosto (raro):
			# applica il suo delta all'insaputa di Zeus e lascia una traccia (pendente).
			scavalcamento = _tenta_scavalcamento(proposte, verdetto)
			if not scavalcamento.is_empty():
				percorso.append(Fase.keys()[Fase.SCAVALCAMENTO])
				delta = Delta.unisci(delta, scavalcamento["delta"])

	# Coalizioni (fase 6-bis): decadono ogni turno e, raramente, se ne formano di nuove
	# dal blocco di dei punitivi della stessa fazione (proposte vuote se nessuno ha reagito).
	_aggiorna_coalizioni(proposte)

	# La ripercussione della resa dei conti (rimbalzo su Ulisse) confluisce nel turno.
	delta = Delta.unisci(delta, resa.get("delta", {}))

	# APPLICAZIONE del delta (reazione divina in_mondo, smarrimento/follia, resa, scavalcamento).
	Delta.applica(stato, delta)

	# NARRAZIONE — Omero reticente, senza nomi di dei (invariante).
	# Se l'azione e' FUORI-MONDO, Omero TACE: non si chiede al modello di narrare un gesto
	# impossibile (l'LLM tenderebbe comunque a raccontarlo). Al giocatore va solo il
	# richiamo, che la UI mostra come avviso. Cosi' il turno e' anche piu' rapido.
	percorso.append(Fase.keys()[Fase.NARRAZIONE])
	var impronta := ""
	if not verdetto.is_empty():
		var attore: Dio = PantheonManager.get_dio(verdetto["attore"])
		if attore != null:
			impronta = attore.impronta
	var narrazione := ""
	if in_mondo:
		narrazione = await LLMManager.narrazione_omero({
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
		})
		_ultima_narrazione = narrazione  # per la continuita' al turno successivo

	# LA CIURMA: i compagni commentano cio' che e' successo. Se Ulisse si e' rivolto a
	# qualcuno per nome, risponde lui; altrimenti parla al piu' uno, per non affollare.
	await _fa_parlare_la_ciurma(input_testo, narrazione)

	# Registrazioni: storico_olimpo (vista Olimpo/debug) + diario (player-facing).
	var voce := {
		"turno": turno,
		"input": input_testo,
		"envelope": envelope,
		"svegli": svegli,
		"episodio": _episodio_corrente(),
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
	stato.storico_olimpo.append(voce)
	stato.diario.append({
		"turno": turno,
		"voce": envelope.get("sintesi", input_testo),
		"esito": Delta.marcatore_diario(delta) if in_mondo else "ill",
	})

	# ESITO — la follia (ammonizione oltre soglia) chiude la partita; altrimenti
	# valgono i controlli sulle stat (ciurma). Gli altri esiti con le loro fasi.
	percorso.append(Fase.keys()[Fase.ESITO])
	var esito: String = val["esito"] if val["esito"] != "continua" else _controlla_esito()

	# AVANZAMENTO — se la partita continua ed e' un turno in-mondo, la tappa puo' concludersi
	# (azione di progresso o tetto turni) e si passa alla successiva; arrivare a Itaca e' vittoria.
	percorso.append(Fase.keys()[Fase.AVANZAMENTO])
	var avanzamento := {"avanzato": false, "intro": "", "episodio": _episodio_corrente()}
	if esito == "continua" and in_mondo:
		avanzamento = await _avanza_episodio(envelope)
		esito = avanzamento["esito"]

	if esito != "continua":
		stato.stato = "finita"
		stato.esito = esito
	else:
		await _aggiorna_cronaca_se_serve()  # memoria della vicenda, ogni N turni

	return {
		"voce": voce,
		"svegli": svegli,
		"in_mondo": in_mondo,
		"esito": esito,
		"episodio": avanzamento["episodio"],
		"avanzato": avanzamento["avanzato"],
		"intro": avanzamento["intro"],
		"transizione": avanzamento.get("transizione", ""),  # traversata verso la nuova tappa
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
		var prep := _prepara_per_arbitrato(attive)
		var v := _arbitra(prep)
		_verdetto_in_chat(v, false)
		return {"proposte": prep, "conflitto": false, "verdetto": v}

	# CONFLITTO: i dei si ribattono, poi Zeus chiude.
	var repliche := await _repliche(attive, envelope)
	var prep_c := _prepara_per_arbitrato(repliche)
	var verdetto: Dictionary = await LLMManager.verdetto_arbitro(prep_c)
	_verdetto_in_chat(verdetto, true)
	return {"proposte": prep_c, "conflitto": true, "verdetto": verdetto}

## Sfondo (fase 6-bis) sulle proposte prima del verdetto: strategie (piano) e peso di
## coalizione. Modulano l'intensita', non sostituiscono la scelta LLM del registro.
func _prepara_per_arbitrato(proposte: Array) -> Array:
	return _applica_peso_coalizioni(_modula_proposte_per_hybris(_modula_proposte_per_piano(proposte)))

## La TRACOTANZA si paga: oltre la soglia, chi punisce colpisce piu' forte. Prima la
## hybris saliva senza mai avere conseguenze — era un numero decorativo.
@onready var _SOGLIA_HYBRIS: int = Bilanciamento.intero("ulisse/soglia_hybris", 50)

func _modula_proposte_per_hybris(proposte: Array) -> Array:
	if int(stato.ulisse.get("hybris", 0)) < _SOGLIA_HYBRIS:
		return proposte
	var out: Array = []
	for p in proposte:
		var q: Dictionary = p.duplicate()
		if _REGISTRI_PUNITIVI.has(String(q.get("registro", ""))):
			q["intensita"] = clampi(int(q.get("intensita", 1)) + 1, 1, 3)
		out.append(q)
	return out

## Ogni dio in 'svegli' propone. 'altri' (opzionale) = proposte altrui da mostrargli (replica).
func _raccogli_proposte(svegli: Array, envelope: Dictionary, altri: Array) -> Array:
	var out: Array = []
	for id in svegli:
		var p: Dictionary = await LLMManager.proposta_dio(PantheonManager.get_dio(id), _contesto_dio(id, envelope, altri))
		out.append(p)
		_in_chat(p)
	return out

## Round 2: ogni dio ribatte vedendo le proposte degli ALTRI.
func _repliche(attive: Array, envelope: Dictionary) -> Array:
	var out: Array = []
	for p in attive:
		var id: String = p.get("dio", "")
		var altri := _altri_dei(attive, id)
		var r: Dictionary = await LLMManager.proposta_dio(PantheonManager.get_dio(id), _contesto_dio(id, envelope, altri))
		out.append(r)
		_in_chat(r)   # e' il botta e risposta: il dio ribatte avendo sentito gli altri
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

## Un dio con un piano a orizzonte "lungo" (la pazienza di Poseidone) inclina la sua
## reazione: aspetta (intensita' giu') finche' Ulisse e' saldo, colpisce piu' forte
## (intensita' su) quando e' debole o vicino alla salvezza. Sfondo, non causa dominante.
func _modula_proposte_per_piano(proposte: Array) -> Array:
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

func _ulisse_vulnerabile() -> bool:
	var animo := int(stato.ulisse.get("stat", {}).get("animo", 100))
	var ep := _episodio_corrente()
	return animo <= _SOGLIA_VULNERABILITA or ep == "naufragio" or ep == "scheria"

# --- Fase 6-bis: coalizioni ---

## Peso di blocco: chi e' in una coalizione attiva spinge con piu' forza (intensita' +).
func _applica_peso_coalizioni(proposte: Array) -> Array:
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
func _aggiorna_coalizioni(proposte: Array) -> void:
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
func _blocco_punitivo_stessa_fazione(proposte: Array) -> Array:
	var membri: Array = []
	for p in proposte:
		if _REGISTRI_PUNITIVI.has(p.get("registro", "")):
			var d: Dio = PantheonManager.get_dio(p.get("dio", ""))
			if d != null and d.fazione == "contro-ritorno":
				membri.append(p.get("dio", ""))
	return membri

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

## Validazione/ammonizione e vaglio della plausibilita' vivono in Validazione (scripts/).
## Qui restano solo i due punti di ingresso, per non spargere la regola in due posti.
func _vaglia_plausibilita(envelope: Dictionary, input_testo: String) -> void:
	await _validazione.vaglia(envelope, input_testo)

func _valida(envelope: Dictionary, input_testo: String) -> Dictionary:
	return _validazione.valida(envelope, input_testo)

## SCAVALCAMENTO: se una proposta punitiva ha perso il verdetto, quel dio puo' (raro)
## fare di testa sua alle spalle di Zeus. Applica il suo delta e registra un pendente.
## Ritorna {} se nessuno scavalca, altrimenti {colpevole, delta, cosa}.
func _tenta_scavalcamento(proposte: Array, verdetto: Dictionary) -> Dictionary:
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
func _perdente_punitivo(proposte: Array, verdetto: Dictionary) -> Dictionary:
	var vincitore: String = verdetto.get("attore", "")
	for p in proposte:
		if p.get("dio", "") != vincitore and _REGISTRI_PUNITIVI.has(p.get("registro", "")):
			return p
	return {}

## RESA DEI CONTI (inizio turno): il sospetto di Zeus sale sui pendenti; alla soglia
## scopre il colpevole, cova ira (relazioni.zeus_verso) e il conto rimbalza su Ulisse.
## Ritorna {} o {scoperti: [id...], delta} (rimbalzo da applicare nel turno).
func _resa_dei_conti() -> Dictionary:
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

func _episodio_corrente() -> String:
	var ep: Variant = stato.ulisse.get("episodio_corrente", null)
	return String(ep) if ep != null else ""

## Eventi di mondo del turno: quelli della tappa corrente + quelli passati dall'esterno.
func _eventi_del_turno(eventi: Array) -> Array:
	var out: Array = eventi.duplicate()
	var ep := episodi.get_episodio(_episodio_corrente()) if episodi else null
	if ep:
		for e in ep.eventi_attivi:
			if not out.has(e):
				out.append(e)
	return out

## AVANZAMENTO della tappa. Ritorna {esito, avanzato, intro, episodio}.
## Si avanza se compare l'azione di progresso (avanza_su_tag) o si tocca il tetto turni.
## Entrare in Itaca = vittoria (esito "itaca").
func _avanza_episodio(envelope: Dictionary) -> Dictionary:
	var v: Dictionary = stato.viaggio
	v["turni_in_episodio"] = int(v.get("turni_in_episodio", 0)) + 1
	var ep := episodi.get_episodio(String(v.get("corrente", "")))
	var fermo := {"esito": "continua", "avanzato": false, "intro": "", "episodio": _episodio_corrente()}
	if ep == null:
		return fermo

	var tag: Array = envelope.get("tag", [])
	var per_tag: bool = ep.avanza_su_tag != null and tag.has(String(ep.avanza_su_tag))
	var per_cap: bool = ep.turni_massimi > 0 and int(v["turni_in_episodio"]) >= ep.turni_massimi
	if not (per_tag or per_cap):
		return fermo

	_fai_cadere_i_destinati(String(v["corrente"]))
	v["completati"].append(v["corrente"])
	var da_nome := ep.nome
	var prossimo := episodi.successivo(String(v["corrente"]))
	if prossimo == "" or prossimo == "itaca":
		var t_it := await _passaggio(da_nome, "Itaca")
		return {"esito": "itaca", "avanzato": true, "intro": intro_corrente(), "episodio": "itaca", "transizione": t_it}
	var intro := _entra_in_episodio(prossimo)
	var trans := await _passaggio(da_nome, _nome_tappa_corrente())
	return {"esito": "continua", "avanzato": true, "intro": intro, "episodio": prossimo, "transizione": trans}

## Breve narrazione di Omero per la traversata tra due tappe (come ci si arriva).
func _passaggio(da: String, a: String) -> String:
	return await LLMManager.narrazione_omero({"passaggio": {"da": da, "a": a}})

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
			agora.scrivi(Agora.CANALE_OLIMPO, dio.nome, "si desta.", stato.turno, "azione")

## Porta una proposta divina nel canale giusto: se il dio e' in coalizione parla anche
## nel gruppo, come si fa in una chat quando si ha un tavolo riservato.
func _in_chat(p: Dictionary) -> void:
	var battuta := String(p.get("dice", "")).strip_edges()
	if battuta == "":
		return
	var dio := PantheonManager.get_dio(String(p.get("dio", "")))
	if dio == null:
		return
	agora.scrivi(Agora.CANALE_OLIMPO, dio.nome, battuta, stato.turno)
	for c in stato.coalizioni:
		if c.get("membri", []).has(dio.id) and c.has("canale"):
			agora.scrivi(String(c["canale"]), dio.nome, battuta, stato.turno)

## Il verdetto: se c'e' stato conflitto lo pronuncia Zeus, altrimenti prevale chi ha
## spinto piu' forte. In chat si legge come la parola che chiude la discussione.
func _verdetto_in_chat(verdetto: Dictionary, arbitrato: bool) -> void:
	var attore := String(verdetto.get("attore", ""))
	if attore == "":
		return
	var dio := PantheonManager.get_dio(attore)
	var nome: String = dio.nome if dio else attore
	var chi := "Zeus" if arbitrato else nome
	var testo := "prevale %s: %s" % [nome, verdetto.get("registro", "?")]
	agora.scrivi(Agora.CANALE_OLIMPO, chi, testo, stato.turno, "verdetto")

## Chi risponde: i compagni interpellati per nome, oppure (a rotazione) uno solo.
## Deterministico: niente casualita' non seminata, e la chat non si affolla.
func _fa_parlare_la_ciurma(input_testo: String, narrazione: String) -> void:
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
		parlanti.append(vivi[stato.turno % vivi.size()])  # a turno, uno per volta
	var contesto := {
		"scena": scena_corrente(),
		"cronaca": stato.cronaca,
		"accaduto": narrazione,
		"ulisse_dice": input_testo,
	}
	# Ulisse compare in chat solo se sta parlando ai suoi.
	if not interpellati.is_empty():
		agora.scrivi(Agora.CANALE_CIURMA, "Ulisse", input_testo, stato.turno)
	for c in parlanti:
		var ctx := contesto.duplicate()
		ctx["interpellato"] = not interpellati.is_empty()
		var battuta: String = await LLMManager.parla_compagno(c, ctx)
		if battuta != "":
			agora.scrivi(Agora.CANALE_CIURMA, String(c.get("nome", "")), battuta, stato.turno)

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
