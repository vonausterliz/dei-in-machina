class_name TracciaCanonica
extends RefCounted

## IL GOLDEN TRACE (CLAUDE.md, mandato punto 5).
##
## Perche' esiste, detto con precisione: i guasti pericolosi di questo progetto sono stati
## quasi tutti SILENZIOSI. Non codice che sbagliava — codice che MANCAVA. Due finali
## dichiarati e irraggiungibili perche' nessuna riga li produceva. Il caricamento che
## ometteva un modulo e lasciava lo stato vecchio a puntare al nuovo. La terraferma che non
## si disegnava perche' una funzione tornava un array vuoto senza lamentarsi. Il controllo
## sulla voce di testo mancante che non poteva scattare.
##
## Nessuno di questi faceva fallire un test, perche' un test verifica cio' che qualcuno ha
## pensato di verificare. Un golden trace no: confronta TUTTO cio' che un turno produce con
## cio' che produceva prima. Un'assenza si vede come una rottura — e' l'unico strumento in
## cui non essere previsti non e' un vantaggio.
##
## Deterministico per costruzione: mock LLM, seed fisso, nessun orologio nella traccia.
## Registrare e confrontare stanno qui, cosi' lo strumento a riga di comando
## (tools/golden_trace/) e il test della suite guardano esattamente la stessa cosa.

const PERCORSO := "res://tests/golden/traccia_canonica.json"
const SEED := 4815162342

## Il copione: input scelti per esercitare risvegli DIVERSI col mock deterministico.
## Cambiarlo invalida la traccia registrata — ed e' giusto cosi': e' la domanda, e se
## cambia la domanda la risposta di prima non vale piu'.
## Accanto a ogni riga c'e' cio' che il gioco fa DAVVERO, verificato sulla traccia — non
## cio' che mi aspettavo. La prima riga portava scritto «-> Poseidone», copiata da
## run_turns.gd: e' falso. Poseidone ha `dorme_finche: maledizione_di_polifemo` e a Troia
## dorme per progetto, quindi il vanto gli passa sopra. Il codice aveva ragione, il commento
## no — ed e' il golden trace ad averlo fatto notare, alla prima registrazione.
const COPIONE := [
	"Sono io, Odisseo, che t'ho accecato!",           # vanto/tracotanza -> hybris, nessun dio
	"Dico al gigante che il mio nome e' Nessuno.",     # astuzia/inganno    -> Atena, aiuto
	"Prendo un aereo e volo a Itaca.",                 # anacronistico      -> richiamo, non narrato
	"Riempio gli otri d'acqua alla sorgente.",         # neutro             -> nessun dio
	"Mi rivolgo al capo dell'olimpo e lo supplico.",   # preghiera allusiva -> Zeus, segno
	# L'AVANZAMENTO DI TAPPA, e adesso con una CAUSA (R-09). Prima non serviva chiederlo: al
	# quarto turno scattava il tetto e la scena cambiava da sola. Tolto il tetto (R-10) la
	# traccia canonica ha smesso di attraversare una tappa — e a dirlo e' stato il secondo
	# test del golden trace, quello che pretende che la traccia eserciti ancora tutto quanto.
	# Ora si salpa per scelta, che e' il modo in cui il viaggio deve procedere.
	"salpo",                                           # rotta -> avanzamento, causa «scelta»
]

# --- Registrare ---

## Esegue il copione e restituisce la traccia. `gm` e `llm` si passano come nodi perche' in
## modalita' --script gli autoload non sono identificatori a compile-time.
static func registra(gm: Node, llm: Node) -> Dictionary:
	llm.mock_mode = true
	gm.nuova_partita(SEED)

	var turni: Array = []
	for i in COPIONE.size():
		if gm.stato.stato != "in_corso":
			break   # una partita finita a meta' copione e' un fatto, e va registrato
		var r: Dictionary = await gm.esegui_turno(String(COPIONE[i]))
		turni.append(_un_turno(i + 1, r, gm))

	return {
		"_nota": "Traccia canonica generata da TracciaCanonica.registra(). NON si modifica a mano: si rigenera con tools/golden_trace/golden_trace.gd -- aggiorna, e la differenza si LEGGE prima di accettarla.",
		"seed": SEED,
		"copione": COPIONE,
		"turni": turni,
		"finale": _finale(gm),
	}

