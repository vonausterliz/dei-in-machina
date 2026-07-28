# Dei in machina — Documento di design

*Versione 0.1 — congelamento pre-Godot*

---

## 1. Concept

Un gioco narrativo agentico sull'*Odissea*. Il giocatore **è Ulisse**; gli dèi del poema sono **agenti AI** con agende in conflitto che competono per farlo tornare a Itaca — o per impedirglielo. Il titolo gioca su *deus ex machina*: il dio calato dalla macchina a sciogliere la trama. Qui gli dèi *sono* la macchina, e il loro intervento *è* il meccanismo del gioco.

L'esperienza centrale: scrivi liberamente cosa fa e dice Ulisse; le tue parole svegliano (o no) gli dèi; loro deliberano e agiscono; un narratore racconta le conseguenze senza mai dirti chi è stato. Il vero gioco è **dedurre** quali potenze hai attirato, e come.

---

## 2. I pilastri di design

Sette principi che reggono tutto. Ogni scelta successiva discende da qui.

**Giocatore = Ulisse, in testo libero.** Non menù, ma scrittura. Le utterance sono il trigger centrale — proprio come nel poema, dove Ulisse che grida il proprio nome a Polifemo scatena Poseidone.

**Dèi nascosti.** Al giocatore succedono cose; la causa la può solo intuire. Nessun concilio visibile, nessuna barra divina.

**Nascosto ma leale.** È il vincolo che regge il gioco: nascosto non deve mai voler dire casuale. La **coerenza vive nel trigger** (una regola stabile: Poseidone reagisce *sempre* alla tracotanza), la **varietà vive nella forma della risposta** (segno, aiuto, castigo, silenzio — decisi dal capriccio). Così la causa è deducibile senza essere mai nominata.

**Omero narratore, reticente.** Un'unica voce epica racconta intro ed esiti. Ma è un aedo che *sa e non dice*: descrive solo ciò che Ulisse può percepire, vago sulle cause ("un dio, e non dirò quale…"). L'Omero vero nomina gli dèi di continuo: qui il vincolo diventa personaggio.

**Deliberazione vera.** Gli dèi si parlano davvero tra loro prima di agire — non azioni parallele riconciliate a posteriori. Poseidone e Atena litigano davanti a Zeus. Va limitata (solo i litiganti, 1–2 giri) per costo e coerenza.

**Capriccio e dono avvelenato.** Cosa ottieni, quando un dio ti ascolta, dipende dal dio e dal suo umore: un segno o un aiuto — o una trappola travestita da aiuto (l'otre di Eolo, l'ospitalità di Circe). Nessuna zona sicura: il silenzio a volte è pietà, l'aiuto a volte è un amo.

**Politica divina.** Gli dèi possono scavalcare Zeus a sua insaputa; quando lui se ne accorge, turni dopo, se la prende col colpevole. La faida ricade sul giocatore di rimbalzo — una tregua o un castigo che *non c'entrano con lui*. Di tanto in tanto gli dei si **coalizzano** in fazioni e perseguono **strategie** a piu turni — sempre come modulazione di sfondo, mai sopra le azioni del giocatore.

**Credibilità — nessun dio suona come un assistente.** Il tradimento più grosso non è *cosa* dice un dio, ma il *registro*: spiegare, prendere le distanze, compiacere, dilungarsi. Un guardrail anti-assistente condiviso (`guardrail_anti_assistente.md`) vale per ogni agente — dèi, Omero, Interprete. E il **tempismo**: non tutti i dèi idonei parlano a ogni turno; il silenzio scelto è parte della credibilità.

---

## 3. Il pantheon

Tutti gli dèi del poema, in due fasce con comportamenti diversi.

