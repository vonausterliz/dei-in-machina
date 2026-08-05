class_name Tracciato
extends RefCounted

## IL DIARIO DELLE INTERAZIONI COL MODELLO — una riga per evento, in ordine di tempo.
##
## Prima il log era una manciata di frecce senza orologio: si vedeva *che* era successo
## qualcosa, non *quando*, non a chi, non quanto era costato. Bastava una domanda semplice —
## «perche' questo turno ha impiegato quaranta secondi?» — per restare senza risposta, e una
## piu' semplice ancora («ma sto parlando con OpenRouter o con Ollama?») per rispondere in
## modo sbagliato: `localhost:11434` e `localhost:8800` si somigliano abbastanza da ingannare.
##
## COSA SI SCRIVE, e perche' proprio questo:
##
##  - **l'ora, con i millisecondi.** Senza, non si misura niente: due righe adiacenti possono
##    distare un millisecondo o mezzo minuto.
##  - **la connessione, PRIMA delle chiamate.** Dove si sta parlando, con quale modello, se
##    si passa dal gateway, se una chiave c'e'. E' la riga che risponde alla domanda che ci si
##    fa per prima quando qualcosa e' lento.
##  - **un numero per chiamata** (`#007`) e il **turno** a cui appartiene. Le chiamate di un
##    turno partono quasi insieme e finiscono in ordine sparso: senza un identificativo, la
##    risposta di Poseidone e quella di Atena sono due righe indistinguibili.
##  - **la latenza di ognuna.** E' il dato che indica il colpevole quando un turno e' lento:
##    una chiamata sola, o tutte?
##  - **i token dichiarati dal provider** (`usage`), non stimati. In ingresso, in uscita, e la
##    causa di fine (`stop`, `length`, …): un `length` spiega una risposta troncata meglio di
##    qualunque congettura.
##  - **gli errori col messaggio del provider**, non solo il codice: «HTTP 401» non dice
##    niente, «No auth credentials found» dice tutto.
##
## COSA NON SI SCRIVE MAI: il valore di una chiave API. Solo se c'e' e da quale variabile
## viene. Un log si incolla in una segnalazione, e non deve costare un segreto.
##
## Il tracciato va in DUE posti: la finestra in gioco (se aperta) e un file in `user://log/`,
## perche' la finestra si chiude e il file resta — ed e' quello che si allega a un problema.

## Dove finiscono i file. Sotto `user://`, cioe' fuori dal progetto: sono dati di chi gioca.
const CARTELLA := "user://log"

## …tranne quando gira la suite, che scrive nella sua cartella usa-e-getta. Senza, ogni
## esecuzione dei test avrebbe aggiunto un tracciato e — con la potatura a dieci — spinto
## fuori quelli veri. E' lo stesso difetto trovato oggi sulle preferenze: uno strumento di
## verifica che consuma i dati di chi gioca. `avvia.sh test` esporta DEI_LOG.
static func cartella() -> String:
	var alt := OS.get_environment("DEI_LOG")
	return alt if alt != "" else CARTELLA

## Quanti file tenere. Un log per avvio, e i piu' vecchi si buttano: nessuno legge il
## quindicesimo, e una cartella che cresce per sempre e' un difetto lento.
const QUANTI_TENERNE := 10
## Oltre questa lunghezza il testo si tronca NELLA FINESTRA. Nel file va intero: il file
## esiste apposta per quando la riga troncata era proprio quella che serviva.
const TAGLIO := 300

## Ogni riga formattata. La GUI ci attacca la finestra; in headless non ascolta nessuno.
var su_riga: Callable = Callable()

var _f: FileAccess = null
var _percorso := ""
var _n := 0
## Il turno di gioco in corso, per legare le chiamate a ciò che il giocatore ha scritto.
var turno := 0

# --- apertura e chiusura ---

