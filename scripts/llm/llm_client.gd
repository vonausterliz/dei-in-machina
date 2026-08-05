class_name LLMClient
extends Node

## Client LLM provider-agnostico sul formato chat-completions di OpenAI
## (design sez. 9). Ollama, Mistral e l'endpoint compatibile di Anthropic parlano
## tutti questa lingua: cambiare provider = cambiare config, non codice.
## E' un Node perche' HTTPRequest deve stare nell'albero della scena.
##
## chat() e' una coroutine: `await client.chat(messaggi, opzioni)`.
## Ritorna sempre un Dictionary: {ok: bool, content: String, error: String, grezzo: Dictionary}.

var base_url: String = "http://localhost:11434"
var model: String = "llama3.3:latest"
var api_key: String = ""
var timeout_sec: float = 120.0
# Path dell'endpoint (dopo base_url). Default OpenAI/Ollama/Mistral; Google usa /v1beta/openai/...
var chat_path: String = "/v1/chat/completions"
var models_path: String = "/v1/models"
## Endpoint proprietario che elenca i modelli CON la loro taglia (Ollama: /api/tags).
## Vuoto = questo provider non ne ha uno, e le taglie restano ignote.
var tags_path: String = ""
## Intestazioni HTTP in piu', dichiarate dal profilo del provider.
##
## Serve ad Anthropic, l'unico che non parla del tutto la lingua di OpenAI: il suo layer di
## compatibilita' accetta il «Authorization: Bearer» su /chat/completions, ma /models
## pretende «x-api-key» e il Bearer lo rifiuta con un 401. L'alternativa era un ramo
## «se il provider e' anthropic» qui dentro; cosi' invece resta un dato nel suo file, e il
## prossimo provider con le sue manie si aggiunge senza toccare il client.
## Il valore SEGNAPOSTO_CHIAVE viene sostituito con la chiave API vera.
var intestazioni_extra: Dictionary = {}

## Nei dati la chiave API non c'e': c'e' questo, e lo sostituisce il client.
const SEGNAPOSTO_CHIAVE := "$CHIAVE"

## Logger opzionale per il debug: se valido, riceve righe di testo con il traffico
## (cosa viene mandato / cosa viene ricevuto). La GUI lo collega alla finestra di log.
var logger: Callable = Callable()

## IL TRACCIATO STRUTTURATO. Se c'e', il client non decide piu' come si scrive una riga:
## riporta i FATTI (quanti messaggi, quanti millisecondi, quali token, che errore) e la
## formattazione la fa `Tracciato`. Separarli serve a due cose — l'ora e il numero di
## chiamata compaiono ovunque senza ripeterli qui, e lo stesso evento puo' finire sia nella
## finestra sia nel file senza che il client sappia dell'esistenza di nessuno dei due.
var tracciato: Tracciato = null
## Chi sta chiamando, per la riga di richiesta: «Interprete», «Poseidone», «Omero».
##
## E' un campo CONDIVISO, scritto da `LLMManager._per()` un attimo prima di consegnare la
## Callable. `chat()` lo copia in una variabile locale alla PRIMA riga e poi non lo rilegge
## piu': oggi le chiamate di un turno sono in fila indiana e la differenza non si vedrebbe,
## ma l'elenco dei modelli in Impostazioni parte mentre una chat e' in volo — e da li' a
## trovarsi la risposta di Omero attribuita al «Vaglio» ci vuole poco.
var agente: String = "?"

