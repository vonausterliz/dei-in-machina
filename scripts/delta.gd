class_name Delta
extends RefCounted

## Motore del DELTA: come cambia il mondo dopo un turno. DETERMINISTICO (GDScript):
## l'LLM sceglie il registro (castigo/aiuto/segno/trappola/silenzio) e la voce; qui i
## NUMERI. Cosi' l'effetto sul gioco e' testabile e l'LLM non inventa danni arbitrari.
## Valori-seme (design sez. 12: taratura numerica rimandata): facili da ritoccare.
##
## Un delta e' un dizionario path->intero, con path a punti:
##   ulisse.animo, ulisse.metis, ulisse.hybris, ulisse.ciurma.vivi,
##   <id_dio>.favore, <id_dio>.ira

const STAT_MIN := 0
const STAT_MAX := 100

const _TAG_HYBRIS := ["tracotanza", "vanto", "empieta", "violenza"]
const _TAG_ASTUZIA := ["astuzia", "inganno"]
## Atti di misura e reverenza: sono l'unico modo di far SCENDERE la tracotanza. Senza
## questi la hybris saliva e basta, e l'indicatore diventava un fondo di scala inutile.
const _TAG_UMILTA := ["preghiera", "supplica", "rispetto", "xenia", "misura"]

## Effetto della sola AZIONE di Ulisse (indipendente dai dei): la tracotanza gonfia
## la hybris, l'astuzia affina la metis, la reverenza la sgonfia.
static func da_azione(envelope: Dictionary) -> Dictionary:
	var d: Dictionary = {}
	var tag: Array = envelope.get("tag", [])
	var intensita: int = int(envelope.get("intensita", 1))
	for t in _TAG_HYBRIS:
		if tag.has(t):
			d["ulisse.hybris"] = d.get("ulisse.hybris", 0) + Bilanciamento.intero("delta/azione/hybris_per_intensita", 2) * intensita
	for t in _TAG_ASTUZIA:
		if tag.has(t):
			d["ulisse.metis"] = d.get("ulisse.metis", 0) + Bilanciamento.intero("delta/azione/metis_per_intensita", 1) * intensita
			break
	# La misura ripaga solo se non stai contemporaneamente tracotando.
	if not d.has("ulisse.hybris"):
		for t in _TAG_UMILTA:
			if tag.has(t):
				d["ulisse.hybris"] = -Bilanciamento.intero("delta/azione/sconto_hybris_per_umilta", 1) * intensita
				break
	return d

## Effetto della REAZIONE di un dio, dato il registro scelto e l'intensita'.
## Un castigo al massimo dell'intensita' COSTA UOMINI: e' l'unico modo in cui la ciurma
## si assottiglia, e senza il suo indicatore restava fermo a 45/45 per tutta la partita
## (e l'esito "ciurma_perduta" era irraggiungibile).
static func da_reazione(dio_id: String, registro: String, intensita: int) -> Dictionary:
	var k: int = max(1, intensita)
	# I pesi vengono da data/bilanciamento.json: tararli non richiede di toccare il codice.
	match registro:
		"castigo":
			var d := {
				"ulisse.animo": Bilanciamento.intero("delta/castigo/animo", -2) * k,
				"%s.ira" % dio_id: Bilanciamento.intero("delta/castigo/ira", 2) * k,
			}
			if k >= 3:
				d["ulisse.ciurma.vivi"] = Bilanciamento.intero("delta/castigo/ciurma_se_intensita_3", -2)
			elif k == 2:
				d["ulisse.ciurma.vivi"] = Bilanciamento.intero("delta/castigo/ciurma_se_intensita_2", -1)
			return d
		"aiuto":
			return {
				"ulisse.animo": Bilanciamento.intero("delta/aiuto/animo", 2) * k,
				"%s.favore" % dio_id: Bilanciamento.intero("delta/aiuto/favore", 1) * k,
			}
		"aiuto_negato":
			return {
				"ulisse.animo": Bilanciamento.intero("delta/aiuto_negato/animo", -1) * k,
				"%s.ira" % dio_id: Bilanciamento.intero("delta/aiuto_negato/ira", 1) * k,
			}
		"segno":
			return {
				"ulisse.metis": Bilanciamento.intero("delta/segno/metis", 1) * k,
				"%s.favore" % dio_id: Bilanciamento.intero("delta/segno/favore", 1),
			}
		"trappola":
			# Pare un aiuto adesso; il costo nascosto e' lavoro di una fase futura.
			return {"ulisse.animo": Bilanciamento.intero("delta/trappola/animo", 1) * k}
		_:
			# silenzio / arbitrato: nessun effetto diretto sulle stat.
			return {}

## Somma additiva di due delta.
static func unisci(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate(true)
	for path in b:
		out[path] = out.get(path, 0) + b[path]
	return out

## Applica il delta allo stato, con clamp sui range sensati.
static func applica(stato: StatoPartita, delta: Dictionary) -> void:
	for path in delta:
		_applica_path(stato, path, int(delta[path]))

static func _applica_path(stato: StatoPartita, path: String, amount: int) -> void:
	var p := path.split(".")
	if p[0] == "ulisse":
		_applica_ulisse(stato, p, amount)
	else:
		_applica_dio(stato, p, amount)

static func _applica_ulisse(stato: StatoPartita, p: PackedStringArray, amount: int) -> void:
	if p.size() == 2 and p[1] == "hybris":
		stato.ulisse["hybris"] = clampi(int(stato.ulisse.get("hybris", 0)) + amount, STAT_MIN, STAT_MAX)
	elif p.size() == 2 and (p[1] == "animo" or p[1] == "metis"):
		var st: Dictionary = stato.ulisse["stat"]
		st[p[1]] = clampi(int(st.get(p[1], 0)) + amount, STAT_MIN, STAT_MAX)
	elif p.size() == 3 and p[1] == "ciurma" and p[2] == "vivi":
		var c: Dictionary = stato.ulisse["stat"]["ciurma"]
		var maxv: int = int(c.get("iniziali", STAT_MAX))
		c["vivi"] = clampi(int(c.get("vivi", 0)) + amount, 0, maxv)
	else:
		push_warning("Delta: path ulisse sconosciuto: %s" % ".".join(p))

static func _applica_dio(stato: StatoPartita, p: PackedStringArray, amount: int) -> void:
	var dio: String = p[0]
	if p.size() == 2 and (p[1] == "favore" or p[1] == "ira") and stato.registro_divino.has(dio):
		var r: Dictionary = stato.registro_divino[dio]
		r[p[1]] = clampi(int(r.get(p[1], 0)) + amount, STAT_MIN, STAT_MAX)
	else:
		push_warning("Delta: path dio sconosciuto: %s" % ".".join(p))

## Marcatore d'esito per il diario (reticente, ambiguo): ando' male / parve giovare / neutro.
static func marcatore_diario(delta: Dictionary) -> String:
	var animo: int = int(delta.get("ulisse.animo", 0))
	var ciurma: int = int(delta.get("ulisse.ciurma.vivi", 0))
	if animo < 0 or ciurma < 0:
		return "ill"
	if animo > 0:
		return "fair"
	return "neutro"
