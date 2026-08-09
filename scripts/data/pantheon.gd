class_name Pantheon
extends RefCounted

## Data layer statico: carica e indicizza data/pantheon.json.

var meta: Dictionary = {}
var _dei: Dictionary = {}  # id (String) -> Dio

static func carica(path: String) -> Pantheon:
	var p := Pantheon.new()
	if not FileAccess.file_exists(path):
		push_error("Pantheon: file non trovato: %s" % path)
		return p
	var testo := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(testo)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Pantheon: JSON non valido: %s" % path)
		return p
	var d: Dictionary = parsed
	p.meta = d.get("_meta", {})
	for voce in d.get("dei", []):
		var dio := Dio.from_dict(voce)
		if dio.id == "":
			push_warning("Pantheon: voce senza id ignorata.")
			continue
		p._dei[dio.id] = dio
	return p

func get_dio(id: String) -> Dio:
	return _dei.get(id, null)

func ha(id: String) -> bool:
	return _dei.has(id)

func tutti() -> Array[Dio]:
	var out: Array[Dio] = []
	for id in _dei.keys():
		out.append(_dei[id])
	return out

func tutti_gli_id() -> Array[String]:
	var out: Array[String] = []
	for id in _dei.keys():
		out.append(id)
	return out

func dei_attivi() -> Array[Dio]:
	var out: Array[Dio] = []
	for dio in tutti():
		if dio.attivo:
			out.append(dio)
	return out

## I NOMI CHE LA NARRAZIONE NON DEVE PRONUNCIARE: solo chi muove i fili dall'Olimpo
## (`nascosto`). Chi si incontra — Eolo, Circe, Polifemo — ha un nome e lo si dice: il poema
## li nomina tutti, e negarlo non nascondeva niente. Vedi `Dio.nascosto`.
func nomi_nascosti() -> Array[String]:
	var out: Array[String] = []
	for dio in tutti():
		if dio.nascosto:
			out.append(dio.nome)
	return out

## Tutti i dei locali legati a un episodio (per accenderli all'ingresso della tappa).
func locali_di_episodio(episodio: String) -> Array[Dio]:
	var out: Array[Dio] = []
	for dio in tutti():
		if dio.fascia == "locale" and dio.episodio != null and String(dio.episodio) == episodio:
			out.append(dio)
	return out

## Riporta tutti i locali a spenti (attivo=false). Usato all'inizio di una nuova partita
## perche' l'accensione delle tappe muta 'attivo' in memoria.
func spegni_locali() -> void:
	for dio in tutti():
		if dio.fascia == "locale":
			dio.attivo = false

func numero_dei() -> int:
	return _dei.size()

## Dei "in ascolto" questo turno: attivi e nella condizione di poter reagire.
## Persistente = sempre in ascolto; locale = solo quando si e' nel suo episodio.
## 'attivo' e' l'interruttore di rollout (stadio 1 = solo i persistenti attivi).
func eleggibili(episodio_corrente: String, accaduti: Array = []) -> Array[String]:
	var out: Array[String] = []
	for dio in tutti():
		if not dio.attivo:
			continue
		# Chi dorme non e' in ascolto: il suo momento non e' ancora arrivato.
		if dio.dorme_finche != "" and not accaduti.has(dio.dorme_finche):
			continue
		if dio.fascia == "persistente":
			out.append(dio.id)
		elif dio.fascia == "locale" and dio.episodio != null and String(dio.episodio) == episodio_corrente:
			out.append(dio.id)
	return out