static func _un_turno(n: int, r: Dictionary, gm: Node) -> Dictionary:
	var voce: Dictionary = r.get("voce", {})
	var envelope: Dictionary = voce.get("envelope", {})
	var stato = gm.stato
	return {
		"n": n,
		"input": String(voce.get("input", "")),
		"episodio": String(voce.get("episodio", "")),
		# Interpretazione: cosa il gioco ha CAPITO. Se un tag sparisce, tutto il resto slitta.
		"tag": _ordinato(envelope.get("tag", [])),
		"plausibilita": String(envelope.get("plausibilita", "")),
		"in_mondo": bool(r.get("in_mondo", false)),
		"ammonizione": String(voce.get("ammonizione", "")),
		# Risveglio: l'insieme dei dei che reagiscono e' il cuore deterministico del gioco.
		"svegliati": _ordinato(r.get("svegli", [])),
		"conflitto": bool(voce.get("conflitto", false)),
		"proposte": _proposte(voce.get("deliberazione", [])),
		"verdetto": _verdetto(voce.get("verdetto", {})),
		"scavalcamento": String(voce.get("scavalcamento", {}).get("dio", "")),
		"delta": _delta(voce.get("delta", {})),
		"esito": String(r.get("esito", "")),
		"avanzato": bool(r.get("avanzato", false)),
		# La narrazione per intero: e' cio' che il giocatore legge, ed e' dove vive
		# l'invariante piu' importante — Omero non nomina mai un dio.
		"narrazione": String(voce.get("narrazione_omero", "")),
		"congedo": String(r.get("congedo", "")),
		"stato": _stato(stato),
		"registro": _registro(stato),
		"ammonizioni": _ammonizioni(stato),
		"ciurma_parla": _ciurma(gm, n),
		"olimpo_parla": _olimpo(gm, n),
	}

static func _stato(stato) -> Dictionary:
	var st: Dictionary = stato.ulisse["stat"]
	return {
		"turno": int(stato.turno),
		# La chiave e' "corrente" (Viaggio.vai_a). Qui c'era scritto "tappa_corrente", che non
		# esiste in nessuna parte dello stato: il campo e' stato vuoto per tutta la vita della
		# traccia, e un avanzamento di tappa sbagliato sarebbe passato inosservato. Il golden
		# trace vede le assenze altrui, non le proprie — questa l'ha trovata la musica, che
		# doveva leggere la stessa chiave per sapere quale capitolo suonare.
		"tappa": String(stato.viaggio.get("corrente", "")),
		"animo": int(st["animo"]),
		"metis": int(st["metis"]),
		"hybris": int(stato.ulisse["hybris"]),
		"ciurma_vivi": int(st["ciurma"]["vivi"]),
	}

## Favore e ira di ogni dio, in ordine alfabetico: un dizionario iterato a caso darebbe
## differenze finte a ogni esecuzione.
static func _registro(stato) -> Dictionary:
	var out: Dictionary = {}
	var nomi: Array = stato.registro_divino.keys()
	nomi.sort()
	for id in nomi:
		var r: Dictionary = stato.registro_divino[id]
		out[String(id)] = "favore=%d ira=%d" % [int(r.get("favore", 0)), int(r.get("ira", 0))]
	return out

## Solo i contatori: `ultimo_richiamo` porta dentro l'input del giocatore, che nella traccia
## comparirebbe due volte, e non aggiunge niente che i contatori non dicano gia'.
static func _ammonizioni(stato) -> Dictionary:
	var out: Dictionary = {}
	var chiavi: Array = stato.ammonizioni.keys() if stato.ammonizioni is Dictionary else []
	chiavi.sort()
	for k in chiavi:
		var v: Variant = stato.ammonizioni[k]
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[String(k)] = int(v)
	return out

static func _proposte(d: Array) -> Array:
	var out: Array = []
	for p in d:
		out.append("%s · %s · %s" % [
			String(p.get("dio", p.get("attore", "?"))),
			String(p.get("registro", "?")),
			String(p.get("dice", "")).substr(0, 80)])
	out.sort()   # l'ordine di deliberazione non e' parte del contratto; l'insieme si'
	return out

static func _verdetto(v: Dictionary) -> String:
	if v.is_empty():
		return ""
	return "%s · %s" % [String(v.get("attore", "?")), String(v.get("registro", "?"))]

