class_name ValidatoreNarrativo
extends RefCounted

## Guardrail deterministico per la prosa di una traversata.
##
## L'API e' volutamente pura: `valida(testo, quadro)` non legge autoload, non modifica lo
## stato e non conosce il Narratore. Il chiamante puo' quindi comporre questo esito con il
## controllo dei nomi divini gia' posseduto da `Narratore`, senza duplicarlo qui.
##
## Quadro minimo:
##   {"origine": "Troia", "destinazione": "Ismaro"}
## Quadro completo (tutti i campi ulteriori sono opzionali):
##   {
##     "rotta": [{"id":"troia", "nome":"La partenza da Troia", "alias":["Troia"]}, ...],
##     "momento": "a mezzogiorno",
##     "fatti_vietati": [
##       {"id":"nave_perduta", "marcatori":["una nave affondo'", "perdettero una nave"]}
##     ]
##   }
##
## `fatti_vietati` non tenta comprensione semantica: controlla soltanto i marcatori
## dichiarati dal quadro. E' una scelta di sicurezza: una frase non riconosciuta passa e
## potra' richiedere un altro validatore; una somiglianza lessicale non diventa da sola un
## fatto permanente. Accenti, maiuscole e apostrofi sono normalizzati e i confronti usano
## confini di parola, non semplici sottostringhe.

const CODICE_TESTO_VUOTO := "testo_vuoto"
const CODICE_TAPPA_ESTRANEA := "tappa_estranea"
const CODICE_USCITA_DESTINAZIONE := "uscita_destinazione"
const CODICE_SECONDO_APPRODO := "secondo_approdo"
const CODICE_MOVIMENTO_IMPREVISTO := "movimento_imprevisto"
const CODICE_TEMPO := "tempo_contraddittorio"
const CODICE_SALTO_TEMPORALE := "salto_temporale"
const CODICE_FATTO_VIETATO := "fatto_vietato"

## Parole descrittive dei titoli che non identificano una tappa da sole. In particolare
## "sole" non puo' significare automaticamente Trinacia: al mezzogiorno il sole e' normale.
const PAROLE_GENERICHE_TAPPA := [
	"la", "il", "lo", "l", "i", "gli", "le", "un", "una", "di", "da", "del", "della",
	"dei", "degli", "delle", "al", "alla", "alle", "terra", "isola", "porto", "antro",
	"palazzo", "soglia", "canto", "stretto", "scoglio", "mare", "tempesta", "partenza",
	"sole",
]

## Forme ristrette: sono contraddizioni temporali esplicite, non atmosfera poetica.
const TEMPI_INCOMPATIBILI := {
	"alba": [
		"a mezzogiorno", "sole allo zenit", "sole alto nel cielo", "al tramonto",
		"sole basso", "sole calante", "notte fonda", "era notte",
	],
	"mezzogiorno": [
		"all alba", "sul far dell alba", "spuntava l alba", "prima luce", "al tramonto",
		"sole basso", "sole calante", "il sole declinava", "calar del sole", "notte fonda",
		"era notte", "scendeva la notte",
	],
	"tramonto": [
		"all alba", "sul far dell alba", "spuntava l alba", "prima luce", "a mezzogiorno",
		"sole allo zenit", "sole alto nel cielo", "notte fonda",
	],
	"notte": [
		"all alba", "sul far dell alba", "spuntava l alba", "prima luce", "a mezzogiorno",
		"sole allo zenit", "sole alto nel cielo", "in pieno giorno",
	],
}

const RE_SALTI_TEMPORALI := [
	"(?<![a-z0-9_])(?:il|al) (?:secondo|terzo|quarto|quinto|sesto|settimo|ottavo|nono|decimo) giorno(?![a-z0-9_])",
	"(?<![a-z0-9_])(?:due|tre|quattro|cinque|sei|sette|otto|nove|dieci|[0-9]+) (?:giorni|notti|albe) dopo(?![a-z0-9_])",
	"(?<![a-z0-9_])da (?:due|tre|quattro|cinque|sei|sette|otto|nove|dieci|[0-9]+) (?:giorni|notti|albe)(?![a-z0-9_])",
	"(?<![a-z0-9_])per (?:due|tre|quattro|cinque|sei|sette|otto|nove|dieci|[0-9]+) (?:giorni|notti|albe)(?![a-z0-9_])",
]

