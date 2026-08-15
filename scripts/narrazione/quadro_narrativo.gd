class_name QuadroNarrativo
extends RefCounted

## Il confine fra il motore deterministico e la voce di Omero.
##
## "Autorevole" qui significa una cosa precisa: il quadro descrive lo stato che il
## gioco ha gia' deciso. Non obbliga il motore a ripetere il poema e non decide la
## trama al posto delle regole. In questa fase la policy passata dal chiamante mantiene
## pero' la rotta dell'Odissea fissa e un eventuale spostamento dovuto alla pressione
## ha causa `prodigio`.
##
## L'API usa soltanto Dictionary/Array. Il validatore dell'azione puo' quindi produrre
## `azione` e `conseguenze` senza importare questa classe, e questa classe non importa il
## validatore: il quadro e' un contratto di dati, non un nuovo orchestratore.

const SCHEMA := "quadro_narrativo/1"
const AUTORITA := "stato_partita"
const CAUSE_PASSAGGIO: Array[String] = ["scelta", "cacciato", "prodigio"]

## La policy corrente viene costruita fuori dal quadro: l'ordine resta nei dati degli
## episodi, non viene duplicato o hardcoded qui. `nomi` e' facoltativo e serve solo a
## rendere piu' leggibili diagnostica e strumenti.
static func politica_rotta_fissa(ordine: Array, nomi: Dictionary = {}) -> Dictionary:
	return {
		"rotta_fissa": true,
		"ordine_tappe": _stringhe(ordine),
		"nomi_tappe": nomi.duplicate(true),
		"pressione_fino_al_prodigio": true,
	}

## Costruisce un quadro senza trattenere riferimenti mutabili del chiamante.
##
## Forme minime:
##   stato: {episodio: {id, nome, scena?}, ...stato player-facing}
##   azione: {testo, sintesi, tipo?, tag?}
##   conseguenze: {delta?, eventi?, fatti?, esito?, pressione?: {grado, spinge}}
##   passaggio: {} oppure {avvenuto:true, da:{id,nome}, a:{id,nome}, causa}
##   fatti: due Array[String]. Solo i fatti ammessi possono diventare permanenti.
static func crea(stato_prima: Dictionary, azione: Dictionary, conseguenze: Dictionary,
		stato_dopo: Dictionary, momento: String, fatti_ammessi: Array = [],
		fatti_vietati: Array = [], passaggio: Dictionary = {},
		politica: Dictionary = {}) -> Dictionary:
	var quadro := {
		"schema": SCHEMA,
		"autorita": AUTORITA,
		"stato_prima": stato_prima.duplicate(true),
		"azione": azione.duplicate(true),
		"conseguenze": conseguenze.duplicate(true),
		"stato_dopo": stato_dopo.duplicate(true),
		"passaggio": _passaggio_normalizzato(passaggio),
		"momento": momento.strip_edges(),
		"fatti": {
			"ammessi": _stringhe(fatti_ammessi),
			"vietati": fatti_vietati.duplicate(true),
		},
		"vincoli": {"salto_temporale_ammesso": false},
		"politica": politica.duplicate(true),
	}
	_aggiungi_vincoli_espliciti(quadro)
	return quadro

## Contesto pronto per LLMManager. I campi legacy sono intenzionali: il mock storico
## legge `sintesi`, mentre il Narratore reale privilegia `quadro_narrativo`. Durante la
## fase 5 i due percorsi possono cosi' essere integrati nello stesso momento.
static func come_contesto_omero(quadro: Dictionary) -> Dictionary:
	var azione: Dictionary = quadro.get("azione", {})
	return {
		"quadro_narrativo": quadro.duplicate(true),
		"azione": String(azione.get("testo", "")),
		"sintesi": String(azione.get("sintesi", "qualcosa accade")),
		"momento": String(quadro.get("momento", "")),
	}