## UN HTTPRequest PER RICHIESTA, non uno per client.
##
## C'era un nodo solo, riusato da tutti: e HTTPRequest ne serve una alla volta. Due chiamate
## sovrapposte facevano sputare a Godot un «Condition "requesting" is true» e lasciavano il
## secondo chiamante con una risposta mai arrivata. Ho provato a metterci una guardia, ed e'
## stato peggio: la collisione e' diventata un errore VISIBILE che accusava la rete —
## «Non raggiungo http://localhost:11434» con Ollama perfettamente in ascolto. Bastava aprire
## Impostazioni mentre il motore si stava accendendo.
##
## La guardia curava il sintomo. La causa e' che due domande indipendenti — «quali modelli
## hai?» e «rispondi a questo turno?» — si contendevano un tubo solo. Un nodo per richiesta,
## creato e buttato: si sovrappongono quante ne servono, e nessuna aspetta l'altra.
##
## (Il nodo lo creano `_apri()` e `_chiudi()`, qui sotto: questo commento sta in cima perche'
## e' la decisione di fondo del trasporto, non un dettaglio di due funzioni.)

## Ogni quanto il battito d'attesa dice che una richiesta e' ancora viva.
const BATTITO_S := 8.0

## IL BATTITO E' PER CHIAMATA, non per client.
##
## C'era un Timer solo, e con lui due campi condivisi (`_n_chiamata`, `_t_inizio`) da cui il
## battito leggeva numero e istante d'inizio. Finche' le chiamate sono in fila indiana funziona;
## appena due si sovrappongono, la seconda sovrascrive i campi e il battito della prima
## comincia a raccontare i secondi dell'altra — sotto il numero sbagliato. E' lo stesso difetto
## che aveva l'HTTPRequest condiviso (vedi sopra), e ha la stessa cura: un tubo per richiesta.
##
## Il Timer nasce figlio dell'HTTPRequest, cosi' `_chiudi()` se lo porta via da solo e non
## resta un battito orfano a scrivere nel log di una chiamata gia' finita.
func _battito_per(h: HTTPRequest, n: int, t0: int) -> void:
	var t := Timer.new()
	t.wait_time = BATTITO_S
	t.one_shot = false
	h.add_child(t)
	t.timeout.connect(func() -> void:
		var passati := int((Time.get_ticks_msec() - t0) / 1000)
		if tracciato != null:
			tracciato.attesa(n, passati)
		else:
			_log("    … in attesa (%d s di %d)…" % [passati, int(timeout_sec)]))
	t.start()

func configura(config: Dictionary, chiave: String = "") -> void:
	base_url = config.get("base_url", base_url)
	model = config.get("model", model)
	api_key = chiave
	timeout_sec = config.get("timeout_sec", timeout_sec)
	# Default OpenAI espliciti: se il profilo non li specifica, si torna a questi (così
	# passando da Google a Mistral il path non resta quello di Google).
	chat_path = config.get("chat_path", "/v1/chat/completions")
	models_path = config.get("models_path", "/v1/models")
	tags_path = config.get("tags_path", "")
	intestazioni_extra = config.get("intestazioni", {})

## Il tubo per UNA richiesta. Chi lo apre lo chiude: `_chiudi()` in ogni uscita.
func _apri() -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = timeout_sec
	add_child(h)
	return h

func _chiudi(h: HTTPRequest) -> void:
	if h:
		remove_child(h)   # subito, non a fine fotogramma: e' un nodo per richiesta
		h.queue_free()

## Le intestazioni di autenticazione, uguali per chat ed elenco dei modelli. Erano scritte
## due volte, e con Anthropic le due copie avrebbero dovuto divergere: un posto solo.
func intestazioni() -> PackedStringArray:
	var h := PackedStringArray()
	if api_key != "":
		h.append("Authorization: Bearer %s" % api_key)
	for nome in intestazioni_extra:
		var valore := String(intestazioni_extra[nome])
		if valore == SEGNAPOSTO_CHIAVE:
			if api_key == "":
				continue   # senza chiave l'intestazione sarebbe vuota: meglio non mandarla
			valore = api_key
		h.append("%s: %s" % [nome, valore])
	return h

