extends GutTest

## IL TRACCIATO, E IL DIFETTO CHE HA RESO INUTILE LA COSA PER CUI ERA STATO SCRITTO.
##
## Il tracciato e' nato per rispondere a «dove si perde tempo?». Nella prima versione l'ora
## veniva composta cosi':
##
##     Time.get_time_dict_from_system()   → ore, minuti, secondi
##     Time.get_ticks_msec() % 1000       → millisecondi
##
## I millisecondi erano quelli di ACCENSIONE DEL GIOCO: con l'orologio non c'entrano niente.
## La stringa aveva la forma giusta e il contenuto casuale, e nel log dell'utente si vedeva
## l'ora andare all'INDIETRO — «12:26:15.484» seguito da «12:26:15.061». Il campo esisteva
## per misurare e rispondeva con rumore.
##
## Nessun test poteva accorgersene perche' nessun test guardava DUE righe insieme: e' una
## proprieta' della successione, non della singola riga. Da qui il primo test di questo file.
##
## Gli altri presidiano le tre cose che il tracciato non puo' sbagliare:
##  - non perdere una chiave API, nemmeno in --tracellm che stampa tutte le intestazioni;
##  - non scrivere il dettaglio HTTP quando non e' stato chiesto;
##  - far tornare il consuntivo del turno, che e' la riga che si legge per prima.

var _t: Tracciato
var _righe: Array[String]

func before_each():
	_t = Tracciato.new()
	_righe = []
	# Nessun file: si intercettano le righe formattate. Cosi' il test non tocca il disco e
	# non puo' consumare i log veri di chi gioca — lo stesso difetto trovato sulle preferenze.
	_t.su_riga = func(r: String) -> void: _righe.append(r)

## I MILLISECONDI DEVONO APPARTENERE AL LORO SECONDO. E' il test che mancava, e la prima
## versione che ne ho scritto NON COGLIEVA IL DIFETTO — vale la pena dire perche'.
##
## Provavo cosi': scrivo duecento righe di fila e pretendo che l'ora non decresca mai.
## Duecento righe si scrivono in due millisecondi: `ticks_msec % 1000` avanza di due, resta
## monotono, e il test passa col difetto dentro. Guardavo un intervallo in cui il difetto
## non puo' manifestarsi. Un test verde che non protegge niente e' peggio di nessun test.
##
## Il difetto vive sul CONFINE DEL SECONDO: quando l'orologio passa da :15 a :16, i
## millisecondi devono aver appena traboccato — grandi prima, piccoli dopo. Con la versione
## rotta i due contatori scattano in momenti scorrelati, e il trabocco cade dove capita.
##
## Qui si attende quel confine e lo si guarda. Costa fino a un secondo di test: e' il prezzo
## per osservare l'unico istante in cui la proprieta' si vede.
func test_i_millisecondi_appartengono_al_loro_secondo():
	var prima_sec := ""
	var prima_ms := -1
	var visto := false
	var fine := Time.get_ticks_msec() + 2000   # tetto: mai un test che puo' non finire
	while Time.get_ticks_msec() < fine:
		_righe = []
		_t.nota("·")
		var ora: String = _righe[0].substr(0, 12)      # "HH:MM:SS.mmm"
		var sec := ora.substr(0, 8)
		var ms := int(ora.substr(9, 3))
		if prima_sec != "" and sec != prima_sec:
			# Il secondo e' appena cambiato: i millisecondi devono essere ricominciati.
			assert_gt(prima_ms, 900,
				"prima del cambio di secondo i millisecondi erano %d, non a fine corsa" % prima_ms)
			assert_lt(ms, 100,
				"dopo il cambio di secondo i millisecondi sono %d, non ricominciati" % ms)
			visto = true
			break
		prima_sec = sec
		prima_ms = ms
	assert_true(visto, "non si e' mai attraversato un cambio di secondo: test inconcludente")

# --- il segreto ---

