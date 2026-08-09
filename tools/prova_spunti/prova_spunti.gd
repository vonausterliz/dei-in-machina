extends SceneTree

## GLI APPIGLI: BASTA LA CHIAMATA DI OMERO, O NE SERVE UNA DEDICATA?
##
## E' la domanda dietro il limite di costo `spunti_separati`. I tre appigli sotto la
## narrazione possono nascere in due modi:
##
##   COMBINATO   Omero narra E li propone nella stessa risposta (blocco ---SPUNTI---).
##               Costa ZERO chiamate: sono righe in piu' in una risposta che ci sarebbe
##               comunque. E' il modo del profilo Frugale.
##   DEDICATO    il Suggeritore li chiede a parte, con un prompt tutto suo che ha gia' la
##               scena narrata. Costa UNA chiamata per turno, circa 72 su una partita
##               intera: il singolo limite piu' caro da togliere. E' il modo del profilo
##               «Senza vincoli».
##
## L'argomento a favore del dedicato e' di QUALITA': «sono piu' mirati, perche' l'agente che
## li scrive non sta contemporaneamente cercando di essere un poeta». L'argomento contro e'
## che rifa' un lavoro gia' fatto. Nessuno dei due si decide leggendo il codice: dipende da
## cosa il modello produce davvero.
##
## Questo strumento glielo chiede. Per ogni scena mette i due modi UNO ACCANTO ALL'ALTRO —
## stesso contesto, stesso modello, stesso seme — e conta cio' che conta: quanti appigli
## SOPRAVVIVONO al filtro vero del gioco (`GameManager.spunti_da_mostrare`, che scarta
## impalcatura, anacronismi, cose fuori tempo e bivi, e rammenda i buchi con gli appigli
## della tappa). Un appiglio che il filtro butta non e' arrivato al giocatore: non conta.
##
## Uso:
##   tools/godot/godot4 --headless --path . --script res://tools/prova_spunti/prova_spunti.gd
##   ... -- <profilo> <quante_scene>       (es. "-- 1_ollama 4"; predefinito: 1_ollama, tutte)
##
## Va SEMPRE contro il modello vero, ignorando il flag mock: e' la parte non deterministica
## del mandato di auto-verifica (CLAUDE.md, punto 6).
##
## TRAPPOLA, gia' pagata due volte: in modalita' `--script` gli autoload NON sono
## identificatori a compile-time. Nominare `GameManager` qui impedirebbe allo script di
## caricarsi. Si passa da `root.get_node("GameManager")`, a runtime.

const PROVIDERS := "res://config/providers/"
const SEED := 4815162342
const SECONDI_MASSIMI := 1200.0

## Le scene su cui misurare. Sono tappe vere, scelte per essere diverse fra loro: una di
## parola, una con un personaggio che offre qualcosa, una di mostro, una di prigionia.
const SCENE := [
	{"tappa": "troia", "azione": "Ordino ai compagni di caricare il bottino e sciogliere le vele.",
		"narrazione": "Le navi si staccarono dalla riva bruciata, e il fumo di Ilio restò basso sull'acqua come un rimprovero."},
	{"tappa": "ciclope", "azione": "Chiedo al gigante il dono dell'ospite, come vuole l'usanza.",
		"narrazione": "Il gigante non rispose subito. Fece rotolare la pietra contro l'imboccatura, e la luce del giorno divenne una fessura sottile."},
	{"tappa": "eolo", "azione": "Ringrazio il re per l'otre e chiedo licenza di partire.",
		"narrazione": "Eolo posò l'otre di cuoio fra le mani di Ulisse, legato con filo d'argento, e non disse cosa vi avesse chiuso dentro."},
	{"tappa": "circe", "azione": "Chiedo a Circe il nome dell'aroma che brucia nella coppa.",
		"narrazione": "Circe versò il vino e vi mescolò qualcosa che rese l'aria dolce. Sorrise, e attese che le coppe si alzassero."},
	{"tappa": "sirene", "azione": "Faccio tappare le orecchie ai compagni con la cera.",
		"narrazione": "Il vento cadde di colpo, e il mare si fece piatto come una lastra. Da oltre gli scogli venne un principio di canto."},
	{"tappa": "ogigia", "azione": "Dico a Calipso che voglio tornare a casa.",
		"narrazione": "L'isola era bella e non finiva mai. Ulisse sedeva sulla riva a guardare il mare che non lo portava da nessuna parte."},
]

var _t0 := 0.0
var _righe: Array = []

func _init() -> void:
	_avvia.call_deferred()