## IL CORPO CHE PARTE DAVVERO, costruito a parte per poterlo GUARDARE senza rete.
##
## Stava dentro `chat()`, e per sapere che cosa il gioco spedisse bisognava spedirlo. Da li'
## e' venuto un difetto silenzioso: `max_tokens` era fra le opzioni — `LLMManager` lo passa a
## 1 per la «prova del modello» — e `chat()` lo BUTTAVA. La prova chiedeva un token e ne
## generava centinaia, e nessuno poteva accorgersene perche' nessuno vedeva il corpo. Peggio:
## senza tetto, un modello che «ragiona» prima di rispondere si prende decine di secondi e
## mille token che nella battuta non compaiono, e nessuno gli dice mai di smettere.
##
## Ora e' una funzione pubblica e pura: `test_llm_client.gd` le chiede il corpo e controlla
## che ogni opzione dichiarata ci sia dentro. Un'opzione che non arriva al provider e'
## indistinguibile da un'opzione ignorata dal provider, e le due cose si curano in modi opposti.
func corpo_richiesta(messaggi: Array, opzioni: Dictionary = {}) -> Dictionary:
	var corpo := {
		"model": model,
		"messages": messaggi,
		"temperature": opzioni.get("temperature", 0.7),
		"stream": false,
	}
	# Seed deterministico per run riproducibili (design: "seed presto").
	if opzioni.has("seed"):
		corpo["seed"] = opzioni["seed"]
	# Forza output JSON quando serve (Interprete): supportato da Ollama /v1 e OpenAI.
	if opzioni.get("json_mode", false):
		corpo["response_format"] = {"type": "json_object"}
	if opzioni.has("max_tokens"):
		corpo["max_tokens"] = opzioni["max_tokens"]
	return corpo

