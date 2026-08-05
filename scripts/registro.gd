class_name Registro
extends RefCounted

## IL DIARIO DELL'APPLICAZIONE — cosa ha fatto il gioco, e cosa gli e' andato storto.
##
## E' il compagno di `Tracciato`, e la divisione fra i due e' netta:
##
##   `Tracciato`  →  le conversazioni col modello. Chiamate, token, latenze, HTTP.
##   `Registro`   →  tutto il resto. L'avvio, le preferenze rilette, la partita caricata,
##                   il motore acceso, la musica, i guai.
##
## Servono due file perche' rispondono a due domande diverse, e mescolarli vuol dire che
## nessuna delle due trova risposta in fretta: cercare «perche' non ho la musica» in
## mezzo a settemila righe di prompt e' peggio che non avere il log.
##
## SI SCRIVE SEMPRE SU FILE, in `user://log/`. La finestra e' una vetrina, e si chiede
## all'avvio con `./avvia.sh --logdei`: un problema si nota dopo, e a quel punto o e' stato
## scritto o non c'e' piu'.
##
## COS'E' UN «EVENTO SIGNIFICATIVO». Non tutto: un log che dice tutto non dice niente. Qui
## finisce cio' che (a) cambia lo stato del gioco in un modo che il giocatore potrebbe non
## aspettarsi, (b) fallisce, o (c) e' una condizione dell'ambiente che spiega un
## comportamento — l'audio muto, una chiave assente, un salvataggio illeggibile.
##
## PERCHE' STATICO. Ci si scrive da dappertutto — autoload, scene, dati, strumenti da riga di
## comando — e un autoload non e' raggiungibile in modalita' `--script` (dove gli autoload non
## esistono ancora come identificatori). Uno stato statico e' l'unica forma che funziona in
## tutti e tre i contesti senza che chi scrive debba sapere in quale si trova.

enum { INFO, AVVISO, ERRORE }

const CARTELLA := "user://log"
## Quanti file tenere, come per il tracciato: nessuno legge il quindicesimo.
const QUANTI_TENERNE := 10
## Oltre questa lunghezza la riga si tronca NELLA FINESTRA. Nel file va intera.
const TAGLIO := 400

## …e nei test si scrive nella cartella usa-e-getta. Stessa ragione del tracciato: uno
## strumento di verifica non deve consumare i dati di chi gioca. `avvia.sh test` esporta DEI_LOG.
static func cartella() -> String:
	var alt := OS.get_environment("DEI_LOG")
	return alt if alt != "" else CARTELLA

## Vero se il gioco e' stato avviato con --logdei: la finestra si apre.
## Il FILE si scrive comunque — questa governa solo la vetrina.
static func a_schermo() -> bool:
	return OS.get_environment("DEI_LOG_APP") != ""

## Ogni riga formattata, per la finestra. In headless non ascolta nessuno.
static var su_riga: Callable = Callable()

static var _f: FileAccess = null
static var _percorso := ""
static var _fuso := 0
static var _fuso_letto := false
## Quanti avvisi e quanti errori, per poterlo dire in coda al file.
static var _avvisi := 0
static var _errori := 0
## Le righe scritte prima che la finestra esistesse. La finestra nasce dopo l'avvio, ed e'
## proprio l'avvio la parte piu' interessante: senza questo, il log a schermo comincerebbe
## dopo la sola sezione che spiega com'e' configurata la macchina.
static var _arretrate: Array[String] = []

# --- apertura e chiusura ---

static func apri(etichetta: String) -> void:
	if _f != null:
		return   # gia' aperto: un secondo apri() troncherebbe il file del primo
	DirAccess.make_dir_recursive_absolute(cartella())
	_pota()
	var quando := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	_percorso = "%s/app-%s-%03d.log" % [cartella(), quando, Time.get_ticks_msec() % 1000]
	_f = FileAccess.open(_percorso, FileAccess.WRITE)
	_avvisi = 0
	_errori = 0
	_arretrate.clear()
	sezione("%s · %s" % [etichetta, Time.get_datetime_string_from_system(false, true)])

static func percorso() -> String:
	return ProjectSettings.globalize_path(_percorso) if _percorso != "" else ""

## In coda si scrive il CONTO. Un file di trecento righe non dice a colpo d'occhio se e'
## andato tutto bene; due numeri si'.
static func chiudi() -> void:
	if _f == null:
		return
	sezione("fine · %s · %s" % [_quanti(_avvisi, "avviso", "avvisi"), _quanti(_errori, "errore", "errori")])
	_f.flush()
	_f.close()
	_f = null

