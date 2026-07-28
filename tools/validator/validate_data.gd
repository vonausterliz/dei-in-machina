extends SceneTree

## Validatore dei contratti-dati (CLAUDE.md, mandato di auto-verifica, punto 3).
## Verifica pantheon.json e stato_partita.json contro il Contratto dell'Interprete:
## ogni trigger_azione nel vocabolario chiuso, ogni trigger_evento dichiarato,
## registro coerente col pantheon, envelope ben formato.
## Uso: tools/godot/godot4 --headless --script res://tools/validator/validate_data.gd
## Rieseguire a ogni modifica dei dati (norme di lavoro, CLAUDE.md).

## Vocabolario chiuso dei tag, da docs/contratto_interprete.md sez. 1.
## Se il contratto cambia, sincronizzare qui.
const TAG_VOCABOLARIO := [
	"tracotanza", "vanto", "astuzia", "inganno", "misura", "coraggio", "violenza", "empieta", "rispetto",
	"preghiera", "supplica", "sacrificio", "xenia", "giuramento", "evocazione",
	"desiderio", "curiosita", "nostalgia", "stanchezza", "fame", "disperazione", "fiducia", "sospetto",
	"intrusione", "rotta", "sfida", "fuga",
]

const PLAUSIBILITA_ENUM := ["in_mondo", "assurdo_diegetico", "anacronistico", "meta_nonsenso"]
const TIPO_ENUM := ["parola", "azione", "preghiera", "rituale", "movimento"]

var _errori: Array[String] = []
var _avvisi: Array[String] = []

func _init() -> void:
	var pantheon := _valida_pantheon("res://data/pantheon.json")
	_valida_stato_partita("res://data/stato_partita.json", pantheon)
	_stampa_report()
	quit(1 if not _errori.is_empty() else 0)

func _err(msg: String) -> void:
	_errori.append(msg)

func _warn(msg: String) -> void:
	_avvisi.append(msg)

func _valida_pantheon(path: String) -> Pantheon:
	var pantheon := Pantheon.carica(path)
	if pantheon.numero_dei() == 0:
		_err("Pantheon: nessun dio caricato da %s" % path)
		return pantheon

	var legenda: Dictionary = pantheon.meta.get("legenda", {})
	var nature_valide: Array = legenda.get("natura", [])
	var fazioni_valide: Array = legenda.get("fazione", [])
	var registri_validi: Array = legenda.get("registri", [])
	var eventi_validi: Array = pantheon.meta.get("vocabolario_eventi", [])

	for dio in pantheon.tutti():
		var etichetta := "dio '%s'" % dio.id
		if dio.id == "" or dio.nome == "":
			_err("%s: id o nome mancante" % etichetta)
		if not nature_valide.is_empty() and not nature_valide.has(dio.natura):
			_err("%s: natura '%s' non in _meta.legenda.natura" % [etichetta, dio.natura])
		if not fazioni_valide.is_empty() and not fazioni_valide.has(dio.fazione):
			_err("%s: fazione '%s' non in _meta.legenda.fazione" % [etichetta, dio.fazione])
		if dio.fascia != "persistente" and dio.fascia != "locale":
			_err("%s: fascia sconosciuta '%s'" % [etichetta, dio.fascia])
		if dio.fascia == "locale" and (dio.episodio == null or String(dio.episodio) == ""):
			_err("%s: fascia 'locale' ma episodio non impostato" % etichetta)
		if dio.fascia == "persistente" and dio.episodio != null:
			_warn("%s: fascia 'persistente' ma episodio impostato a '%s'" % [etichetta, dio.episodio])

		for tag in dio.trigger_azione:
			if not TAG_VOCABOLARIO.has(tag):
				_err("%s: trigger_azione '%s' fuori dal vocabolario chiuso" % [etichetta, tag])
		for evento in dio.trigger_evento:
			if not eventi_validi.is_empty() and not eventi_validi.has(evento):
				_err("%s: trigger_evento '%s' non dichiarato in _meta.vocabolario_eventi" % [etichetta, evento])
		for registro in dio.registri:
			if not registri_validi.is_empty() and not registri_validi.has(registro):
				_err("%s: registro '%s' non in _meta.legenda.registri" % [etichetta, registro])

	return pantheon