const FORME_APPRODO_IGNOTO := [
	"spiaggia sconosciuta", "riva sconosciuta", "costa sconosciuta", "isola sconosciuta",
	"spiaggia senza nome", "riva senza nome", "costa senza nome", "isola senza nome",
	"un altra spiaggia", "un altra riva", "un altra costa", "un altra isola",
	"una seconda spiaggia", "una seconda riva", "un secondo approdo", "nuovo approdo",
	"approdo di nuovo",
]

const RE_VERBO_PARTENZA := "(?<![a-z0-9_])(?:lascia(?:no|re)?|lascio|lasciarono|abbandona(?:no|re)?|abbandono|abbandonarono|riparti(?:rono|re)?|salpa(?:rono|re)?|si allontana(?:rono)?|si allontano)(?![a-z0-9_])"
const RE_APPRODO := "(?<![a-z0-9_])(?:approda(?:rono|re)?|approdo|sbarca(?:rono|re)?|sbarco|tocca(?:rono)? terra|raggiunse(?:ro)? la riva)(?![a-z0-9_])"
const RE_PARTENZA_FERMO := "(?<![a-z0-9_])(?:lascia(?:no|re)?|lascio|lasciarono|abbandona(?:no|re)?|abbandono|abbandonarono|parti(?:rono|re)?|riparti(?:rono|re)?|salpa(?:rono|re)?|salpo|si allontana(?:rono)?|si allontano|prese(?:ro)? il mare|riprese(?:ro)? il mare|sciolse(?:ro)? le vele|leva(?:rono)? l ancora)(?![a-z0-9_])"
const RE_APPRODO_FERMO := "(?<![a-z0-9_])(?:approda(?:rono|re)?|approdo|sbarca(?:rono|re)?|sbarco|tocca(?:rono)? terra|raggiunse(?:ro)? la riva|giunse(?:ro)? (?:a|ad|in|su|presso)|raggiunse(?:ro)? (?:a|ad|in|su|presso)|arriva(?:rono)? (?:a|ad|in|su|presso)|mise(?:ro)? piede a terra)(?![a-z0-9_])"


func valida(testo: String, quadro: Dictionary) -> Dictionary:
	var violazioni: Array = []
	var pulito := testo.strip_edges()
	if pulito == "":
		_aggiungi(violazioni, CODICE_TESTO_VUOTO, "La narrazione e' vuota.", "")
		return {"ok": false, "violazioni": violazioni}

	var t := _normalizza(pulito)
	_valida_tappe(t, quadro, violazioni)
	_valida_movimento(t, quadro, violazioni)
	_valida_tempo(t, quadro, violazioni)
	_valida_fatti(t, quadro, violazioni)
	return {"ok": violazioni.is_empty(), "violazioni": violazioni}


## Unisce esiti omogenei prodotti da guardrail indipendenti. Il controllo dei nomi divini
## puo' aggiungere qui la propria violazione, mantenendo una sola decisione finale.
static func componi(risultati: Array) -> Dictionary:
	var tutte: Array = []
	var tutti_ok := true
	for risultato in risultati:
		if typeof(risultato) != TYPE_DICTIONARY:
			tutti_ok = false
			continue
		tutti_ok = tutti_ok and bool(risultato.get("ok", false))
		for violazione in risultato.get("violazioni", []):
			tutte.append(violazione)
	return {"ok": tutti_ok and tutte.is_empty(), "violazioni": tutte}