## Adattatore verso un guardrail testuale esterno. Restituisce il contratto minimo usato
## da `ValidatoreNarrativo`, ma non ne importa la classe: nessuna dipendenza circolare e
## nessun obbligo per chi produce il quadro di conoscere il validatore della prosa.
static func per_validatore(quadro: Dictionary) -> Dictionary:
	var passaggio: Dictionary = quadro.get("passaggio", {})
	var avvenuto := bool(passaggio.get("avvenuto", false))
	var ep_prima: Dictionary = quadro.get("stato_prima", {}).get("episodio", {})
	var politica: Dictionary = quadro.get("politica", {})
	var nomi: Dictionary = politica.get("nomi_tappe", {})
	var rotta: Array = []
	for id in politica.get("ordine_tappe", []):
		var nome: Variant = nomi.get(String(id), String(id))
		if typeof(nome) == TYPE_DICTIONARY:
			var voce: Dictionary = nome.duplicate(true)
			voce["id"] = String(id)
			rotta.append(voce)
		else:
			rotta.append({"id": String(id), "nome": String(nome)})
	var pressione: Dictionary = _pressione(quadro.get("conseguenze", {}))
	var origine := String(passaggio.get("da", {}).get("nome", "")) if avvenuto else String(ep_prima.get("nome", ""))
	var destinazione := String(passaggio.get("a", {}).get("nome", "")) if avvenuto else origine
	return {
		"passaggio_avvenuto": avvenuto,
		"origine": origine,
		"destinazione": destinazione,
		"causa": String(passaggio.get("causa", "")) if avvenuto else "",
		"rotta": rotta,
		"momento": String(quadro.get("momento", "")),
		"salto_temporale_ammesso": bool(quadro.get("vincoli", {}).get(
			"salto_temporale_ammesso", false)),
		"pressione": pressione.duplicate(true),
		"fatti_vietati": quadro.get("fatti", {}).get("vietati", []).duplicate(true),
	}

## Valida struttura e invarianti correnti. Non consulta singleton, file o validatori
## esterni: e' pura e quindi usabile sia nei test sia dall'integrazione del turno.
static func valida(quadro: Dictionary) -> Dictionary:
	var errori: Array[String] = []
	if String(quadro.get("schema", "")) != SCHEMA:
		errori.append("schema assente o non supportato")
	if String(quadro.get("autorita", "")) != AUTORITA:
		errori.append("l'autorita' deve essere lo stato della partita")

	var prima := _stato(quadro.get("stato_prima", null), "stato_prima", errori)
	var dopo := _stato(quadro.get("stato_dopo", null), "stato_dopo", errori)
	_valida_azione(quadro.get("azione", null), errori)
	_valida_conseguenze(quadro.get("conseguenze", null), errori)
	if String(quadro.get("momento", "")).strip_edges() == "":
		errori.append("momento assente")

	var fatti: Variant = quadro.get("fatti", null)
	if typeof(fatti) != TYPE_DICTIONARY:
		errori.append("fatti deve distinguere ammessi e vietati")
	else:
		_valida_lista_stringhe(fatti.get("ammessi", null), "fatti.ammessi", errori)
		_valida_fatti_vietati(fatti.get("vietati", null), errori)
	var vincoli: Variant = quadro.get("vincoli", null)
	if typeof(vincoli) != TYPE_DICTIONARY:
		errori.append("vincoli narrativi assenti")
	elif bool(vincoli.get("salto_temporale_ammesso", true)):
		errori.append("questa fase non ammette salti temporali inventati")

	var politica: Variant = quadro.get("politica", null)
	if typeof(politica) != TYPE_DICTIONARY:
		errori.append("politica narrativa assente")
		politica = {}
	if not bool(politica.get("rotta_fissa", false)):
		errori.append("questa fase richiede la rotta fissa")
	if not bool(politica.get("pressione_fino_al_prodigio", false)):
		errori.append("questa fase richiede pressione fino al prodigio")
	var ordine: Variant = politica.get("ordine_tappe", [])
	_valida_lista_stringhe(ordine, "politica.ordine_tappe", errori)
	if typeof(ordine) == TYPE_ARRAY and ordine.is_empty():
		errori.append("politica.ordine_tappe non puo' essere vuoto")

	var passaggio: Variant = quadro.get("passaggio", null)
	if typeof(passaggio) != TYPE_DICTIONARY:
		errori.append("passaggio deve essere esplicito")
	else:
		_valida_passaggio(passaggio, prima, dopo, ordine if typeof(ordine) == TYPE_ARRAY else [], errori)
		var pressione: Dictionary = _pressione(quadro.get("conseguenze", {}))
		if bool(pressione.get("spinge", false)):
			if not bool(passaggio.get("avvenuto", false)):
				errori.append("la pressione che spinge deve produrre un passaggio")
			elif String(passaggio.get("causa", "")) != "prodigio":
				errori.append("la pressione puo' spostare Ulisse solo come prodigio")

	return {"ok": errori.is_empty(), "errori": errori}

