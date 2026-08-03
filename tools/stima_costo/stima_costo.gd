extends SceneTree

## STIMA DEL COSTO IN TOKEN di una partita intera, da Troia a Itaca.
##
## Non e' un preventivo tirato a indovinare: costruisce i messaggi VERI di ogni agente
## (`costruisci_messaggi`, gli stessi che partono a runtime) su contesti realistici, li
## misura, e li moltiplica per il profilo di una partita completa.
##
## Uso: tools/godot/godot4 --headless --script res://tools/stima_costo/stima_costo.gd
##
## Il costo e' un vincolo di design in questo progetto (tier gratuito: il pavimento e'
## richieste/secondo, non la latenza), quindi va reso OSSERVABILE come tutto il resto.

## Rapporto caratteri/token per l'italiano. L'inglese sta su ~4; l'italiano ha parole piu'
## lunghe e piu' accenti, e i tokenizer BPE lo spezzano di piu': ~3,3 e' la stima prudente.
const CHAR_PER_TOKEN := 3.3

## Quanto e' lunga, in caratteri, la risposta tipica di ogni agente (misurata sulle
## partite reali con Mistral Small e Gemini Flash).
const OUT_CHAR := {
	"interprete": 320,      # envelope JSON
	"vaglio": 20,           # una parola
	"ricognizione": 15,     # un id
	"dio": 180,             # registro + intensita + una battuta secca
	"arbitro": 200,
	"omero": 1100,          # racconto + 3 spunti nella stessa risposta
	"suggeritore": 260,
	"cronista": 800,        # ~120 parole
	"compagno": 120,
}

var _pantheon: Pantheon
var _episodi: Episodi
var _ciurma: Ciurma

func _init() -> void:
	_pantheon = Pantheon.carica("res://data/pantheon.json")
	_episodi = Episodi.carica("res://data/episodi.json")
	_ciurma = Ciurma.carica()
	var misure := _misura_agenti()
	_stampa_misure(misure)
	_stampa_partita(misure)
	quit(0)

# --- misura dei messaggi veri ---

func _misura_agenti() -> Dictionary:
	var out := {}
	_agente_in_misura = "interprete"
	out["interprete"] = _caratteri(Interprete.new(_pantheon.tutti_gli_id(), _pantheon)
		.costruisci_messaggi(_azione()))
	# Il dio: si misura sul caso MEDIO (un persistente, con taccuino pieno e un altro
	# dio in campo), che e' la forma che il prompt ha quasi sempre dal terzo turno in poi.
	_agente_in_misura = "dio"
	var dio_ag := DioAgente.new()
	out["dio"] = _caratteri(dio_ag.costruisci_messaggi(
		_pantheon.get_dio("poseidone"), _contesto_dio()))
	_agente_in_misura = "arbitro"
	out["arbitro"] = _caratteri(Arbitro.new(_pantheon).costruisci_messaggi(_proposte()))
	var nomi: Array = []
	for d in _pantheon.tutti():
		nomi.append(d.nome)
	_agente_in_misura = "omero"
	out["omero"] = _caratteri(Narratore.new(nomi).costruisci_messaggi(_contesto_omero()))
	_agente_in_misura = "suggeritore"
	out["suggeritore"] = _caratteri(Suggeritore.new().costruisci_messaggi(_contesto_omero()))
	_agente_in_misura = "cronista"
	out["cronista"] = _caratteri(Cronista.new().costruisci_messaggi({
		"precedente": _cronaca(), "fatti": _fatti(), "luogo": "L'antro del Ciclope",
	}))
	_agente_in_misura = "compagno"
	out["compagno"] = _caratteri(Compagno.new().costruisci_messaggi(
		_ciurma.get_compagno("euriloco"), _contesto_compagno()))
	_agente_in_misura = ""
	# Vaglio e ricognizione riusano il system prompt dell'Interprete con una domanda
	# secca: il prompt di sistema pesa uguale, il messaggio utente quasi niente.
	out["vaglio"] = out["interprete"] - _lunghezza(_azione()) + 60
	out["ricognizione"] = out["vaglio"]
	return out

