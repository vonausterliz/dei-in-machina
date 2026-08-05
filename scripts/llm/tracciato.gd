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
##  - **l'ora, con i millisecondi VERI.** Senza, non si misura niente: due righe adiacenti
##    possono distare un millisecondo o mezzo minuto. Vedi `_ora()` per come si e' sbagliato.
##  - **la connessione, PRIMA delle chiamate.** Dove si sta parlando, con quale modello, se
##    si passa dal gateway, se una chiave c'e'. E' la riga che risponde alla domanda che ci si
##    fa per prima quando qualcosa e' lento.
##  - **un numero per chiamata** (`#007`) e il **turno** a cui appartiene. Le chiamate di un
##    turno partono quasi insieme e finiscono in ordine sparso: senza un identificativo, la
##    risposta di Poseidone e quella di Atena sono due righe indistinguibili.
##  - **la latenza di ognuna, e in che cosa se n'e' andata** (preparazione / rete / lettura).
##    E' il dato che indica il colpevole quando un turno e' lento: una chiamata sola, o tutte?
##  - **i token dichiarati dal provider** (`usage`), non stimati. In ingresso, in uscita, i
##    **letti dalla cache**, quelli **di ragionamento** che non si vedono nella risposta ma si
##    pagano in tempo e in denaro, e la causa di fine (`stop`, `length`, …).
##  - **il consuntivo di ogni turno**: quanto e' durato, quanta parte in rete, e quale agente
##    se l'e' preso. E' la risposta alla domanda «dove si perde tempo», scritta invece che
##    lasciata da dedurre sommando righe a mano.
##  - **il confine del gioco**: cosa entra (l'azione scritta dal giocatore) e cosa esce
##    (narrazione, spunti, delta sugli dei). Un tracciato di sole chiamate HTTP dice come ha
##    risposto il modello, non che cosa il gioco gli ha chiesto e che cosa ne ha fatto.
##  - **gli errori col messaggio del provider**, non solo il codice: «HTTP 401» non dice
##    niente, «No auth credentials found» dice tutto.
##
## COSA NON SI SCRIVE MAI: il valore di una chiave API. Nemmeno in modalita' `--tracellm`,
## che stampa tutte le intestazioni HTTP: quelle di autenticazione passano da `_oscura()` e
## restano una coda di quattro caratteri. Un log si incolla in una segnalazione, e non deve
## costare un segreto.
##
## Il tracciato va in DUE posti: la finestra in gioco (se aperta) e un file in `user://log/`,
## perche' la finestra si chiude e il file resta — ed e' quello che si allega a un problema.

## Dove finiscono i file. Sotto `user://`, cioe' fuori dal progetto: sono dati di chi gioca.
const CARTELLA := "user://log"

## …tranne quando gira la suite, che scrive nella sua cartella usa-e-getta. Senza, ogni
## esecuzione dei test avrebbe aggiunto un tracciato e — con la potatura a dieci — spinto
## fuori quelli veri. E' lo stesso difetto trovato sulle preferenze: uno strumento di
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
## Quanto di un corpo HTTP si stampa in `--tracellm`. Un prompt di sistema sono settemila
## caratteri e un log dove ogni chiamata occupa due schermate non si legge: si vede la testa,
## e il conto dei byte dice quanto resta. Chi vuole tutto alza questo numero — non e' un
## limite del formato, e' una scelta di leggibilita'.
const TAGLIO_CORPO := 2000

## IL DETTAGLIO HTTP — `--tracellm`.
##
## Il tracciato normale dice l'esito di una chiamata: quanto ci ha messo, quanti token, com'e'
## finita. Basta per capire *quale* chiamata e' lenta, non *perche'*: per quello serve vedere
## la richiesta come e' partita davvero — verbo, indirizzo, intestazioni, corpo — e la risposta
## come e' arrivata, comprese le intestazioni che il provider usa per dire cose che nel corpo
## non ci sono (i limiti di frequenza, chi ha servito la richiesta a monte, se e' passata da
## una cache). E' molto testo, e per questo si chiede: `./avvia.sh --tracellm`.
var dettaglio := false

## Ogni riga formattata. La GUI ci attacca la finestra; in headless non ascolta nessuno.
var su_riga: Callable = Callable()

var _f: FileAccess = null
var _percorso := ""
var _n := 0
## Il turno di gioco in corso, per legare le chiamate a ciò che il giocatore ha scritto.
var turno := 0