**Persistenti** (sempre in ascolto, valutati ogni turno; favore/ira cumulativi — il motore della deduzione): **Atena** (pro-ritorno, premia l'astuzia), **Poseidone** (contro-ritorno, dorme finché non accechi Polifemo), **Zeus** (arbitro, custode di xenia e ordine).

**Locali / episodici** (si attivano solo alla loro tappa, colpiscono forte una volta): **Polifemo** (proxy che innesca Poseidone), **Eolo**, **Circe**, **Ermes** (esecutore di Zeus), **Tiresia** (fonte di segni nell'Ade), **Sirene**, **Scilla**, **Elio** (castigo catastrofico a Trinacia), **Calipso** (anti-ritorno per amore), **Ino/Leucotea** (soccorritrice).

Esclusi di proposito gli dèi dei racconti incassati (Afrodite/Ares/Efesto del canto di Demodoco, Proteo di Menelao): non agiscono nella linea di Ulisse. Reversibile.

Ogni dio ha **impronta** tematica (la firma con cui il narratore lo lascia intravedere: Poseidone = sempre acqua), **agenda**, **voce**, **temperamento**, e i **trigger** che lo svegliano. Dettaglio completo in `pantheon.json`.

---

## 4. L'interazione col giocatore

Una **chat libera** è il cuore, perché è ciò che fa funzionare l'interpretazione divina. Ma nuda paralizza (foglio bianco) e sfora (scope): la si sostiene con **affordance diegetiche** — la ciurma che mormora, un pensiero di Ulisse — che mostrano lo spazio senza chiudere la scrittura. Le **scelte discrete** si tengono solo per i bivi veri (Scilla o Cariddi? apri l'otre?).

Il **diario di bordo** è meccanica, non decorazione: in un gioco di deduzione il giocatore deve poter rileggere il passato per formulare teorie. Reticente, senza nomi, con un marcatore d'esito ambiguo (andò male / parve giovare / neutro).

Nessun pannello divino: le stat di Ulisse (metis, animo, ciurma) sì, il resto resta muto. La sobrietà protegge il mistero. *Mockup di riferimento:* `odissea_interfaccia.html`.

---

## 5. Lo strato divino

Ogni dio-agente, quando reagisce, riceve l'azione interpretata più il proprio stato (favore/ira correnti, umore, agenda) e decide **in carattere** se intervenire e con quale registro (segno / aiuto / castigo / trappola / silenzio) e intensità.

Se due o più dèi confliggono, parte la **deliberazione vera**; l'**Arbitro** (Zeus) chiude con un verdetto, calcola il delta sul mondo e su Ulisse, aggiorna il registro nascosto.

Sopra a tutto, la **politica divina**: un dio bocciato può scavalcare Zeus di nascosto (registra un pendente + applica un delta occulto). Un **sospetto** in capo a Zeus sale ogni turno — una spia rivale lo accelera — e alla soglia scatta la **resa dei conti**: Zeus confronta il colpevole e ne cova ira (`relazioni.zeus_verso`), con ripercussioni che rimbalzano su Ulisse.

Di tanto in tanto gli dei si **coalizzano**: due o piu con un interesse condiviso fanno blocco, spalleggiandosi nella deliberazione (un blocco di voto che pesa sull'Arbitro) e unendo influenza per scavalcare o persino sfidare Zeus. Rare, col tetto, e instabili: si sciolgono a obiettivo raggiunto o quando gli interessi divergono. In parallelo i singoli dei possono avere **strategie**: un `piano` leggero (obiettivo + innesco) che inclina le loro reazioni invece di sostituirle — la pazienza crudele di Poseidone, che aspetta il momento peggiore per colpire. Al giocatore arrivano come ondate coordinate e tempismi crudeli; restano modulazione di sfondo, mai la causa dominante (che resta l'azione di Ulisse), e vanno tenute rare per non annegare il segnale deducibile.

Tutto questo il giocatore non lo vede. Lo vede solo lo sviluppatore, nella **vista Olimpo** (debug attivabile): l'inverso della schermata del giocatore, tutto nominato — envelope, deliberazione, verdetto, scavalcamenti. La stessa vista è anche la **rivelazione di fine partita** (chi ti amava, chi ti odiava). *Mockup di riferimento:* `odissea_vista_olimpo.html`.

---

## 6. Validazione e ammonizione

L'input fuori contesto ("sparo al ciclope", "prendo un aereo") va gestito **in modo diegetico**, mai con un box d'errore. La `plausibilita` è un campo dell'Interprete (in_mondo / assurdo_diegetico / anacronistico / meta_nonsenso), a costo quasi zero.

La scala è a gradini: prima Omero si rifiuta di narrarlo e ti riporta dentro; se insisti, il mondo lo legge come smarrimento e l'animo cala; se perseveri, gli dèi lo prendono per empietà e follia — e uno colpisce (game-over `follia`). La morte non è un "validatore con la skin di Poseidone": è **empietà contro l'ordine**, che ricade già nella sua agenda.

Cautela obbligatoria: i falsi positivi qui **uccidono**, quindi scala dolce all'inizio, letale solo dopo nonsenso ripetuto e inequivocabile; e le ammonizioni **decadono** se torni a giocare sensato.

---

## 7. Rigiocabilità

Via di mezzo: **trigger fissi** (la logica mitologica canonica — una maestria che ti porti tra le partite), ma **capricci, umori e ordine degli episodi variabili** a ogni partita (guidati dal `seed`). La conoscenza si trasferisce, ma ogni run sorprende.

---

## 8. Architettura

Idioma Godot Autoload, come da prassi. Quattro pilastri:

- **Data layer** — `pantheon.json`: statico, tutti gli dèi, `attivo` come interruttore di stadio.
- **Contratto dell'Interprete** — vocabolario chiuso dei tag + envelope JSON di output. Ponte tra testo libero e trigger.
- **Stato di partita** — `stato_partita.json`: runtime. Registro divino nascosto, ammonizioni, diario, storico Olimpo, relazioni divine, scavalcamenti pendenti.
- **Macchina del turno** — l'orchestrazione.

Singleton previsti: **GameManager** (stato, FSM del turno, esiti), **PantheonManager** (risveglio, ledger, umori), **LLMManager** provider-agnostico. Agenti logici via LLM: Interprete, Dèi, Arbitro, Narratore (Omero).

La FSM del turno: `RESA_DEI_CONTI → ATTESA_INPUT → INTERPRETAZIONE → (VALIDAZIONE) → RISVEGLIO → DELIBERAZIONE → ARBITRATO → (SCAVALCAMENTO) → APPLICAZIONE → NARRAZIONE → ESITO → AVANZAMENTO`. Diagramma completo in `macchina_del_turno.mermaid`.

**Budget di chiamate LLM per turno** (conta sul tier gratuito): turno muto ~2 (Interprete + Omero); turno normale ~4; turno con deliberazione ~6–9. La deliberazione vera è la voce cara: tenerla ai soli dèi in conflitto e a 1–2 giri la rende sostenibile.

Il principio "nascosto ma leale" si riflette nel codice: il **trigger-gate è regola** (GDScript deterministico), la **risposta è LLM** (carattere e capriccio). Un **filtro di ritmo** sul risveglio — non tutti gli idonei reagiscono ogni volta — protegge insieme la credibilità e il budget di chiamate.

---

## 9. Modello LLM e piano di rollout

Layer LLM **provider-agnostico**, costruito sul formato chat-completions di OpenAI: modello, `base_url` e chiave stanno in config. Ollama, Mistral e l'endpoint compatibile di Anthropic parlano tutti quella lingua — cambiare provider è cambiare impostazioni, non codice.

Modello di partenza: **Mistral (Large 3) sul tier gratuito** — italiano di casa, dati in UE, e per un giocatore singolo di fatto gratis.

Rollout a stadi (interruttore = `attivo` nel pantheon + provider in config):

1. **Ollama in locale** — solo *plumbing* (loop, chiamate, JSON, stato, vista Olimpo). Non si giudica qui la scrittura.
2. **Mistral gratis, pantheon ridotto** (i 3 persistenti) — qui si giudica e si tarano le personalità.
3. **Mistral gratis, pantheon pieno** — si accendono i locali, un episodio alla volta.

Regola d'oro: Ollama è il collaudo dell'impianto, non il metro della scrittura. La taratura vera comincia allo stadio 2.

---

## 10. Inventario dei file

- `pantheon.json` — data layer (schema 0.2)
- `contratto_interprete.md` — contratto dell'Interprete (v0.1)
- `stato_partita.json` — schema dello stato runtime (0.2)
- `macchina_del_turno.mermaid` — orchestrazione del turno
- `odissea_interfaccia.html` — mockup schermata giocatore
- `odissea_vista_olimpo.html` — mockup vista Olimpo (debug)
- *questo documento* — congelamento del design

---

## 11. Esiti

Vittoria: **itaca**. Sconfitte: **morte**, **ciurma_perduta**, **prigionia_eterna** (Calipso, se non riparti mai), **follia** (nonsenso reiterato).

---

## 12. Punti aperti

Da decidere prima o durante lo sviluppo:

- La distinzione fine tra *bivio* (scelta secca) e *azione parlata* (testo libero), episodio per episodio.
- Polarità esplicita dei tag (xenia onorata vs violata, ecc.) — rimandata a contratto v0.2 se il tagging risulta ambiguo.
- Contenuto e obiettivi di ogni episodio (condizioni di avanzamento, dilemmi).
- Taratura numerica di stat, soglie ed esiti (per ora valori-seme).
- Probabilità e vincoli dello scavalcamento (tenerlo raro, per non annegare il segnale deducibile).
- Frequenza e coesione delle coalizioni, e quanto le strategie a più turni possono inclinare senza diluire il legame azione -> conseguenza.
- Se reintrodurre gli dèi dei racconti incassati come colore.

---

## 13. Roadmap di implementazione

Fette sottili e testabili; il provider segue il rollout Ollama -> Mistral.

0. **Scaffolding + Data Layer** — progetto, Autoload vuoti, caricamento pantheon, load/save stato. (Ollama non serve ancora.)
1. **LLMManager + Interprete** — client provider-agnostico su Ollama; testo -> envelope validato. Lo spike più rischioso, presto.
2. **Ciclo del turno minimo** — FSM fino a Omero; dei solo *selezionati* (risveglio), non ancora chiamati.
3. **I dei reagiscono + Arbitro** — un solo dio, delta, Omero reticente. Prima fetta giocabile; qui si passa a **Mistral** e si tarano le personalità.
4. **Deliberazione vera** — conflitto tra dei + vista Olimpo minima.
5. **Validazione & ammonizione** — plausibilità, scala diegetica, decadimento, follia.
6. **Politica divina** — scavalcamento + resa dei conti + `zeus_verso`.
6. **-bis · Coalizioni & strategie** — alleanze temporanee e piani a più turni. Rare e bounded; *dopo* il nucleo, non blocca l'MVP.
7. **Episodi (pantheon pieno)** — `episodi.json`, locali accesi uno per volta; si parte dal Ciclope.
8. **UI vera + diario + rifinitura** — mockup, due voci, toggle Olimpo.

**Consigli pratici:** console di debug prima della UI; LLMManager mockabile (FSM testabile a LLM spento); chiamate async + JSON difensivo; system prompt fuori dal codice; seed presto.