## Caratteri totali della richiesta. Registra anche, a parte, la quota di SISTEMA: e' la
## parte identica a ogni chiamata dello stesso agente, quindi l'unica che il prompt
## caching di un provider puo' risparmiare.
var _sistema: Dictionary = {}
var _agente_in_misura := ""

func _caratteri(messaggi: Array) -> int:
	var n := 0
	var sys := 0
	for m in messaggi:
		var l := String(m.get("content", "")).length()
		n += l
		if String(m.get("role", "")) == "system":
			sys += l
	if _agente_in_misura != "":
		_sistema[_agente_in_misura] = sys
	return n

func _lunghezza(s: String) -> int:
	return s.length()

# --- contesti realistici (presi dai dati veri, non inventati) ---

func _azione() -> String:
	return "Grido al ciclope accecato: sono io, Odisseo distruttore di rocche, figlio di Laerte, che t'ho tolto la vista!"

func _cronaca() -> String:
	# ~120 parole: il tetto che il Cronista ha nel suo prompt.
	var p := "Lasciata Troia in fiamme con dodici navi, i suoi hanno saccheggiato la citta' dei Ciconi e sono stati respinti con perdite. "
	p += "Il vento li ha spinti alla terra dei mangiatori di loto, dove alcuni compagni hanno dimenticato il ritorno e sono stati trascinati alle navi in catene. "
	p += "Ora sono chiusi nell'antro di un pastore mostruoso che ha divorato due uomini davanti a tutti e ha sbarrato l'uscita con un masso che venti carri non muoverebbero. "
	p += "Il capo ha fatto bere al gigante il vino nero di Marone e gli ha detto di chiamarsi Nessuno. Il palo d'olivo e' temprato nella brace. "
	p += "Gli uomini sono stanchi, affamati, e cominciano a guardare il loro capo come si guarda chi li ha portati li'."
	return p

func _memoria() -> Array:
	return [
		"- turno 3, a La citta' dei Ciconi — «Ulisse guida il saccheggio della citta'» — volevi castigo (forza 2). Fosti respinto: prevalse Atena.",
		"- turno 5, a La terra dei Lotofagi — «Ulisse trascina i compagni alle navi» — volevi segno (forza 1). Non se ne fece nulla.",
		"- turno 8, a L'antro del Ciclope — «Ulisse entra nella grotta senza attendere il padrone» — volevi trappola (forza 2). Hai prevalso.",
		"- turno 9, a L'antro del Ciclope — «Ulisse offre il vino al gigante» — volevi aiuto_negato (forza 2). Zeus ti nego', e agisti lo stesso di nascosto.",
		"- turno 11, a L'antro del Ciclope — «Ulisse acceca il ciclope col palo temprato» — volevi castigo (forza 3). Hai prevalso.",
	]

func _contesto_dio() -> Dictionary:
	return {
		"favore": 0, "ira": 45, "umore": "rancoroso",
		"envelope": _envelope(),
		"altri_dei": [{
			"nome": "Atena", "registro": "aiuto",
			"dice": "E' mio. L'ho seguito da Troia e non lo lascio a te.",
		}],
		"cronaca": _cronaca(),
		"detto_ai_compagni": "Reggete il palo saldo, e non guardatelo in faccia.",
		"memoria": _memoria(),
		"memoria_riassunto": "Prima, dal turno 1 al 2 (Troia, La citta' dei Ciconi) sei intervenuto 2 volte: hai voluto castigo 2 volte; hai respinto 2 volte.",
	}

func _envelope() -> Dictionary:
	return {
		"plausibilita": "in_mondo", "tipo": "parola",
		"tag": ["vanto", "tracotanza"], "dio_invocato": null,
		"bersaglio": "polifemo", "tono": "sfida", "intensita": 3,
		"sintesi": "Ulisse grida il proprio nome al ciclope accecato.",
	}

func _proposte() -> Array:
	return [
		{"dio": "poseidone", "registro": "castigo", "intensita": 3,
		 "dice": "Ha detto il suo nome. Adesso il mare sa dove cercarlo."},
		{"dio": "atena", "registro": "aiuto", "intensita": 2,
		 "dice": "E' mio. L'ho seguito da Troia e non lo lascio a te."},
	]