## Traduce il quadro in istruzioni per Omero. La serializzazione e' unica: nessun
## chiamante deve ricostruire a mano un sottoinsieme diverso dello stato autorevole.
static func per_prompt(quadro: Dictionary) -> String:
	var controllo := valida(quadro)
	if not bool(controllo["ok"]):
		return ""
	var prima: Dictionary = quadro["stato_prima"]
	var dopo: Dictionary = quadro["stato_dopo"]
	var azione: Dictionary = quadro["azione"]
	var conseguenze: Dictionary = quadro["conseguenze"]
	var passaggio: Dictionary = quadro["passaggio"]
	var fatti: Dictionary = quadro["fatti"]
	var righe: Array[String] = [
		"QUADRO NARRATIVO AUTOREVOLE (fonte: stato della partita).",
		"Autorevole NON significa fedelta' forzata al poema: significa che non puoi correggere, completare o oltrepassare cio' che il motore ha deciso.",
		"MOMENTO: %s" % quadro["momento"],
		"SALTO TEMPORALE: vietato. Narra questo stesso momento; non inventare giorni o notti trascorsi (per esempio «il terzo giorno», «due notti dopo»).",
		"STATO PRIMA: %s" % _stato_per_prompt(prima),
		"AZIONE DI ULISSE: parole/gesto «%s»; sintesi «%s»; tipo %s; tag %s." % [
			azione.get("testo", ""), azione.get("sintesi", ""),
			azione.get("tipo", "non specificato"), JSON.stringify(azione.get("tag", []))],
		"CONSEGUENZE DETERMINISTICHE (sono gia' accadute; non aumentarle ne' sostituirle): %s" % JSON.stringify(conseguenze),
		"STATO DOPO: %s" % _stato_per_prompt(dopo),
	]
	if bool(passaggio["avvenuto"]):
		righe.append("PASSAGGIO UNICO: da «%s» [%s] a «%s» [%s], causa «%s». Raccontalo una volta sola e fermati nella tappa di arrivo." % [
			passaggio["da"].get("nome", ""), passaggio["da"].get("id", ""),
			passaggio["a"].get("nome", ""), passaggio["a"].get("id", ""),
			passaggio["causa"]])
	else:
		righe.append("PASSAGGIO: nessuno. Ulisse resta nella stessa tappa: non farlo partire, salpare, approdare o giungere altrove.")
	if String(conseguenze.get("esito", "continua")) != "continua":
		righe.append("ESITO FINALE: %s. Questa stessa voce chiude il racconto: non proporre azioni successive e non aprire una nuova scena." % conseguenze.get("esito", ""))
	righe.append("FATTI AMMESSI: %s" % _elenco(fatti["ammessi"], "nessun fatto permanente oltre a quelli gia' nel quadro"))
	righe.append("FATTI VIETATI: %s" % _elenco_fatti(fatti["vietati"], "qualsiasi fatto permanente non presente nel quadro"))
	righe.append("LIBERTA' DI PROSA: puoi variare ritmo, immagini e dettagli sensoriali momentanei. Non trasformarli in nuovi personaggi, oggetti, perdite, promesse, partenze, approdi o altre conseguenze permanenti.")
	return "\n".join(righe)

## Controllo testuale volutamente stretto: i fatti vietati sono stringhe dichiarate dal
## chiamante. La semantica non viene indovinata con euristiche fragili; se una stringa
## vietata compare davvero, il Narratore puo' ritentare e infine usare il ripiego.
static func violazioni_testuali(quadro: Dictionary, testo: String) -> Array[String]:
	var out: Array[String] = []
	var fatti: Dictionary = quadro.get("fatti", {})
	var basso := _normalizza_per_confronto(testo)
	for fatto in fatti.get("vietati", []):
		var marcatori: Array = [fatto] if typeof(fatto) == TYPE_STRING else fatto.get("marcatori", [])
		for marcatore in marcatori:
			var vietato := _normalizza_per_confronto(String(marcatore))
			if vietato != "" and _contiene_affermazione(basso, vietato):
				out.append("fatto vietato: %s" % _descrivi_fatto(fatto))
				break
	return out