## Il consuntivo del turno in corso: quando è cominciato e quanto ha preso ogni agente.
## Serve a `chiude_turno()`, che è il posto in cui la domanda «dove si perde tempo» ha una
## risposta invece di un elenco di righe da sommare a mano.
var _turno_t0 := 0
var _per_agente: Dictionary = {}   # nome -> {chiamate, ms, tok_in, tok_out, cache, costo}
var _turno_chiamate := 0

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
	_intesta("%s · %s%s" % [etichetta, Time.get_datetime_string_from_system(false, true),
		"  ·  dettaglio HTTP acceso (--tracellm)" if dettaglio else ""])

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
	if dati.has("max_tokens"):
		pezzi.append("max_out=%s" % dati["max_tokens"])
	if bool(dati.get("json", false)):
		pezzi.append("json")
	_riga("REQ ", n, "  ".join(pezzi))
	if dati.has("prompt"):
		_riga("    ", n, "↑ %s" % _pulisci(String(dati["prompt"])), true)
	return n

## Una risposta arriva. `usage` è quello dichiarato dal provider, quando lo manda.
##
## I CAMPI ANNIDATI di `usage` non sono un vezzo: `cached_tokens` è la sola prova che la cache
## di prompt stia funzionando (l'81% del nostro ingresso è prefisso ripetuto identico), e
## `reasoning_tokens` è la spiegazione di un modello che ci mette venti secondi per rispondere
## tre righe — le altre mille le ha pensate, e non compaiono da nessun'altra parte.
func risposta(n: int, dati: Dictionary) -> void:
	var pezzi: Array = ["HTTP %d" % int(dati.get("stato", 0)), "%d ms" % int(dati.get("ms", 0))]
	var u: Dictionary = dati.get("usage", {})
	if not u.is_empty():
		# INTERI. Il JSON di Godot restituisce i numeri come float, e senza questa conversione
		# nel log comparivano «token in=2043.0 out=96.0»: nessun test se ne sarebbe accorto (il
		# valore e' giusto) e nessuno l'avrebbe corretto, perche' un log lo si legge di corsa e
		# ci si abitua. Si e' visto solo guardando un tracciato vero.
		pezzi.append("token in=%s out=%s tot=%s" % [
			_intero(u, "prompt_tokens"), _intero(u, "completion_tokens"), _intero(u, "total_tokens")])
		var cache := _annidato(u, "prompt_tokens_details", "cached_tokens")
		if cache > 0:
			var totale_in := int(u.get("prompt_tokens", 0))
			pezzi.append("cache=%d (%d%%)" % [cache, roundi(100.0 * cache / maxi(totale_in, 1))])
		var scritti := _annidato(u, "prompt_tokens_details", "cache_write_tokens")
		if scritti > 0:
			pezzi.append("cache_scritta=%d" % scritti)
		# Token pensati e mai mostrati. Se ci sono, sono quasi sempre la risposta alla
		# domanda «perche' e' lento»: si pagano in secondi e non si vedono nell'output.
		var pensiero := _annidato(u, "completion_tokens_details", "reasoning_tokens")
		if pensiero > 0:
			pezzi.append("⚠ ragionamento=%d tok (invisibili nella risposta)" % pensiero)
		if u.has("cost"):
			pezzi.append("costo=$%.5f" % float(u["cost"]))
	var fine := String(dati.get("fine", ""))
	if fine != "":
		# `length` vuol dire troncata dal tetto di token, non dal modello: è la spiegazione
		# di una risposta che finisce a metà frase, e va detta invece di farla dedurre.
		pezzi.append("fine=%s%s" % [fine, "  ⚠ TRONCATA" if fine == "length" else ""])
	_riga("RES ", n, "  ".join(pezzi))
	# CHI HA RISPOSTO DAVVERO. Su OpenRouter il modello lo serve un terzo (DeepInfra, Together,
	# Fireworks…) e la scelta cambia da una chiamata all'altra: due chiamate allo stesso nome
	# di modello possono differire di un ordine di grandezza in latenza per questo solo motivo.
	var chi := String(dati.get("servito_da", ""))
	if chi != "":
		_riga("    ", n, "servito da: %s" % chi)
	if dati.has("contenuto"):
		_riga("    ", n, "↓ %s" % _pulisci(String(dati["contenuto"])), true)
	_conta(String(dati.get("agente", "?")), int(dati.get("ms", 0)), u)