## messaggi: Array di {role, content}. opzioni: {temperature, seed, json_mode, max_tokens}.
func chat(messaggi: Array, opzioni: Dictionary = {}) -> Dictionary:
	# `agente` e' condiviso e cambia sotto i piedi: si copia qui, una volta, e da qui in giu'
	# si usa solo `chi`. Vedi il commento sul campo.
	var chi := agente
	if not is_inside_tree():
		return _errore("client non nell'albero della scena")

	var t_prep := Time.get_ticks_msec()
	var corpo := corpo_richiesta(messaggi, opzioni)

	var headers := PackedStringArray(["Content-Type: application/json"])
	headers.append_array(intestazioni())

	var url := base_url.trim_suffix("/") + chat_path
	var carico := JSON.stringify(corpo)
	var n := 0
	if tracciato != null:
		var caratteri := 0
		for m in messaggi:
			if typeof(m) == TYPE_DICTIONARY:
				caratteri += String(m.get("content", "")).length()
		var dati := {
			"modello": model, "messaggi": messaggi.size(), "caratteri_in": caratteri,
			"temperatura": corpo["temperature"], "json": opzioni.get("json_mode", false),
			"prompt": _ultimo_utente(messaggi),
		}
		if corpo.has("max_tokens"):
			dati["max_tokens"] = corpo["max_tokens"]
		n = tracciato.richiesta(chi, dati)
		tracciato.http_richiesta(n, "POST", url, headers, carico)
	else:
		_log("  ⇢ POST %s · model=%s · temp=%s%s" % [url, model, corpo["temperature"], " · json" if opzioni.get("json_mode", false) else ""])
		_log("    ⇡ invio: %s" % Bbcode.neutro(_tronca(_ultimo_utente(messaggi), 240)))
	var h := _apri()
	var t_rete := Time.get_ticks_msec()
	var err := h.request(url, headers, HTTPClient.METHOD_POST, carico)
	if err != OK:
		_chiudi(h)
		return _fallita(n, "richiesta HTTP fallita in partenza: %s" % error_string(err))

	_battito_per(h, n, t_rete)
	var risultato: Array = await h.request_completed
	_chiudi(h)
	# risultato = [result, response_code, headers, body]
	var result_code: int = risultato[0]
	var status: int = risultato[1]
	var teste: PackedStringArray = risultato[2]
	var body: PackedByteArray = risultato[3]

	var ms := Time.get_ticks_msec() - t_rete
	var t_lettura := Time.get_ticks_msec()
	var testo := body.get_string_from_utf8()
	if tracciato != null:
		tracciato.http_risposta(n, status, teste, testo, ms)

	if result_code != HTTPRequest.RESULT_SUCCESS:
		if result_code == HTTPRequest.RESULT_TIMEOUT:
			return _fallita(n, "timeout: nessuna risposta entro %d s (modello troppo lento su questa macchina?)" % int(timeout_sec))
		return _fallita(n, "trasporto HTTP fallito (result=%d) — il provider non risponde?" % result_code)
	if status < 200 or status >= 300:
		# `_perche()` conosce i casi che si spiegano da soli (401 col Gateway acceso) e
		# tiene il messaggio del provider. Prima chat() lo buttava e teneva solo il codice.
		return _fallita(n, _perche(status, body))

	var parsed = JSON.parse_string(testo)
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fallita(n, "risposta non-JSON dal provider")

	# I token li dichiara il PROVIDER, in `usage`: sono quelli fatturati. La nostra stima
	# in partenza serve solo a non restare al buio prima della risposta.
	var uso: Dictionary = parsed.get("usage", {}) if typeof(parsed.get("usage")) == TYPE_DICTIONARY else {}
	var contenuto := _estrai_contenuto(parsed)
	if contenuto == "":
		# UNA RISPOSTA VUOTA NON E' UN FATTO SOLO. La riga della traccia si scrive comunque —
		# altrimenti l'unico caso in cui i token servono davvero e' l'unico in cui mancano — e
		# il `grezzo` si consegna a chi chiama, perche' «il modello ha prodotto token ma niente
		# contenuto» e «il modello non ha risposto» si curano in modi opposti e da qui non si
		# vede quale delle due interessi.
		if tracciato != null:
			tracciato.risposta(n, {"stato": status, "ms": ms, "usage": uso, "agente": chi,
				"fine": _motivo_fine(parsed), "servito_da": _servito_da(parsed)})
		var esito := _fallita(n, _perche_vuota(parsed, uso))
		esito["grezzo"] = parsed
		return esito

	if tracciato != null:
		tracciato.risposta(n, {
			"stato": status, "ms": ms, "usage": uso, "agente": chi,
			"fine": _motivo_fine(parsed), "contenuto": contenuto,
			"servito_da": _servito_da(parsed),
		})
		tracciato.tempi(n, t_rete - t_prep, ms, Time.get_ticks_msec() - t_lettura)
	else:
		# Il corpo della risposta e' testo del modello, e la finestra del Log lo mostra in
		# BBCode: senza neutralizzarlo una quadra generata dal modello colorerebbe il log.
		_log("    ⇣ HTTP %d · %s" % [status, Bbcode.neutro(_tronca(contenuto, 320))])
	return {"ok": true, "content": contenuto, "error": "", "grezzo": parsed}

## PERCHE' LA RISPOSTA E' VUOTA. «Nessun contenuto nella risposta del provider» e' vero e
## inutile: non dice se il modello ha taciuto, se l'abbiamo strozzato noi, o se ha parlato
## in un campo che non guardiamo.
##
## I tre casi si distinguono dai dati che il provider manda gia':
##  - `finish_reason: length` con dei token in uscita → l'ha troncata **il nostro tetto**;
##  - un campo `reasoning` pieno e `content` nullo → e' un modello a ragionamento
##    obbligatorio che ha speso tutto a pensare (DeepSeek V4, Qwen3.8…). In partita, senza
##    tetto, scrive normalmente: il consiglio giusto e' alzare il tetto, non cambiare modello;
##  - zero token in uscita → allora si', il modello non ha prodotto niente.
##
## E' costato un modello rifiutato per errore: la prova pre-partita chiedeva un token solo,
## DeepSeek lo spendeva nel ragionamento, e il gioco concludeva «non risponde».
func _perche_vuota(risposta: Dictionary, uso: Dictionary) -> String:
	var out := int(uso.get("completion_tokens", 0))
	var fine := _motivo_fine(risposta)
	if _ha_ragionato(risposta):
		return "risposta vuota: il modello ha speso a ragionare %s concesso (è un modello a ragionamento obbligatorio). Alza il tetto di token." % (
			"l'unico token" if out == 1 else "tutti i %d token" % out)
	if fine == "length" and out > 0:
		return "risposta vuota: troncata dal tetto di token dopo %d token, prima di scrivere" % out
	return "nessun contenuto nella risposta del provider"