## Ultima difesa dopo due uscite non conformi. Non inventa: usa solo azione,
## conseguenze ammesse e l'eventuale passaggio gia' deciso.
static func ripiego(quadro: Dictionary, includi_passaggio: bool = true) -> String:
	var azione: Dictionary = quadro.get("azione", {})
	var passaggio: Dictionary = quadro.get("passaggio", {})
	var fatti: Dictionary = quadro.get("fatti", {})
	var parti: Array[String] = []
	var sintesi := String(azione.get("sintesi", "")).strip_edges()
	if sintesi != "":
		parti.append(sintesi.trim_suffix(".") + ".")
	for fatto in fatti.get("ammessi", []):
		var f := String(fatto).strip_edges()
		if f != "":
			parti.append(f.trim_suffix(".") + ".")
	if includi_passaggio and bool(passaggio.get("avvenuto", false)):
		parti.append(_passaggio_di_ripiego(passaggio))
	return " ".join(parti).strip_edges()

## Ripiego di ultima istanza quando il quadro vieta esplicitamente un passaggio. Non usa
## la sintesi dell'azione: potrebbe contenere un tentativo o un desiderio di movimento che
## il motore non ha applicato. Dice soltanto la relazione certa fra stato prima e dopo.
static func ripiego_fermo(quadro: Dictionary) -> String:
	return "Il gesto non porto' Ulisse altrove; rimase dov'era e nessun passaggio si compi'."

static func _passaggio_normalizzato(passaggio: Dictionary) -> Dictionary:
	if passaggio.is_empty() or not bool(passaggio.get("avvenuto", true)):
		return {"avvenuto": false, "da": {}, "a": {}, "causa": ""}
	return {
		"avvenuto": true,
		"da": Dictionary(passaggio.get("da", {})).duplicate(true) if typeof(passaggio.get("da", {})) == TYPE_DICTIONARY else {},
		"a": Dictionary(passaggio.get("a", {})).duplicate(true) if typeof(passaggio.get("a", {})) == TYPE_DICTIONARY else {},
		"causa": String(passaggio.get("causa", "")),
	}

static func _aggiungi_vincoli_espliciti(quadro: Dictionary) -> void:
	var vietati: Array = quadro["fatti"]["vietati"]
	_append_unico(vietati, "un secondo passaggio nello stesso turno")
	_append_unico(vietati, "una tappa alternativa a quella decisa dal motore")
	_append_unico(vietati, "un nuovo fatto permanente non presente nel quadro")

static func _valida_azione(valore: Variant, errori: Array[String]) -> void:
	if typeof(valore) != TYPE_DICTIONARY:
		errori.append("azione deve essere un dizionario")
		return
	if String(valore.get("testo", "")).strip_edges() == "":
		errori.append("azione.testo assente")
	if String(valore.get("sintesi", "")).strip_edges() == "":
		errori.append("azione.sintesi assente")
	if valore.has("tag") and typeof(valore["tag"]) != TYPE_ARRAY:
		errori.append("azione.tag deve essere un array")

static func _valida_conseguenze(valore: Variant, errori: Array[String]) -> void:
	if typeof(valore) != TYPE_DICTIONARY:
		errori.append("conseguenze deve essere un dizionario")
		return
	if valore.has("delta") and typeof(valore["delta"]) != TYPE_DICTIONARY:
		errori.append("conseguenze.delta deve essere un dizionario")
	if valore.has("eventi") and typeof(valore["eventi"]) != TYPE_ARRAY:
		errori.append("conseguenze.eventi deve essere un array")
	if valore.has("fatti") and typeof(valore["fatti"]) != TYPE_ARRAY:
		errori.append("conseguenze.fatti deve essere un array")
	if valore.has("pressione"):
		if typeof(valore["pressione"]) != TYPE_DICTIONARY:
			errori.append("conseguenze.pressione deve essere un dizionario")
		elif int(valore["pressione"].get("grado", 0)) < 0:
			errori.append("conseguenze.pressione.grado non puo' essere negativo")