## In che cosa se n'è andato il tempo di UNA chiamata. Separare la rete dal resto serve a
## rispondere a una domanda che altrimenti resta aperta: è lento il provider, o siamo noi?
## Finora la risposta era sempre «il provider», ma era una supposizione, non una misura.
func tempi(n: int, preparazione_ms: int, rete_ms: int, lettura_ms: int) -> void:
	_riga("TEMPI", n, "preparazione %d ms · rete %d ms · lettura %d ms · totale %d ms" % [
		preparazione_ms, rete_ms, lettura_ms, preparazione_ms + rete_ms + lettura_ms])

## Un errore. `dettaglio` è il messaggio del provider, non la nostra parafrasi.
func errore(n: int, cosa: String, dettaglio_msg: String = "") -> void:
	_riga("ERR ", n, cosa + ("  — %s" % _pulisci(dettaglio_msg) if dettaglio_msg != "" else ""))

## Un ritentativo: se non si vede, un turno lento sembra una chiamata lenta.
func ritenta(n: int, tentativo: int, di: int, attesa_s: float, perche: String) -> void:
	_riga("RETRY", n, "tentativo %d/%d fra %.1f s — %s" % [tentativo, di, attesa_s, perche])

## Segno d'attesa: una richiesta ancora in volo dopo parecchi secondi. Senza, un modello
## lento e un modello morto sono indistinguibili.
func attesa(n: int, secondi: float) -> void:
	_riga("WAIT", n, "in corso da %.0f s…" % secondi)

## Una nota qualunque, per ciò che non è né richiesta né risposta.
func nota(testo: String) -> void:
	_riga("··· ", "", _pulisci(testo))

# --- il dettaglio HTTP (--tracellm) ---

## LA RICHIESTA COM'È PARTITA. Verbo, indirizzo, intestazioni, corpo.
##
## Le intestazioni passano da `_oscura()`: `Authorization` e `x-api-key` diventano una coda di
## quattro caratteri. Non è una precauzione teorica — questo è il file che si allega a una
## segnalazione, e la modalità che lo rende utile è anche quella che lo renderebbe pericoloso.
func http_richiesta(n: int, metodo: String, url: String, intestazioni: PackedStringArray, corpo: String) -> void:
	if not dettaglio:
		return
	_riga("HTTP", n, "→ %s %s" % [metodo, url])
	for h in intestazioni:
		_riga("HTTP", n, "    %s" % _oscura(h))
	if corpo != "":
		_riga("HTTP", n, "    corpo %d byte:" % corpo.to_utf8_buffer().size())
		_riga("HTTP", n, "    %s" % _corpo(corpo))

## LA RISPOSTA COM'È ARRIVATA. Lo stato, le intestazioni, il corpo grezzo.
##
## Le intestazioni contano quanto il corpo: `x-ratelimit-remaining` dice se si sta per essere
## strozzati, `retry-after` di quanto, e alcuni provider dichiarano lì (e non nel JSON) chi ha
## servito la richiesta a monte e se è passata da una cache.
func http_risposta(n: int, stato: int, intestazioni: PackedStringArray, corpo: String, ms: int) -> void:
	if not dettaglio:
		return
	_riga("HTTP", n, "← HTTP %d  in %d ms" % [stato, ms])
	for h in intestazioni:
		_riga("HTTP", n, "    %s" % _oscura(h))
	if corpo != "":
		_riga("HTTP", n, "    corpo %d byte:" % corpo.to_utf8_buffer().size())
		_riga("HTTP", n, "    %s" % _corpo(corpo))

# --- il confine del gioco ---

## Il confine fra un turno e l'altro: è ciò che rende leggibile un file di mille righe.
func apre_turno(numero: int, azione: String) -> void:
	turno = numero
	_turno_t0 = Time.get_ticks_msec()
	_per_agente = {}
	_turno_chiamate = 0
	_intesta("turno %d — %s" % [numero, _pulisci(azione)])

## COSA ENTRA NEL GIOCO. L'azione scritta dal giocatore, prima che diventi prompt.
func entra(cosa: String, valore: String) -> void:
	_riga("GIOCO", "", "↘ ENTRA  %s: %s" % [cosa, _pulisci(valore)], true)