## Il modello ha pensato senza parlare? OpenRouter mette il pensiero in `reasoning`, accanto a
## un `content` nullo. Non lo si usa MAI come risposta — il ragionamento non è la battuta di
## un dio — ma sapere che c'è cambia la diagnosi.
func _ha_ragionato(risposta: Dictionary) -> bool:
	var choices: Variant = risposta.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or Array(choices).is_empty():
		return false
	var primo: Variant = choices[0]
	if typeof(primo) != TYPE_DICTIONARY:
		return false
	var m: Variant = (primo as Dictionary).get("message", {})
	return typeof(m) == TYPE_DICTIONARY and String((m as Dictionary).get("reasoning", "")) != ""

## CHI HA SERVITO LA RICHIESTA A MONTE, quando il provider lo dichiara.
##
## OpenRouter e' un intermediario: dietro un solo nome di modello ci sono piu' fornitori di
## calcolo, e ne sceglie uno per chiamata. Due chiamate identiche possono differire di un
## ordine di grandezza in latenza solo per questo, e senza questa riga la differenza resta
## inspiegabile. Gli altri provider il campo non ce l'hanno: si ritorna "" e non si stampa
## nulla, invece di inventare un valore.
func _servito_da(risposta: Dictionary) -> String:
	var pezzi: Array[String] = []
	var p := String(risposta.get("provider", ""))
	if p != "":
		pezzi.append(p)
	var id := String(risposta.get("id", ""))
	if id != "":
		pezzi.append("id=%s" % id)   # serve a chiedere conto al provider di UNA chiamata
	return "  ".join(pezzi)

## Perche' la risposta e' finita: «stop» (il modello ha concluso), «length» (l'ha troncata il
## tetto di token), «content_filter»… Un JSON che arriva a meta' si spiega quasi sempre qui.
func _motivo_fine(risposta: Dictionary) -> String:
	var choices: Variant = risposta.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or Array(choices).is_empty():
		return ""
	var primo: Variant = choices[0]
	return String(primo.get("finish_reason", "")) if typeof(primo) == TYPE_DICTIONARY else ""

## Estrae il testo del messaggio dalla risposta chat-completions.
func _estrai_contenuto(risposta: Dictionary) -> String:
	var choices = risposta.get("choices", [])
	if typeof(choices) != TYPE_ARRAY or choices.is_empty():
		return ""
	var primo: Dictionary = choices[0]
	var messaggio: Dictionary = primo.get("message", {})
	# `content` ESISTE E VALE null quando il modello non ha scritto nulla — e' cosi' che
	# risponde OpenRouter per i modelli a ragionamento. Il valore predefinito di `get()` non
	# scatta (la chiave c'e'), e da qui usciva un null dentro una funzione tipizzata String.
	var c: Variant = messaggio.get("content")
	return String(c) if typeof(c) == TYPE_STRING else ""

## «HTTP 401» e basta non dice niente a nessuno: non chi ha risposto, non perche'. Il corpo
## della risposta di solito lo dice in chiaro («No API key found in request»), e finora lo
## buttavamo via — chat() lo teneva, l'elenco dei modelli no. E se si sta passando dal
## Gateway, il consiglio giusto e' l'OPPOSTO di quello solito: la chiave non va messa nel
## gioco, ce l'ha lui, e va nel SUO ambiente.
func _perche(stato: int, corpo: PackedByteArray) -> String:
	var testo := corpo.get_string_from_utf8().strip_edges().replace("\n", " ")
	var fine := " — %s" % testo.substr(0, 200) if testo != "" else ""
	if stato in [401, 403]:
		var dove := "il Gateway (che le chiavi le tiene lui: mettila nel suo ambiente, non in Settings)" \
			if base_url.contains("localhost:8800") or base_url.contains("127.0.0.1:8800") \
			else "il provider"
		return "HTTP %d: chiave API rifiutata o assente. La chiede %s%s" % [stato, dove, fine]
	return "HTTP %d%s" % [stato, fine]

