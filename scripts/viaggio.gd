class_name Viaggio
extends RefCounted

## IL VIAGGIO: dove si trova Ulisse, quando la tappa si chiude, cosa quella tappa consente.
##
## Estratto da GameManager, che era tornato oltre le mille righe. La regola delle tappe
## stava sparsa in tredici metodi in mezzo alla macchina del turno, e ogni volta che una
## tappa acquistava una proprieta' nuova (`non_ancora`, `emette_su_tag`,
## `trattiene_dopo_turni`) il file cresceva di un altro pezzo che col turno non c'entrava.
##
## Qui dentro NON si chiama mai l'LLM e non si scrive mai in chat: sono decisioni, e le
## decisioni si testano senza rete. La narrazione della traversata la chiede il GameManager,
## che e' l'orchestratore.
##
## L'ordine delle tappe e' quello del poema, FISSO (design sez. 7): non e' un contenitore,
## e' la causalita' della storia.

var episodi: Episodi = null
var _stato: StatoPartita = null

## Quante volte una tappa che trattiene avverte prima di tenerti per sempre.
var avvisi_prigionia: int = Bilanciamento.intero("prigionia/avvisi", 3)

func _init(gli_episodi: Episodi, stato: StatoPartita) -> void:
	episodi = gli_episodi
	_stato = stato

# --- Dove siamo ---

func corrente() -> String:
	var ep: Variant = _stato.ulisse.get("episodio_corrente", null)
	return String(ep) if ep != null else ""

func _ep() -> Episodio:
	return episodi.get_episodio(corrente()) if episodi else null

func nome_corrente() -> String:
	var e := _ep()
	return e.nome if e else ""

## Intro della tappa corrente (per aprire la scena).
func intro_corrente() -> String:
	var e := _ep()
	return e.intro if e else ""

## Ancora di scena (luogo + chi e' presente + vincoli): serve a Omero e al Suggeritore per
## restare coerenti e non inventare luoghi o personaggi assenti.
func scena_corrente() -> String:
	var e := _ep()
	return e.scena if e else ""

## A che punto e' il ritorno: inizio / mezzo / vicino (per l'orientamento discreto).
func progresso() -> String:
	var ord: Array = episodi.ordine()
	var i := ord.find(corrente())
	if i < 0 or ord.size() <= 1:
		return "inizio"
	var f := float(i) / float(ord.size() - 1)
	if f < 0.34:
		return "inizio"
	elif f < 0.72:
		return "mezzo"
	return "vicino"

# --- Entrare e uscire da una tappa ---

## Entra in una tappa: la rende corrente, azzera i turni-in-tappa e accende i suoi dei
## locali. Ritorna l'intro (il chiamante decide cosa farne).
func entra(id: String) -> String:
	_stato.viaggio["corrente"] = id
	_stato.viaggio["turni_in_episodio"] = 0
	_stato.ulisse["episodio_corrente"] = id
	accendi_locali(id)
	var e := episodi.get_episodio(id)
	return e.intro if e else ""

## Mette in ascolto i dei locali di una tappa. Separato da entra() perche' anche RIPRENDERE
## una partita salvata deve riaccenderli — ma senza "entrare", che azzererebbe i turni gia'
## spesi li' (e a Ogigia si potrebbe restare per sempre salvando e ricaricando).
func accendi_locali(id: String) -> void:
	for dio in PantheonManager.pantheon.locali_di_episodio(id):
		dio.attivo = true
		if _stato.registro_divino.has(dio.id):
			_stato.registro_divino[dio.id]["risvegliato"] = true