## UNA CHIAVE NON ESCE MAI, nemmeno col dettaglio HTTP acceso. E' la modalita' che rende il
## log utile ed e' anche quella che lo renderebbe pericoloso: questo file si allega a una
## segnalazione. Si prova con la chiave DENTRO l'intestazione piu' comune e con le varianti
## di scrittura che usano i vari provider.
func test_la_chiave_non_finisce_mai_nel_log():
	_t.dettaglio = true
	var segreto := "sk-or-v1-0123456789abcdef0123456789abcdef"
	_t.http_richiesta(1, "POST", "https://esempio/v1/chat", PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % segreto,
		"x-api-key: %s" % segreto,
		"X-Api-Key: %s" % segreto,          # maiuscole diverse: lo confronto e' normalizzato
		"x-goog-api-key: %s" % segreto,
	]), "{}")
	var tutto := "\n".join(_righe)
	assert_false(tutto.contains(segreto), "la chiave INTERA e' finita nel log")
	assert_false(tutto.contains("sk-or-v1-0123"), "un pezzo utile della chiave e' nel log")
	# …ma qualcosa deve restare, o non si potrebbe rispondere a «e' quella giusta?».
	assert_true(tutto.contains("cdef"), "non resta la coda per riconoscere la chiave")
	assert_true(tutto.contains("oscurata"), "non si dice che il valore e' stato oscurato")
	# Le intestazioni innocue passano intere: oscurarle sarebbe perdere informazione.
	assert_true(tutto.contains("Content-Type: application/json"))

# --- i due livelli ---

## Senza --tracellm il dettaglio HTTP NON si scrive. Un log che stampa i corpi quando non
## gli e' stato chiesto e' illeggibile, e con i corpi si porta dietro le intestazioni.
func test_il_dettaglio_http_tace_se_non_e_chiesto():
	_t.dettaglio = false
	_t.http_richiesta(1, "POST", "https://esempio/v1/chat", PackedStringArray(["A: b"]), "{\"x\":1}")
	_t.http_risposta(1, 200, PackedStringArray(["C: d"]), "{\"y\":2}", 10)
	assert_eq(_righe.size(), 0, "ha scritto il dettaglio HTTP senza --tracellm")

func test_col_dettaglio_si_vede_verbo_indirizzo_e_corpo():
	_t.dettaglio = true
	_t.http_richiesta(7, "POST", "https://esempio/v1/chat", PackedStringArray([]), "{\"model\":\"x\"}")
	var tutto := "\n".join(_righe)
	assert_true(tutto.contains("POST https://esempio/v1/chat"), "manca verbo o indirizzo")
	assert_true(tutto.contains("{\"model\":\"x\"}"), "manca il corpo")
	assert_true(tutto.contains("#007"), "la riga non e' legata alla sua chiamata")

# --- i campi ricchi di usage ---

## `cached_tokens` e' la sola prova che la cache di prompt funzioni: l'81% del nostro
## ingresso e' prefisso ripetuto identico, e senza questo campo non si sa se lo stiamo
## pagando due volte. Prima si leggevano solo i tre totali e il resto si buttava.
func test_la_risposta_dice_quanto_e_arrivato_dalla_cache():
	_t.risposta(1, {"stato": 200, "ms": 900, "usage": {
		"prompt_tokens": 2000, "completion_tokens": 100, "total_tokens": 2100,
		"prompt_tokens_details": {"cached_tokens": 1600},
	}})
	var r := _righe[0]
	assert_true(r.contains("cache=1600"), "non dice quanti token sono arrivati dalla cache")
	assert_true(r.contains("80%"), "non dice che quota dell'ingresso e' stata risparmiata")

## I token di ragionamento si pagano in secondi e non compaiono nella risposta: sono la
## spiegazione piu' frequente di un modello che «e' lento» senza scrivere molto.
func test_la_risposta_denuncia_i_token_di_ragionamento():
	_t.risposta(1, {"stato": 200, "ms": 21000, "usage": {
		"prompt_tokens": 900, "completion_tokens": 1200, "total_tokens": 2100,
		"completion_tokens_details": {"reasoning_tokens": 1100},
	}})
	assert_true(_righe[0].contains("ragionamento=1100"),
		"non segnala i token pensati e mai mostrati")

