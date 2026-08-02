extends GutTest

## Dei-agenti e Narratore: parti deterministiche (prompt + parsing + invarianti),
## con chat_fn finta, senza rete.

class FakeChat:
	var risposte: Array = []
	var chiamate: int = 0
	func chat(_m: Array, _o: Dictionary) -> Dictionary:
		var i: int = min(chiamate, risposte.size() - 1)
		chiamate += 1
		return risposte[i]

func _ok(c: String) -> Dictionary:
	return {"ok": true, "content": c, "error": ""}

var _p: Pantheon

func before_each():
	_p = Pantheon.carica("res://data/pantheon.json")

# --- Contesto di mondo condiviso (in OGNI agente, nessun placeholder residuo) ---

func test_mondo_in_tutti_gli_agenti():
	var prompts := [
		DioAgente.new().system_prompt(_p.get_dio("atena")),
		Narratore.new(_nomi()).system_prompt(),
		Arbitro.new(_p).system_prompt(),
		Suggeritore.new().system_prompt(),
		Interprete.new([], _p).system_prompt(),
	]
	for sp in prompts:
		assert_string_contains(sp, "età del bronzo", "il blocco mondo dev'essere presente")
		assert_eq(sp.find("{{"), -1, "nessun placeholder residuo")

# --- DioAgente ---

func test_prompt_dio_include_guardrail_e_voce():
	var ag := DioAgente.new()
	var sp := ag.system_prompt(_p.get_dio("poseidone"))
	assert_string_contains(sp, "non un assistente")   # guardrail
	assert_string_contains(sp, "Poseidone")
	assert_string_contains(sp, "castigo")             # un suo registro

func test_proposta_valida_parsata():
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"registro":"castigo","intensita":3,"dice":"Il mare non dimentica."}')]
	var p := await ag.proponi(_p.get_dio("poseidone"), {"envelope": {}}, fake.chat)
	assert_eq(p["registro"], "castigo")
	assert_eq(p["intensita"], 3)
	assert_eq(p["dio"], "poseidone")

func test_registro_non_ammesso_diventa_silenzio():
	# 'aiuto' non e' tra i registri di Poseidone: va rifiutato.
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"registro":"aiuto","intensita":2,"dice":"Ti aiuto."}')]
	var p := await ag.proponi(_p.get_dio("poseidone"), {"envelope": {}}, fake.chat)
	assert_eq(p["registro"], "silenzio")

func test_output_malformato_diventa_silenzio():
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok("non so cosa fare")]
	var p := await ag.proponi(_p.get_dio("atena"), {"envelope": {}}, fake.chat)
	assert_eq(p["registro"], "silenzio")

func test_intensita_clampata():
	var ag := DioAgente.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"registro":"aiuto","intensita":9,"dice":"x"}')]
	var p := await ag.proponi(_p.get_dio("atena"), {"envelope": {}}, fake.chat)
	assert_eq(p["intensita"], 3)

# --- Narratore (invariante nessun nome di dio) ---

func _nomi() -> Array:
	var out: Array = []
	for d in _p.tutti():
		out.append(d.nome)
	return out

func test_prompt_omero_ha_le_direttive_di_stile():
	# Lo stile della prosa e' una scelta dell'autore, non un dettaglio: se qualcuno
	# riscrive il prompt e le perde, il test lo dice invece di scoprirlo giocando.
	var sp := Narratore.new(_nomi()).system_prompt()
	assert_string_contains(sp, "PARATASSI")
	assert_string_contains(sp, "arcaismi")
	assert_string_contains(sp, "PROSA")
	assert_eq(sp.find("Conferma di aver compreso"), -1,
		"niente istruzioni meta: Omero deve narrare, non confermare")

func test_narratore_include_la_scena_nel_messaggio():
	# La scena (grounding) deve arrivare a Omero, per non far derivare la narrazione.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({"sintesi": "guardo il mare", "scena": "Antro del ciclope, chiuso da un masso."})
	assert_string_contains(m[1]["content"], "Antro del ciclope")

func test_narratore_include_storia_e_orientamento():
	# Continuita' del discorso + orientamento discreto: storia, ultima voce, luogo/progresso.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({
		"sintesi": "prego", "storia": ["accecato il ciclope", "fuggito dall'antro"],
		"ultima_narrazione": "Il mare si gonfiò contro di te.",
		"luogo": "L'isola di Eolo", "progresso": "mezzo", "morale": "duro",
	})
	var testo: String = m[1]["content"]
	assert_string_contains(testo, "accecato il ciclope")   # storia
	assert_string_contains(testo, "Il mare si gonfiò")     # continuita' immediata
	assert_string_contains(testo, "L'isola di Eolo")       # orientamento (luogo)