## «1 avvisi» in coda a un file che si allega a una segnalazione fa sembrare trascurato tutto
## il resto. Costa tre righe.
static func _quanti(n: int, uno: String, molti: String) -> String:
	return "nessun %s" % uno if n == 0 else "%d %s" % [n, uno if n == 1 else molti]

static func _pota() -> void:
	var dir := DirAccess.open(cartella())
	if dir == null:
		return
	var vecchi: Array = []
	for n in dir.get_files():
		if n.begins_with("app-") and n.ends_with(".log"):
			vecchi.append(n)
	vecchi.sort()
	while vecchi.size() >= QUANTI_TENERNE:
		dir.remove(vecchi.pop_front())

# --- scrivere ---

## Un fatto: e' successo, ed e' andato come doveva.
static func info(dove: String, cosa: String) -> void:
	_riga(INFO, dove, cosa)

## Qualcosa non e' come dovrebbe, ma il gioco va avanti. E' il livello piu' utile dei tre:
## gli errori si notano da soli, gli avvisi no — e sono quelli che spiegano i comportamenti
## strani («la musica non parte», «gli dei non reagiscono»).
static func avviso(dove: String, cosa: String) -> void:
	_avvisi += 1
	_riga(AVVISO, dove, cosa)

## Qualcosa e' fallito. Va anche sul terminale: chi guarda la console non deve dover aprire
## un file per sapere che c'e' stato un problema.
##
## `printerr` E NON `push_error`. La prima versione usava `push_error`, ed era sbagliata per
## due motivi che si sono visti subito:
##
##  - il BACKTRACE che Godot allega punta a `Registro.errore()`, cioe' alla riga che scrive il
##    log. Di un «il provider non risponde» indica il messaggero, mai la causa: e' rumore
##    travestito da diagnostica.
##  - `push_error` e' per gli errori di PROGRAMMAZIONE — un indice fuori posto, un nodo
##    mancante. Un provider che risponde 401 non lo e': e' il mondo che si comporta male, ed
##    e' esattamente cio' che questo registro esiste per annotare. Confonderli vuol dire che
##    chi cerca un bug vero deve prima scartare le condizioni normali.
##
## L'ha detto la suite: due test che provocano apposta un guaio del motore sono diventati
## rossi per «errori inattesi» pur funzionando come dovevano.
static func errore(dove: String, cosa: String) -> void:
	_errori += 1
	_riga(ERRORE, dove, cosa)
	printerr("[%s] %s" % [dove, cosa])

## Un titolo, per separare le fasi. Un log senza confini e' una colata.
static func sezione(titolo: String) -> String:
	var riga := "%s  ── %s ──" % [_ora(), titolo]
	_emetti(riga, riga)
	return riga

## LE RIGHE DI PRIMA, alla finestra che nasce dopo. Vedi `_arretrate`.
static func riversa_in(chi: Callable) -> void:
	su_riga = chi
	if not chi.is_valid():
		return
	for r in _arretrate:
		chi.call(r)
	_arretrate.clear()

const _ETICHETTA := {INFO: "     ", AVVISO: "AVVISO", ERRORE: "ERRORE"}

static func _riga(livello: int, dove: String, cosa: String) -> void:
	var testa := "%s  %-6s %-14s " % [_ora(), _ETICHETTA[livello], dove]
	var pulito := cosa.strip_edges().replace("\n", "⏎ ").replace("\t", " ")
	var breve := pulito if pulito.length() <= TAGLIO else pulito.substr(0, TAGLIO) + " […]"
	_emetti(testa + pulito, testa + breve)

static func _emetti(intera: String, breve: String) -> void:
	if _f != null:
		_f.store_line(intera)
		_f.flush()   # se il gioco muore, il log dev'esserci: e' il caso che conta
	# La finestra e' una RichTextLabel in BBCode: una quadra in un messaggio d'errore
	# aprirebbe un marcatore vero. Si neutralizza qui, al confine.
	var pronta := Bbcode.neutro(breve)
	if su_riga.is_valid():
		su_riga.call(pronta)
	elif _f != null:
		# Solo se il file e' aperto: prima di `apri()` non c'e' nessuna sessione a cui
		# appartengano, e tenerle vorrebbe dire riversarle nella successiva.
		_arretrate.append(pronta)

# --- l'ora, con i millisecondi veri (stessa storia di Tracciato._ora) ---

static func _ora() -> String:
	if not _fuso_letto:
		_fuso = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		_fuso_letto = true
	var u := Time.get_unix_time_from_system() + _fuso
	var intero := floori(u)
	var giorno := intero % 86400
	return "%02d:%02d:%02d.%03d" % [
		giorno / 3600, (giorno / 60) % 60, giorno % 60, int((u - intero) * 1000.0)]