func _contesto_omero() -> Dictionary:
	var ep := _episodi.get_episodio("ciclope")
	return {
		"sintesi": "Ulisse grida il proprio nome al ciclope accecato.",
		"azione": _azione(),
		"scena": ep.scena if ep else "",
		"cronaca": _cronaca(),
		"storia": [
			"Ulisse entra nella grotta senza attendere il padrone.",
			"Ulisse offre al gigante il vino nero di Marone.",
			"Ulisse dice di chiamarsi Nessuno.",
			"Ulisse tempra il palo d'olivo nella brace.",
			"Ulisse acceca il ciclope nel sonno.",
		],
		"ultima_narrazione": "Il grido riempi' la grotta e usci' dalla bocca dell'antro come fumo. Fuori, sulle alture, altre voci risposero, e il gigante brancolava contro le pareti chiamando un nome che non era nome.",
		"luogo": "L'antro del Ciclope", "progresso": "inizio", "morale": "duro",
		"svegli": ["poseidone", "atena"],
		"verdetto": {"attore": "poseidone", "registro": "castigo", "intensita": 3,
			"dice": "Che il mare lo provi. Cosi' ho detto."},
		"delta": {"ulisse.animo": -6, "ulisse.hybris": 8},
		"impronta": "acqua, sale, il rumore del mare anche dove il mare non c'e'",
		"esito_segno": "le cose hanno preso una brutta piega",
		"detto_ai_compagni": "Reggete il palo saldo, e non guardatelo in faccia.",
		"momento": "verso sera",
	}

func _contesto_compagno() -> Dictionary:
	var ep := _episodi.get_episodio("ciclope")
	return {
		"scena": ep.scena if ep else "",
		"cronaca": _cronaca(),
		"accaduto": String(_contesto_omero()["ultima_narrazione"]),
		"ulisse_dice": _azione(),
		"interpellato": true,
	}

func _fatti() -> Array:
	var out: Array = []
	for i in 4:
		out.append("- Ulisse: «%s» → %s" % [_azione(), String(_contesto_omero()["ultima_narrazione"])])
	return out

# --- il profilo di una partita intera ---

## Quanti turni dura una partita che arriva a Itaca senza forzare l'avanzamento: il tetto
## di ogni tappa. E' il caso PEGGIORE realistico — chi gioca dritto avanza sul tag e
## chiude prima.
func _turni_totali() -> int:
	var n := 0
	for id in _episodi.ordine():
		var ep := _episodi.get_episodio(id)
		if ep:
			n += ep.turni_massimi
	return n

func _stampa_misure(m: Dictionary) -> void:
	print("\n=== PROMPT MISURATI (caratteri della richiesta, system + user) ===\n")
	print("  agente            caratteri  token in   di cui fissi (cacheabili)")
	print("  ──────────────────────────────────────────────────────────────────")
	var chiavi := ["interprete", "vaglio", "dio", "arbitro", "omero", "suggeritore", "cronista", "compagno"]
	for k in chiavi:
		var sys := int(_sistema.get(k, _sistema.get("interprete", 0)))
		print("  %-16s %8d %9d %9d  (%d%%)" % [
			k, int(m[k]), _tok(int(m[k])), _tok(sys),
			int(round(100.0 * float(sys) / float(m[k])))])

func _tok(caratteri: int) -> int:
	return int(round(float(caratteri) / CHAR_PER_TOKEN))

## Un turno MEDIO, pesato su come vanno davvero le partite:
##  - l'Interprete parte sempre;
##  - il vaglio salta quando si clicca uno spunto (succede spesso): 0,6;
##  - la ricognizione LLM del dio e' rara (serve un'invocazione parafrasata): 0,1;
##  - dei svegli: ~1,1 in media (molti turni non ne svegliano nessuno, quelli caldi due o tre);
##  - repliche: solo quando ci sono due o piu voci in campo, col tetto di 2: ~0,5;
##  - Zeus arbitra solo in conflitto vero: ~0,2;
##  - Omero parte a ogni turno in-mondo: 0,95;
##  - un compagno commenta sempre: 1.
const PESI := {
	"interprete": 1.0, "vaglio": 0.6, "ricognizione": 0.1,
	"dio": 1.6,     # 1,1 proposte + 0,5 repliche
	"arbitro": 0.2, "omero": 0.95, "compagno": 1.0,
}