func test_narratore_usa_azione_grezza():
	# Omero deve ricevere le parole esatte di Ulisse, per rispondere proprio a quelle.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({"azione": "chiedo udienza al re", "sintesi": "richiesta"})
	assert_string_contains(m[1]["content"], "chiedo udienza al re")

func test_narratore_passaggio_tra_tappe():
	# Il passaggio genera un messaggio dedicato (traversata), non la narrazione normale.
	var nar := Narratore.new(_nomi())
	var m := nar.costruisci_messaggi({"passaggio": {"da": "Ismaro", "a": "la terra dei Lotofagi"}})
	assert_string_contains(m[1]["content"], "PASSAGGIO")
	assert_string_contains(m[1]["content"], "Ismaro")
	assert_string_contains(m[1]["content"], "Lotofagi")

func test_narrazione_pulita_passa():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("Il mare si gonfio' senza ragione, e il vento giro' contro di te.")]
	var testo := await nar.narra({"sintesi": "x"}, fake.chat)
	assert_string_contains(testo, "mare")
	assert_false(nar.nomina_un_dio(testo))

func test_nome_di_dio_scatena_retry():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [
		_ok("Poseidone gonfio' le onde contro di te."),          # nomina: rifiutata
		_ok("Un dio del profondo gonfio' le onde contro di te."), # pulita
	]
	var testo := await nar.narra({"sintesi": "x"}, fake.chat)
	assert_false(nar.nomina_un_dio(testo))
	assert_eq(fake.chiamate, 2)

func test_redazione_ultima_difesa():
	# Se il modello insiste a nominare, il narratore redige il nome.
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("Atena ti guido' la mano.")]  # unica risposta, sempre con nome
	var testo := await nar.narra({"sintesi": "x"}, fake.chat)
	assert_false(nar.nomina_un_dio(testo), "il nome va redatto: %s" % testo)
	assert_string_contains(testo.to_lower(), "un dio")

# --- Omero + spunti in UNA chiamata (il pezzo che risparmia una chiamata per turno) ---

func _risposta_con_spunti() -> String:
	return """Il fumo saliva dalle capanne e il vento lo portava verso il mare.
Nessuno ti fermo', ma qualcosa, in alto, prese nota.

---SPUNTI---
- Richiama i compagni alle navi e riparti
- Offri parte del bottino a chi resta sulla riva
! Grida il tuo nome perche' tutti lo ricordino"""

func test_omero_narra_e_propone_in_una_sola_chiamata():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok(_risposta_con_spunti())]
	var r := await nar.narra_e_suggerisci({"sintesi": "x"}, fake.chat)
	assert_eq(fake.chiamate, 1, "UNA chiamata: e' tutto il punto")
	assert_string_contains(r["narrazione"], "Il fumo saliva")
	assert_false(r["narrazione"].contains("SPUNTI"), "il separatore non va a schermo")
	assert_false(r["narrazione"].contains("Richiama i compagni"), "gli spunti non sono prosa")
	assert_eq(r["spunti"].size(), 3)
	assert_eq(r["spunti"][0]["testo"], "Richiama i compagni alle navi e riparti")
	assert_false(r["spunti"][0]["rischio"])
	assert_true(r["spunti"][2]["rischio"], "il '!' segna lo spunto rischioso")

## Se il modello dimentica il blocco, la narrazione non deve andare persa: gli spunti
## restano vuoti e il LLMManager ripiega su quelli generici.
func test_senza_blocco_resta_la_narrazione():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("Il mare si gonfio' senza ragione.")]
	var r := await nar.narra_e_suggerisci({"sintesi": "x"}, fake.chat)
	assert_string_contains(r["narrazione"], "mare")
	assert_eq(r["spunti"].size(), 0)

## Chi vuole solo la prosa (i passaggi fra le tappe) non deve ritrovarsi il blocco a
## schermo se il modello lo aggiunge lo stesso.
func test_narra_taglia_il_blocco_quando_non_serve():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok(_risposta_con_spunti())]
	var testo := await nar.narra({"passaggio": {"da": "Ismaro", "a": "Eea"}}, fake.chat)
	assert_false(testo.contains("SPUNTI"))
	assert_false(testo.contains("Richiama i compagni"))