## `etichetta` finisce nell'intestazione: chi ha aperto il file, e quando.
##
## IL NOME PORTA I MILLISECONDI. Con la sola precisione al secondo due tracciati aperti nello
## stesso istante ricevevano lo stesso nome, e il secondo apriva in WRITE il file del primo:
## le righe di uno sparivano dentro l'altro. Non e' un caso di laboratorio — succede a ogni
## avvio in cui uno strumento gira accanto al gioco, ed e' cosi' che l'ho scoperto.
func apri(etichetta: String) -> void:
	DirAccess.make_dir_recursive_absolute(cartella())
	_pota()
	var quando := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "-")
	_percorso = "%s/llm-%s-%03d.log" % [cartella(), quando, Time.get_ticks_msec() % 1000]
	_f = FileAccess.open(_percorso, FileAccess.WRITE)
	_intesta("%s · %s" % [etichetta, Time.get_datetime_string_from_system(false, true)])

func percorso() -> String:
	return ProjectSettings.globalize_path(_percorso) if _percorso != "" else ""

func chiudi() -> void:
	if _f != null:
		_f.flush()
		_f.close()
		_f = null

## Tiene solo i file più recenti.
func _pota() -> void:
	var dir := DirAccess.open(cartella())
	if dir == null:
		return
	var vecchi: Array = []
	for n in dir.get_files():
		if n.begins_with("llm-") and n.ends_with(".log"):
			vecchi.append(n)
	vecchi.sort()
	while vecchi.size() >= QUANTI_TENERNE:
		dir.remove(vecchi.pop_front())

# --- gli eventi ---

## La connessione: dove si parla, con cosa, e con quali credenziali. Si scrive quando il
## motore reale si accende e ogni volta che la destinazione cambia.
func connessione(dati: Dictionary) -> void:
	_intesta("connessione")
	_riga("CONN", "", "provider=%s  modello=%s" % [dati.get("provider", "?"), dati.get("modello", "?")])
	_riga("CONN", "", "endpoint=%s" % dati.get("endpoint", "?"))
	var via := String(dati.get("gateway", ""))
	_riga("CONN", "", "gateway=%s" % (via if via != "" else "no (diretto al provider)"))
	# Mai il VALORE. Solo se c'è, e da dove verrebbe: è la differenza fra un log
	# incollabile in una segnalazione e un segreto perso.
	var env := String(dati.get("chiave_env", ""))
	if env == "":
		_riga("CONN", "", "chiave=non serve (provider locale)")
	else:
		_riga("CONN", "", "chiave=%s (variabile %s)" % [
			"presente" if bool(dati.get("chiave_presente", false)) else "ASSENTE", env])
	if dati.has("timeout_s"):
		_riga("CONN", "", "timeout=%s s" % dati["timeout_s"])

## Una richiesta parte. Ritorna il numero assegnato: va ripassato a `risposta`/`errore`,
## ed è ciò che permette di ricucire una risposta alla sua domanda.
func richiesta(agente: String, dati: Dictionary) -> int:
	_n += 1
	var n := _n
	var pezzi: Array = ["turno=%d" % turno, "agente=%s" % agente]
	if dati.has("modello"):
		pezzi.append("modello=%s" % dati["modello"])
	if dati.has("messaggi"):
		pezzi.append("msg=%d" % int(dati["messaggi"]))
	if dati.has("caratteri_in"):
		pezzi.append("in≈%s" % _tok(int(dati["caratteri_in"])))
	if dati.has("temperatura"):
		pezzi.append("temp=%s" % dati["temperatura"])
	if bool(dati.get("json", false)):
		pezzi.append("json")
	_riga("REQ ", n, "  ".join(pezzi))
	if dati.has("prompt"):
		_riga("    ", n, "↑ %s" % _pulisci(String(dati["prompt"])), true)
	return n