func _errore(msg: String) -> Dictionary:
	return {"ok": false, "content": "", "error": msg, "grezzo": {}}

## Come _errore ma lo rende visibile (percorso di chat()). `n` e' il numero della chiamata
## che sta fallendo: si passa invece di leggerlo da un campo, cosi' l'errore finisce sempre
## sotto la richiesta giusta anche quando ce n'e' piu' d'una in volo.
func _fallita(n: int, msg: String) -> Dictionary:
	if tracciato != null:
		tracciato.errore(n, msg)
	else:
		_log("    ⇣ [lb]ERRORE] %s" % Bbcode.neutro(msg))
	return _errore(msg)

func _log(riga: String) -> void:
	if logger.is_valid():
		logger.call(riga)

func _tronca(s: String, n: int) -> String:
	var t := s.replace("\n", " ")
	return t if t.length() <= n else t.substr(0, n) + " …"

func _ultimo_utente(messaggi: Array) -> String:
	var out := ""
	for m in messaggi:
		if typeof(m) == TYPE_DICTIONARY and m.get("role", "") == "user":
			out = String(m.get("content", ""))
	return out

## Elenca i modelli disponibili sul provider (formato OpenAI /v1/models, supportato da
## Ollama). Ritorna {ok, modelli: Array[String], errore}. Serve alla verifica pre-partita.
##
## Passando dal Gateway il percorso porta «?provider=…», per dire di CHI vogliamo l'elenco.
## Un gateway avviato prima di quella modifica confronta il percorso intero e non lo
## riconosce: risponde 404 «non trovato», e l'utente si vede accusare l'indirizzo. Avevo
## scritto che sarebbe stato retrocompatibile: non lo era. Qui si riprova una volta senza la
## query — che e' esattamente il comportamento di prima, cioe' il provider predefinito.
func elenca_modelli() -> Dictionary:
	var r := await _elenca(models_path)
	if not bool(r["ok"]) and String(r["errore"]).begins_with("HTTP 404") and models_path.contains("?"):
		_log("    ↻ 404 con la query: gateway non aggiornato? riprovo senza")
		return await _elenca(models_path.get_slice("?", 0))
	return r

## UNA GET, TRACCIATA, in un posto solo.
##
## L'elenco dei modelli, l'elenco dettagliato, lo /stato del Gateway e il ping erano quattro
## copie della stessa danza: apri, chiedi, aspetta, chiudi, controlla due codici. Quattro copie
## vogliono dire quattro punti in cui aggiungere il tracciato — e infatti nessuno dei quattro
## ce l'aveva, cosi' meta' del traffico del gioco (tutto quello all'avvio e in Impostazioni)
## restava fuori dal log. La domanda «quali chiamate HTTP fa questo gioco?» non aveva risposta.
##
## Ritorna {ok, stato, corpo: String, errore}. Chi chiama interpreta il corpo come sa.
func _chiedi(percorso: String, etichetta: String) -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "stato": 0, "corpo": "", "errore": "client non nell'albero della scena"}
	var url := base_url.trim_suffix("/") + percorso
	var teste := intestazioni()
	var n := 0
	if tracciato != null:
		n = tracciato.richiesta(etichetta, {"modello": model, "metodo": "GET"})
		tracciato.http_richiesta(n, "GET", url, teste, "")
	var h := _apri()
	var t0 := Time.get_ticks_msec()
	var err := h.request(url, teste, HTTPClient.METHOD_GET)
	if err != OK:
		_chiudi(h)
		return _chiedi_fallita(n, "connessione fallita: %s" % error_string(err))
	var r: Array = await h.request_completed
	_chiudi(h)
	var ms := Time.get_ticks_msec() - t0
	var corpo := (r[3] as PackedByteArray).get_string_from_utf8()
	if tracciato != null:
		tracciato.http_risposta(n, int(r[1]), r[2], corpo, ms)
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS:
		return _chiedi_fallita(n, "server non raggiungibile (result=%d)" % int(r[0]))
	if int(r[1]) < 200 or int(r[1]) >= 300:
		return _chiedi_fallita(n, _perche(int(r[1]), r[3]))
	if tracciato != null:
		tracciato.risposta(n, {"stato": int(r[1]), "ms": ms, "agente": etichetta})
	return {"ok": true, "stato": int(r[1]), "corpo": corpo, "errore": ""}