## L'invariante vale anche negli spunti: un nome divino li' sarebbe player-facing.
func test_l_invariante_vale_anche_sugli_spunti():
	var nar := Narratore.new(_nomi())
	assert_true(nar.nomina_un_dio("Prega Poseidone perche' plachi le onde"))
	assert_string_contains(nar.redigi("Prega Poseidone perche' plachi le onde").to_lower(), "un dio")

## REGRESSIONE v2.10 -> v2.17. In italiano il DIALOGO si apre con la lineetta. Avendo
## messo "—" fra i marcatori di elenco, ogni battuta di Omero veniva scambiata per uno
## spunto: tagliata dal racconto e trasformata in un bottone. Con una scena molto dialogata
## il racconto restava quasi vuoto — "Omero non scrive".
## Il prompt gli CHIEDE dialoghi "con naturalezza drammatica": era un difetto garantito.
func test_i_dialoghi_con_la_lineetta_restano_nel_racconto():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("""Il re dei Ciconi scese dal colle e ti guardo' a lungo.

— Chi sei tu, che vieni dal mare con le navi cariche?
— Nessuno — rispondesti, e il vento porto' via la parola.""")]
	var r := await nar.narra_e_suggerisci({"sintesi": "x"}, fake.chat)
	assert_string_contains(r["narrazione"], "Chi sei tu", "la battuta e' racconto, non uno spunto")
	assert_string_contains(r["narrazione"], "Nessuno", "e nemmeno la risposta si tocca")
	assert_eq(r["spunti"].size(), 0, "qui di spunti non ce n'erano")

## Una scena TUTTA di dialogo non deve sparire.
func test_una_scena_tutta_dialogata_non_si_svuota():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("""— Fermi ai remi! — gridasti.
— E se ci inseguono? — chiese Euriloco.
— Allora remeremo piu' forte.""")]
	var testo := await nar.narra({"sintesi": "x"}, fake.chat)
	assert_string_contains(testo, "Fermi ai remi")
	assert_string_contains(testo, "remeremo piu' forte")

## Gli spunti veri continuano a funzionare: quelli hanno l'intestazione.
func test_gli_spunti_veri_si_riconoscono_ancora():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok("""Il mare si apri' davanti alle prue.

---SPUNTI---
- Vira verso la costa.
- Tieni il largo e prosegui.
! Sfida il vento gridando il tuo nome.""")]
	var r := await nar.narra_e_suggerisci({"sintesi": "x"}, fake.chat)
	assert_eq(r["spunti"].size(), 3)
	assert_true(r["spunti"][2]["rischio"])
	assert_false(r["narrazione"].contains("Vira verso"))

# --- Regressione: impalcatura del prompt colata nel racconto (uscite VERE di Mistral) ---

## Il modello non ha scritto "---SPUNTI---" ma ha inventato la sua intestazione, ed e'
## perfino rimbalzato l'etichetta ORIENTAMENTO del contesto come se fosse un titolo.
## Col confronto letterale non trovavamo nulla e il blocco finiva a schermo, dentro il
## racconto. Chi gioca legge una storia: li' non deve comparire nessuna impalcatura.
func _uscita_vera_con_orientamento() -> String:
	return """Poi il mare sputo' un pesce morto oltre la poppa, ventre in su.

---
ORIENTAMENTO
Il ritorno si allontana, la spedizione si assottiglia.
---
- Prendi il pesce tra le mani.
- ! Getta il pesce in mare senza toccarlo con le dita.
- Sciacqua le mani nella scia."""

func _uscita_vera_separatore_storto() -> String:
	return """Il re dei Ciconi scende dal colle su un destriero nero. Poi sputa tra le onde.

---
SPUNTI---
! SACRIFICA un capro nero sulle rive del fiume.
- Manda un uomo a chiedere acqua dolce ai villaggi vicini.
- Offri al re il tuo mantello di porpora, e taccia."""

func test_separatore_storto_viene_riconosciuto_lo_stesso():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok(_uscita_vera_separatore_storto())]
	var r := await nar.narra_e_suggerisci({"sintesi": "x"}, fake.chat)
	assert_string_contains(r["narrazione"], "destriero nero")
	assert_false(r["narrazione"].contains("SPUNTI"), "nel racconto non ci va")
	assert_false(r["narrazione"].contains("capro nero"), "gli spunti non sono prosa")
	assert_eq(r["spunti"].size(), 3)
	assert_true(r["spunti"][0]["rischio"], "il '!' segna il rischioso")