static func _stato(valore: Variant, nome: String, errori: Array[String]) -> Dictionary:
	if typeof(valore) != TYPE_DICTIONARY:
		errori.append("%s deve essere un dizionario" % nome)
		return {}
	var episodio: Variant = valore.get("episodio", null)
	if typeof(episodio) != TYPE_DICTIONARY:
		errori.append("%s.episodio deve essere un dizionario" % nome)
		return valore
	if String(episodio.get("id", "")).strip_edges() == "":
		errori.append("%s.episodio.id assente" % nome)
	if String(episodio.get("nome", "")).strip_edges() == "":
		errori.append("%s.episodio.nome assente" % nome)
	return valore

static func _valida_passaggio(passaggio: Dictionary, prima: Dictionary, dopo: Dictionary,
		ordine: Array, errori: Array[String]) -> void:
	if not passaggio.has("avvenuto") or typeof(passaggio["avvenuto"]) != TYPE_BOOL:
		errori.append("passaggio.avvenuto deve essere booleano")
		return
	var prima_id := _episodio_id(prima)
	var dopo_id := _episodio_id(dopo)
	if not bool(passaggio["avvenuto"]):
		if prima_id != "" and dopo_id != "" and prima_id != dopo_id:
			errori.append("lo stato cambia tappa ma passaggio.avvenuto e' falso")
		return
	var da: Variant = passaggio.get("da", null)
	var a: Variant = passaggio.get("a", null)
	if typeof(da) != TYPE_DICTIONARY or typeof(a) != TYPE_DICTIONARY:
		errori.append("un passaggio richiede da e a")
		return
	var da_id := String(da.get("id", ""))
	var a_id := String(a.get("id", ""))
	if da_id == "" or a_id == "":
		errori.append("passaggio.da/a richiedono un id")
	if da_id != prima_id:
		errori.append("passaggio.da non coincide con lo stato prima")
	if a_id != dopo_id:
		errori.append("passaggio.a non coincide con lo stato dopo")
	var causa := String(passaggio.get("causa", ""))
	if not CAUSE_PASSAGGIO.has(causa):
		errori.append("causa del passaggio non valida: %s" % causa)
	var i := ordine.find(da_id)
	if i < 0 or i + 1 >= ordine.size():
		errori.append("origine del passaggio assente o finale nella rotta fissa")
	elif String(ordine[i + 1]) != a_id:
		errori.append("passaggio fuori rotta: dopo %s viene %s, non %s" % [da_id, ordine[i + 1], a_id])

static func _pressione(conseguenze: Variant) -> Dictionary:
	if typeof(conseguenze) != TYPE_DICTIONARY:
		return {}
	var p: Variant = conseguenze.get("pressione", {})
	return p if typeof(p) == TYPE_DICTIONARY else {}

static func _episodio_id(stato: Dictionary) -> String:
	var ep: Variant = stato.get("episodio", {})
	return String(ep.get("id", "")) if typeof(ep) == TYPE_DICTIONARY else ""

static func _stato_per_prompt(stato: Dictionary) -> String:
	var ep: Dictionary = stato.get("episodio", {})
	var altri := stato.duplicate(true)
	altri.erase("episodio")
	var base := "tappa «%s» [%s]" % [ep.get("nome", ""), ep.get("id", "")]
	var scena := String(ep.get("scena", "")).strip_edges()
	if scena != "":
		base += "; scena: %s" % scena
	if not altri.is_empty():
		base += "; dati: %s" % JSON.stringify(altri)
	return base

static func _passaggio_di_ripiego(passaggio: Dictionary) -> String:
	var da := String(passaggio["da"].get("nome", passaggio["da"].get("id", "la terra lasciata")))
	var a := String(passaggio["a"].get("nome", passaggio["a"].get("id", "la nuova sponda")))
	match String(passaggio.get("causa", "")):
		"cacciato":
			return "Respinto da %s, Ulisse riparo' verso %s." % [da, a]
		"prodigio":
			return "Una forza piu' grande lo strappo' a %s e lo condusse fino a %s." % [da, a]
		_:
			return "Ulisse lascio' %s e volse la rotta verso %s." % [da, a]