## AVANZAMENTO. Ritorna {avanzato, esito, episodio, intro, da, a, chiude}.
## Si avanza sull'azione di progresso (avanza_su_tag) o al tetto di turni; entrare a Itaca
## e' vittoria. `chiude` e' la tappa appena conclusa ("" se non si e' avanzato): il
## GameManager la usa per far cadere chi deve cadere. `da`/`a` servono alla traversata.
##
## Niente `await` qui dentro: la traversata la fa narrare il chiamante.
func avanza(envelope: Dictionary) -> Dictionary:
	var v: Dictionary = _stato.viaggio
	v["turni_in_episodio"] = int(v.get("turni_in_episodio", 0)) + 1
	var e := episodi.get_episodio(String(v.get("corrente", "")))
	var fermo := {"avanzato": false, "esito": "continua", "episodio": corrente(),
		"intro": "", "da": "", "a": "", "chiude": ""}
	if e == null:
		return fermo

	var tag: Array = envelope.get("tag", [])
	var per_tag: bool = e.avanza_su_tag != null and tag.has(String(e.avanza_su_tag))
	var per_cap: bool = e.turni_massimi > 0 and int(v["turni_in_episodio"]) >= e.turni_massimi
	if not (per_tag or per_cap):
		return fermo
	fermo["causa"] = ""
	var causa := _causa(String(e.avanza_su_tag) if per_tag else "", per_cap)

	var chiusa := String(v["corrente"])
	var da_nome := e.nome
	v["completati"].append(chiusa)
	var prossimo := episodi.successivo(chiusa)
	if prossimo == "" or prossimo == "itaca":
		return {"avanzato": true, "esito": "itaca", "episodio": "itaca", "causa": causa,
			"intro": intro_corrente(), "da": da_nome, "a": "Itaca", "chiude": chiusa}
	var intro := entra(prossimo)
	return {"avanzato": true, "esito": "continua", "episodio": prossimo, "causa": causa,
		"intro": intro, "da": da_nome, "a": nome_corrente(), "chiude": chiusa}

## PERCHE' SI CAMBIA SCENA. Tre cause sole, e nessun cambio senza una di queste (R-09):
##
##   scelta   — se n'e' andato lui
##   cacciato — l'hanno cacciato
##   prodigio — e' successo qualcosa di sovrannaturale
##
## Nasce da una partita vera: «non posso trovarmi a combattere coi Ciconi e poi al turno dopo
## trovarmi dai Lotofagi». E infatti era cosi': Ciconi e Lotofagi si erano chiusi tutti e due
## per TETTO DI TURNI, cioe' per un contatore scaduto — un cambio di scena senza niente da
## raccontare. Omero riceveva solo «da» e «a», quindi non poteva nemmeno accorgersene: gli
## restava la prosa del mare che si allarga, uguale per una fuga e per un commiato.
##
## `fuga` e' un buon segnale di congedo — scappare È andarsene, sotto la spinta di qualcuno —
## e vale `cacciato`. Ogni altro tag d'uscita e' una partenza voluta.
##
## Il ramo `per_cap` qui è provvisorio: `prodigio` è la causa meno falsa che si possa dare a
## un contatore, ma resta un cambio che il giocatore non ha visto arrivare. Lo sostituirà la
## pressione narrativa (R-10), che al posto del tetto fa mormorare la ciurma, irrobustisce
## gli avversari e infine sospinge Ulisse altrove — con un evento che si legge, turno per
## turno, prima che la scena cambi.
const CAUSE := ["scelta", "cacciato", "prodigio"]

static func _causa(tag_uscita: String, per_tetto: bool) -> String:
	if tag_uscita == "fuga":
		return "cacciato"
	if tag_uscita != "":
		return "scelta"
	return "prodigio" if per_tetto else "scelta"

# --- Cosa consente la tappa ---

## Eventi di mondo del turno: quelli della tappa corrente + quelli passati dall'esterno.
func eventi_del_turno(eventi: Array) -> Array:
	var out: Array = eventi.duplicate()
	var e := _ep()
	if e:
		for ev in e.eventi_attivi:
			if not out.has(ev):
				out.append(ev)
	return out

## Quel che ACCADE resta accaduto. Una tappa puo' dichiarare che un certo tag dell'azione
## fa succedere un evento (nell'antro, il vanto di Ulisse chiama la maledizione di
## Polifemo): da li' in poi chi dormeva in attesa di quell'evento e' sveglio per sempre.
func registra_eventi_accaduti(envelope: Dictionary, eventi_turno: Array) -> void:
	var tag: Array = envelope.get("tag", [])
	var e := _ep()
	if e:
		for t in tag:
			var ev := String(e.emette_su_tag.get(String(t), ""))
			if ev != "" and not _stato.eventi_accaduti.has(ev):
				_stato.eventi_accaduti.append(ev)
	for ev in eventi_turno:
		if not _stato.eventi_accaduti.has(String(ev)):
			_stato.eventi_accaduti.append(String(ev))