## COSA ESCE DAL GIOCO. La narrazione, gli spunti, il delta sugli dei: il risultato che il
## giocatore vede. Un tracciato di sole chiamate dice come ha risposto il modello, non che
## cosa il gioco ne ha fatto — e fra le due cose c'è tutto il codice che abbiamo scritto noi.
func esce(cosa: String, valore: String) -> void:
	_riga("GIOCO", "", "↗ ESCE   %s: %s" % [cosa, _pulisci(valore)], true)

## IL CONSUNTIVO — dove si è perso il tempo, scritto invece che lasciato da dedurre.
##
## È la riga che questo file esisteva per produrre. Un turno lento non è informativo: lo è
## sapere che di quaranta secondi trentasei sono stati due dèi, e che uno solo ne ha presi
## venti perché ha «ragionato» mille token che nella sua battuta non compaiono.
func chiude_turno() -> void:
	if _turno_t0 == 0:
		return
	var totale := Time.get_ticks_msec() - _turno_t0
	_intesta("consuntivo turno %d — %.1f s" % [turno, totale / 1000.0])
	var in_rete := 0
	var tok_in := 0
	var tok_out := 0
	var cache := 0
	var costo := 0.0
	for a in _per_agente:
		var d: Dictionary = _per_agente[a]
		in_rete += int(d["ms"])
		tok_in += int(d["tok_in"])
		tok_out += int(d["tok_out"])
		cache += int(d["cache"])
		costo += float(d["costo"])
	_riga("BILANCIO", "", "%d chiamate · %.1f s in rete (%d%%) · %.1f s nel gioco" % [
		_turno_chiamate, in_rete / 1000.0, roundi(100.0 * in_rete / maxi(totale, 1)),
		maxi(totale - in_rete, 0) / 1000.0])
	# In ordine di tempo speso: il colpevole in cima, che è come si legge un consuntivo.
	var nomi: Array = _per_agente.keys()
	nomi.sort_custom(func(a, b): return int(_per_agente[a]["ms"]) > int(_per_agente[b]["ms"]))
	for i in nomi.size():
		var a: String = nomi[i]
		var d: Dictionary = _per_agente[a]
		_riga("BILANCIO", "", "  %-22s %d ×  %6.1f s%s" % [
			a, int(d["chiamate"]), int(d["ms"]) / 1000.0,
			"   ← il più lento" if i == 0 and nomi.size() > 1 else ""])
	if tok_in > 0 or tok_out > 0:
		var quota := "" if cache == 0 else "  (di cui %d dalla cache, %d%%)" % [
			cache, roundi(100.0 * cache / maxi(tok_in, 1))]
		_riga("BILANCIO", "", "  token  in=%d%s  out=%d%s" % [
			tok_in, quota, tok_out, "  ·  costo $%.5f" % costo if costo > 0.0 else ""])
	_turno_t0 = 0

## Somma una risposta nel consuntivo del turno. Privato: lo chiama `risposta()`, perché
## il posto giusto per contare è quello in cui il dato arriva, non un secondo punto da
## ricordarsi di chiamare (che è il modo in cui i contatori smettono di tornare).
func _conta(agente: String, ms: int, u: Dictionary) -> void:
	if _turno_t0 == 0:
		return
	_turno_chiamate += 1
	if not _per_agente.has(agente):
		_per_agente[agente] = {"chiamate": 0, "ms": 0, "tok_in": 0, "tok_out": 0, "cache": 0, "costo": 0.0}
	var d: Dictionary = _per_agente[agente]
	d["chiamate"] = int(d["chiamate"]) + 1
	d["ms"] = int(d["ms"]) + ms
	d["tok_in"] = int(d["tok_in"]) + int(u.get("prompt_tokens", 0))
	d["tok_out"] = int(d["tok_out"]) + int(u.get("completion_tokens", 0))
	d["cache"] = int(d["cache"]) + _annidato(u, "prompt_tokens_details", "cached_tokens")
	d["costo"] = float(d["costo"]) + float(u.get("cost", 0.0))

# --- formattazione ---