func _valida_stato_partita(path: String, pantheon: Pantheon) -> void:
	if not FileAccess.file_exists(path):
		_warn("StatoPartita: nessun file in %s, salto la validazione dello stato" % path)
		return
	var stato := StatoPartita.carica(path)
	if stato == null:
		_err("StatoPartita: impossibile caricare %s" % path)
		return

	for id in stato.registro_divino.keys():
		if not pantheon.ha(id):
			_err("StatoPartita.registro_divino: id '%s' non esiste nel pantheon" % id)
	for dio in pantheon.tutti():
		if not stato.registro_divino.has(dio.id):
			_warn("StatoPartita.registro_divino: manca la voce per '%s'" % dio.id)

	var zeus_verso: Dictionary = stato.relazioni.get("zeus_verso", {})
	for id in zeus_verso.keys():
		if not pantheon.ha(id):
			_err("StatoPartita.relazioni.zeus_verso: id '%s' non esiste nel pantheon" % id)
		if id == "zeus":
			_err("StatoPartita.relazioni.zeus_verso: zeus non dovrebbe comparire verso se stesso")

	for voce in stato.scavalcamenti_pendenti:
		var colpevole: String = voce.get("colpevole", "")
		if not pantheon.ha(colpevole):
			_err("StatoPartita.scavalcamenti_pendenti: colpevole '%s' non esiste nel pantheon" % colpevole)

	for coalizione in stato.coalizioni:
		for membro in coalizione.get("membri", []):
			if not pantheon.ha(membro):
				_err("StatoPartita.coalizioni: membro '%s' non esiste nel pantheon" % membro)

	var eventi_validi: Array = pantheon.meta.get("vocabolario_eventi", [])
	for voce in stato.storico_olimpo:
		var turno = voce.get("turno", "?")
		var envelope: Dictionary = voce.get("envelope", {})
		_valida_envelope(envelope, "storico_olimpo[turno=%s].envelope" % turno)
		for sveglio in voce.get("svegli", []):
			if not pantheon.ha(sveglio):
				_err("storico_olimpo[turno=%s]: dio sveglio '%s' non esiste nel pantheon" % [turno, sveglio])
		for evento in voce.get("eventi_emessi", []):
			if not eventi_validi.is_empty() and not eventi_validi.has(evento):
				_err("storico_olimpo[turno=%s]: evento emesso '%s' non dichiarato" % [turno, evento])

func _valida_envelope(envelope: Dictionary, etichetta: String) -> void:
	if envelope.is_empty():
		_err("%s: envelope mancante o vuoto" % etichetta)
		return
	var plausibilita = envelope.get("plausibilita", null)
	if not PLAUSIBILITA_ENUM.has(plausibilita):
		_err("%s: plausibilita '%s' non valida" % [etichetta, plausibilita])
	var tipo = envelope.get("tipo", null)
	if not TIPO_ENUM.has(tipo):
		_err("%s: tipo '%s' non valido" % [etichetta, tipo])
	var tag: Array = envelope.get("tag", [])
	for t in tag:
		if not TAG_VOCABOLARIO.has(t):
			_err("%s: tag '%s' fuori dal vocabolario chiuso" % [etichetta, t])
	if plausibilita != "in_mondo" and tag.size() > 0:
		_warn("%s: plausibilita '%s' ma tag non vuoti (regola 5 del contratto)" % [etichetta, plausibilita])

func _stampa_report() -> void:
	print("\n=== Validatore contratti-dati — Dei in machina ===\n")
	if _errori.is_empty():
		print("Nessun errore.")
	else:
		print("ERRORI (%d):" % _errori.size())
		for e in _errori:
			print(" - %s" % e)
	print("")
	if not _avvisi.is_empty():
		print("AVVISI (%d):" % _avvisi.size())
		for w in _avvisi:
			print(" - %s" % w)
	print("")