func _process(_d: float) -> bool:
	if _t0 > 0.0 and (Time.get_ticks_msec() / 1000.0) - _t0 > SECONDI_MASSIMI:
		printerr("[!] tempo scaduto")
		quit(2)
	return false

func _avvia() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	var args := OS.get_cmdline_user_args()
	var nome_profilo: String = args[0] if args.size() > 0 else "1_ollama"
	var quante: int = int(args[1]) if args.size() > 1 else 0

	var profilo := _carica_json("%s%s.json" % [PROVIDERS, nome_profilo])
	if profilo.is_empty():
		printerr("Profilo non trovato: %s%s.json" % [PROVIDERS, nome_profilo])
		quit(1)
		return

	var client := LLMClient.new()
	root.add_child(client)
	client.configura(profilo, OS.get_environment(String(profilo.get("api_key_env", ""))))

	print("\n=== Gli appigli: combinato (gratis) contro dedicato (+1 chiamata) ===")
	print("Provider: %s | modello: %s | seme: %d\n" % [client.base_url, client.model, SEED])

	if not await client.disponibile():
		printerr("Provider non raggiungibile a %s. Ollama è attivo? (`ollama serve`)" % client.base_url)
		quit(1)
		return

	var gm := root.get_node("GameManager")
	var pantheon := root.get_node("PantheonManager")
	var narratore := Narratore.new(pantheon.pantheon.nomi_nascosti())
	var suggeritore := Suggeritore.new()
	var chat := Callable(client, "chat")

	var scene: Array = SCENE.duplicate()
	if quante > 0:
		scene = scene.slice(0, quante)

	for scena in scene:
		await _misura(gm, narratore, suggeritore, chat, scena)

	_riepilogo(scene.size())
	quit(0)

## Una scena, due strade. Stesso contesto, stesso seme: l'unica differenza è chi scrive.
func _misura(gm, narratore: Narratore, suggeritore: Suggeritore, chat: Callable, scena: Dictionary) -> void:
	var tappa := String(scena["tappa"])
	gm.nuova_partita(SEED)
	gm.vai_a_tappa(tappa)
	var luogo: String = gm.viaggio.nome_corrente()
	print("── %s — «%s»" % [luogo, scena["azione"]])

	var ctx := {
		"azione": scena["azione"],
		"sintesi": scena["azione"],
		"scena": gm.scena_corrente(),
		"luogo": luogo,
		"episodio": luogo,
		"cronaca": "",
		"ultima_narrazione": "",
		"progresso": "in mezzo al viaggio",
		"morale": "incerto",
		"svegli": [],
		"verdetto": {},
		"delta": {},
		"impronta": "",
		"momento": "il sole già calava",
	}

	# COMBINATO: la risposta di Omero porta con sé il blocco degli appigli.
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = await narratore.narra_e_suggerisci(ctx, chat, SEED)
	var ms_omero := Time.get_ticks_msec() - t0
	var grezzi_c: Array = r.get("spunti", [])
	var buoni_c: Array = gm.spunti_da_mostrare(grezzi_c)
	var propri_c := _quanti_dal_modello(grezzi_c, buoni_c)

	# DEDICATO: il Suggeritore riparte dalla scena appena narrata.
	ctx["narrazione"] = String(r.get("narrazione", ""))
	t0 = Time.get_ticks_msec()
	var grezzi_d: Array = await suggeritore.suggerisci(ctx, chat, SEED)
	var ms_sugg := Time.get_ticks_msec() - t0
	var buoni_d: Array = gm.spunti_da_mostrare(grezzi_d)
	var propri_d := _quanti_dal_modello(grezzi_d, buoni_d)

	var storti_c := _stampa("combinato (gratis)", grezzi_c, buoni_c, propri_c, ms_omero, true)
	var storti_d := _stampa("dedicato  (+1 chiamata)", grezzi_d, buoni_d, propri_d, ms_sugg, false)
	print("")

	_righe.append({
		"tappa": tappa, "propri_c": propri_c, "propri_d": propri_d,
		"storti_c": storti_c, "storti_d": storti_d,
		"ms_omero": ms_omero, "ms_sugg": ms_sugg,
	})

## LA FORMA, non solo il numero.
##
## Il conteggio dice «pari» e nasconde la differenza vera: Omero, che sta scrivendo da
## poeta, contagia il blocco degli appigli. Ne escono righe di PROSA («Lasciatevi indietro
## l'isola mentre il sole morente dipinge gli scafi rossi»), infiniti («offrirgli altro
## cibo»), plurali («Guardate indietro») — mentre la convenzione del gioco è l'imperativo di
## seconda singolare, come nei dati: «Sguaina il bronzo…».
##
## Quattro difetti OGGETTIVI, cioè riconoscibili senza giudizio: virgolette attorno,
## punto e virgola in coda, più parole di quante il prompt ne conceda, e un primo verbo che
## non è un ordine rivolto a Ulisse. Il resto — se l'appiglio sia *interessante* — non si
## misura qui: si legge.
const PAROLE_MASSIME := 12