func _stampa_partita(m: Dictionary) -> void:
	var turni := _turni_totali()
	var tappe := _episodi.ordine().size()
	var cronache := int(floor(float(turni) / float(Bilanciamento.intero("memoria/cronaca_ogni", 4))))

	print("\n=== UNA PARTITA INTERA, DA TROIA A ITACA ===\n")
	print("  tappe: %d · turni al tetto di ogni tappa: %d" % [tappe, turni])
	print("  (e' il caso peggiore realistico: chi avanza sul tag di progresso chiude prima)\n")

	var righe: Array = []
	var chiam_tot := 0.0
	var in_tot := 0.0
	var out_tot := 0.0

	for k in PESI:
		var chiamate: float = float(PESI[k]) * float(turni)
		var costo_in: int = int(m.get(k, m["interprete"]))
		var costo_out: int = int(OUT_CHAR[k])
		righe.append([k, chiamate, _tok(int(chiamate * costo_in)), _tok(int(chiamate * costo_out))])
		chiam_tot += chiamate
		in_tot += chiamate * costo_in
		out_tot += chiamate * costo_out

	# Fuori dal turno: cronaca ogni N turni, traversata a ogni cambio tappa,
	# spunti d'apertura una volta sola.
	righe.append(["cronista", float(cronache), _tok(cronache * int(m["cronista"])), _tok(cronache * int(OUT_CHAR["cronista"]))])
	chiam_tot += cronache
	in_tot += cronache * int(m["cronista"])
	out_tot += cronache * int(OUT_CHAR["cronista"])

	var traversate := tappe - 1
	righe.append(["omero (traversate)", float(traversate), _tok(traversate * int(m["omero"])), _tok(traversate * 400)])
	chiam_tot += traversate
	in_tot += traversate * int(m["omero"])
	out_tot += traversate * 400

	righe.append(["suggeritore (apertura)", 1.0, _tok(int(m["suggeritore"])), _tok(int(OUT_CHAR["suggeritore"]))])
	chiam_tot += 1
	in_tot += int(m["suggeritore"])
	out_tot += int(OUT_CHAR["suggeritore"])

	print("  agente                  chiamate     token IN    token OUT")
	print("  ───────────────────────────────────────────────────────────")
	for r in righe:
		print("  %-22s %9.0f %12d %12d" % [r[0], r[1], r[2], r[3]])
	print("  ───────────────────────────────────────────────────────────")
	print("  %-22s %9.0f %12d %12d" % ["TOTALE", chiam_tot, _tok(int(in_tot)), _tok(int(out_tot))])
	print("\n  Totale token (in + out): %d" % _tok(int(in_tot + out_tot)))
	print("  Media per turno: %d chiamate · %d token" % [
		int(round(chiam_tot / float(turni))), _tok(int((in_tot + out_tot) / float(turni)))])
	# Quota fissa dell'ingresso, pesata sulle chiamate: e' quanto risparmierebbe un
	# provider con prompt caching.
	var fisso := 0.0
	for r in righe:
		var k := String(r[0]).get_slice(" ", 0)
		fisso += float(r[1]) * float(_sistema.get(k, _sistema.get("interprete", 0)))
	print("\n  NOTA: sono token SENZA cache di prompt. Il system prompt e' identico a ogni")
	print("  chiamata dello stesso agente: %d token su %d in ingresso (%d%%) sono ripetuti" % [
		_tok(int(fisso)), _tok(int(in_tot)), int(round(100.0 * fisso / in_tot))])
	print("  identici. Con un provider che offre il prompt caching, la parte IN scende a")
	print("  circa %d token pieni + il resto a tariffa ridotta." % _tok(int(in_tot - fisso)))
