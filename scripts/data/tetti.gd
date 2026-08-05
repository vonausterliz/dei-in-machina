class_name Tetti
extends RefCounted

## IL TETTO ALL'USCITA DI OGNI AGENTE, per nome.
##
## `max_tokens` era supportato dal client, passato da `LLMManager`, e non impostato da
## NESSUN agente: in un tracciato di partita vera (5 agosto 2026) compare solo nella «prova
## del modello». Senza tetto, un modello che divaga genera finche' non decide di smettere —
## e Omero e' il 28% del tempo di un turno.
##
## I VALORI SONO LARGHI, E DI PROPOSITO. Non servono a stringere: servono a mettere un
## fondo alla coda lunga. Sono tarati a circa tre volte l'uscita osservata sul campo, e
## l'uscita osservata sta nel commento accanto a ciascuno. Un tetto stretto qui
## risparmierebbe poco e romperebbe molto:
##
##   - i MODELLI CHE RAGIONANO spendono il budget nel ragionamento prima di scrivere. Con
##     un tetto basso tornano `content: null` e `finish_reason: length` — succede davvero,
##     e ci sono cascato in v2.38 mettendo `max_tokens: 1` alla prova del modello;
##   - una narrazione tagliata a meta' e' peggio di una narrazione lunga.
##
## I nomi sono quelli che `LLMManager._per()` scrive in `LLMClient.agente`, cioe' gli stessi
## che compaiono nel tracciato e nel consuntivo di turno: se ne cambi uno, cambialo qui.
##
## CHI NON E' IN TABELLA PRENDE `predefinito`, e non si prova a indovinare chi sia.
## Gli dei si annunciano col proprio nome («Atena», «Zeus») e i compagni col loro
## («Euriloco (ciurma)»): riconoscerli vorrebbe dire interrogare il pantheon, cioe'
## nominare l'Autoload `PantheonManager` da dentro un `class_name`. Quella strada e' gia'
## costata due volte: un Autoload non e' un identificatore globale in modalita' `--script`,
## e il solo nominarlo impedisce allo script di caricarsi negli strumenti da riga di comando
## (vedi la nota in `tools/foto_gioco.gd`). Un unico ripiego largo copre entrambi, e non
## puo' scollarsi dal pantheon perche' non lo guarda.

const PERCORSO := "res://data/tetti_uscita.json"

static var _dati: Dictionary = {}
static var _caricato := false

static func _carica() -> void:
	if _caricato:
		return
	_caricato = true
	if not FileAccess.file_exists(PERCORSO):
		return   # nessun tetto: esattamente com'era prima
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERCORSO))
	if typeof(parsed) == TYPE_DICTIONARY:
		_dati = parsed
	else:
		push_error("Tetti: JSON non valido in %s" % PERCORSO)

## Il tetto per un agente, o 0 se non ne ha uno (= nessun limite).
## NON SO CHI SIA: nessun tetto. `"?"` e' il valore iniziale di `LLMClient.agente`, cioe' il
## segnaposto di una chiamata che non si e' annunciata. `predefinito` vale per un agente che
## ha un NOME e non e' in tabella — un dio, l'Arbitro — non per l'ignoto: mettere un tetto a
## una chiamata che non sappiamo cosa sia e' esattamente il modo di tagliarne una che aveva
## bisogno di spazio. L'ha trovato un test gia' esistente, che pretendeva che nel corpo non
## comparisse niente che nessuno avesse chiesto.
static func per_agente(nome: String) -> int:
	_carica()
	if nome == "" or nome == "?" or not bool(_dati.get("attivo", true)):
		return 0
	var tetti: Dictionary = _dati.get("agenti", {})
	if tetti.has(nome):
		return int(tetti[nome])
	# I compagni si annunciano come «Euriloco (ciurma)»: un tetto solo per tutti, e per
	# riconoscerli basta il suffisso — nessuno deve chiedere niente al pantheon.
	if nome.ends_with("(ciurma)") and tetti.has("compagno"):
		return int(tetti["compagno"])
	return int(_dati.get("predefinito", 0))

## Solo per i test: dimentica cio' che ha letto.
static func ricarica() -> void:
	_caricato = false
	_dati = {}

## Solo per i test: la tabella si detta invece di leggerla. Serve a provare `attivo: false`
## — il paracadute — senza scrivere un file e senza sperare che venga letto.
static func per_prova(dati: Dictionary) -> void:
	_dati = dati
	_caricato = true