func test_etichetta_del_contesto_non_finisce_nel_racconto():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok(_uscita_vera_con_orientamento())]
	var r := await nar.narra_e_suggerisci({"sintesi": "x"}, fake.chat)
	assert_string_contains(r["narrazione"], "pesce morto")
	assert_false(r["narrazione"].contains("ORIENTAMENTO"), "e' un'etichetta interna")
	assert_false(r["narrazione"].contains("---"), "niente barre di separazione nel racconto")
	assert_eq(r["spunti"].size(), 3, "gli spunti si riconoscono anche senza intestazione")

## "- ! Getta..." — il modello combina i due marcatori. Vale come rischioso, e il testo
## non deve conservare i simboli.
func test_marcatori_combinati():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok(_uscita_vera_con_orientamento())]
	var r := await nar.narra_e_suggerisci({"sintesi": "x"}, fake.chat)
	assert_eq(r["spunti"][1]["testo"], "Getta il pesce in mare senza toccarlo con le dita.")
	assert_true(r["spunti"][1]["rischio"])

## Anche chi vuole la sola prosa (i passaggi fra le tappe) non deve vedere l'impalcatura.
func test_la_prosa_da_sola_resta_pulita():
	var nar := Narratore.new(_nomi())
	var fake := FakeChat.new()
	fake.risposte = [_ok(_uscita_vera_con_orientamento())]
	var testo := await nar.narra({"passaggio": {"da": "Ismaro", "a": "Eea"}}, fake.chat)
	assert_string_contains(testo, "pesce morto")
	for scoria in ["ORIENTAMENTO", "SPUNTI", "---", "Prendi il pesce"]:
		assert_false(testo.contains(scoria), "residuo nel racconto: %s" % scoria)

# --- Suggeritore (spunti d'azione player-facing) ---

func test_prompt_suggeritore_include_guardrail():
	var s := Suggeritore.new()
	assert_string_contains(s.system_prompt(), "non un assistente")

func test_suggeritore_parsa_tre_spunti():
	var s := Suggeritore.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"spunti":[{"testo":"Piega ai remi","rischio":false},{"testo":"Prega chi veglia sugli astuti","rischio":false},{"testo":"Sfida il mare","rischio":true}]}')]
	var sp := await s.suggerisci({"episodio": "il mare"}, fake.chat)
	assert_eq(sp.size(), 3)
	assert_eq(sp[0]["testo"], "Piega ai remi")
	assert_true(sp[2]["rischio"], "il terzo e' marcato rischioso")

func test_suggeritore_taglia_a_tre():
	var s := Suggeritore.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"spunti":[{"testo":"a"},{"testo":"b"},{"testo":"c"},{"testo":"d"}]}')]
	var sp := await s.suggerisci({}, fake.chat)
	assert_eq(sp.size(), 3, "al massimo 3 spunti")

func test_suggeritore_malformato_vuoto():
	var s := Suggeritore.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok("non so proprio")]
	var sp := await s.suggerisci({}, fake.chat)
	assert_eq(sp, [], "output inservibile -> vuoto (il manager mette i generici)")

# --- Cronista (memoria rotolante della vicenda) ---

func test_cronista_prompt_e_messaggi():
	var c := Cronista.new()
	assert_string_contains(c.system_prompt(), "non un assistente")  # guardrail
	assert_string_contains(c.system_prompt(), "età del bronzo")     # mondo
	var m := c.costruisci_messaggi({
		"precedente": "Ulisse lasciò Troia.",
		"fatti": ["- Ulisse: «saccheggio» → i Ciconi contrattaccarono"],
		"luogo": "Ismaro",
	})
	assert_string_contains(m[1]["content"], "Ulisse lasciò Troia")
	assert_string_contains(m[1]["content"], "Ciconi contrattaccarono")

func test_cronista_ritorna_riassunto():
	var c := Cronista.new()
	var fake := FakeChat.new()
	fake.risposte = [_ok("Lasciata Troia, Ulisse saccheggiò Ismaro e perse uomini.")]
	var r := await c.aggiorna({"precedente": "", "fatti": ["- x"]}, fake.chat)
	assert_string_contains(r, "Ismaro")

