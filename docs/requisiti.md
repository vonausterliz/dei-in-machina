# Requisiti consolidati — Dei in machina

*Stato al 20 agosto 2026 · POC Ciconi · baseline 622 test verdi (59 script)*

Questo documento raccoglie in un posto solo **tutto ciò che il gioco deve fare**, con lo
stato di ciascun requisito verificato **sul codice**, non sul diario di lavoro. Nasce perché
i requisiti erano sparsi fra tre fonti che non si parlavano: il design congelato, le
richieste fatte a voce durante le sessioni di gioco (finite in `STATO_LAVORI.md`), e
comportamenti che esistono solo nel codice senza essere scritti da nessuna parte.

## Come leggere

| Stato | Significato |
|---|---|
| ✅ | Fatto, e c'è un test che lo sorveglia |
| ✔︎ | Fatto, ma **nessun test** lo protegge da una regressione |
| 🟡 | Parziale — la colonna *Note* dice cosa manca |
| ⬜ | Non fatto |
| ⚠️ | **Divergenza dal design**: fatto diversamente, o dichiarato e mai fatto |

**Origine** dice da dove viene il requisito: `D§n` = design doc, sezione n · `U` = richiesta
diretta dell'umano in sessione · `C` = CLAUDE.md (norme di lavoro) · `E` = emerso dal
codice/dal gioco, mai formalizzato prima.

> **Aggiornato il 20 agosto 2026.** ADR-001 supera il vincolo di sequenza canonica per il solo slice Ciconi: il canone resta lore; la run deriva da eventi committed. Il comportamento legacy resta esplicitamente invariato negli altri episodi.

---

## 1. Concept e vincoli di prodotto

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| C-01 | Il giocatore **è Ulisse** e agisce scrivendo in **testo libero**, non scegliendo da un menù | D§2 | ✅ | `main.gd` campo d'azione; `test_turno.gd` |
| C-02 | Gli dèi sono **nascosti**: il giocatore ne subisce gli effetti e può solo dedurne la causa | D§2 | ✅ | Invariante N-01 |
| C-03 | **Nascosto ma leale**: la coerenza vive nel trigger (regola stabile), la varietà nella forma della risposta | D§2 | ✅ | `Pantheon.risveglio` deterministico; `test_risveglio.gd` |
| C-04 | Il mondo e fondato sull'*Odissea*: lore, luoghi e quindici tappe restano contenuto e attrattori, non una sequenza obbligatoria. La run deriva dagli eventi committed | U, ADR-001 | 🟡 | POC iniziale Ciconi; legacy invariato altrove |
| C-05 | Tutto in **italiano** | U | ✔︎ | Testi in `data/testi/`, `data/lingua/`; `prompts/mondo.txt` chiude con «in italiano» |
| C-06 | **Nessuna dipendenza nuova** senza motivarla: solo i built-in di Godot | C | ✅ | Anche il lettore di shapefile è scritto a mano (`tools/coste/`) |
| C-07 | **Nessun segreto nel repo**: le chiavi API vivono fuori (env o preferenze utente) | C | ✅ | `llm_manager.gd::_leggi_chiave`; `.gitignore` |
| C-08 | Il **costo** è un vincolo di progetto, non un dettaglio: sul tier gratuito meno chiamate batte più concorrenza | E | ✅ | `tools/stima_costo/`; ~450 chiamate e ~1,03 M token a partita |

---

## 2. La macchina del turno

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| T-01 | Ogni turno segue la FSM: resa dei conti → interpretazione → vaglio → validazione → risveglio → deliberazione → arbitrato → applicazione → scavalcamento → narrazione → esito → avanzamento | D§8 | ✅ | `game_manager.gd::esegui_turno`; `fsm_path` nella traccia |
| T-02 | L'**Interprete** traduce il testo libero in un envelope JSON del vocabolario **chiuso** | D§8, `contratto_interprete.md` | ✅ | `scripts/llm/interprete.gd`; `test_interprete.gd`, `test_contratto.gd` |
| T-03 | Output LLM malformato non rompe mai il turno: ogni agente ha un **fallback valido** | C | ✅ | `test_agenti_llm.gd` |
| T-04 | Le chiamate LLM sono **async** | C | ✅ | Tutte coroutine, in entrambi i percorsi (mock e reale) |
| T-05 | Un **seme** rende la partita riproducibile | C, D§7 | ✅ | `nuova_partita(seed)`; `_rng.seed` |
| T-06 | Una transizione avviene solo mediante un evento di movimento validato o una conseguenza causale committed; tag, tempo e canone non bastano | U, ADR-001 | 🟡 | POC Ciconi; `Viaggio` legacy altrove |
| T-07 | Morte e incapacita derivano soltanto da un `ValidatedOutcome` committed; la sorte canonica e rischio/attrattore, non evento schedulato | U, ADR-001 | 🟡 | POC Ciconi; morti legacy altrove |
| T-08 | Fra due tappe Omero narra la **traversata** | E | ✅ | Nella stessa voce atomica del turno; `passaggio {da,a,causa}` nel `QuadroNarrativo`, nessuna seconda chiamata |

---

## 2-bis. Mondo, lore e causalita

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| W-01 | Lore e GameState sono distinti; un evento del poema non e automaticamente un fatto della run | ADR-001 | 🟡 | POC Ciconi |
| W-02 | Gli eventi canonici diventano fatti solo dopo validazione e commit | ADR-001 | 🟡 | POC Ciconi |
| W-03 | Solo world/rule engine modifica il GameState; gli LLM non committano fatti | U | 🟡 | POC Ciconi |
| W-04 | Azioni emergenti sono risolte con primitive e regole generali, non rami per frase | U | 🟡 | POC Ciconi |
| W-05 | World truth, knowledge e belief sono stati distinti e con provenance | U | 🟡 | POC Ciconi |
| W-06 | Risorse, ferite, morti, agreement, relazioni e knowledge persistono dopo commit | U | 🟡 | POC Ciconi |
| W-07 | Un attrattore puo suggerire opportunita ma non aggira precondizioni o muta lo stato | ADR-001 | 🟡 | POC Ciconi |
| W-08 | Ogni movimento ha origine, destinazione, causa ed evento autorizzante | ADR-001 | 🟡 | POC Ciconi |

---

## 3. Gli dèi come agenti

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| G-01 | Tutti gli dèi del poema, in due fasce: **persistenti** (sempre in ascolto) e **locali** (solo alla loro tappa) | D§3 | ✅ | 13 dèi in `data/pantheon.json`; `test_pantheon.gd` |
| G-02 | Un dio si desta **solo** per un suo trigger: azione (tag), evento di mondo, o invocazione diretta | D§8 | ✅ | `Pantheon.risveglio`; `test_risveglio.gd` |
| G-03 | Un persistente **non innescato resta silente** (altrimenti il segnale non è deducibile) | D§8 | ✅ | Deciso in Fase 2 contro l'esempio illustrativo dei dati |
| G-04 | Un dio può **dormire** finché un certo evento non è accaduto (Poseidone fino all'accecamento) | U (v2.26) | ✅ | `dio.dorme_finche` + `stato.eventi_accaduti`; `test_dei_che_dormono.gd` |
| G-05 | Gli **eventi accaduti restano accaduti**, per sempre | U (v2.26) | ✅ | `episodio.emette_su_tag` → `eventi_accaduti` |
| G-06 | L'invocazione è riconosciuta anche per **epiteto allusivo** e per **parafrasi** | U (Fase 2.1) | ✅ | Tre livelli in `_risolvi_invocazione`; `test_invocazione_allusiva.gd` |
| G-07 | Il dio sceglie **in carattere** registro, intensità e una battuta; i registri sono vincolati al suo profilo | D§5 | ✅ | `dio_agente.gd`; `test_agenti_llm.gd` |
| G-08 | Ogni dio ha un **anti-pattern**: cosa non direbbe mai | U (v2.26) | ✅ | 13/13; `test_pantheon.gd` |
| G-09 | Ogni dio ha un **antefatto**: cosa ricorda di prima della storia (Troia, i conti aperti) | U | ✅ | 13/13; `test_memoria_dei.gd` |
| G-10 | Ogni dio ha un **simbolo** (lettere greche) mostrato accanto al nome | U (v2.23) | ✅ | 13/13; niente emoji — il font non ne ha i glifi |
| G-11 | Gli dèi si **parlano fra loro**: chi è in campo rilegge gli altri e ribatte | U (v2.27) | ✅ | `_repliche`, tetto `MAX_REPLICHE = 2`; `test_dialogo_olimpo.gd` |
| G-12 | Se puniscono e aiutano insieme, **Zeus arbitra** e chiude con parole sue | D§5 | ✅ | `arbitro.gd`; `_verdetto_in_chat`; `test_agora.gd` |
| G-13 | Senza contesa il verdetto è **deterministico** (la proposta più intensa) | D§8 | ✅ | `_arbitra` |
| G-14 | Il **capriccio**: il registro può essere un dono avvelenato | D§2 | ✔︎ | `dono_avvelenato` nei dati, `trappola` fra i registri |
| G-15 | **Filtro di ritmo**: non tutti gli idonei reagiscono ogni turno (credibilità + budget) | D§8 | ⬜ | Mai implementato. Oggi reagiscono *tutti* gli innescati |
| G-16 | La volontà che passa si vede **come gesto di chi la spunta**, non annunciata da un narratore | U (v2.33) | ✅ | `gesto.gd`, campo `gesto` del dio, ripiego in `olimpo/gesti`; `test_gesto.gd`, `test_agora.gd` |

---

## 4. La ciurma

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| U-01 | I compagni sono quelli **nominati nell'Odissea**, con carattere come lo delinea Omero | U | ✅ | 6 in `data/ciurma.json`; `test_ciurma.gd` |
| U-02 | I compagni **non sono nascosti**: Omero può nominarli | U | ✅ | Esclusi dal controllo di reticenza |
| U-03 | La chat della ciurma è **interattiva**: Ulisse ci scrive davvero | U | ✅ | `_on_ciurma_invio`; `test_gui.gd` |
| U-04 | Ulisse può rivolgersi a **uno per nome** (o con `@`); risponde quello | U | ✅ | `Ciurma.destinatari_in`; `test_ciurma.gd` |
| U-05 | **Chi muore tace**: la voce sparisce dalla conversazione | U | ✅ | `Ciurma.fai_cadere`; `test_ciurma.gd` |
| U-06 | Parlare ai compagni **non fa girare il mondo**: è un *beat*, costa una chiamata | U (v2.9) | ✅ | `esegui_beat`; `test_ciurma.gd` |
| U-07 | Le parole dette a bordo **non si perdono**: il turno successivo le consegna a Interprete, dèi e Omero | U (v2.9) | ✅ | `parole_ai_compagni`; `_testo_per_interprete` |
| U-08 | Due beat di fila non hanno lo **stesso interlocutore** | E | ✅ | Rotazione deterministica; `test_ciurma.gd` |
| U-09 | Un **gesto** compiuto nel mondo non diventa una battuta in bocca a Ulisse | U (v2.8) | ✅ | `test_ciurma.gd` |
| U-10 | Ogni compagno ha un **anti-pattern** e un **simbolo** | U (v2.26) | ✅ | 6/6; `test_ciurma.gd` |
| U-11 | **Memoria per compagno** (chi ha perso un fratello, chi ha visto Polifemo divorare i suoi) | U | 🟡 | Riceve `cronaca` + `scena`, ma **non ha un taccuino privato** come gli dèi |

---

## 5. Narrazione e reticenza

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| N-01 | **Omero non nomina MAI un dio *nascosto*.** Vale per narrazione, diario, spunti, cronaca | D§2, C | ✅ | Prompt + post-controllo + **redazione** (`Narratore.redigi`); `test_agenti_llm.gd`. Ristretto ai soli nascosti in v2.45, vedi N-02 |
| N-02 | **Chi Ulisse incontra ha un nome, e lo si dice.** L'invariante nasconde *chi muove i fili dall'Olimpo*, non i personaggi in scena | U (v2.45) | ✅ | Valeva su tutte e tredici le voci del pantheon. Il conto, dal tracciato del 6 agosto 2026: **10 ritentativi di Omero su 43 chiamate (23%)**, e in tutti e dieci il nome vietato era il personaggio presente — Eolo alle sue isole (turni 15-19), Circe a casa sua (23-28), **mai un olimpio**. È anche il «doppio passaggio ai Lestrigoni»: `#195`/`#196` non erano due transizioni (`viaggio.avanza()` ha un solo chiamante) ma il ritentativo di `Narratore.narra()`, `msg=2` → `msg=3`. Il ritentativo fallisce quasi sempre — come si narra l'isola di Eolo senza dire Eolo? — quindi interviene `redigi()`, e a schermo è arrivato «Chiedi a **un dio** il nome dell'aroma» mentre Circe versava il vino. **Fatto:** campo `nascosto` in `pantheon.json`, dichiarato voce per voce (`Dio.nascosto`, default **true**: nel dubbio si nasconde); `Pantheon.nomi_nascosti()` alimenta il Narratore; la distinzione è scritta in `prompts/mondo.txt`, incluso da tutti e sette gli agenti, e nelle quattro istruzioni per-agente. **Dichiarato, non dedotto dalla tappa corrente:** Ermes ha `episodio: circe` perché è lì che interviene, ma la sua è un'intromissione olimpia. Il validatore pretende il campo (letto dal **JSON grezzo**: nel `Dio` tipizzato il default c'è già) e avvisa se il `dio_locale` di una tappa è nascosto. `test_dei_nascosti.gd`, 7 controlli, fra cui la coerenza fra dato e prompt |
| N-02 | Il **guardrail anti-assistente** è nel prompt di **ogni** agente, anche futuri | D§2, C | ✅ | Verificato da test su tutti gli agenti |
| N-03 | Omero lascia intravedere la causa con l'**impronta** del dio, mai col nome | D§2 | ✔︎ | `impronta` passata nel contesto |
| N-04 | I **system prompt stanno in file esterni**, non nel codice | C | ✅ | `prompts/*.txt`; nessuna stringa di prompt in `.gd` |
| N-05 | L'**impalcatura del prompt** non deve mai comparire nel racconto | U (v2.10, v2.17) | ✅ | `_prosa()` + riconoscimento tollerante; `test_agenti_llm.gd` |
| N-06 | Il **diario** è reticente, con marcatore d'esito ambiguo (andò male / parve giovare / neutro) | D§4 | ✅ | `Delta.marcatore_diario` |
| N-07 | Fuori-mondo **Omero tace**: al giocatore va solo il richiamo | E (v2.20) | ✅ | Chiedere al modello di «non narrare» non funzionava |
| N-08 | La narrazione porta un **marcatore temporale** quando il momento cambia | U (v2.25) | ✅ | `momento_corrente()` |
| N-09 | **Entità persistenti**: personaggi e oggetti introdotti da Omero non devono sparire il turno dopo | U | 🟡 | Mitigato da `scena` (ancora per tappa) e `ultima_narrazione`, ma **non c'è un registro delle entità** introdotte a runtime |
| N-10 | Omero riceve un **quadro narrativo autorevole** che distingue stato prima, azione, conseguenze deterministiche, stato dopo, momento, fatti ammessi/vietati ed eventuale passaggio unico (`da/a/causa`) | U (fase 4, 15 agosto 2026) | ✅ | «Autorevole» significa stato della partita, non fedeltà forzata al poema. Contratto puro `QuadroNarrativo`, prompt dedicato, compatibilità mock e test in `test_quadro_narrativo.gd` |
| N-11 | Azione, conseguenze e cambio tappa sono narrati in una **transizione atomica**, senza seconda partenza/secondo approdo | U (fase 5, 15 agosto 2026) | ✅ | `GameManager` applica `Viaggio`, costruisce/valida prima-dopo-passaggio e chiama Omero una volta; Main non appende più traversata/intro. `test_transizione_atomica.gd`, `test_flusso_narrativo_progressivo.gd` |