## OGIGIA TI TIENE SOLO SE GLIELO LASCI FARE.
## Ritorna "" (niente), "prigionia" (un avviso) o "prigionia_eterna" (fine).
##
## L'isola aveva `turni_massimi` come ogni altra tappa, quindi dopo otto turni la nave
## ripartiva da sola. Ma «restare per sempre» e' *il* pericolo di Ogigia, e con
## l'avanzamento automatico non esisteva il modo di restare: la sconfitta
## `prigionia_eterna`, dichiarata dal design, non poteva accadere in nessuna partita.
##
## Salpare scioglie tutto, sempre: dev'essere una scelta, non una trappola.
func trattiene(envelope: Dictionary, in_mondo: bool) -> String:
	if not in_mondo:
		return ""   # chi paga gia' un'ammonizione non ne prende due nello stesso turno
	var e := _ep()
	if e == null or e.trattiene_dopo_turni <= 0:
		return ""
	var tag: Array = envelope.get("tag", [])
	if e.avanza_su_tag != null and tag.has(String(e.avanza_su_tag)):
		_stato.ammonizioni["prigionia"] = 0   # chi riparte non e' prigioniero
		return ""
	if int(_stato.viaggio.get("turni_in_episodio", 0)) < e.trattiene_dopo_turni:
		return ""   # i turni di grazia: guardare il mare non e' ancora una colpa
	var n := int(_stato.ammonizioni.get("prigionia", 0)) + 1
	_stato.ammonizioni["prigionia"] = n
	return "prigionia_eterna" if n >= avvisi_prigionia else "prigionia"

# --- Gli appigli della tappa ---

## Parole che NON possono comparire in uno spunto finche', qui, la cosa non e' accaduta.
func vietate() -> Array:
	var e := _ep()
	return e.non_ancora if e else []

## Gli appigli quando quelli generati non reggono: SOLO quelli della tappa, che sanno dove
## ti trovi. I generici sono stati tolti — tre frasi buone per ogni occasione non erano
## buone per nessuna: «piega ai remi e prosegui la rotta» compariva anche mentre Ulisse era
## chiuso nell'antro del Ciclope. Se una tappa non ne dichiara, non si inventa niente.
func spunti_di_riserva() -> Array:
	var e := _ep()
	return e.spunti_di_riserva if e else []

## GLI SPUNTI SONO UNA PROMESSA: cio' che il gioco offre, il gioco lo accetta e lo sa
## rendere. Sul campo la promessa si e' rotta in tre modi, tutti presidiati qui:
##  - fra le frasi e' comparso «---SPUNTI», cioe' l'impalcatura del prompt;
##  - sono arrivati anacronismi, che poi il gioco stesso avrebbe respinto;
##  - all'isola di Eolo veniva proposto «apri l'otre», e Eolo l'otre non l'ha ancora dato.
## Il prompt puo' chiedere tutto questo, ma resta una preghiera: questa e' la garanzia.
func filtra_spunti(spunti: Array) -> Array:
	var proibite := vietate()
	var out: Array = []
	for s in spunti:
		var t := String(s.get("testo", "")).strip_edges() if typeof(s) == TYPE_DICTIONARY else String(s).strip_edges()
		if t == "" or e_impalcatura(t):
			continue
		if Validazione.e_anacronistico(t):
			continue
		var basso := t.to_lower()
		var proibito := false
		for v in proibite:
			if basso.contains(String(v).to_lower()):
				proibito = true
				break
		if not proibito:
			out.append(s if typeof(s) == TYPE_DICTIONARY else {"testo": t, "rischio": false})
	return out

## Una riga di ponteggio scappata dal prompt (---SPUNTI, ORIENTAMENTO, soli trattini).
static func e_impalcatura(t: String) -> bool:
	var re := RegEx.new()
	re.compile("(?i)^[ \\t-]*(spunti|orientamento)[ \\t:-]*$")
	return re.search(t) != null or t.strip_edges().lstrip("-").strip_edges() == ""