## L'ORA, CON I MILLISECONDI VERI.
##
## Qui c'era un difetto che vale la pena raccontare, perche' e' della specie peggiore: uno
## strumento di misura che produce un numero plausibile e sbagliato. I secondi venivano da
## `Time.get_time_dict_from_system()` e i millisecondi da `Time.get_ticks_msec() % 1000` —
## cioe' dai millisecondi di ACCENSIONE DEL GIOCO, che con l'orologio non hanno alcun
## rapporto. Il risultato aveva la forma giusta e il contenuto casuale, e nel log dell'utente
## si vedeva l'ora andare all'INDIETRO: «12:26:15.484» seguito da «12:26:15.061».
##
## Nessun test poteva accorgersene (la stringa e' ben formata) e a occhio non si nota, perche'
## si guarda il secondo. Se ne accorge solo chi prova a MISURARE qualcosa — che e' l'unica
## ragione per cui i millisecondi erano stati messi. Il campo esisteva per rispondere a «dove
## si perde tempo» e rispondeva con rumore.
##
## Ora tutto viene da una sola lettura dell'orologio, cosi' le due meta' non possono
## discordare. Per le DURATE resta giusto `get_ticks_msec()`: e' monotono, e non lo sposta
## un cambio d'ora.
func _ora() -> String:
	var u := Time.get_unix_time_from_system() + _scarto_fuso()
	var intero := floori(u)
	var giorno := intero % 86400
	return "%02d:%02d:%02d.%03d" % [
		giorno / 3600, (giorno / 60) % 60, giorno % 60, int((u - intero) * 1000.0)]

## Lo scarto dal tempo universale, in secondi. Letto una volta: cambia due volte l'anno.
var _fuso := 0
var _fuso_letto := false

func _scarto_fuso() -> int:
	if not _fuso_letto:
		_fuso = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		_fuso_letto = true
	return _fuso

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

## Un corpo HTTP su una riga sola, accorciato in coda. Va sul file INTERO fino a
## TAGLIO_CORPO: un JSON spezzato su venti righe rende il log illeggibile proprio quando
## serve scorrerlo in fretta.
func _corpo(t: String) -> String:
	var s := t.replace("\n", " ").replace("\t", " ")
	if s.length() <= TAGLIO_CORPO:
		return s
	return "%s  […altri %d caratteri]" % [s.substr(0, TAGLIO_CORPO), s.length() - TAGLIO_CORPO]

## UN'INTESTAZIONE HTTP RESA INNOCUA. Di una credenziale resta il nome, la lunghezza e le
## ultime quattro cifre: abbastanza per dire «è quella giusta?», troppo poco per usarla.
## L'elenco è di nomi INTERI e minuscoli: `_oscura` normalizza prima di confrontare, perché
## i provider li scrivono come vogliono (`Authorization`, `X-Api-Key`, `x-goog-api-key`).
const CHIAVI_SEGRETE := ["authorization", "x-api-key", "x-goog-api-key", "api-key", "cookie", "set-cookie"]

func _oscura(intestazione: String) -> String:
	var punto := intestazione.find(":")
	if punto < 0:
		return intestazione
	var nome := intestazione.substr(0, punto)
	if not CHIAVI_SEGRETE.has(nome.strip_edges().to_lower()):
		return intestazione
	var valore := intestazione.substr(punto + 1).strip_edges()
	if valore == "":
		return "%s: (vuota)" % nome
	# «Bearer sk-or-v1-abc…» → il prefisso resta, il segreto no.
	var coda := valore.substr(maxi(valore.length() - 4, 0))
	return "%s: %s… (%d caratteri, oscurata)" % [nome, coda.lpad(8, "·"), valore.length()]

## Stima grossolana dei token in ingresso: ~4 caratteri per token sui testi latini. È una
## STIMA e si vede che lo è (il «≈»); quelli veri arrivano dal provider, dopo.
func _tok(caratteri: int) -> String:
	var t := caratteri / 4
	return "%.1fk tok" % (t / 1000.0) if t >= 1000 else "%d tok" % t

## Un campo di `usage` come intero, o «?» se non c'è. Vedi il commento in `risposta()`.
func _intero(d: Dictionary, campo: String) -> String:
	return str(int(d[campo])) if d.has(campo) else "?"

## Un intero dentro un dizionario annidato, o 0. I campi ricchi di `usage` sono opzionali e
## di forma variabile fra provider: leggerli difensivamente è la differenza fra un dato in
## più e un crash a metà partita.
func _annidato(d: Dictionary, dentro: String, campo: String) -> int:
	var sotto: Variant = d.get(dentro)
	if typeof(sotto) != TYPE_DICTIONARY:
		return 0
	return int((sotto as Dictionary).get(campo, 0))