func test_cronista_errore_ritorna_vuoto():
	# Se l'LLM non risponde si tiene il riassunto precedente (nessuna perdita di memoria).
	var c := Cronista.new()
	var fake := FakeChat.new()
	fake.risposte = [{"ok": false, "content": "", "error": "giu'"}]
	assert_eq(await c.aggiorna({"precedente": "vecchio", "fatti": []}, fake.chat), "")

func test_agenti_ricevono_la_cronaca():
	# La memoria arriva a Omero, al Suggeritore e ai dei.
	var cron := "Ulisse ha accecato il ciclope ed è fuggito."
	var mo := Narratore.new(_nomi()).costruisci_messaggi({"cronaca": cron, "sintesi": "x"})
	assert_string_contains(mo[1]["content"], "accecato il ciclope")
	var ms := Suggeritore.new().costruisci_messaggi({"cronaca": cron})
	assert_string_contains(ms[1]["content"], "accecato il ciclope")
	var md := DioAgente.new().costruisci_messaggi(_p.get_dio("poseidone"), {"cronaca": cron, "envelope": {}})
	assert_string_contains(md[1]["content"], "accecato il ciclope")

# --- Arbitro (Zeus) ---

func _proposte_conflitto() -> Array:
	return [
		{"dio": "atena", "registro": "aiuto", "intensita": 2, "dice": "Lo difendo."},
		{"dio": "poseidone", "registro": "castigo", "intensita": 3, "dice": "Che il mare lo prenda."},
	]

func test_arbitro_verdetto_valido():
	var arb := Arbitro.new(_p)
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"attore":"poseidone","registro":"castigo","intensita":2,"dice":"Il mare avra il suo pegno, ma non la vita."}')]
	var v := await arb.decidi(_proposte_conflitto(), fake.chat)
	assert_eq(v["attore"], "poseidone")
	assert_eq(v["registro"], "castigo")
	assert_eq(v["intensita"], 2, "Zeus puo' ridurre l'intensita'")

func test_arbitro_attore_non_in_campo_va_in_fallback():
	# Zeus nomina un dio che non era in campo: verdetto rifiutato -> fallback (piu' intensa).
	var arb := Arbitro.new(_p)
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"attore":"circe","registro":"trappola","intensita":3,"dice":"x"}')]
	var v := await arb.decidi(_proposte_conflitto(), fake.chat)
	assert_eq(v["attore"], "poseidone", "fallback: la proposta piu' intensa")

func test_arbitro_malformato_va_in_fallback():
	var arb := Arbitro.new(_p)
	var fake := FakeChat.new()
	fake.risposte = [_ok("Decido io e basta.")]
	var v := await arb.decidi(_proposte_conflitto(), fake.chat)
	assert_eq(v["attore"], "poseidone")
	assert_eq(v["registro"], "castigo")

# --- Un dio che si desta deve almeno COMMENTARE ---

## «Gli dèi tendono a destarsi ma dire poco»: nella Vista Olimpo comparivano righe come
## «Poseidone si desta.» e nient'altro. Due cause, entrambe nostre.
##
## La prima: se il modello sbaglia il registro (ne inventa uno, o non e' fra i suoi), si
## ripiegava su silenzio BUTTANDO VIA la battuta. Il dio aveva parlato benissimo e la sua
## voce spariva per un errore di etichetta.
func test_una_battuta_buona_non_si_perde_per_un_registro_sbagliato():
	var ag := DioAgente.new()
	var dio := PantheonManager.get_dio("poseidone")
	var fake := FakeChat.new()
	fake.risposte = [_ok('{"registro":"maremoto","intensita":2,"dice":"Il mare non dimentica."}')]
	var p := await ag.proponi(dio, {}, fake.chat)
	assert_eq(String(p["registro"]), "silenzio", "un registro inventato non si applica")
	assert_eq(String(p["dice"]), "Il mare non dimentica.", "ma la voce resta")

## La seconda: il prompt invitava a tacere («dice: "" se taci»). Ora distingue AGIRE dal
## PARLARE — si puo' non agire e commentare lo stesso.
func test_il_prompt_chiede_sempre_una_battuta():
	var sp := DioAgente.new().system_prompt(PantheonManager.get_dio("atena"))
	assert_false(sp.contains('"" se taci'), "non si invita piu' al silenzio muto")
	assert_string_contains(sp.to_lower(), "commenta", "anche chi non agisce dice la sua")