func _chiedi_fallita(n: int, msg: String) -> Dictionary:
	if tracciato != null:
		tracciato.errore(n, msg)
	return {"ok": false, "stato": 0, "corpo": "", "errore": msg}

func _elenca(percorso: String) -> Dictionary:
	var r := await _chiedi(percorso, "elenco modelli")
	if not bool(r["ok"]):
		return {"ok": false, "modelli": [], "errore": r["errore"]}
	var parsed = JSON.parse_string(String(r["corpo"]))
	var modelli: Array = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for m in parsed.get("data", []):
			if typeof(m) == TYPE_DICTIONARY and m.has("id"):
				modelli.append(String(m["id"]))
	return {"ok": true, "modelli": modelli, "errore": ""}

## I MODELLI CON LA LORO TAGLIA, dove il provider sa dirla.
##
## `elenca_modelli()` usa l'endpoint in formato OpenAI, che da' i soli nomi. Ollama ne ha
## anche uno suo — `/api/tags` — che aggiunge la dimensione sul disco, i parametri e la
## quantizzazione: e' cio' che serve per dire, accanto a ogni modello, se questa macchina ce
## la fa a farlo girare. Il percorso lo dichiara il profilo (`tags_path`); chi non lo
## dichiara non ha nulla di simile, e qui si risponde «non lo so» invece di indovinare.
## Ritorna {ok, modelli: [{nome, byte, parametri, quantizzazione}], errore}.
func elenca_dettagli() -> Dictionary:
	if tags_path == "":
		return {"ok": false, "modelli": [], "errore": "nessun elenco dettagliato per questo provider"}
	var r := await _chiedi(tags_path, "elenco dettagliato")
	if not bool(r["ok"]):
		return {"ok": false, "modelli": [], "errore": r["errore"]}
	var parsed = JSON.parse_string(String(r["corpo"]))
	var out: Array = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for m in parsed.get("models", []):
			if typeof(m) != TYPE_DICTIONARY:
				continue
			var det: Dictionary = m.get("details", {})
			out.append({
				"nome": String(m.get("name", "")),
				"byte": int(m.get("size", 0)),
				"parametri": String(det.get("parameter_size", "")),
				"quantizzazione": String(det.get("quantization_level", "")),
			})
	return {"ok": true, "modelli": out, "errore": ""}

## Una GET qualunque su questo indirizzo, con la risposta gia' interpretata.
## Serve a chiedere al Gateway il suo /stato — che non e' un endpoint da provider.
func get_json(percorso: String) -> Dictionary:
	var r := await _chiedi(percorso, "GET %s" % percorso)
	if not bool(r["ok"]):
		return {"ok": false, "dati": {}, "errore": r["errore"]}
	var d: Variant = JSON.parse_string(String(r["corpo"]))
	if typeof(d) != TYPE_DICTIONARY:
		return {"ok": false, "dati": {}, "errore": "risposta non-JSON"}
	return {"ok": true, "dati": d, "errore": ""}

## Ping leggero: verifica che il provider risponda e che il modello esista.
func disponibile() -> bool:
	var r := await _chiedi(models_path, "ping")
	return bool(r["ok"]) and int(r["stato"]) == 200