## Una risposta arriva. `usage` è quello dichiarato dal provider, quando lo manda.
func risposta(n: int, dati: Dictionary) -> void:
	var pezzi: Array = ["HTTP %d" % int(dati.get("stato", 0)), "%d ms" % int(dati.get("ms", 0))]
	var u: Dictionary = dati.get("usage", {})
	if not u.is_empty():
		pezzi.append("token in=%s out=%s tot=%s" % [
			u.get("prompt_tokens", "?"), u.get("completion_tokens", "?"), u.get("total_tokens", "?")])
	var fine := String(dati.get("fine", ""))
	if fine != "":
		# `length` vuol dire troncata dal tetto di token, non dal modello: è la spiegazione
		# di una risposta che finisce a metà frase, e va detta invece di farla dedurre.
		pezzi.append("fine=%s%s" % [fine, "  ⚠ TRONCATA" if fine == "length" else ""])
	_riga("RES ", n, "  ".join(pezzi))
	if dati.has("contenuto"):
		_riga("    ", n, "↓ %s" % _pulisci(String(dati["contenuto"])), true)

## Un errore. `dettaglio` è il messaggio del provider, non la nostra parafrasi.
func errore(n: int, cosa: String, dettaglio: String = "") -> void:
	_riga("ERR ", n, cosa + ("  — %s" % _pulisci(dettaglio) if dettaglio != "" else ""))

## Un ritentativo: se non si vede, un turno lento sembra una chiamata lenta.
func ritenta(n: int, tentativo: int, di: int, attesa_s: float, perche: String) -> void:
	_riga("RETRY", n, "tentativo %d/%d fra %.1f s — %s" % [tentativo, di, attesa_s, perche])

## Segno d'attesa: una richiesta ancora in volo dopo parecchi secondi. Senza, un modello
## lento e un modello morto sono indistinguibili.
func attesa(n: int, secondi: float) -> void:
	_riga("WAIT", n, "in corso da %.0f s…" % secondi)

## Il confine fra un turno e l'altro: è ciò che rende leggibile un file di mille righe.
func apre_turno(numero: int, azione: String) -> void:
	turno = numero
	_intesta("turno %d — %s" % [numero, _pulisci(azione)])

## Una nota qualunque, per ciò che non è né richiesta né risposta.
func nota(testo: String) -> void:
	_riga("··· ", "", _pulisci(testo))

# --- formattazione ---

func _ora() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d.%03d" % [t["hour"], t["minute"], t["second"], Time.get_ticks_msec() % 1000]

func _intesta(titolo: String) -> String:
	var riga := "%s  ── %s ──" % [_ora(), titolo]
	_emetti(riga, riga)
	return riga

## Una riga, in due versioni: intera per il file, tagliata per la finestra.
func _riga(tipo: String, n: Variant, testo: String, tagliabile := false) -> void:
	var eti := "#%03d" % int(n) if typeof(n) == TYPE_INT else "    "
	var testa := "%s  %s %s  " % [_ora(), eti, tipo]
	var breve := testo if not tagliabile or testo.length() <= TAGLIO else testo.substr(0, TAGLIO) + " […]"
	_emetti(testa + testo, testa + breve)

func _emetti(intera: String, breve: String) -> void:
	if _f != null:
		_f.store_line(intera)
		_f.flush()   # se il gioco muore, il log dev'esserci lo stesso: è il caso che conta
	if su_riga.is_valid():
		# La finestra è una RichTextLabel in BBCode: una quadra generata dal modello
		# aprirebbe un marcatore vero. Si neutralizza qui, al confine.
		su_riga.call(Bbcode.neutro(breve))

func _pulisci(t: String) -> String:
	return t.strip_edges().replace("\n", "⏎ ").replace("\t", " ")

## Stima grossolana dei token in ingresso: ~4 caratteri per token sui testi latini. È una
## STIMA e si vede che lo è (il «≈»); quelli veri arrivano dal provider, dopo.
func _tok(caratteri: int) -> String:
	var t := caratteri / 4
	return "%.1fk tok" % (t / 1000.0) if t >= 1000 else "%d tok" % t