---

## 6. Gli appigli (spunti)

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| S-01 | Tre appigli contestuali sotto la narrazione; la scrittura libera resta la quarta via | D§4 | ✅ | `_mostra_spunti` |
| S-02 | Nascono nella **stessa chiamata** di Omero (costo zero) | E (v2.19) | ✅ | `narrazione_e_spunti` |
| S-03 | Nessun appiglio **anacronistico** | U | ✅ | `filtra_spunti` → `e_anacronistico`; `test_filtro_spunti.gd` |
| S-04 | Nessun appiglio **fuori tempo** («apri l'otre» prima che Eolo lo dia) | U | ✅ | `episodio.non_ancora`; `test_spunti_coerenti.gd` |
| S-05 | Nessuna **impalcatura** fra gli appigli (`---SPUNTI`, `ORIENTAMENTO`) | U | ✅ | `_e_impalcatura` |
| S-06 | **Niente appigli generici**: solo frasi che sanno dove ti trovi | U (v2.26) | ✅ | `spunti_di_riserva` per tappa, 15/15. Il generico è stato *eliminato*, non affiancato |
| S-07 | **Il gioco non può rifiutare ciò che ha appena proposto** | U (v2.22) | ✅ | `gia_proposto()` salta il vaglio LLM; `test_spunti_coerenti.gd` |
| S-10 | **La promessa non ha clausole di costo.** Un'impostazione decide quanto il gioco *spende*, mai se il gioco si *contraddice* | E (v2.45) | ✅ | S-07 aveva una clausola: `and not Costi.acceso("vaglia_sempre")`. Col profilo «Senza vincoli» la promessa si spegneva e il gioco bocciava i propri suggerimenti — provato sul campo il 6 agosto 2026: tre appigli generati dal gioco, cliccati, respinti come anacronismi. **Il test che copriva il punto era complice**: asseriva i due *flag* invece dell'invariante osservabile, e restava verde col difetto (la stessa trappola di I-21). **Fatto:** la clausola è sparita; col profilo che lo chiede il vaglio parte ancora, ma solo per *guardare* — un disaccordo finisce in `app-*.log` e dice che il prompt di Omero è da rivedere. `GameManager._sorveglia_appiglio()`, `LLMManager.mock_vaglio_classe` (l'unico modo di mettere sotto prova un vaglio che boccia, a mock). 3 controlli nuovi in `test_spunti_coerenti.gd`, 1 riscritto in `test_costi.gd` |
| S-11 | **La forma dell'appiglio è un ordine rivolto a Ulisse**, e la strada gratis vale quella a pagamento | E (v2.46) | ✅ | Misurato col modello vero, non stimato (`tools/prova_spunti/`, mistral-small3.2 in locale, 6 scene, 4 giri). **Prima:** la strada gratis (Omero narra e propone nella stessa risposta) dava **11 appigli storti su 13**, la dedicata 1 su 16 — punto e virgola della prosa in coda, virgolette, infiniti («Offrire vino»), plurali («Guardate indietro»), **terza persona** («Promette a Calipso di tornare»), cioè racconto invece di una scelta offerta a chi gioca. Omero sta scrivendo da poeta e contagia l'elenco: era esattamente la ragione per cui esisteva il limite di costo `spunti_separati`. **Fatto:** regole di FORMA con esempi contrastivi nei due prompt (`omero_system.txt`, `suggeritore_system.txt`), blocco degli appigli reso obbligatorio quando c'è un'azione, e ripulitura deterministica in `Viaggio.ripulisci()` — virgolette attorno, grassetto markdown, punto e virgola e virgola in coda — in un posto solo, quello che attraversano tutte e due le strade. **Dopo:** 16 appigli su 18 per entrambe, 3 storti contro 2: pari. Quindi `spunti_separati` è **spento anche nel profilo «Senza vincoli»** — restava una chiamata per turno, ~72 a partita, per rifare un lavoro già fatto. Resta accendibile: la misura vale per un modello solo. `test_filtro_spunti.gd`, 7 controlli nuovi |
| S-12 | L'**impalcatura in grassetto** non diventa un appiglio | E (v2.46) | ✅ | «SPUNTI**» è comparso fra gli appigli a schermo: il modello scrive l'intestazione in grassetto markdown (`**---SPUNTI---**`), il lettore di Omero sbuccia i marcatori davanti e lascia gli asterischi in coda. Il riconoscitore d'impalcatura conosceva solo trattini. **Nessun test poteva vederlo**: nel mock il modello non scrive markdown — l'ha trovato la misura contro il modello vero, che è il motivo per cui esiste. `Viaggio.e_impalcatura()` ora conta asterischi, cancelletti e trattini bassi come ponteggio; e un appiglio VERO in grassetto perde il grassetto, non la frase |
| S-08 | **Bivi veri** per i momenti che lo meritano (Scilla o Cariddi? apri l'otre?) | D§4, U (v2.30) | ⬜ | **Revocato dall'umano in v2.34**: il surrogato col campo `rischio` (‡ + conferma) non reggeva la lettura fra tre frasi omeriche. Ora `rischio: true` vuol dire *non proporlo*. Chi vuole rischiare scrive nel campo libero. `test_bivi.gd` |
| S-09 | Un bivio si riconosce a vista, prima di cliccarlo | U (v2.30) | ⬜ | Decaduto con S-08: non ci sono più bivi da riconoscere |
| S-10 | Rischiare amplifica **anche il bene**: è un bivio, non una penalità mascherata | U (v2.30) | ✅ | La REGOLA resta e resta sorvegliata (`forza_con_rischio`, `esegui_turno(…, rischio)`): è dove si attaccheranno i bivi veri, se torneranno. `test_bivi.gd` |
| S-11 | Le due chat (Olimpo, Ciurma) sono **incastrate nella pagina**, non finestre a sé | U (v2.34) | ✅ | `pannello_chat.gd`, colonna destra; `test_gui.gd` |
| S-12 | Carta e chat hanno una **lente** che le mostra grandi quanto la schermata | U (v2.34) | ✅ | `lente.gd`; `test_gui.gd` |
| S-13 | «La tua condizione» sta **su una riga sola in fondo**; il diario di bordo non è più a schermo | U (v2.34) | ✅ | `_riga_condizione`; i dati del diario restano nello stato |
| S-14 | Intestazione: **logo**, titolo, sottotitolo di seguito, comandi a destra; niente versione né modello | U (v2.34) | ✅ | `_intestazione`, `marchio.gd`; versione in Settings › Informazioni |
| S-15 | Un brano di musica per **ogni momento del gioco**, configurabile senza toccare il codice | U (v2.34) | ✅ | `data/musica.json`, `colonna_sonora.gd`; `test_musica.gd`. Oggi solo lo splash ha un brano |

---

## 7. Memoria

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| M-01 | Ogni dio mantiene memoria di **tutto** ciò che succede, e anche di **prima** della storia | U (v2.12) | ✅ | `antefatto` + taccuino privato; `test_memoria_dei.gd` |
| M-02 | Oltre i 5 ricordi recenti si **condensa**, non si cancella | U (v2.13) | ✅ | `memoria_vecchia`; riassunto in GDScript, **zero chiamate LLM** |
| M-03 | Il ricordo registra **come è andata** (prevalso / respinto / agito di nascosto) | E | ✅ | `_annota_nella_memoria`, scritto dopo il verdetto |
| M-04 | Una **cronaca** condivisa a costo costante, aggiornata ogni N turni | E | ✅ | `cronista.gd`; ~120 parole |
| M-05 | La cronaca è **ripulita dai nomi divini** (finisce anche a Omero) | E | ✅ | `aggiorna_cronaca` riusa il controllo del Narratore |
| M-06 | Continuità del discorso fra turni | E | ✅ | `ultima_narrazione` + `_storia_recente` |

---

## 8. Validazione e ammonizione

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| V-01 | L'input fuori contesto è gestito **in modo diegetico**, mai con un box d'errore | D§6 | ✅ | `validazione.gd`; `test_ammonizione.gd` |
| V-02 | Scala a gradini: richiamo → smarrimento (l'animo cala) → **follia** (fine partita) | D§6 | ✅ | Soglie in `bilanciamento.json` |
| V-03 | Le ammonizioni **decadono** se torni a giocare sensato | D§6 | ✅ | `turni_puliti` + `decadimento_ogni` |
| V-04 | Scala **dolce**: qui il falso positivo uccide | D§6 | ✅ | Primo scivolone senza danno |
| V-05 | **Secondo parere** LLM dedicato per gli anacronismi che nessuna lista prevede | E | ✅ | `verifica_plausibilita`, una domanda secca a temp 0 |
| V-06 | La salvaguardia **deterministica** (marcatori moderni) non si scavalca mai | U (v2.22) | ✅ | Vale anche sugli spunti già offerti |

---

## 9. Politica divina

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| P-01 | Un dio bocciato può **scavalcare Zeus** di nascosto (raro) | D§2 | ✅ | `tenta_scavalcamento`; `test_politica_divina.gd` |
| P-02 | Il **sospetto** di Zeus sale ogni turno; alla soglia scopre il colpevole | D§5 | ✅ | `resa_dei_conti` |
| P-03 | La faida ricade su Ulisse **di rimbalzo**, senza che c'entri | D§2 | ✅ | `rimbalzo_ulisse` |
| P-04 | **Coalizioni** rare e instabili, con un canale di gruppo | D§5 | ✅ | `aggiorna_coalizioni`; `test_coalizioni.gd` |
| P-05 | **Piani** a più turni che *inclinano* la reazione senza sostituirla | D§5 | ✅ | `modula_per_piano` |
| P-06 | La **tracotanza** oltre soglia si paga: chi punisce colpisce più forte | E | ✅ | `modula_per_hybris` |
| P-07 | Coalizioni e piani restano **modulazione di sfondo**, mai la causa dominante | D§5 | ✅ | Modulano l'intensità, mai il registro |

---

## 10. Interfaccia

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| I-01 | Schermata giocatore sullo stile del mockup (mare/osso/oro, serif) | D§4 | ✅ | `main.gd`; `mockup/odissea_interfaccia.html` |
| I-02 | Stat di Ulisse visibili: metis, animo, ciurma, hybris. **Nessun pannello divino** | D§4 | ✅ | Il resto resta muto |
| I-03 | **Vista Olimpo**: chat in **sola lettura**, gli dèi si parlano | U | ✅ | `test_agora.gd`, `test_gui.gd` |
| I-04 | **Vista Ciurma**: chat **interattiva** | U | ✅ | vedi §4 |
| I-05 | Le due viste **non si mescolano** | U (v2.7) | ✅ | `Agora` vista per canale; `test_agora.gd` |
| I-06 | **Distintivo** (avatar) accanto a ogni nome | U (v2.23) | ✅ | `Agora.distintivo` |
| I-07 | Le chat **scorrono da sole** all'ultima riga | U (v2.23) | ✅ | `FinestraTesto.imposta` → `_in_fondo` |
| I-08 | Un **collante temporale** scandisce le tre viste senza numerare i turni | U (v2.23, v2.25) | ✅ | Momento del giorno + azione; `test_collante_temporale.gd` |
| I-09 | Le finestre di servizio **non spariscono** dietro la principale | U (v2.7) | ✅ | `transient` (non `always_on_top`: Godot li vieta insieme) |
| I-10 | **Carta del Mediterraneo** con coste vere, in stile antico, coerente col gioco | U (v2.24, v2.27) | ✅ | Natural Earth, ritagliata sul Mediterraneo del poema |
| I-11 | La posizione di Ulisse è **evidenziata in rosso** | U (v2.27) | ✅ | `C_OXBLOOD` + anello pulsante |
| I-12 | **Splash screen** con logo a tema | U (v2.11) | ✔︎ | `splash.gd`, meccanismo di Anticitera disegnato in codice |
| I-13 | **Log LLM** live con i tempi di ogni chiamata | E | ✔︎ | Segnale `llm_log` |
| I-14 | Scala HiDPI/Retina e ridimensionamento | E | ✔︎ | `content_scale_factor`; le sotto-finestre non lo ereditano, gestite a mano |
| I-15 | **Rotta curva animata** (Bezier) con Ulisse che scivola e lascia la scia | U | ⬜ | Progettata in `STATO_LAVORI.md` §6, mai fatta. Oggi: spezzate, oro pieno per il percorso e punteggiato per il resto |
| I-16 | **Salvare e riprendere** la partita | E, U (v2.30) | ✅ | Menu *Partita* nella GUI, `:salva`/`:carica` in console. `carica_partita` è ora simmetrico a `nuova_partita`; `test_salvataggio.gd` |
| I-17 | Riprendere restituisce **tutto**: chat, diario, caduti, locali della tappa, voce di Omero | U (v2.30) | ✅ | `Agora.to_dict/from_dict`, `Ciurma.riprendi_caduti`, `_accendi_locali`; `test_salvataggio.gd` |
| I-18 | Le viste di **servizio** nascono chiuse, sempre | U (v2.36) | ✅ | Il Log LLM si riapriva da solo per due strade: la geometria ricordava se era aperto, e `_attiva_reale()` lo spalancava — cioè a **ogni** avvio col motore reale in preferenza. La prima cosa che si vedeva del gioco era una finestra di traffico HTTP. Ora `salva_geometria()` non scrive più `aperta`: caduta la ragione, caduto il dato. `test_il_log_llm_nasce_chiuso`, `test_la_geometria_ricorda_dove_non_se` |
| I-19 | **Menu Aiuto** nel gioco: le regole e i problemi frequenti | U (v2.36) | ✅ | Le regole stavano solo nei documenti: chi apre il gioco e non il repository non poteva sapere che gli dèi dormono. Due pagine corte più il rimando ai `.md`; il testo scorre in un `ScrollContainer`, perché a dimensione libera la pagina chiedeva 972 px su una finestra di 1033 e i bottoni finivano fuori. Quattro test in `test_gui.gd` |
| I-20 | I **guai del motore** si dicono in una finestra, non nella narrazione | U (v2.36) | ✅ | Ogni esito finiva in coda al racconto di Omero — riuscita compresa (`[modalità Mistral: dèi e narratore reali…]`, a ogni avvio). Un errore vero aveva lo stesso peso di una battuta e restava indietro appena la narrazione cresceva. Ora un `AcceptDialog` col bottone che **apre** Settings; la narrazione contiene solo narrazione. `test_la_narrazione_non_annuncia_il_motore` |

---

## 11. Strato LLM, provider, operatività

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| L-01 | Layer **provider-agnostico** (formato chat-completions) | D§9 | ✅ | Cambiare provider è cambiare config, non codice |
| L-02 | Il **mock** rende deterministica l'intera macchina, senza rete | C | ✅ | Tutti i 547 test |
| L-03 | Il simulato **non è più uno stato in cui si possa giocare** | U (v2.20, v2.21) | ✅ | Tolto dal menu; resta come motore di test |
| L-04 | **Scelta del modello** dall'interfaccia, ricordata **per provider** | U (v2.20) | ✅ | `test_scelta_modello.gd`. In v2.32 corretto il caso in cui *tornava indietro da sola*: a motore spento `imposta_modello` scriveva nel profilo di Ollama, e il menu si risincronizzava da quello vero, invariato |
| L-05 | L'elenco modelli mostra **solo quelli testuali** | U (v2.20) | ✅ | `escludi_modelli` nel profilo del provider |
| L-06 | **Prova il modello**: verifica separata «il server risponde?» / «il modello genera?» | U (v2.18) | ✅ | Generazione vera da un token: essere elencati non basta |
| L-07 | Il **gateway** è un *trasporto*, ortogonale al provider | U (v2.14) | ✅ | `test_gateway_trasporto.gd` |
| L-08 | Un solo comando avvia il gioco su Linux e macOS, scaricando Godot se manca | U | ✔︎ | `avvia.sh` |
| L-09 | Sincronizzazione con la seconda macchina | U | ✔︎ | `sync-mac.sh` (rsync su chiave SSH), fuori dal repository perché contiene utente e IP. Esclude `.git` e `.git-lavoro`, ma **porta a parte gli hook**: senza, l'altra macchina sarebbe l'unica da cui i dati personali possono ancora uscire |
| L-10 | **Streaming** della narrazione | U | ⬜ | Oggi il turno arriva tutto insieme |
| L-11 | **Parallelizzare** le chiamate degli dèi, dietro un flag di Impostazioni | U (v2.9) | ⬜ | Utile solo *fuori* dal tier gratuito, dove il pavimento non è più req/s. È il knob C7 di `costi.md`, non ancora commutabile |
| L-12 | Provider **OpenRouter**: un endpoint per centinaia di modelli | U (v2.31) | ✅ | `config/providers/6_openrouter.json`. `nome_pieno: true`, perché lì la barra è parte del nome; `test_openrouter.gd` |
| L-13 | I provider si chiamano **col nome del provider**: Ollama, Mistral, Google, OpenAI, Anthropic, OpenRouter | U (v2.32) | ✅ | Si chiamavano col nome di un modello («Gemini 3.5 Flash»), che è la cosa che cambia sotto. I nomi vecchi si traducono (`NOMI_STORICI`); `test_provider.gd` |
| L-14 | **Ollama è un provider come gli altri**, non un motore a parte | U (v2.32) | ✅ | Stava in `llm_config.json`, fuori dall'elenco: per questo col motore su Ollama non si poteva scegliere quale modello installato usare. Ora `1_ollama.json` con `locale: true`; sparisce il selettore «chi dà voce agli dèi», resta un interruttore solo — dèi finti o veri |
| L-15 | **«Aggiorna elenco»** interroga il provider **selezionato**, non il motore acceso | U (v2.32) | ✅ | Chiamava `verifica_provider()`: con Ollama in esecuzione e OpenRouter scelto, mostrava i modelli di Ollama come se fossero di OpenRouter. Ora `elenca_modelli_del_profilo()`, che non genera nulla; `test_provider.gd` |
| L-16 | Ogni provider propone i suoi **modelli curati** senza chiedere nulla alla rete | U (v2.32) | ✅ | `modelli_noti` nel file del provider — niente cache, che invecchia in silenzio. Il predefinito dev'essere fra loro (`test_provider.gd`), e `tools/verifica_modelli/` li confronta col catalogo vero |
| L-17 | I modelli si scelgono **Autore → Modello** quando i nomi hanno la barra | U (v2.32) | ✅ | OpenRouter ne offre 338: un menu piatto non è un elenco, è un muro. `LLMManager.autori/modelli_di`; `test_settings_ui.gd` |
| L-18 | Provider **Anthropic** | U (v2.32) | ✅ | L'unico che non parla del tutto la lingua di OpenAI: `/chat/completions` accetta il Bearer, `/models` pretende `x-api-key`. Risolto con `intestazioni` dichiarate nel profilo, non con un ramo nel client |
| L-19 | **Anthropic passa dal Gateway** come tutti gli altri | U (v2.36) | ✅ | Non era fra i provider di `limiti.json`. Le intestazioni che gli servono (`x-api-key`, `anthropic-version`) le dichiara il dato, col segnaposto `$CHIAVE` dei profili di gioco — nessun ramo «se è Anthropic» nel codice. Porta `"gratuito": false`: lì il Gateway fa da coda, non fa risparmiare, e lo scrive all'avvio |
| L-32 | La finestra Impostazioni **si risincronizza a ogni apertura** | E (v2.41) | ✅ | `_sincronizza()` girava solo in `_ready()`, e lì è troppo presto: la finestra nasce in `_costruisci_ui()`, le preferenze si rileggono la riga dopo. La spunta «Gateway» si fissava sul valore di prima — sul Mac mostrava «no» mentre il gioco ci passava. Ora sta in `_on_apertura()`, il punto obbligato per qualunque strada apra la finestra |
| L-33 | «Salva e applica» **salva e applica** | E (v2.41) | ✅ | Tre bugie con lo stesso messaggio verde: una chiave nuova non veniva applicata se una vecchia era nell'ambiente (impossibile correggerla dalla finestra fatta per correggerla); salvare a campi vuoti **cancellava** le chiavi già salvate; e diceva «salvato» anche se la scrittura falliva. Ora si rilegge prima di dirlo. `test_salva_impostazioni.gd` |
| L-29 | La **regola del Gateway** è una tabella di verità, e ha i suoi test | U (v2.40) | ✅ | «Ollama mai; gli altri solo con la spunta; senza spunta, diretti.» Esisteva a pezzi, sfiorata di lato da qualche test e dichiarata da nessuno. `test_regola_gateway.gd`: le tre righe, più la reversibilità e il caso senza trasporto configurato |
| L-30 | Il **trasporto si ripristina prima del provider** | E (v2.40) | ✅ | `imposta_profilo()` riconfigura il client leggendo `usa_gateway`, e `_ripristina_provider()` lo assegnava DOPO, con un assegnamento diretto: il campo diceva una cosa e il client ne faceva un'altra finché qualcuno non lo riconfigurava per caso. Ora passa da `imposta_gateway()`, che cambia tutti e due insieme |
| L-31 | La migrazione che **accende il Gateway** deve dichiararlo | E (v2.40) | ✅ | La vecchia preferenza `provider_idx: 0` significava «gateway», e la conversione lo accendeva scrivendolo su disco — in silenzio, e per sempre. Chi non ha mai spuntato quella casella non aveva modo di sapere perché ci passava. La deduzione resta, l'omissione no |
| L-25 | Il nome del modello si confronta col catalogo **come lo conosce il provider** | E (v2.39) | ✅ | `_senza_prefisso()` faceva `get_slice("/", 1)`, che non toglie il primo pezzo: restituisce il secondo e butta il resto. Su due segmenti coincidono; su tre — «openrouter/deepseek/deepseek-v4-flash» dietro il Gateway — diventava «deepseek», e il gioco dichiarava «modello non caricato» di un modello presente e funzionante. `modello_atteso()` non porta più l'instradamento: quello serve solo sul filo |
| L-26 | Un modello a **ragionamento obbligatorio** non va bocciato dalla verifica | E (v2.39) | ✅ | Con `max_tokens: 1` DeepSeek V4 spende l'unico token a pensare e torna `content: null`: la prova concludeva «non risponde». Ora il tetto è 64 e il giudizio è sui **token prodotti**, non sul contenuto — che può mancare per una nostra impostazione. `tools/prova_modello_che_ragiona.gd`, con HTTP vero |
| L-27 | Una risposta vuota dice **perché** è vuota | E (v2.39) | ✅ | «Nessun contenuto» è vero e inutile. Tre casi distinti dai dati che il provider manda già: troncata dal nostro tetto, spesa in ragionamento, o davvero muta. Il `grezzo` si consegna anche quando si fallisce: «ha prodotto token senza contenuto» e «non ha risposto» si curano in modi opposti |
| L-28 | Il Gateway non mette in **cache** una risposta inservibile | E (v2.39) | ✅ | Un `200` dice che il provider ha lavorato, non che la risposta serva. Una troncata in cache torna identica per un'ora a ogni ritentativo, senza rete: la stessa `gen-…` per trentacinque secondi, e un modello sano che sembra guasto in modo riproducibile. Sei controlli in `prova_instradamento.py` |
| L-21 | Le **preferenze di chi gioca** non possono essere toccate dalla suite | E (v2.37) | ✅ | `test_gateway_trasporto.gd` chiamava `Impostazioni.dimentica("provider_nome")` sul file **vero**: dopo `./avvia.sh test` il gioco ripiegava sul profilo [0] (Ollama, 24 B) e diventava lentissimo, con `localhost:11434` nel log che somigliava al gateway. Tre sottosistemi innocenti accusati. Ora `DEI_IMPOSTAZIONI` e `DEI_LOG` puntano a una cartella usa-e-getta: nessun test *può* toccarli |
| L-22 | Le **opzioni di chiamata** dichiarate arrivano davvero al provider | E (v2.38) | ✅ | `max_tokens` era fra le opzioni e `chat()` lo buttava: la «prova del modello» chiedeva 1 token e ne generava centinaia. Senza tetto, un modello che ragiona prende decine di secondi e nessuno gli dice di smettere. `test_llm_client.gd` |
| L-23 | Lo **stato di una chiamata** è della chiamata, non del client | E (v2.38) | ✅ | `_n_chiamata`, `_t_inizio` e il Timer del battito erano campi condivisi: con due chiamate in volo (l'elenco modelli parte mentre una chat aspetta) latenza e numero finivano sulla riga sbagliata. Stessa cura dell'HTTPRequest — uno per richiesta |
| L-24 | **Anche le GET** sono traffico, e vanno tracciate | E (v2.38) | ✅ | Elenco modelli, elenco dettagliato, `/stato` del Gateway e ping erano quattro copie della stessa danza, nessuna tracciata: metà del traffico del gioco — tutto quello d'avvio e di Impostazioni — non compariva da nessuna parte. Un solo `_chiedi()` |
| L-20 | Il Gateway **non ripiega mai** su un provider diverso da quello chiesto | E (v2.36) | ✅ | Ripiegava sul predefinito: con Anthropic scelto e non configurato, le chiamate finivano a **Mistral** e l'elenco modelli mostrava quelli di Mistral come suoi. Un errore di configurazione — visibile — diventava la risposta di un altro modello, che non si vede. Ora il provider si dichiara in query string anche sulla chat, e uno sconosciuto è un `400` che dice quali ci sono |

---

## 12. Rigiocabilità ed esiti — **la sezione da guardare**

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| R-01 | **Trigger fissi** fra le partite: la maestria si trasferisce | D§7 | ✅ | La regola del risveglio non dipende dal seme |
| R-02 | **Capricci e umori variabili** a ogni partita, guidati dal seme | D§7 | ✔︎ | `umore` nel registro divino; temperatura del modello |
| R-03 | La causalita e nello stato e negli eventi, non nell'ordine del poema; la rotta canonica e un attrattore | ADR-001 | 🟡 | POC Ciconi; superata la decisione v2.30 per il nuovo slice |
| R-04 | Vittoria: **itaca** | D§11 | ✅ | `_avanza_episodio` |
| R-05 | La **follia** (nonsenso reiterato) porta alla morte | D§11, U (v2.29) | ✅ | `validazione.gd`: la follia resta la *causa* (`classe`), l'esito è `morte`; `test_ammonizione.gd` |
| R-06 | Sconfitta: **ciurma_perduta** | D§11 | ✅ | `_controlla_esito`; raggiungibile da v1.6 (il castigo al massimo costa uomini) |
| R-07 | Sconfitta: **morte** | D§11, U (v2.29) | ✅ | Prodotta dalla follia indotta dagli anacronismi reiterati; `test_ammonizione.gd`, `test_congedo.gd` |
| R-08 | Sconfitta: **prigionia_eterna** (Calipso, se non riparti mai) | D§11, U (v2.29) | ✅ | Ogigia non avanza più da sola (`trattiene_dopo_turni: 4`): 3 avvisi, poi ci si resta; `test_prigionia.gd` |
| R-09 | Ogni finale si chiude con un **congedo epico** di Omero, non con un'etichetta | U (v2.29) | ✅ | `_congedo()`; testo di ripiego nei dati; `test_congedo.gd` |
| R-10 | Si può **sempre** salpare da Ogigia: la prigionia è una scelta, non una trappola | U (v2.29) | ✅ | Il tag di progresso azzera il conto; `test_prigionia.gd` |

> Tutti e cinque gli esiti dichiarati in `esiti_possibili` sono ora raggiungibili. Nota: la
> partita non finisce più con esito `follia` — la follia è ciò che *causa* la morte, e resta
> leggibile nella `classe` dell'ammonizione e nella traccia.

---

## 12-bis. I profili di costo

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| K-01 | I limiti nati per **risparmiare chiamate** sono identificati e scritti in un posto solo | U (v2.31) | ✅ | `docs/costi.md`: 13 scelte, classificate in 💰 puro costo / ⚖️ costo+design / 🔒 meccanica |
| K-02 | Due profili predefiniti: **Frugale** (i limiti attuali) e **Senza vincoli** | U (v2.31) | ✅ | `data/profili_costo.json`; non modificabili — sono il riferimento della taratura |
| K-03 | Il profilo si sceglie da una **scheda in Impostazioni** | U (v2.31) | ✅ | Disegnata dai descrittori: un limite aggiunto ai dati compare da solo |
| K-10 | Ogni limite dev'essere **comprensibile**: etichetta senza gergo, una riga di effetto, «?» con la spiegazione intera | U (v2.32) | ✅ | Il giudizio sulla prima versione fu «completamente incomprensibile». Tre testi per limite in `profili_costo.json`; `test_settings_ui.gd` pretende che ci siano tutti e tre |
| K-11 | **Cancellare** un profilo proprio, mai i due predefiniti | U (v2.32) | ✅ | Il bottone c'era già ma compariva e spariva: ora c'è sempre, spento sui predefiniti con la ragione nel tooltip, e chiede conferma |
| K-04 | Si può **creare** un profilo proprio e scegliere cosa limitare | U (v2.31) | ✅ | Sempre a partire da uno esistente; vive nelle preferenze utente. La finestra era illeggibile: un `AcceptDialog` è una **Window a sé** e non eredita il `content_scale_factor` del genitore — col 150% usciva grande come un francobollo |
| K-05 | I ⚖️ (costo + design) si **alzano**, non si tolgono | U (v2.31) | ✅ | `max_repliche` 2→4, `compagni_per_turno` 1→2; `test_costi.gd` |
| K-06 | Ogni knob dichiarato deve avere **effetto osservabile** | E | ✅ | Un interruttore che non fa niente è peggio di uno assente; `test_costi.gd` |
| K-07 | I **beat** restano fuori dai profili | U (v2.31) | ✅ | Nati per costo, oggi sono una regola di gioco |
| K-08 | Rendere commutabili i quattro limiti rimasti fuori (C2, C5, C7, C8) | E | ⬜ | Ognuno per un motivo diverso, scritto in `docs/costi.md`: agente mancante, stato noto-cattivo, L-11, testo di prompt |
| K-09 | Mostrare il **profilo attivo** in partita, accanto al motore | E | ⬜ | Con «senza vincoli» un turno passa da 6 a ~10 chiamate: è un'informazione che serve |

---

## 13. Qualità, verifica, manutenibilità

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| Q-01 | **Mock dell'LLM**, costruito per primo | C (mandato 1) | ✅ | `llm_mock.gd` |
| Q-02 | **Test delle unità deterministiche** headless | C (mandato 2) | ✅ | 547 test GUT su 55 script, `./avvia.sh test` |
| Q-03 | **Validatore dei contratti-dati**, rieseguito a ogni modifica | C (mandato 3) | ✅ | `tools/validator/` |
| Q-04 | **Dumper di traccia** headless | C (mandato 4) | ✅ | `tools/trace_dumper/` |
| Q-05 | **Golden trace / snapshot** di un turno canonico | C (mandato 5) | ✅ | `scripts/traccia_canonica.gd` + `tools/golden_trace/` + `test_golden_trace.gd`. Sei turni canonici col mock e seed fisso; confronto per percorso, così un'**assenza** compare come `SPARITO`. Provato iniettando un guasto finto. Un secondo test pretende che la traccia eserciti ancora risveglio, narrazione, ammonizione, avanzamento, delta e ciurma: un golden trace che non tocca niente resta verde per sempre |
| Q-06 | **Scenario runner** per la qualità LLM | C (mandato 6) | 🟡 | `tools/scenario_runner/` copre **solo l'Interprete**. In v2.46 si è aggiunto `tools/prova_spunti/`, che copre **Omero e il Suggeritore** sul solo terreno degli appigli: mette le due strade una accanto all'altra sullo stesso contesto e conta ciò che sopravvive al filtro vero del gioco, più quattro difetti di forma oggettivi. Restano scoperti gli dèi e l'Arbitro |
| Q-07 | **Rosso prima di verde**: per un bug, prima il test che lo mostra | C | ✅ | Seguito in tutta la serie v2.x |
| Q-08 | I **valori numerici** stanno nei dati, non nel codice | E | ✅ | `data/bilanciamento.json` |
| Q-09 | I **testi** stanno nei dati, non nel codice | E | ✅ | `data/testi/`, `data/lingua/` |
| Q-10 | `STATO_LAVORI.md` sempre aggiornato | C | ✅ | Recuperato fino a v2.28 |
| Q-11 | La documentazione descrive **il codice che gira** | U (v2.28) | ✅ | `docs/architettura_dettaglio.md`, i due `.mermaid`, questo documento |
| Q-12 | **Estrarre il Viaggio** da `GameManager` e **dividere `main.gd`** | C | 🟡 | Viaggio e Taccuino **estratti** (v2.31): `game_manager.gd` 1164 → 972 righe, firme pubbliche intatte. Resta la metà più grossa: **`main.gd`, 1284 righe** (cresciuto con il menu Aiuto e il dialogo dei guai), dove la costruzione dell'interfaccia va separata dalla logica |
| Q-14 | Un file di test che **non compila** non può passare inosservato | E (v2.32) | ✅ | GUT lo salta senza dirlo, e la suite resta verde: è successo **quattro volte**. `test_aaa_i_test_compilano.gd` carica ogni `.gd` di `tests/` e fallisce col nome del file |
| Q-15 | Ogni **chiave di testo** citata nel codice deve esistere | E (v2.32) | ✅ | `Testi.s()` ritorna il percorso quando la voce manca: un refuso finisce a schermo senza far fallire niente. `test_testi.gd` scandaglia tutti i `.gd` |
| Q-16 | L'**impaginazione** delle finestre si guarda, non si deduce | U (v2.32) | ✅ | `tools/foto_settings.gd` ritrae le due schede e i dialoghi. Ha trovato due cose che nessun test vedeva: gli apostrofi ASCII nei testi a schermo e il «Cancel» inglese nei dialoghi di Godot |
| Q-17 | Il file di test guasto dev'essere **riconosciuto davvero** | E (v2.35) | ✅ | Q-14 si reggeva su «`load()` torna null», che in Godot 4.7 è **falso**: la guardia passava sempre. Ora `can_instantiate()`, e un test rompe uno script apposta per pretendere che la guardia fallisca |
| Q-18 | Il golden trace registra anche **cosa il giocatore legge**, non solo cosa il gioco decide | E (v2.34) | ✅ | Campo `olimpo_parla`: le righe della Vista Olimpo in ordine e col tipo. Mancava, e per settimane è rimasta a schermo una riga che nessuno strumento poteva vedere |
| Q-19 | L'**instradamento del Gateway** si prova, non si assume | E (v2.36) | ✅ | `llm_gateway/prova_instradamento.py`: due provider finti su localhost che registrano chi ha ricevuto cosa e con quali intestazioni. Diciassette controlli, un secondo, senza rete né chiavi vere — compreso quello che conta, «un provider sconosciuto non diventa Mistral». Dal lato del gioco, un test confronta `config/providers/` con `limiti.json`: un provider selezionabile che il Gateway non conosce renderebbe la spunta una trappola |

| Q-20 | Il **tracciato delle chiamate** è cronologico, per chiamata, e dice dove va il tempo | U (v2.37) | ✅ | `scripts/llm/tracciato.gd`: ora con i millisecondi, riga di connessione, numero per chiamata, latenza, token dichiarati dal provider, causa di fine. Su file sempre (`user://log/`, ultimi dieci), a schermo con `--debugllm` |
| Q-21 | Il **dettaglio HTTP** di ogni richiesta e risposta si può chiedere all'avvio | U (v2.38) | ✅ | `./avvia.sh --tracellm`: verbo, indirizzo, intestazioni e corpo, in entrambe le direzioni. Le credenziali passano da `_oscura()` — resta la coda di quattro caratteri. `test_tracciato.gd` prova con cinque grafie diverse dell'intestazione che la chiave non esca |
| Q-22 | Un **orologio** in un log dev'essere un orologio | E (v2.38) | ✅ | I millisecondi venivano da `get_ticks_msec() % 1000` — l'accensione del gioco, non l'ora: forma giusta, contenuto casuale, e nel log dell'utente l'ora andava **all'indietro** (`.484` poi `.061`). Il campo esisteva per misurare e rispondeva con rumore. Il primo test che scrissi non lo coglieva (duecento righe in due millisecondi non attraversano un confine di secondo): quello buono aspetta il cambio di secondo e pretende che i millesimi traboccino lì |
| Q-23 | Il tracciato dice **cosa entra e cosa esce dal gioco**, non solo cosa risponde il modello | U (v2.38) | ✅ | Righe `GIOCO ↘ ENTRA` / `↗ ESCE` e il **consuntivo di turno**: durata, quota in rete, e quale agente se l'è presa. Fra la risposta del modello e ciò che il giocatore legge c'è tutto il codice nostro, ed era l'unica parte che nessuna riga raccontava |
| Q-24 | La **cache dei prompt** dev'essere misurabile prima che ottimizzata | E (v2.38) | ✅ | L'81% dell'ingresso è prefisso ripetuto identico (`tools/stima_costo`), e su DeepSeek/OpenAI/Gemini la cache è **automatica**: non mancava la cache, mancava la prova che funzionasse. Ora `cached_tokens` e `reasoning_tokens` si leggono e finiscono nel consuntivo. Su Anthropic `cache_control` **non è implementabile** dalla nostra strada: il suo layer OpenAI-compatibile non lo supporta (e ignora in silenzio anche `response_format` e `seed`) |
| Q-25 | Il **launcher** ha i suoi test: è il punto in cui ogni sessione comincia | E (v2.42) | ✅ | `./avvia.sh console --debugllm` non funzionava: l'analisi degli argomenti usava `for a in "$@"; do … shift … done`, che scorre una **copia** mentre `shift` muove quelli veri. I due si disallineano, lo `shift` si mangia «console», e `MODE` diventa `--debugllm`. Con una sola opzione funzionava per caso — l'unico modo in cui era stato provato. Ora un `while` vero e `tools/prova_avvio_sh.sh`: 24 controlli su modi, opzioni, ordine inverso, combinazioni, trattino singolo, opzione ignota e modo ignoto — con l'ultima riga sostituita da un'eco, così si vede cosa *sarebbe* stato eseguito |
| Q-26 | L'**aiuto** nomina tutto ciò che il launcher accetta, e costa niente | U (v2.42) | ✅ | «*che è sta roba? `./avvia.sh -tracellm` → Uso: ./avvia.sh [gui\|console\|test\|musica\|installa-menu]*». Tre opzioni consegnate in tre versioni e mai scritte nell'unico posto dove si va a cercarle. Ora `mostra_uso()` elenca modi, opzioni ed esempi, distingue «Opzione sconosciuta» da «Modo sconosciuto», e quattro controlli pretendono che l'aiuto le nomini davvero. L'analisi degli argomenti è stata spostata **subito dopo `DIR=`**: prima girava dopo due passate di `godot --import`, e `--help` costava **4,745 s** contro gli 0,004 s di adesso |
| Q-27 | Il launcher **non scalda Ollama** se il provider scelto non è Ollama | E (v2.42) | ✅ | `ollama_preflight` girava sempre: nel primo tracciato consegnato, un modello locale da 24B veniva caricato in memoria mentre la partita andava su OpenRouter. Ora `_provider_scelto()` legge `provider_nome` da `impostazioni.json` (percorso di macOS o di Linux) e il preflight si ferma se non è «Ollama locale». Quattro controlli in `tools/prova_avvio_sh.sh` estraggono le due funzioni vere e le eseguono con un `HOME` finto. Provati sabotando il cancello: il primo tentativo **si piantava** invece di fallire, perché il preflight sabotato andava a cercare il server locale davvero — ora la chiamata ha un guinzaglio (`timeout`) e lo stdin chiuso |
| V-01 | La **tracotanza è dentro il mondo**, sempre: un rifiuto sbagliato non può punire chi sta giocando bene | E (v2.44) | ✅ | Da un tracciato di partita vera: «sono odisseo! il più forte guerriero acheo» → `anacronistico`; «distruggiamo tutta la città dei cicorni» → `assurdo_diegetico` (è **canone**, il sacco di Ismaro). In tutti e tre i casi il `tono` era giusto — *vanto*, *tracotanza*, *arrogante* — ed era l'etichetta a sbagliare: il modello confondeva «insensato» con «di un'altra epoca». E respingere costa un'ammonizione, su una scala che finisce in **follia**: il test lo stampa in chiaro, `richiamo → smarrimento → follia`. Il gioco puniva come pazzia il proprio motore. Ora il prompt giudica **solo l'epoca** e dichiara la tracotanza in_mondo con tre esempi; `test_plausibilita.gd` usa le frasi vere |
| V-02 | «**anacronistico**» senza un marcatore d'epoca è un verdetto falso, e si scarta | E (v2.44) | ✅ | È l'unica classe fuori-mondo con una definizione **oggettiva** e un riconoscitore deterministico (`Validazione.e_anacronistico`). Se la lista non trova niente di moderno, il verdetto dell'LLM non si applica: gratis, senza chiedere a nessuno. Le altre classi sono giudizi, e un giudizio che può chiudere la partita vuole **due pareri concordi** — l'Interprete propone, il Vaglio conferma. Costa una chiamata in più solo quando si sta per respingere |
| V-03 | I **tag sopravvivono** a un verdetto ribaltato | E (v2.44) | ✅ | La regola «fuori-mondo → tag vuoti» stava nel *prompt*, e un prompt è una preghiera: un'etichetta sbagliata portava via anche le prove, e una tracotanza tornava senza il tag `tracotanza`. Ora è codice (`Validazione._respingi()`), applicata **solo a rifiuto definitivo** — e vale anche per il ramo deterministico, che prima li lasciava passare. Senza questo la correzione sarebbe stata invisibile: mossa accettata, ma nessun dio destato |
| L-20 | Ogni agente parte con un **tetto all'uscita** | E (v2.44) | ✅ | `max_tokens` era supportato dal client, passato da `LLMManager` e impostato da **nessun agente**: in un tracciato di 17 turni compare solo nella «prova del modello». `data/tetti_uscita.json` + `Tetti`, ricavati da ~3× l'uscita massima osservata sul campo, con **pavimento a 256** perché un modello che ragiona spende il budget nel ragionamento e tornerebbe `content: null` (succede: v2.38, `max_tokens: 1`). Chi non si annuncia (`agente == "?"`) non prende tetti — l'ha trovato un test già esistente, che pretendeva che nel corpo non comparisse niente che nessuno avesse chiesto |
| R-12 | **Un cambio di scena deve avere una causa, e il giocatore deve leggerla.** Le cause legittime sono tre: *me ne sono andato io* (`scelta`), *mi hanno cacciato* (`cacciato`), *è successo qualcosa di sovrannaturale* (`prodigio`). Un cambio senza causa non deve esistere | U (v2.45) | ✅ | Formulato da Luca il 6 agosto 2026 dopo una partita: «non posso trovarmi a combattere coi Ciconi e poi al turno dopo trovarmi dai Lotofagi». Dal tracciato delle 00:45: **Ciconi e Lotofagi chiusi entrambi dal tetto dei turni**, cioè da un contatore scaduto, senza nulla da raccontare. Oggi `_passaggio(da, a)` passa a Omero **solo origine e destinazione**: il perché non esiste come dato, quindi il narratore non può scriverlo e ripiega sulla prosa marina generica. **Fatto:** `Viaggio.avanza()` restituisce `causa`, `_passaggio(da, a, causa)` la porta a Omero, e `Narratore._perche()` la traduce in tre istruzioni **diverse** — un test lo pretende, perché un motivo uguale per tutte sarebbe un campo che c'è e non serve. `fuga` → `cacciato`. `test_causa_passaggio.gd`, 6 controlli |
| R-13 | Il **tetto dei turni** non teletrasporta più: diventa **pressione narrativa** crescente | U (v2.45) | ✅ | «lo eliminerei ma farei in modo che dopo, che ne so, dieci turni, la ciurma cominci a mollare Ulisse, gli dèi lo sospingano altrove, gli avversari diventino più forti». Il tetto è per costruzione un cambio *senza* causa, quindi R-09 lo vieta. Al suo posto una scala a gradi che **emette eventi** — il macchinario esiste già (`eventi_attivi`, `trigger_evento`, `emette_su_tag`) e gli eventi svegliano gli dèi e arrivano a Omero: la ciurma mormora, gli avversari si fanno arditi, e infine gli dèi lo sospingono, che è l'uscita con causa `prodigio`. **Fatto:** `Viaggio.grado_pressione()` / `evento_pressione()` / `la_pressione_spinge()`, numeri in `data/bilanciamento.json` (`viaggio/pressione_da: 10`, `pressione_passo: 3`). Al primo tentativo la partenza scattava appena il grado toccava 3 e — siccome è `avanza()` a incrementare il contatore — il terzo grado nasceva e chiudeva la tappa nello stesso istante: «gli dèi lo sospingono» non compariva mai in un turno giocabile. Lo stesso difetto che si stava correggendo, rifatto uguale; l'ha trovato una misura turno per turno, non un test |
| R-14 | I **tag d'uscita** dicono quale causa sono, e `rotta` non è una causa | E (v2.45) | ✅ | `rotta` è il tag d'uscita di **nove tappe su quindici** (Troia, Eolo, Circe, Ade, Sirene, Scilla, Trinacia, Ogigia, Scheria): tappe che si chiudevano per sbaglio parlando di direzioni. Nel tracciato, «ai remi dobbiamo arrivare ad itaca!» (tipo `azione`, tag `desiderio/nostalgia/rotta`) ha chiuso Troia al turno 3 mentre Ulisse incitava i rematori. L'Interprete non aveva sbagliato: di rotta si parlava davvero — era il gioco a leggere un *argomento* come una *partenza*. `fuga` invece è un buon segnale — scappare *è* andarsene — e vale `cacciato`. **Fatto (via a, la più economica):** `Viaggio.e_un_congedo()` pretende `tipo: movimento` insieme a `rotta`, sfruttando un campo che l'envelope ha già; nessun tag nuovo, nessun prompt riscritto. Un envelope **senza** `tipo` non è un movimento: nel dubbio si resta. Il predicato è **uno solo** perché la domanda si poneva in due punti — l'avanzamento e la prigionia di Ogigia — e correggerne uno avrebbe lasciato Calipso a sciogliere la prigionia su una chiacchiera. `test_uscita_rotta.gd`, 7 controlli |
| I-21 | La **sequenza d'avvio** è: apertura → si dissolve → *solo* il popup delle tre scelte → la schermata di gioco | U (v2.43) | ✅ | Chiesta tre volte. Il passo «si dissolve» non avveniva: con la soglia, `Splash.congeda()` usciva senza avviare nessuna sfumatura, e il popup compariva **sopra la schermata d'apertura ancora intera** — marchio, titolo, e l'invito «un tasto, e il viaggio comincia» che a quel punto non serviva più a niente. Ora l'uscita è in **due tempi**: il *velo* sfuma l'emblema e a dissolvenza finita annuncia `pronto` (è lì che nasce il popup); il *sipario* sfuma il fondale scuro solo dopo la scelta, e sotto c'è la partita già costruita. `test_sipario.gd` (6 controlli sul confine fra i due tempi) e `tools/foto_soglia.gd`, che adesso pretende emblema a 0,00 e fondale a 1,00 nell'istante dello scatto |
| I-22 | Le voci del popup d'avvio sono **tre, sempre, e in quest'ordine**: nuova partita · carica partita salvata · impostazioni | U (v2.43) | ✅ | Erano due e con altri nomi. «Comincia da Troia» al posto di «Nuova partita»: più evocativo e sbagliato — in un menu d'avvio la voce deve dire **cosa fa**, non dove porta, e chi ha un salvataggio a Ogigia legge «Troia» e non sa se stia per perderlo. E «Carica partita salvata» compariva **solo se** c'era un salvataggio: decisione mia, con un argomento plausibile (un bottone che a volte non fa niente insegna a non fidarsi degli altri), su cui avevo perfino scritto un test — che è il modo più efficace di rendere permanente uno sbaglio, e infatti è sopravvissuto a una segnalazione con la suite verde. Ora la voce c'è sempre; senza salvataggio è **spenta e dice perché**. Il test che difendeva l'errore è stato sostituito dal suo contrario |
| I-19 | La partita **non comincia** prima che si sia scelto | E (v2.41) | ✅ | Il sipario si alzava, sotto c'era una partita già cominciata — la voce di Omero, i tre appigli — e sopra la soglia chiedeva ancora cosa fare: si vedeva il gioco rispondere a una domanda non ancora posta. Un'ottimizzazione nata buona (avviare sotto l'apertura per non far aspettare) diventata sbagliata con la soglia. Ora il sipario si trattiene (`Splash.trattieni`) e `_apri_scena()` aspetta la scelta. `tools/foto_soglia.gd` conta i caratteri di narrazione dietro il dialogo |
| I-20 | Un guaio del motore all'avvio **non viene inghiottito** | E (v2.41) | ✅ | Godot vieta due finestre esclusive figlie dello stesso genitore: il popup del guaio e la soglia si contendevano il posto, e con una chiave sbagliata non compariva niente. Ora i guai arrivati prima della scelta entrano nel referto della soglia — che è anche il posto giusto: lì c'è scritto cosa sistemare. Trovato da uno strumento di scatto, non da un test |
| I-21 | Dalla soglia **non si scappa** senza scegliere | E (v2.41) | ✅ | Senza «OK» il dialogo si chiudeva comunque con Esc, e dietro c'era il sipario tenuto alzato apposta: si restava davanti all'apertura per sempre. Una lambda vuota su `close_requested` non basta — il segnale è un avviso, non una richiesta di permesso |
| I-22 | Un dialogo **non muta** il dizionario di chi lo apre | E (v2.41) | ✅ | `aggiungi_guaio()` scriveva nella struttura del chiamante. L'ha detto un test passandogli una costante: in GDScript sono di sola lettura, e il dialogo è esploso invece di corrompere in silenzio — il modo fortunato di scoprirlo |
| I-16 | Fra il sipario e la prima mossa c'è una **soglia** | U (v2.40) | ✅ | Il gioco cominciava sempre una partita nuova: il salvataggio c'era da sempre, ma per riprenderlo bisognava sapere che il menu esisteva — un lavoro conservato che il gioco non offre di riprendere è indistinguibile da uno perso. `DialogoAvvio`: riprendi (con capitolo, turno e data), nuova, impostazioni, più il referto di motore e audio |
| I-17 | Le finestre modali **non si vedono** dagli strumenti di scatto | E (v2.40) | ✅ | `_niente_dialoghi`: la soglia è una finestra davanti alla cosa da ritrarre, e sarebbe stata la terza volta che uno scatto fotografa la cosa sbagliata (prima lo splash, poi la pagina non aggiornata) |
| I-18 | Un dialogo **si veste da sé** | E (v2.40) | ✅ | Il tema lo dava chi lo apriva (`Main._veste_dialogo`), e `tools/foto_avvio.gd` non ce l'ha: il primo scatto ritraeva col grigio di sistema una finestra che nessuno vedrà mai. Uno strumento che mostra un aspetto diverso da quello vero è peggio di nessuno strumento |
| Q-29 | Il **diario dell'applicazione**: cosa fa il gioco, e cosa gli va storto | U (v2.40) | ✅ | `scripts/registro.gd`, separato dal tracciato del modello perché sono due domande. Su file sempre (`user://log/app-*.log`), a schermo con `./avvia.sh --logdei`. Tre livelli; il conto di avvisi ed errori in coda |
| Q-30 | All'avvio si dichiara **se si passa dal Gateway**, e perché | E (v2.40) | ✅ | Domanda posta due volte dall'umano, e due volte senza una riga che rispondesse: si deduceva da un indirizzo nel traffico HTTP, dove `localhost:11434` e `localhost:8800` si somigliano. Ora `Main._instradamento()` lo scrive a parole, con il motivo |
| Q-31 | Un **logger** non usa `push_error` | E (v2.40) | ✅ | Il backtrace di Godot punta alla riga che scrive il log, mai alla causa: di un «provider non risponde» indica il messaggero. E `push_error` è per gli errori di programmazione — un 401 non lo è. L'ha detto la suite: due test che provocano un guaio apposta sono diventati rossi per «errori inattesi» |
| Q-26 | Il tracciato non deve **mentire** sulle credenziali | E (v2.39) | ✅ | Col Gateway acceso scriveva «chiave=non serve (provider locale)» davanti a OpenRouter: la spiegazione di Ollama sotto un provider remoto. E quella chiave serve eccome — va nell'ambiente del Gateway, ed è il passo che tutti saltano. La riga che doveva dirlo diceva l'opposto |
| Q-27 | Il blocco `── connessione ──` si scrive **quando cambia qualcosa** | E (v2.39) | ✅ | `_riconfigura()` è chiamata a ogni prova e due volte per verifica: sette blocchi identici da sei righe in trentacinque secondi, che spezzano le chiamate da leggere di fila. Ripetere un cambio che non c'è stato non aggiunge informazione: insegna a saltare il blocco |
| Q-28 | Un banco di prova che **non è in piedi** non produce fallimenti | E (v2.39) | ✅ | `finto_provider.py` usciva dopo 120 s e lo strumento che gli parla riportava tre fallimenti circostanziati contro codice sano. Ora il finto serve finché non lo si ferma, e lo strumento controlla prima che qualcuno risponda: «non ho potuto misurare» non è «ho misurato e va male» |
| Q-25 | Il tracciato **si guarda**, non si deduce dai test | C (mandato) | ✅ | `tools/prova_tracciato.gd` contro un provider finto in formato OpenRouter: un turno vero, HTTP vero, zero token. Ha trovato due cose che nessun test vedeva — i token stampati come `2043.0` e la coda della chiave da verificare **sul file** invece che sull'intenzione |

---

## 13-bis. Sicurezza e riservatezza

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| X-01 | **Nessun segreto nel repository**, mai, nemmeno nella cronologia | C | ✅ | Verificato su tutti i commit: zero chiavi. Le chiavi vivono in `user://impostazioni.json`; l'ambiente ha la precedenza |
| X-02 | Il **valore** di una chiave non si stampa mai — né nel Log LLM né nel Gateway | E (v2.32) | ✅ | Si dice solo *se* c'è. Incollare un log per chiedere aiuto non deve costare una chiave |
| X-03 | Il Gateway ascolta **solo su `127.0.0.1`** | E | ✅ | `gateway.py`; non ha autenticazione, e non deve essere esposto |
| X-04 | Il testo che arriva da un modello **non può scrivere marcatori** nell'interfaccia | E (v2.35) | ✅ | Le viste sono BBCode: una quadra generata dal modello aprirebbe un marcatore vero, e una battuta potrebbe travestirsi da voce del gioco. Neutralizzato al confine in `bbcode.gd`; `test_bbcode_ostile.gd` |
| X-05 | Il binario di Godot scaricato si **verifica** prima di eseguirlo | E (v2.35) | ✅ | SHA-512 contro l'impronta pubblicata da Godot, in `avvia.sh`. «Viene dal posto giusto» non è «è il file giusto» |
| X-06 | **Nessuna telemetria**: l'unico traffico è verso il motore scelto da chi gioca | C | ✅ | `SECURITY.md` dice anche cosa *non* c'è |
| X-07 | Nulla di **personale** nel repository pubblicato, cronologia compresa | U (v2.35, v2.36) | ✅ | Due riscritture. La seconda per un `__pycache__/*.pyc` tracciato per sbaglio: un `.pyc` contiene il **percorso assoluto** del sorgente, cioè la home con il nome utente, e nessuno l'aveva scritto — l'aveva generato Python e raccolto un `git add -A`. Tolto anche il nome da un messaggio di commit. Verificato blob per blob su tutti i 120 commit |
| X-08 | **Licenza** dichiarata, e componenti di terzi attribuiti | U (v2.35) | ✅ | `LICENSE` (AGPL-3.0), `TERZE_PARTI.md`, `fonts/OFL.txt` |
| X-09 | Il gioco apre **un solo indirizzo**, ed è una costante | E (v2.36) | ✅ | Il bottone «Apri su GitHub» chiama `OS.shell_open()`: unico punto del gioco che lo fa, e l'URL è `Main.REPOSITORY`, mai composto da un dato e men che meno da ciò che dice un modello. `test_l_indirizzo_del_repository_e_una_costante_https`, e la regola è scritta in `SECURITY.md` per chi tocca quel file dopo |
| X-10 | Un **cancello** impedisce di committare dati personali | E (v2.36) | ✅ | `.git/hooks/pre-commit` (contenuto indicizzato e nomi dei file) e `commit-msg` (il messaggio). Non possono stare nel repository: contengono le stringhe che nascondono, quindi vivono in `.git/`, che git non versiona per costruzione. Schemi lunghi almeno sei caratteri, o l'audio compresso darebbe falsi allarmi — in `scheria.mp3` c'è «LucA» per caso. Provato su cinque casi, e sui quindici mp3 per verificare che **non** gridi al lupo |
| X-11 | Il progetto è **pubblicato**, e il cantiere resta fuori | U (v2.36) | ✅ | Due repository: `dei-in-machina` pubblico (120 commit, 552 file) e `dei-in-machina-lavoro` privato per diario, requisiti, `CLAUDE.md`, mockup e `lavoro.sh`. Verificato sull'albero **remoto**, non sul disco. I trailer di co-autore sono stati tolti e l'assistenza AI è dichiarata in `TERZE_PARTI.md`, dove si legge |

---

## 13-ter. Coda della sezione 13

| ID | Requisito | Origine | Stato | Dove / Note |
|---|---|---|---|---|
| Q-13 | **Traduzione** en/fr/de/el | U | ⬜ | I testi sono già fuori dal codice. Il punto critico non è il testo ma i **tre elenchi in cui la lingua è logica**: marcatori di anacronismo, cue di invocazione, epiteti degli dèi |

---

## 14. Riepilogo

| | Requisiti | |
|---|---:|---:|
| ✅ Fatti e sorvegliati da test | 186 | 89% |
| ✔︎ Fatti, senza test dedicato | 10 | 5% |
| 🟡 Parziali | 4 | 2% |
| ⬜ Non fatti | 9 | 4% |
| ⚠️ Divergenze dal design | **0** | — |
| **Totale** | **209** | |

**Nessuna divergenza aperta.** Codice e design dicono la stessa cosa: quello che resta è
lavoro non fatto (⬜) o fatto a metà (🟡), che è una condizione onesta. Un requisito
dichiarato e mai fatto, invece, è peggio di un requisito che non c'è.

### Chiuso in v2.29

**R-07 e R-08**, i due esiti irraggiungibili. La follia indotta dagli anacronismi ora
*uccide* (esito `morte`); Ogigia non avanza più da sola e chi indugia troppo ci resta per
sempre. Entrambi si chiudono con un **congedo epico** di Omero (R-09), e da Ogigia si può
sempre salpare (R-10): la prigionia dev'essere una scelta, non una trappola.

### Decisione storica v2.30 — superata in parte da ADR-001

- **I-16** — il salvataggio è finito e collegato (menu *Partita*, `:salva`/`:carica`).
- **R-03 (storico)** — v2.30 cancellava la variabilita; ADR-001 supera quella decisione per il world slice: il canone e lore e la causalita deriva dagli eventi committed.
- **S-08** — REVOCATO in v2.34 su richiesta dell'umano (era stato ottenuto col campo `rischio` invece che con un secondo tipo
  di turno.

### Cosa resta da fare — l'elenco completo

Nessuna divergenza aperta: quello che segue è lavoro non fatto o fatto a metà, in ordine di
quanto secondo me conta.

**Debito che protegge il resto**

1. **Q-12 · Dividere `main.gd`** 🟡 — 1284 righe, il file più grosso: costruzione
   dell'interfaccia e logica di gioco intrecciate. La prima metà (Viaggio, Taccuino) è fatta.
   Ora c'è il golden trace a fare da rete durante lo spostamento, che prima non c'era.
2. **Q-06 · Scenario runner** 🟡 — copre solo l'Interprete. La qualità di Omero e degli dèi
   non è osservabile in modo sistematico: si giudica giocando.

**Qualità del gioco**

3. **G-15 · Filtro di ritmo sul risveglio** ⬜ — oggi reagiscono *tutti* gli dèi innescati.
   Il design lo voleva per la credibilità (il silenzio scelto è un personaggio) *e* per il
   budget: è l'unica voce che migliorerebbe il gioco **risparmiando** chiamate.
4. **U-11 · Taccuino dei compagni** 🟡 — gli dèi ricordano, i compagni no. Chi ha visto
   Polifemo divorare i suoi dovrebbe parlarne diversamente.
5. **N-09 · Entità persistenti** 🟡 — personaggi e oggetti che Omero introduce a runtime non
   hanno un registro: mitigato da `scena` e `ultima_narrazione`, non risolto.

**Costi e provider**

6. **K-09 · Mostrare il profilo attivo in partita** ⬜ — piccolo e utile: con «senza vincoli»
   un turno passa da 6 a ~10 chiamate.
7. **K-08 · I quattro limiti non commutabili** ⬜ — C2 vuole un agente nuovo, C5 ha lo stato
   acceso noto-cattivo, C7 è L-11, C8 vive nel prompt.
8. **L-11 · Parallelizzare le chiamate degli dèi** ⬜ — vuole un layer a segnali; utile solo
   fuori dal tier gratuito.
9. **L-10 · Streaming della narrazione** ⬜ — oggi il turno arriva tutto insieme.

**Rifiniture**

10. **I-15 · Rotta curva animata** ⬜ — Bezier con Ulisse che scivola e lascia la scia; oggi
    sono spezzate. La carta è appena stata sistemata, quindi non urge.
11. **Q-13 · Traduzioni en/fr/de/el** ⬜ — i testi sono già fuori dal codice; il punto critico
    sono i **tre elenchi in cui la lingua è logica** (marcatori di anacronismo, cue di
    invocazione, epiteti degli dèi), che tradotti smetterebbero di funzionare in silenzio.

### Chiuso in v2.36

Nove requisiti nuovi, tutti chiusi. Non erano nell'elenco perché non erano stati formulati:
sono nati da difetti trovati usando il gioco e da ciò che serviva per pubblicarlo.

- **I-18 · Le viste di servizio nascono chiuse.** Il Log LLM si apriva da solo a ogni avvio.
- **I-19 · Menu Aiuto.** Le regole erano solo nei documenti; ora sono anche nel gioco.
- **I-20 · I guai del motore in una finestra.** La narrazione contiene solo narrazione.
- **L-19 · Anthropic passa dal Gateway.** Con le sue intestazioni dichiarate nel dato.
- **L-20 · Il Gateway non ripiega mai.** Era il difetto peggiore della serie: una
  configurazione mancante che diventava la risposta di un altro modello.
- **Q-19 · L'instradamento si prova**, con due provider finti e diciassette controlli.
- **X-09 · Un solo indirizzo, costante**, e la regola scritta per chi verrà dopo.
- **X-10 · Un hook** che rifiuta i commit con dati personali, provato in entrambi i sensi.
- **X-11 · Pubblicato**, con il cantiere in un repository separato.

Fuori dai requisiti, nella stessa serie: la colonna sonora è passata da uno a quindici brani
su venti momenti; la documentazione ha guadagnato lo stato del collaudo, il disclaimer sui
costi, come si crea la chiave Mistral e la sezione «Problemi frequenti».

### Chiuso in v2.32

**Q-05 · il golden trace**, che era in testa a questo elenco. Sei turni canonici col mock e
seed fisso, confrontati per intero: un'assenza compare come `SPARITO`. Provato iniettando un
guasto finto, non solo scritto. È lo strumento che mancava contro la classe di guasto che ha
dominato questa serie — codice che non sbaglia, codice che **manca**.

**Il layer dei provider** (L-13…L-18): sei provider chiamati col nome del provider, Ollama
fra loro invece che a parte, «Aggiorna elenco» che interroga chi deve, i modelli curati nei
dati con uno strumento che li verifica sul catalogo vero, Anthropic.

**La scheda «Costi»** (K-10, K-11), riscritta e — finalmente — **guardata a schermo**: il
limite che avevo dichiarato nella versione precedente di questo documento è caduto. Lo
strumento non si pianta più: si piantava perché girava `--headless`, dove una `Window` non
ha un viewport da cui leggere.

**Verificato a schermo** (`tools/foto_settings.gd`): entrambe le schede di Impostazioni, il
dialogo di aiuto e quello di creazione profilo. Restano non ritratte le tre finestre di
servizio (Log, Olimpo, Ciurma), che però non hanno impaginazione propria: sono testo.

---

## 15. Le tre divergenze — analisi e decisioni (chiuse in v2.30)

**Tutte e tre sono chiuse.** Questa sezione resta come verbale: cosa dicevano il design e il
codice, e perché si è deciso così. Le decisioni si dimenticano; le motivazioni servono a chi
riaprirà la questione fra sei mesi — magari io stesso.

### 15.1 · I-16 — Il salvataggio → **FATTO**

**Il design non lo chiede.** Non compare in nessuna sezione: è un requisito *emerso*, perché
il codice per farlo è stato scritto e non finito. Questa è la divergenza più semplice delle
tre, e anche l'unica che è davvero un difetto e non una scelta.

**Cosa c'è.** `GameManager.salva_partita()` funziona: serializza `StatoPartita` in
`user://partita.json`. È `carica_partita()` che non regge. Confrontato con `nuova_partita()`,
il caricamento **non** ricostruisce:

| Cosa manca | Conseguenza |
|---|---|
| `_politica = PoliticaDivina.new(...)` | **Crash al primo turno**: `esegui_turno` chiama `_politica.resa_dei_conti()` sulla prima riga |
| `ciurma = Ciurma.carica()` | I compagni spariscono in silenzio: `_fa_parlare_la_ciurma` esce subito se `ciurma == null` |
| Il canale `Ciurma` nell'Agora | La chat dei compagni non esiste più |
| `PantheonManager.pantheon.spegni_locali()` + riaccensione della tappa | I locali sono un flag **in memoria**, non nel salvataggio: ricaricando dentro il Ciclope, Polifemo è spento |
| `_rng.seed`, `_ultima_narrazione` | Run non riproducibile; Omero riparte dalla narrazione della partita precedente |

E due cose non sono **proprio nel salvataggio**:

- **`Agora`** — le due chat (Olimpo e Ciurma) non vengono serializzate. Anche sistemando il
  caricamento, si riprenderebbe con le conversazioni vuote.
- **`Ciurma.caduti`** — chi è morto **tornerebbe in vita**.

Nessun test copre `carica_partita`: è per questo che è potuto marcire.

**Le opzioni.** (a) Finirlo: rendere `carica_partita` simmetrico a `nuova_partita`, aggiungere
`agora` e `caduti` allo schema dello stato, e un test che salva a metà partita, ricarica e
prosegue. (b) Toglierlo: cancellare i due metodi finché non serve davvero.

**Deciso (a), fatto in v2.30.** `carica_partita` è ora simmetrico a `nuova_partita`; `agora`,
`ciurma_caduti` e `ultima_narrazione` sono nello schema dello stato; le chiavi intere delle
intestazioni sopravvivono al giro su JSON; il diario si **ridisegna** invece di appendersi.
Esposto nel menu *Partita* e come `:salva` / `:carica` in console. Nove test in
`test_salvataggio.gd`, più uno di interfaccia.

Una nota che vale oltre questo caso: il crash da `_politica` null si vede **solo** caricando
a gioco appena avviato. Con una partita già in corso il modulo vecchio sopravviveva e
continuava a scrivere nello stato precedente — nessun errore, e la politica divina che
lavora su una partita che non esiste più. Il silenzio era il caso peggiore, non il crash.

### 15.2 · R-03 — Decisione v2.30 **SUPERATA DA ADR-001**

**Cosa dice il design** (§7, *Rigiocabilità*): «trigger fissi (la logica mitologica canonica
— una maestria che ti porti tra le partite), ma **capricci, umori e ordine degli episodi
variabili** a ogni partita (guidati dal `seed`)».

**Cosa fa il codice.** `Episodi.ordine()` restituisce l'ordine del file, sempre lo stesso:
Troia → Ciconi → Lotofagi → Ciclope → Eolo → Lestrigoni → Circe → Ade → Sirene → Scilla →
Trinacia → Ogigia → naufragio → Scheria → Itaca.

C'è però un **indizio archeologico**: `stato.viaggio["ordine_episodi"]` viene scritto a ogni
nuova partita e **non è mai letto da nessuno**. È il campo predisposto per il rimescolamento
che non è mai arrivato.

**Perché è più delicata di quanto sembri.** Il poema ha una causalità che l'ordine incarna:

- il Ciclope **deve** venire prima del resto: è lì che nasce `maledizione_di_polifemo`, e
  senza quell'evento Poseidone dorme per tutta la partita (`dorme_finche`);
- l'**Ade** contiene la profezia di Tiresia, che avverte di Sirene, Scilla e delle vacche del
  Sole: metterla dopo la svuota;
- **Circe** avverte di Scilla e Trinacia: stesso problema;
- **Ogigia → naufragio → Scheria** è una catena unica: la zattera che si sfascia presuppone
  la zattera;
- `non_ancora` ed `emette_su_tag` sono tarati su una sequenza nota.

Rimescolare tutto romperebbe metà del gioco. Rimescolare *alcune* tappe sarebbe possibile —
Ciconi, Lotofagi, Lestrigoni sono episodi narrativi senza dio locale né catene di causa — ma
il guadagno è modesto: sono tre tappe su quindici, e sono le meno memorabili.

**Le opzioni.** (a) Rimescolare solo il blocco «neutro» (3 tappe). (b) Variare qualcos'altro
col seme al posto dell'ordine: quali dèi sono più suscettibili, gli umori iniziali, quali
eventi opzionali scattano. (c) **Cancellare il requisito dal design** e dire perché.

**Deciso (c), fatto in v2.30.** La sezione 7 del design ora dice che l'ordine è fisso, con
la motivazione per esteso. Il campo morto `viaggio.ordine_episodi` è stato rimosso da
`stato_partita.gd`, dallo schema JSON e da `nuova_partita`.

**Decisione del 20 agosto 2026 (ADR-001).** Non si introduce un rimescolamento casuale della lista. Si rimuove invece l'obbligo narrativo: lore e geografia restano seed, mentre movimento, alleanze, morti e conseguenze diventano veri solo tramite eventi committed e precondizioni causali. Il POC applica questa politica soltanto a Ciconi/Ismaro; il legacy resta invariato altrove.

### 15.3 · S-08 — Le scelte discrete per i bivi veri → **FATTO col `rischio`**

**Cosa dice il design** (§4): la chat libera è il cuore, ma «le **scelte discrete** si tengono
solo per i bivi veri (Scilla o Cariddi? apri l'otre?)».

**Cosa fa il codice.** Esistono solo i tre appigli, che sono **prefill di testo**: cliccarne
uno riempie il campo d'azione, e da lì il testo è modificabile e passa per l'Interprete come
qualunque altra frase.

**Qual è davvero la differenza.** Non è di interfaccia, è di **garanzia**:

| | Appiglio (oggi) | Bivio (design) |
|---|---|---|
| Si può modificare | Sì | No: si sceglie |
| Chi decide l'esito | L'LLM, come sempre | Il codice: ramo A o ramo B, deterministico |
| Si può eluderlo | Sì, scrivendo altro | No: la scena non prosegue senza scegliere |
| Conseguenza | Quella che emerge | Garantita e diversa nei due rami |

Nel poema, «Scilla o Cariddi» è la scena in cui Ulisse **sa** che perderà sei uomini e sceglie
di perderli. Oggi il giocatore può scrivere «passo in mezzo evitando entrambe» e vedere cosa
succede — il che è coerente col resto del gioco, ma toglie il momento.

**Il costo nascosto.** Un bivio vero non è un widget: è un **secondo tipo di turno**, con la
sua macchina (niente Interprete, niente vaglio, conseguenze scritte a mano nei dati). E ogni
bivio va autorato tappa per tappa — è contenuto, non meccanica.

**Le opzioni.** (a) Costruirlo per due o tre momenti soli (Scilla/Cariddi, l'otre di Eolo, le
vacche del Sole). (b) Ottenere l'effetto senza un meccanismo nuovo: un appiglio marcato
`rischio: true` — il campo **esiste già** in `spunti_di_riserva` e oggi non fa niente — che il
codice tratti come impegno, con una conferma e un esito garantito. (c) Cancellarlo dal design.

**Deciso (b), fatto in v2.30.** Un appiglio con `rischio: true`:

1. si riconosce a vista — segno `‡` e rosso-sangue;
2. **non finisce nel campo modificabile**: chiede conferma («questa è una scelta, non un
   suggerimento») e poi agisce;
3. la reazione degli dèi sale di **un grado d'intensità**, in qualunque direzione abbiano
   scelto — `GameManager.forza_con_rischio`, deterministico, con tetto a 3.

Il punto 3 è la garanzia; i primi due sono forma. E amplifica **anche il bene**: un aiuto
rischiato vale di più. Se fosse solo una penalità sarebbe una trappola travestita da scelta,
e i giocatori imparerebbero semplicemente a non premere mai il bottone rosso.

Il marchio arriva già da Omero, che apre col «!» gli spunti pericolosi (`narratore.gd`), e il
filtro degli spunti lo conserva — se lo perdesse, i bivi tornerebbero suggerimenti qualunque.
Otto test in `test_bivi.gd`.

Resta possibile (a) — il bivio vero, con rami scritti a mano — per i due o tre momenti che
lo meritassero davvero.