## RISVEGLIO (macchina_del_turno.mermaid): tra gli eleggibili, chi si sveglia per
## via dei TRIGGER. Regola deterministica (GDScript), cuore del "nascosto ma leale":
## stessa azione -> stessi tag -> stessi dei svegliati. Un dio si sveglia se
##  - un suo trigger_azione e' tra i tag dell'envelope, OPPURE
##  - un suo trigger_evento e' tra gli eventi di mondo di questo turno, OPPURE
##  - e' il dio_invocato (Ulisse lo chiama per nome).
##
## NOTA DI DESIGN: il testo dice i persistenti "valutati ogni turno", ma la coerenza
## "vive nel trigger" e il diagramma gatea il risveglio sui trigger. Scelta: risveglio
## gated dai trigger (un persistente non-innescato resta silente), cosi' il segnale e'
## deducibile. L'esempio in stato_partita.json (svegli = tutti i persistenti) e' trattato
## come illustrativo, non normativo. Vedi STATO_LAVORI.md.
func risveglio(envelope: Dictionary, eventi: Array, episodio_corrente: String,
		accaduti: Array = []) -> Array[String]:
	var tag: Array = envelope.get("tag", [])
	var dio_invocato: Variant = envelope.get("dio_invocato", null)
	var out: Array[String] = []
	for id in eleggibili(episodio_corrente, accaduti):
		var dio := get_dio(id)
		if _combacia(dio.trigger_azione, tag) \
				or _combacia(dio.trigger_evento, eventi) \
				or (dio_invocato != null and String(dio_invocato) == id):
			out.append(id)
	return out

func _combacia(triggers: Array, presenti: Array) -> bool:
	for t in triggers:
		if presenti.has(t):
			return true
	return false

## Risolve un riferimento a un dio dentro il testo libero — anche ALLUSIVO
## ("il capo dell'olimpo" -> zeus, "signore dei mari" -> poseidone) — cercando nome
## ed epiteti come sottostringhe. Ritorna l'id del dio, o "" se nessuno.
## Deterministico (GDScript): l'allusione la scioglie una regola, non l'LLM.
## Longest-match: se piu' epiteti combaciano, vince il piu' lungo (piu' specifico),
## cosi' "figlia di zeus" -> atena batte "zeus" -> zeus.
func risolvi_invocato(testo: String) -> String:
	return risolvi_invocato_dett(testo)["id"]

## Come risolvi_invocato, ma dice anche COME ha combaciato:
##  {id: String, per_nome: bool}. per_nome=true se il match e' un nome proprio /
##  appellativo di una sola parola (es. "atena", "pallade", "poseidone") — segnale
##  forte di invocazione diretta; false se e' un epiteto allusivo multi-parola
##  (es. "capo dell'olimpo", "signore dei mari"). Il GameManager usa la distinzione:
##  il nome proprio sveglia comunque, l'epiteto allusivo solo con intento di preghiera.
func risolvi_invocato_dett(testo: String) -> Dictionary:
	var t := _normalizza_testo(testo)
	if t == "":
		return {"id": "", "per_nome": false}
	var best_id := ""
	var best_len := 0
	var best_per_nome := false
	for dio in tutti():
		var alias_list: Array[String] = dio.epiteti.duplicate()
		if not alias_list.has(dio.nome):
			alias_list.append(dio.nome)
		for alias in alias_list:
			var a := _normalizza_testo(alias)
			if a == "" or a.length() <= best_len:
				continue
			var e_nome := (a.find(" ") == -1)  # una sola parola = nome proprio
			# Nome proprio: match a PAROLA INTERA (cosi' "atena" non scatta dentro "catena").
			# Epiteto allusivo multi-parola: sottostringa (e' una locuzione distintiva).
			var trovato := _parola_intera(t, a) if e_nome else (t.find(a) != -1)
			if trovato:
				best_len = a.length()
				best_id = dio.id
				best_per_nome = e_nome
	return {"id": best_id, "per_nome": best_per_nome}

## Vero se `parola` compare in `testo` come parola intera (confini non alfanumerici).
func _parola_intera(testo: String, parola: String) -> bool:
	var re := RegEx.new()
	re.compile("\\b" + parola + "\\b")
	return re.search(testo) != null

## Minuscolo + accenti rimossi, per un confronto robusto sull'input del giocatore.
func _normalizza_testo(s: String) -> String:
	var out := s.to_lower()
	var da := ["à", "á", "è", "é", "ì", "í", "ò", "ó", "ù", "ú"]
	var a := ["a", "a", "e", "e", "i", "i", "o", "o", "u", "u"]
	for i in da.size():
		out = out.replace(da[i], a[i])
	return out