func _difetti_di_forma(testo: String) -> Array:
	var t := testo.strip_edges()
	var out: Array = []
	if t.length() >= 2 and t[0] in ["\"", "«", "'"]:
		out.append("virgolette")
	if t.ends_with(";") or t.ends_with(","):
		out.append("punteggiatura")
	if t.split(" ", false).size() > PAROLE_MASSIME:
		out.append("troppo lungo")
	var prima := String(t.split(" ", false)[0] if t != "" else "").to_lower().trim_suffix(",")
	for coda in ["are", "ere", "ire"]:
		if prima.ends_with(coda) and prima.length() > 4:
			out.append("infinito")
			break
	for coda in ["ate", "ete", "ite"]:
		if prima.ends_with(coda) and prima.length() > 4:
			out.append("plurale")
			break
	return out

## Quanti degli appigli MOSTRATI vengono davvero dal modello e non dal rammendo della
## tappa. È il numero che decide: tre appigli a schermo non vogliono dire tre appigli
## generati — i buchi li ricuce `spunti_di_riserva()`, che sono scritti nei dati.
func _quanti_dal_modello(grezzi: Array, mostrati: Array) -> int:
	var dal_modello := {}
	for s in grezzi:
		dal_modello[String(s.get("testo", "")).strip_edges().to_lower()] = true
	var n := 0
	for s in mostrati:
		if dal_modello.has(String(s.get("testo", "")).strip_edges().to_lower()):
			n += 1
	return n

## Stampa il blocco e ritorna quanti appigli SUOI hanno un difetto di forma.
func _stampa(etichetta: String, grezzi: Array, mostrati: Array, propri: int, ms: int, e_omero: bool) -> int:
	var nota := " (la narrazione era comunque da fare)" if e_omero else ""
	var storti := 0
	var righe: Array = []
	for s in mostrati:
		var suo := _e_del_modello(grezzi, s)
		var testo := String(s.get("testo", ""))
		var difetti: Array = _difetti_di_forma(testo) if suo else []
		if not difetti.is_empty():
			storti += 1
		righe.append("      %s %s%s" % [
			"  " if suo else " ↺",   # ↺ = rammendo della tappa
			testo,
			"   ← %s" % ", ".join(difetti) if not difetti.is_empty() else ""])
	print("   %-24s %d generati → %d a schermo, di cui %d suoi (%d storti) · %d ms%s" % [
		etichetta, grezzi.size(), mostrati.size(), propri, storti, ms, nota])
	for r in righe:
		print(r)
	return storti

func _e_del_modello(grezzi: Array, s: Dictionary) -> bool:
	var t := String(s.get("testo", "")).strip_edges().to_lower()
	for g in grezzi:
		if String(g.get("testo", "")).strip_edges().to_lower() == t:
			return true
	return false

func _riepilogo(quante: int) -> void:
	var propri_c := 0
	var propri_d := 0
	var storti_c := 0
	var storti_d := 0
	var ms_sugg := 0
	var pieni_c := 0
	var pieni_d := 0
	for r in _righe:
		propri_c += int(r["propri_c"])
		propri_d += int(r["propri_d"])
		storti_c += int(r["storti_c"])
		storti_d += int(r["storti_d"])
		ms_sugg += int(r["ms_sugg"])
		if int(r["propri_c"]) >= 3:
			pieni_c += 1
		if int(r["propri_d"]) >= 3:
			pieni_d += 1
	print("=== Riepilogo su %d scene ===" % quante)
	print("Appigli propri (non rammendo)   combinato %d/%d · dedicato %d/%d" % [
		propri_c, quante * 3, propri_d, quante * 3])
	print("Scene con tre appigli propri    combinato %d/%d · dedicato %d/%d" % [
		pieni_c, quante, pieni_d, quante])
	print("Appigli STORTI di forma         combinato %d/%d · dedicato %d/%d" % [
		storti_c, propri_c, storti_d, propri_d])
	print("Costo della strada dedicata:    %d chiamate, %.1f s in questa prova" % [quante, ms_sugg / 1000.0])
	print("")
	print("Come si legge: se il combinato riempie le tre righe da solo, la chiamata dedicata")
	print("paga per rifare un lavoro già fatto. Se invece lascia buchi, quei buchi li sta")
	print("ricucendo `spunti_di_riserva()` — appigli scritti nei dati, uguali a ogni partita.")

func _carica_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