## Adattatore minimo per un guardrail booleano esterno (per esempio `nomina_un_dio`).
## Non esegue quel controllo: trasforma soltanto il suo esito nel formato componibile.
static func esito_esterno(ok: bool, codice: String, dettaglio: String = "") -> Dictionary:
	if ok:
		return {"ok": true, "violazioni": []}
	return {"ok": false, "violazioni": [{
		"codice": codice,
		"dettaglio": dettaglio,
		"riferimento": "",
	}]}


func _valida_tappe(testo: String, quadro: Dictionary, violazioni: Array) -> void:
	var origine := String(quadro.get("origine", quadro.get("da", "")))
	var destinazione := String(quadro.get("destinazione", quadro.get("a", "")))
	var consentite := _forme_nome(origine)
	_unisci_uniche(consentite, _forme_nome(destinazione))
	var passaggio_avvenuto := bool(quadro.get("passaggio_avvenuto", true))

	# La rotta e' una sequenza fissa. Ogni voce che non e' origine o destinazione e' una
	# terza tappa, passata o futura: una traversata non deve anticiparla ne' tornarci.
	for voce in quadro.get("rotta", []):
		var forme := _forme_tappa(voce)
		if _interseca(forme, consentite):
			continue
		for forma in forme:
			if _menzione_tappa_illegittima(testo, forma, passaggio_avvenuto):
				_aggiungi(violazioni, CODICE_TAPPA_ESTRANEA,
					"La traversata nomina una tappa diversa da origine e destinazione.", forma)
				break

	# Serve anche a chi non vuole passare l'intero itinerario (o a nomi storici che non
	# coincidono con l'id tecnico dell'episodio).
	for voce in quadro.get("tappe_vietate", []):
		for forma in _forme_tappa(voce):
			if not consentite.has(forma) and _menzione_tappa_illegittima(testo, forma, passaggio_avvenuto):
				_aggiungi(violazioni, CODICE_TAPPA_ESTRANEA,
					"La traversata nomina una tappa esplicitamente esclusa dal quadro.", forma)
				break


func _valida_movimento(testo: String, quadro: Dictionary, violazioni: Array) -> void:
	var origine := String(quadro.get("origine", quadro.get("da", "")))
	var destinazione := String(quadro.get("destinazione", quadro.get("a", "")))
	var forme_origine := _forme_nome(origine)
	var forme_destinazione := _forme_nome(destinazione)
	if not bool(quadro.get("passaggio_avvenuto", true)):
		_valida_turno_fermo(testo, violazioni)
		return
	if forme_destinazione.is_empty():
		return

	# Il luogo PIU VICINO ancora il verbo: lasciare Troia e il passaggio corretto,
	# lasciare Ismaro ne apre invece un secondo. La destinazione vicina non basta,
	# perche origine e meta compaiono normalmente entrambe. Le negazioni non partono.
	var re_partenza := _regex(RE_VERBO_PARTENZA)
	if re_partenza != null:
		for m in re_partenza.search_all(testo):
			if _e_negata(testo, m.get_start()):
				continue
			var distanza_dest := _distanza_forme(testo, forme_destinazione, m.get_start(), 84)
			var distanza_orig := _distanza_forme(testo, forme_origine, m.get_start(), 84)
			if distanza_dest >= 0 and (distanza_orig < 0 or distanza_dest < distanza_orig):
				_aggiungi(violazioni, CODICE_USCITA_DESTINAZIONE,
					"La traversata prosegue dopo aver raggiunto la destinazione.", m.get_string())
				break

	for forma in FORME_APPRODO_IGNOTO:
		var m_ignoto := _trova_frase(testo, forma)
		if m_ignoto != null and not _e_negata(testo, m_ignoto.get_start()):
			_aggiungi(violazioni, CODICE_SECONDO_APPRODO,
				"Compare una seconda sponda, diversa dalla destinazione fissata.", forma)
			break

	# Un verbo d'approdo e' lecito soltanto se, nello stesso breve passaggio, si ancora
	# alla destinazione. Questo coglie "approdarono a una costa rocciosa" senza dover
	# indovinare il nome della costa.
	var re_approdo := _regex(RE_APPRODO)
	if re_approdo != null:
		for m in re_approdo.search_all(testo):
			if _e_negata(testo, m.get_start()):
				continue
			# Una meta nominata molto piu avanti non sana un primo approdo intermedio.
			if not _una_forma_vicina(testo, forme_destinazione, m.get_start(), m.get_end(), 48):
				_aggiungi(violazioni, CODICE_SECONDO_APPRODO,
					"Un approdo non e' ancorato alla destinazione del quadro.", m.get_string())
				break