## Un `usage` senza i campi annidati non deve rompere niente: la forma cambia da provider a
## provider, e meta' non li manda affatto.
func test_un_usage_povero_non_rompe_nulla():
	_t.risposta(1, {"stato": 200, "ms": 100, "usage": {"prompt_tokens": 10}})
	_t.risposta(2, {"stato": 200, "ms": 100, "usage": {}})
	_t.risposta(3, {"stato": 200, "ms": 100})
	# Nessun campo annidato, nessuna quota: solo cio' che c'e' davvero.
	assert_eq(_righe.size(), 3)
	assert_false(_righe[1].contains("cache="))

# --- il consuntivo ---

## LA RIGA PER CUI IL TRACCIATO ESISTE. Un turno lento non e' informativo; lo e' sapere
## quale agente se l'e' preso. Si simula un turno con tre risposte e si pretende che il
## consuntivo dica il totale, il colpevole e i token.
func test_il_consuntivo_dice_chi_si_e_preso_il_tempo():
	_t.apre_turno(3, "Grido il mio nome al ciclope")
	_t.risposta(1, {"stato": 200, "ms": 1000, "agente": "Interprete",
		"usage": {"prompt_tokens": 100, "completion_tokens": 10}})
	_t.risposta(2, {"stato": 200, "ms": 9000, "agente": "Poseidone",
		"usage": {"prompt_tokens": 200, "completion_tokens": 20}})
	_t.risposta(3, {"stato": 200, "ms": 500, "agente": "Omero",
		"usage": {"prompt_tokens": 300, "completion_tokens": 30}})
	_righe = []
	_t.chiude_turno()
	var tutto := "\n".join(_righe)
	assert_true(tutto.contains("consuntivo turno 3"), "manca l'intestazione del consuntivo")
	assert_true(tutto.contains("3 chiamate"), "non conta le chiamate")
	assert_true(tutto.contains("Poseidone"), "non nomina gli agenti")
	assert_true(tutto.contains("il più lento"), "non indica il colpevole")
	# Il colpevole va NOMINATO sulla sua riga, non su una qualunque: e' l'unica cosa che si
	# legge davvero, e metterla accanto al nome sbagliato sarebbe peggio che non metterla.
	for r in _righe:
		if r.contains("il più lento"):
			assert_true(r.contains("Poseidone"),
				"«il più lento» e' accanto all'agente sbagliato: %s" % r)
	assert_true(tutto.contains("in=600"), "non somma i token in ingresso")
	assert_true(tutto.contains("out=60"), "non somma i token in uscita")

## Le risposte fuori da un turno (avvio, prova del modello, Impostazioni) non devono
## finire nel consuntivo del turno successivo: gonfierebbero un conto che si legge come
## «quanto e' costato questo turno».
func test_fuori_dal_turno_non_si_conta():
	_t.risposta(1, {"stato": 200, "ms": 5000, "agente": "prova del modello"})
	_t.apre_turno(1, "azione")
	_t.risposta(2, {"stato": 200, "ms": 100, "agente": "Interprete"})
	_righe = []
	_t.chiude_turno()
	var tutto := "\n".join(_righe)
	assert_true(tutto.contains("1 chiamate"), "ha contato una chiamata di fuori turno")
	assert_false(tutto.contains("prova del modello"))

## Chiudere un turno mai aperto non deve scrivere niente (ne' esplodere): succede a ogni
## partita caricata e a ogni turno finito in errore prima di cominciare.
func test_chiudere_un_turno_mai_aperto_non_fa_nulla():
	_t.chiude_turno()
	assert_eq(_righe.size(), 0)

# --- il confine del gioco ---

func test_si_vede_cosa_entra_e_cosa_esce():
	_t.entra("azione del giocatore", "Offro una libagione")
	_t.esce("narrazione", "612 caratteri")
	assert_true(_righe[0].contains("ENTRA"))
	assert_true(_righe[0].contains("Offro una libagione"))
	assert_true(_righe[1].contains("ESCE"))
	assert_true(_righe[1].contains("612 caratteri"))

## Il testo del giocatore e quello del modello arrivano con a capo dentro: una riga di log
## che diventa tre righe rompe la lettura cronologica, che e' l'unica cosa che questo
## formato garantisce.
func test_gli_a_capo_non_spezzano_una_riga():
	_t.entra("azione", "prima riga\nseconda riga\n\tterza")
	assert_eq(_righe.size(), 1, "una riga di log e' diventata piu' d'una")
	assert_false(_righe[0].contains("\n"))