static func _delta(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var chiavi: Array = d.keys()
	chiavi.sort()
	for k in chiavi:
		out[String(k)] = d[k]
	return out

## Chi ha parlato in ciurma in questo turno, e cosa: e' il ritmo che il profilo di costo
## governa, ed e' sparito una volta senza che nessuno se ne accorgesse.
static func _ciurma(gm: Node, turno: int) -> Array:
	var out: Array = []
	var canale: Dictionary = gm.agora.canali.get(Agora.CANALE_CIURMA, {})
	for m in canale.get("messaggi", []):
		if int(m.get("turno", -1)) == turno and String(m.get("autore", "")) != "Ulisse":
			out.append("%s: %s" % [String(m["autore"]), String(m.get("testo", "")).substr(0, 60)])
	out.sort()
	return out

## Cio' che si LEGGE nella Vista Olimpo, in ordine e col tipo di riga.
##
## Mancava, e la mancanza si e' pagata: la traccia teneva d'occhio la chat della ciurma e
## non quella degli dei, cosi' e' rimasta a schermo per settimane una riga di servizio
## («Nessuno si oppone: la volonta' di X passa») che nessuno strumento poteva vedere. Le
## proposte c'erano gia' nella traccia, ma come dati: la traccia sapeva cosa il gioco
## aveva DECISO, non cosa il giocatore avrebbe LETTO.
##
## Qui l'ordine conta, al contrario della ciurma: prima si parla, poi agisce chi la spunta.
## E conta il TIPO — voce, azione, verdetto, sistema — perche' il difetto era esattamente
## quello: la cosa giusta scritta nel registro sbagliato.
static func _olimpo(gm: Node, turno: int) -> Array:
	var out: Array = []
	var canale: Dictionary = gm.agora.canali.get(Agora.CANALE_OLIMPO, {})
	for m in canale.get("messaggi", []):
		if int(m.get("turno", -1)) != turno:
			continue
		out.append("%s · %s: %s" % [
			String(m.get("tipo", "?")), String(m.get("autore", "—")),
			String(m.get("testo", "")).substr(0, 80)])
	return out

static func _finale(gm: Node) -> Dictionary:
	return {
		"stato_partita": String(gm.stato.stato),
		"esito": String(gm.stato.esito) if gm.stato.esito != null else "",
		"turni_giocati": int(gm.stato.turno),
		"voci_storico": gm.stato.storico_olimpo.size(),
		"voci_diario": gm.stato.diario.size(),
		"stato": _stato(gm.stato),
		"registro": _registro(gm.stato),
	}

static func _ordinato(a) -> Array:
	var out: Array = []
	for x in a:
		out.append(String(x))
	out.sort()
	return out

# --- Confrontare ---

## Le differenze fra due tracce, in righe leggibili. Vuoto = identiche.
##
## Ricorsivo e per percorso: «turni/3/svegliati» dice subito DOVE. Un confronto secco fra
## due dizionari direbbe solo «diversi», che e' quanto basta per far fallire un test e non
## basta per capire cosa e' cambiato — e questo strumento serve a capire.
static func confronta(attesa: Variant, ottenuta: Variant, dove: String = "") -> Array:
	var fuori: Array = []

	# I NUMERI PRIMA DEI TIPI. Un intero scritto in JSON torna indietro come float: 3 diventa
	# 3.0, e un confronto sui tipi darebbe una differenza per OGNI numero della traccia —
	# settantacinque righe di rumore in cui una differenza vera non si troverebbe piu'.
	# (E' lo stesso inciampo delle chiavi intere in Agora: JSON non ha interi, ha numeri.)
	if _numero(attesa) and _numero(ottenuta):
		if not is_equal_approx(float(attesa), float(ottenuta)):
			fuori.append("%s: %s invece di %s" % [dove, str(ottenuta), str(attesa)])
		return fuori

	if typeof(attesa) != typeof(ottenuta):
		return ["%s: tipo diverso (atteso %s, ottenuto %s)" % [
			dove, type_string(typeof(attesa)), type_string(typeof(ottenuta))]]

	if attesa is Dictionary:
		var chiavi: Array = attesa.keys()
		for k in ottenuta.keys():
			if not chiavi.has(k):
				chiavi.append(k)
		chiavi.sort()
		for k in chiavi:
			var qui := "%s/%s" % [dove, k] if dove != "" else String(k)
			if not attesa.has(k):
				fuori.append("%s: COMPARSO (%s)" % [qui, _breve(ottenuta[k])])
			elif not ottenuta.has(k):
				fuori.append("%s: SPARITO (c'era: %s)" % [qui, _breve(attesa[k])])
			else:
				fuori.append_array(confronta(attesa[k], ottenuta[k], qui))
		return fuori

	if attesa is Array:
		if attesa.size() != ottenuta.size():
			fuori.append("%s: %d voci invece di %d" % [dove, ottenuta.size(), attesa.size()])
		for i in mini(attesa.size(), ottenuta.size()):
			fuori.append_array(confronta(attesa[i], ottenuta[i], "%s/%d" % [dove, i]))
		for i in range(attesa.size(), ottenuta.size()):
			fuori.append("%s/%d: COMPARSO (%s)" % [dove, i, _breve(ottenuta[i])])
		for i in range(ottenuta.size(), attesa.size()):
			fuori.append("%s/%d: SPARITO (c'era: %s)" % [dove, i, _breve(attesa[i])])
		return fuori

	if attesa != ottenuta:
		fuori.append("%s:\n      atteso:   %s\n      ottenuto: %s" % [
			dove, _breve(attesa), _breve(ottenuta)])
	return fuori

static func _numero(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func _breve(v: Variant) -> String:
	var s := JSON.stringify(v)
	return s if s.length() <= 100 else s.substr(0, 100) + "…"

# --- Su disco ---

static func salva(traccia: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(PERCORSO.get_base_dir())
	var f := FileAccess.open(PERCORSO, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(traccia, "  ") + "\n")
	f.close()
	return true

## La traccia registrata, o {} se non c'e' ancora.
static func attesa() -> Dictionary:
	if not FileAccess.file_exists(PERCORSO):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO))
	return d if typeof(d) == TYPE_DICTIONARY else {}