func _valida_turno_fermo(testo: String, violazioni: Array) -> void:
	var re_partenza := _regex(RE_PARTENZA_FERMO)
	if re_partenza != null:
		for m in re_partenza.search_all(testo):
			if not _e_negata(testo, m.get_start()):
				_aggiungi(violazioni, CODICE_MOVIMENTO_IMPREVISTO,
					"Il quadro non contiene un passaggio, ma la prosa fa partire Ulisse.", m.get_string())
				break

	for forma in FORME_APPRODO_IGNOTO:
		var m_ignoto := _trova_frase(testo, forma)
		if m_ignoto != null and not _e_negata(testo, m_ignoto.get_start()):
			_aggiungi(violazioni, CODICE_MOVIMENTO_IMPREVISTO,
				"Il quadro non contiene un passaggio, ma la prosa introduce un approdo.", forma)
			break

	var re_approdo := _regex(RE_APPRODO_FERMO)
	if re_approdo != null:
		for m in re_approdo.search_all(testo):
			if _e_negata(testo, m.get_start()) or _e_nome_di_movimento(testo, m):
				continue
			_aggiungi(violazioni, CODICE_MOVIMENTO_IMPREVISTO,
				"Il quadro non contiene un passaggio, ma la prosa fa approdare Ulisse.", m.get_string())
			break


## Nel turno fermo un nome di luogo non e da solo un movimento: memoria, sogno e
## desiderio restano prosa lecita. Diventa violazione soltanto quando una costruzione
## breve afferma arrivo o presenza in quella tappa.
func _menzione_tappa_illegittima(testo: String, forma: String, _passaggio_avvenuto: bool) -> bool:
	# Anche durante una traversata il solo nome non sposta Ulisse: puo sognare Itaca o
	# ricordare Troia. Le stesse costruzioni contestuali valgono in entrambi i rami.
	var luogo := _escape_regex(_normalizza(forma)).replace(" ", " +")
	var arrivo := _regex("(?<![a-z0-9_])(?:giunse(?:ro)?|raggiunse(?:ro)?|arriva(?:rono)?|arrivo|approda(?:rono)?|approdo|sbarca(?:rono)?|sbarco|entro|entrarono|mise(?:ro)? piede)(?: [a-z0-9_]+){0,4} " + luogo + "(?![a-z0-9_])")
	if arrivo != null:
		for m in arrivo.search_all(testo):
			if not _e_negata(testo, m.get_start()) and not _e_nome_di_movimento(testo, m):
				return true
	var presenza := _regex("(?<![a-z0-9_])(?:era|erano|furono|rimase|rimasero|si trovo|si trovava|si trovarono) (?:gia )?(?:a|ad|in|su|presso) " + luogo + "(?![a-z0-9_])")
	if presenza != null:
		for m in presenza.search_all(testo):
			if not _e_negata(testo, m.get_start()):
				return true
	return false


## Approdo, sbarco e arrivo, dopo la normalizzazione degli accenti, possono essere
## verbi oppure nomi. L approdo era quieto non fa muovere nessuno.
func _e_nome_di_movimento(testo: String, m: RegExMatch) -> bool:
	var primo := String(m.get_string()).split(" ", false)[0]
	if not ["approdo", "sbarco", "arrivo"].has(primo):
		return false
	var da := maxi(0, m.get_start() - 18)
	var prefisso := testo.substr(da, m.get_start() - da)
	var re := _regex("(?<![a-z0-9_])(?:l|il|lo|un|questo|quell|primo|secondo) +$")
	return re != null and re.search(prefisso) != null


