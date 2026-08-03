class_name Taccuino
extends RefCounted

## IL TACCUINO PRIVATO DEGLI DEI: cosa ognuno ha voluto, turno per turno, e come e' finita.
##
## Non basta la `cronaca` condivisa: quella e' ripulita dai nomi divini — finisce anche a
## Omero, che non deve nominarli — quindi un dio non vi ritroverebbe nemmeno le proprie
## opere. Senza questo, ogni turno una potenza millenaria riparte smemorata.
##
## Estratto da GameManager insieme al Viaggio: e' un concetto suo, con una regola sua
## (i recenti per esteso, i vecchi condensati), e non c'entra con la macchina del turno.
## Niente LLM qui dentro: il condensato si calcola in GDScript, perche' farlo scrivere al
## modello sarebbe una chiamata per dio ogni N turni, e sotto il free tier si sentirebbe.

var _stato: StatoPartita = null

func _init(stato: StatoPartita) -> void:
	_stato = stato

## Quanti ricordi restano PER ESTESO. Oltre questo non si cancella nulla: i piu' vecchi
## si condensano in `memoria_vecchia`. Cosi' il prompt resta a dimensione costante — un
## taccuino che cresce all'infinito lo paga l'utente a ogni turno — ma un dio non
## dimentica: una potenza millenaria che perde il conto dei propri torti non e' credibile.
var ricordi_per_dio: int = Bilanciamento.intero("memoria/ricordi_per_dio", 5)

## Il taccuino privato degli dei. Ognuno annota cosa ha voluto e come e' finita: se ha
## prevalso, se e' stato respinto, se ha agito di nascosto dopo il no di Zeus.
##
## Non basta la `cronaca` condivisa: quella e' ripulita dai nomi divini (finisce anche a
## Omero, che non deve nominarli), quindi un dio non vi ritroverebbe nemmeno le proprie
## opere. Senza questo, ogni turno una potenza millenaria riparte smemorata.
func annota(proposte: Array, verdetto: Dictionary, scavalcamento: Dictionary,
		envelope: Dictionary, luogo: String, nome_vincitore: String) -> void:
	var vincitore := String(verdetto.get("attore", ""))
	var fatto := String(envelope.get("sintesi", "qualcosa"))
	for p in proposte:
		var id := String(p.get("dio", ""))
		if id == "" or not _stato.registro_divino.has(id):
			continue
		var registro := String(p.get("registro", "silenzio"))
		if registro == "silenzio":
			continue  # tacere non lascia un ricordo
		var esito := "nulla"
		if String(scavalcamento.get("colpevole", "")) == id:
			esito = "nascosto"
		elif id == vincitore:
			esito = "prevalso"
		elif vincitore != "":
			esito = "respinto"
		_ricorda(id, {
			"t": _stato.turno,
			"luogo": luogo,
			"fatto": fatto.strip_edges().trim_suffix("."),
			"registro": registro,
			"intensita": int(p.get("intensita", 1)),
			"esito": esito,
			"contro": nome_vincitore if esito == "respinto" else "",
		})

## Il ricordo si conserva STRUTTURATO, non gia' impaginato: e' cio' che permette di
## riassumerlo davvero quando invecchia (contare i registri, gli esiti, i luoghi) invece
## di dover rileggere delle frasi. La prosa si compone al momento di darla al dio.
func _ricorda(id: String, ricordo: Dictionary) -> void:
	var reg: Dictionary = _stato.registro_divino[id]
	var memoria: Array = reg.get("memoria", [])
	memoria.append(ricordo)
	while memoria.size() > ricordi_per_dio:
		_condensa(reg, memoria.pop_front())   # non si butta: si sedimenta
	reg["memoria"] = memoria

## Un ricordo che esce dai recenti entra nel condensato. Nulla si perde: cambia la grana.
func _condensa(reg: Dictionary, ricordo: Dictionary) -> void:
	var v: Dictionary = reg.get("memoria_vecchia", StatoPartita.memoria_vuota())
	v["quanti"] = int(v["quanti"]) + 1
	var t := int(ricordo["t"])
	v["dal_turno"] = t if int(v["dal_turno"]) == 0 else mini(int(v["dal_turno"]), t)
	v["al_turno"] = maxi(int(v["al_turno"]), t)
	var registri: Dictionary = v["registri"]
	var r := String(ricordo["registro"])
	registri[r] = int(registri.get(r, 0)) + 1
	var esito := String(ricordo["esito"])
	if v.has(esito):
		v[esito] = int(v[esito]) + 1
	var luoghi: Array = v["luoghi"]
	var luogo := String(ricordo["luogo"])
	if luogo != "" and not luoghi.has(luogo):
		luoghi.append(luogo)
	reg["memoria_vecchia"] = v

## Il condensato reso in una frase, per il prompt del dio. "" se non c'e' ancora nulla
## di vecchio. Deterministico: nessuna chiamata LLM per riassumere (sarebbe una chiamata
## per dio ogni N turni, e sotto il free tier si sentirebbe).
func riassunto_memoria(id: String) -> String:
	var reg: Dictionary = _stato.registro_divino.get(id, {}) if _stato else {}
	var v: Dictionary = reg.get("memoria_vecchia", {})
	if v.is_empty() or int(v.get("quanti", 0)) == 0:
		return ""
	var voleri: Array[String] = []
	for r in v["registri"]:
		var n := int(v["registri"][r])
		voleri.append("%s %d volte" % [r, n] if n > 1 else String(r))
	var esiti: Array[String] = []
	if int(v["prevalso"]) > 0:
		esiti.append("prevalso %d volte" % int(v["prevalso"]))
	if int(v["respinto"]) > 0:
		esiti.append("respinto %d volte" % int(v["respinto"]))
	if int(v["nascosto"]) > 0:
		esiti.append("%d volte hai agito di nascosto dopo un no di Zeus" % int(v["nascosto"]))
	var dove := " (%s)" % ", ".join(v["luoghi"]) if not v["luoghi"].is_empty() else ""
	return "Prima, dal turno %d al %d%s sei intervenuto %d volte: hai voluto %s; hai %s." % [
		int(v["dal_turno"]), int(v["al_turno"]), dove, int(v["quanti"]),
		", ".join(voleri), " e ".join(esiti) if not esiti.is_empty() else "lasciato correre",
	]

## I ricordi recenti, per esteso, nella forma che legge il dio.
func ricordi_recenti(id: String) -> Array:
	var out: Array = []
	var reg: Dictionary = _stato.registro_divino.get(id, {}) if _stato else {}
	for r in reg.get("memoria", []):
		var coda := "Hai prevalso."
		match String(r["esito"]):
			"nascosto": coda = "Zeus ti nego', e agisti lo stesso di nascosto."
			"respinto": coda = "Fosti respinto: prevalse %s." % r.get("contro", "un altro")
			"nulla": coda = "Non se ne fece nulla."
		# La sintesi arriva gia' come frase compiuta ("Ulisse grida il proprio nome…"):
		# incastonarla fra virgolette evita di doverla cucire alla grammatica della riga.
		out.append("- turno %d, a %s — «%s» — volevi %s (forza %d). %s" % [
			int(r["t"]), r["luogo"], r["fatto"], r["registro"], int(r["intensita"]), coda])
	return out