static func _valida_lista_stringhe(valore: Variant, nome: String, errori: Array[String]) -> void:
	if typeof(valore) != TYPE_ARRAY:
		errori.append("%s deve essere un array" % nome)
		return
	for voce in valore:
		if typeof(voce) != TYPE_STRING or String(voce).strip_edges() == "":
			errori.append("%s contiene una voce non valida" % nome)

static func _valida_fatti_vietati(valore: Variant, errori: Array[String]) -> void:
	if typeof(valore) != TYPE_ARRAY:
		errori.append("fatti.vietati deve essere un array")
		return
	for voce in valore:
		if typeof(voce) == TYPE_STRING and String(voce).strip_edges() != "":
			continue
		if typeof(voce) == TYPE_DICTIONARY and String(voce.get("id", "")).strip_edges() != "":
			var marcatori: Variant = voce.get("marcatori", [])
			if typeof(marcatori) == TYPE_ARRAY:
				continue
		errori.append("fatti.vietati contiene una voce non valida")

static func _stringhe(valori: Array) -> Array[String]:
	var out: Array[String] = []
	for valore in valori:
		var s := String(valore).strip_edges()
		if s != "":
			out.append(s)
	return out

static func _append_unico(valori: Array, valore: String) -> void:
	if not valori.has(valore):
		valori.append(valore)

static func _elenco(valori: Array, vuoto: String) -> String:
	return "; ".join(_stringhe(valori)) if not valori.is_empty() else vuoto

static func _elenco_fatti(valori: Array, vuoto: String) -> String:
	if valori.is_empty():
		return vuoto
	var out: Array[String] = []
	for valore in valori:
		out.append(_descrivi_fatto(valore))
	return "; ".join(out)

static func _descrivi_fatto(fatto: Variant) -> String:
	if typeof(fatto) == TYPE_DICTIONARY:
		return String(fatto.get("descrizione", fatto.get("id", "fatto vietato")))
	return String(fatto)

static func _normalizza_testo(testo: String) -> String:
	return " ".join(testo.to_lower().split()).strip_edges()

## Il controllo dei fatti e' letterale, ma non ingenuo: un marcatore deve coincidere con
## parole intere e non deve essere negato. Cosi' `una nave affondo'` non combacia dentro
## `nessuna nave affondo'`, e `non una nave affondo'` non diventa un falso fatto.
static func _contiene_affermazione(testo: String, marcatore: String) -> bool:
	var re := RegEx.new()
	var schema := "(?<![a-z0-9_])" + _escape_regex(marcatore).replace("\\ ", "\\s+") + "(?![a-z0-9_])"
	if re.compile(schema) != OK:
		return false
	for m in re.search_all(testo):
		if not _e_negata(testo, m.get_start()):
			return true
	return false

static func _e_negata(testo: String, inizio: int) -> bool:
	var da := maxi(0, inizio - 52)
	var prefisso := testo.substr(da, inizio - da)
	var re := RegEx.new()
	if re.compile("(?:^|[^a-z0-9_])(?:(?:non|nessun[oaie]?|mai)(?:\\s+[a-z0-9_]+){0,3}|senza(?:\\s+(?:mai|poter|voler|dover|alcun[oa]?|nessun[oa]?))?)\\s*$") != OK:
		return false
	return re.search(prefisso) != null

static func _normalizza_per_confronto(testo: String) -> String:
	var out := testo.to_lower().replace("’", "'").replace("‘", "'")
	var da := ["à", "á", "â", "ä", "è", "é", "ê", "ë", "ì", "í", "î", "ï", "ò", "ó", "ô", "ö", "ù", "ú", "û", "ü"]
	var a :=  ["a", "a", "a", "a", "e", "e", "e", "e", "i", "i", "i", "i", "o", "o", "o", "o", "u", "u", "u", "u"]
	for i in da.size():
		out = out.replace(da[i], a[i])
	for separatore in ["'", "\n", "\r", "\t", ",", ".", ";", ":", "!", "?", "«", "»", "(", ")", "—", "–", "-"]:
		out = out.replace(separatore, " ")
	var spazi := RegEx.new()
	if spazi.compile("\\s+") == OK:
		out = spazi.sub(out, " ", true)
	return out.strip_edges()

static func _escape_regex(testo: String) -> String:
	var out := testo
	for c in ["\\", ".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|"]:
		out = out.replace(c, "\\" + c)
	return out