func _valida_salto_temporale(testo: String, quadro: Dictionary, violazioni: Array) -> void:
	if bool(quadro.get("salto_temporale_ammesso", false)):
		return
	for schema in RE_SALTI_TEMPORALI:
		var re := _regex(String(schema))
		if re == null:
			continue
		for m in re.search_all(testo):
			if _e_negata(testo, m.get_start()):
				continue
			_aggiungi(violazioni, CODICE_SALTO_TEMPORALE,
				"La prosa introduce una durata che il quadro non ha deciso.", m.get_string())
			return


func _valida_tempo(testo: String, quadro: Dictionary, violazioni: Array) -> void:
	_valida_salto_temporale(testo, quadro, violazioni)
	var atteso := _momento_canonico(String(quadro.get("momento", quadro.get("quando", ""))))
	if atteso == "":
		return
	for forma in TEMPI_INCOMPATIBILI.get(atteso, []):
		var m := _trova_frase(testo, String(forma))
		if m != null and not _e_negata(testo, m.get_start()):
			_aggiungi(violazioni, CODICE_TEMPO,
				"Il quadro dice «%s», ma la prosa colloca la scena in un altro momento." % atteso,
				String(forma))
			return


func _valida_fatti(testo: String, quadro: Dictionary, violazioni: Array) -> void:
	for fatto in quadro.get("fatti_vietati", []):
		var id := "fatto_vietato"
		var marcatori: Array = []
		if typeof(fatto) == TYPE_DICTIONARY:
			id = String(fatto.get("id", id))
			for chiave in ["marcatori", "forme", "affermazioni"]:
				for valore in fatto.get(chiave, []):
					marcatori.append(String(valore))
		elif typeof(fatto) == TYPE_STRING:
			marcatori.append(String(fatto))
		for marcatore in marcatori:
			var forma := _normalizza(marcatore)
			var m := _trova_frase(testo, forma)
			if m != null and not _e_negata(testo, m.get_start()):
				_aggiungi(violazioni, CODICE_FATTO_VIETATO,
					"La prosa afferma un fatto permanente vietato dal quadro.", id)
				break


func _forme_tappa(voce: Variant) -> Array:
	var out: Array = []
	if typeof(voce) == TYPE_STRING:
		_aggiungi_forme_nome(out, String(voce))
	elif typeof(voce) == TYPE_DICTIONARY:
		_aggiungi_forma(out, String(voce.get("id", "")))
		_aggiungi_forme_nome(out, String(voce.get("nome", "")))
		for chiave in ["alias", "forme"]:
			for valore in voce.get(chiave, []):
				_aggiungi_forme_nome(out, String(valore))
	return out


func _forme_nome(nome: String) -> Array:
	var out: Array = []
	_aggiungi_forme_nome(out, nome)
	return out


func _aggiungi_forme_nome(out: Array, nome: String) -> void:
	var n := _normalizza(nome)
	_aggiungi_forma(out, n)
	for parola in n.split(" ", false):
		if parola.length() >= 4 and not PAROLE_GENERICHE_TAPPA.has(parola):
			_aggiungi_forma(out, parola)


func _aggiungi_forma(out: Array, forma: String) -> void:
	var f := _normalizza(forma)
	if f != "" and not out.has(f):
		out.append(f)


func _interseca(a: Array, b: Array) -> bool:
	for valore in a:
		if b.has(valore):
			return true
	return false


func _unisci_uniche(dest: Array, sorgente: Array) -> void:
	for valore in sorgente:
		if not dest.has(valore):
			dest.append(valore)


func _una_forma_vicina(testo: String, forme: Array, inizio: int, fine: int, distanza: int) -> bool:
	var da := maxi(0, inizio - distanza)
	var a := mini(testo.length(), fine + distanza)
	var intorno := testo.substr(da, a - da)
	for forma in forme:
		if _contiene_frase(intorno, String(forma)):
			return true
	return false


func _distanza_forme(testo: String, forme: Array, centro: int, limite: int) -> int:
	var migliore := -1
	for forma in forme:
		var re := _regex("(?<![a-z0-9_])" + _escape_regex(String(forma)) + "(?![a-z0-9_])")
		if re == null:
			continue
		for m in re.search_all(testo):
			var distanza := mini(absi(m.get_start() - centro), absi(m.get_end() - centro))
			if distanza <= limite and (migliore < 0 or distanza < migliore):
				migliore = distanza
	return migliore


func _momento_canonico(momento: String) -> String:
	var m := _normalizza(momento)
	if _contiene_frase(m, "mezzogiorno"):
		return "mezzogiorno"
	if _contiene_frase(m, "alba"):
		return "alba"
	if _contiene_frase(m, "tramonto"):
		return "tramonto"
	if _contiene_frase(m, "notte"):
		return "notte"
	return ""


## Evita i falsi positivi piu comuni da negazione esplicita. Non e un parser della
## lingua: non/nessuno/mai possono reggere fino a tre parole; senza deve reggere
## direttamente azione o modale noto. Senza indugio non nega il verbo successivo.
func _e_negata(testo: String, inizio: int) -> bool:
	var da := maxi(0, inizio - 52)
	var prefisso := testo.substr(da, inizio - da)
	var re := _regex("(?:^|[^a-z0-9_])(?:(?:non|nessun[oaie]?|mai)(?:\\s+[a-z0-9_]+){0,3}|senza(?:\\s+(?:mai|poter|voler|dover|alcun[oa]?|nessun[oa]?))?)\\s*$")
	return re != null and re.search(prefisso) != null


func _contiene_frase(testo: String, forma: String) -> bool:
	return _trova_frase(testo, forma) != null


func _trova_frase(testo: String, forma: String) -> RegExMatch:
	var f := _normalizza(forma)
	if f == "":
		return null
	var re := _regex("(?<![a-z0-9_])" + _escape_regex(f).replace("\\ ", "\\s+") + "(?![a-z0-9_])")
	return re.search(testo) if re != null else null


func _regex(schema: String) -> RegEx:
	var re := RegEx.new()
	if re.compile(schema) != OK:
		return null
	return re


func _normalizza(testo: String) -> String:
	var out := testo.to_lower().replace("’", "'").replace("‘", "'")
	var da := ["à", "á", "â", "ä", "è", "é", "ê", "ë", "ì", "í", "î", "ï", "ò", "ó", "ô", "ö", "ù", "ú", "û", "ü"]
	var a :=  ["a", "a", "a", "a", "e", "e", "e", "e", "i", "i", "i", "i", "o", "o", "o", "o", "u", "u", "u", "u"]
	for i in da.size():
		out = out.replace(da[i], a[i])
	# Apostrofi e punteggiatura separano parole. Comprimerli in spazi rende equivalenti
	# "all'alba" e "all alba" senza trasformare frammenti di parola in corrispondenze.
	var separatori := ["'", "\n", "\r", "\t", ",", ".", ";", ":", "!", "?", "«", "»", "(", ")", "—", "–", "-"]
	for s in separatori:
		out = out.replace(s, " ")
	var re_spazi := _regex("\\s+")
	return re_spazi.sub(out, " ", true).strip_edges() if re_spazi != null else out.strip_edges()


func _escape_regex(testo: String) -> String:
	var out := testo
	for c in ["\\", ".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|"]:
		out = out.replace(c, "\\" + c)
	return out


func _aggiungi(violazioni: Array, codice: String, dettaglio: String, riferimento: String) -> void:
	for esistente in violazioni:
		if esistente.get("codice", "") == codice and esistente.get("riferimento", "") == riferimento:
			return
	violazioni.append({
		"codice": codice,
		"dettaglio": dettaglio,
		"riferimento": riferimento,
	})
