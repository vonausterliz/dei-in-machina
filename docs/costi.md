# Le scelte dettate dal costo — inventario

*Ricognizione sul codice a v2.30. Base per i **profili di costo** configurabili.*

Tredici scelte di questo gioco non sono state prese perché rendevano il gioco migliore, ma
perché **una chiamata LLM in più costava troppo** sul tier gratuito (dove il vincolo non è
il prezzo ma il pavimento richieste/secondo: Mistral ~1 req/s). Questo documento le elenca
tutte, in un posto solo, così si può decidere quali tenere.

Riferimento: una partita intera vale **~450 chiamate e ~1,03 M token** (`tools/stima_costo/`).

---

## La classificazione, che è il punto

Non tutte queste scelte sono uguali, ed è la cosa più importante prima di costruire un
profilo «senza vincoli»:

| Classe | Significato | Togliendo il limite… |
|---|---|---|
| 💰 **Puro costo** | Deciso solo per risparmiare chiamate | …il gioco migliora o resta uguale, e costa di più |
| ⚖️ **Costo + design** | Il risparmio coincideva con una ragione narrativa | …il gioco **può peggiorare**: va alzato il tetto, non tolto |
| 🔒 **Diventato meccanica** | Nato per costo, oggi è una regola di gioco | …non è un knob: cambierebbe il gioco, non il conto |

---

## 1. 💰 Puro costo — si possono togliere

| # | Scelta | Dove | Oggi | Se tolto |
|---|---|---|---|---|
| C1 | La **cronaca** si aggiorna ogni N turni, non ogni turno | `bilanciamento.json` → `memoria/cronaca_ogni: 4` | 1 chiamata ogni 4 turni | Memoria più fresca per tutti gli agenti. **+19 chiamate** a partita |
| C2 | Il **condensato della memoria** di ogni dio è calcolato in GDScript | `game_manager.gd::riassunto_memoria` | 0 chiamate | Un riassunto scritto dall'LLM sarebbe più vivo. **+1 per dio ogni N turni** — la voce più cara di tutte |
| C3 | **Omero e gli spunti in una chiamata sola** | `narratore.gd::narra_e_suggerisci` | 1 chiamata | Spunti generati a parte, con un prompt dedicato. **+72** |
| C4 | Il **vaglio** si salta se il testo è uno spunto già offerto | `game_manager.gd::_vaglia_plausibilita` | ~46 vagli su 76 turni | Nessun guadagno di qualità (è in-mondo per costruzione). **+30** |
| C5 | **Omero tace** sui turni fuori-mondo | `esegui_turno` | 0 chiamate | Nessuno: chiedergli di «non narrare» non funzionava comunque |
| C6 | La **ricognizione LLM del dio invocato** parte solo con un indizio | `_indizio_invocazione` | ~8 chiamate | Riconoscerebbe parafrasi più oscure. **+68** |
| C7 | Le proposte degli dèi sono **seriali**, non parallele | `_raccogli_proposte` | — | Turno molto più rapido. Non cambia il numero di chiamate, ma **sfonda il pavimento req/s** del tier gratuito |
| C8 | La **cronaca** è capata a ~120 parole | `prompts/cronista_system.txt` | prompt costante | Memoria più ricca, prompt che cresce a ogni turno |
| C9 | I **ricordi per dio** tenuti per esteso sono 5 | `bilanciamento.json` → `memoria/ricordi_per_dio` | prompt costante | Un dio ricorda più cose per esteso; prompt più lungo |

## 2. ⚖️ Costo + design — alzare, non togliere

| # | Scelta | Dove | Oggi | Attenzione |
|---|---|---|---|---|
| D1 | **Al massimo 2 dèi ribattono** per turno | `game_manager.gd` → `MAX_REPLICHE = 2` | +0,5 chiamate/turno | Il commento nel codice dice due cose insieme: «ogni replica è una chiamata» **e** «una conversazione a cinque non è più una conversazione». Togliere il tetto rende la Vista Olimpo un coro confuso |
| D2 | **Un solo compagno parla** spontaneamente | `_fa_parlare_la_ciurma` | 1 chiamata | La ragione scritta è «per non affollare»: con sei voci a ogni turno la chat diventa illeggibile. Ma il limite vale solo per chi parla *da sé*: **se li chiami per nome rispondono tutti**, quindi una valvola in mano al giocatore c'è già |
| D3 | Il **filtro di ritmo** sul risveglio (mai implementato, G-15) | — | tutti gli innescati reagiscono | Qui è il contrario: implementarlo **risparmierebbe** chiamate *e* migliorerebbe la credibilità (il silenzio scelto è un personaggio) |

## 3. 🔒 Diventato meccanica — non è un knob

| # | Scelta | Perché non si tocca |
|---|---|---|
| M1 | I **beat**: parlare ai compagni non fa girare il mondo (1 chiamata invece di 9) | Nato da una richiesta di **fluidità** (v2.9: «due ritmi invece di uno»); il risparmio venne in regalo. Oggi è una regola di gioco: le parole restano in sospeso e il turno successivo le consegna all'Interprete — perché i trigger scattino lo stesso — agli dèi e a Omero. Renderli turni pieni non toglierebbe un limite: **svuoterebbe di senso le parole in sospeso**, farebbe destare un dio per ogni frase detta a bordo (e la deduzione annegherebbe nel rumore), e smentirebbe sei test in `test_ciurma.gd`. Il knob tarabile *dentro* i beat è un altro, ed è D2: quanti compagni rispondono |

> **Corretto il 3 agosto 2026 — qui c'era una seconda voce, il congedo, e non ci doveva
> stare.** L'avevo elencata come «🔒 non è un knob», ma la frase vera è che il congedo **non
> è mai stato una limitazione di costo**: è una chiamata sola perché è un epitaffio, non
> perché ne avessi vietate altre. Il commento nel codice dice «non pesa sul turno», e avevo
> scambiato una *giustificazione* per un *vincolo*. Un inventario di vincoli deve contenere
> solo cose che qualcuno potrebbe voler togliere.

---

## Le decisioni prese (3 agosto 2026) e cosa è stato costruito

**I 💰 entrano nel profilo. I ⚖️ si alzano, ma restano configurabili da Settings. I beat non
si toccano.**

Costruito: `data/profili_costo.json` (i due preset, non modificabili), `scripts/data/costi.gd`
(`Costi.limite()` / `Costi.acceso()`), e una **scheda «Costi»** in Impostazioni che si
disegna dai descrittori — aggiungere un limite ai dati lo fa comparire nel pannello da solo,
senza toccare l'interfaccia. I profili creati dall'utente vivono nelle sue preferenze; si
crea sempre **a partire da uno esistente**, così si modifica invece di compilare da zero.

### I sette limiti collegati

| Limite | Frugale | Senza vincoli |
|---|---:|---:|
| `cronaca_ogni` (C1) | 4 | 1 |
| `ricordi_per_dio` (C9) | 5 | 12 |
| `spunti_separati` (C3) | no | **no** (era «sì»: vedi sotto) |
| `vaglia_sempre` (C4) | no | sì (ma **non respinge**: guarda e annota) |
| `ricognizione_sempre` (C6) | no | sì |
| `max_repliche` (D1) ⚖️ | 2 | **4** (alzato, non tolto) |
| `compagni_per_turno` (D2) ⚖️ | 1 | **2** (alzato, non tolto) |

### Il limite che una misura ha spento

`spunti_separati` (C3) era acceso nel profilo «Senza vincoli»: chiedeva i tre appigli con una
chiamata dedicata, ~72 su una partita intera — il **singolo limite più caro** dell'elenco. La
ragione era di qualità: gli appigli scritti da un agente che non sta contemporaneamente
cercando di essere un poeta sono più mirati.

Era vero. Misurato il 9 agosto 2026 con `tools/prova_spunti/` contro il modello vero (Ollama
locale, `mistral-small3.2`, sei scene, quattro giri): la strada gratis dava **11 appigli
storti su 13** — punto e virgola della prosa in coda, infiniti, plurali, terza persona
(«Promette a Calipso di tornare») — contro 1 su 16 della strada a pagamento.

Sistemata la forma nei due prompt con esempi contrastivi, e ripulito in codice ciò che è
oggettivo (`Viaggio.ripulisci()`: virgolette, grassetto markdown, punteggiatura d'elenco), le
due strade si equivalgono: **16 appigli su 18 per entrambe**, 3 storti contro 2. Da lì il
limite è spento anche nel profilo libero. Resta accendibile, perché la misura vale per **un**
modello: se ne provi un altro e gli appigli di Omero peggiorano, quella chiamata è la rete.

> **Regola che ne esce, e vale per tutti gli altri:** nessun limite di costo si toglie senza
> averlo misurato col modello vero. La stessa misura, prima delle correzioni, diceva che
> questo limite serviva eccome. La prossima candidata è `cronaca_ogni` nel profilo libero
> (1 → 4: ~19 chiamate a partita), e lì si paga in coerenza della memoria, non in secondi.

### I quattro che NON sono diventati knob, e perché

Un interruttore che non fa niente è peggio di un interruttore assente. Questi quattro non
sono commutabili sul codice di oggi:

- **C2** (condensato della memoria scritto dall'LLM) — non esiste il percorso: servirebbe un
  agente nuovo. È una funzionalità da costruire, non un limite da togliere.
- **C5** (Omero anche fuori-mondo) — il percorso fu *rimosso* perché non funzionava: al
  modello si chiedeva di «non narrare un gesto impossibile» e lo narrava lo stesso. Lo stato
  «acceso» è noto-cattivo, e offrirlo sarebbe offrire un difetto.
- **C7** (proposte in parallelo) — è L-11 nei requisiti: vuole un layer a segnali, perché
  GDScript non consente coroutine non-`await`. Lavoro a sé.
- **C8** (cap della cronaca a ~120 parole) — vive nel testo di `prompts/cronista_system.txt`,
  non nel codice. Si cambia editando il prompt.
- **D3** (filtro di ritmo) — non è mai stato implementato: è G-15, un requisito aperto, e
  *risparmierebbe* chiamate invece di costarne.

---

## Le domande da cui è partito tutto (risposte sopra)

**(a) Cosa deve contenere davvero il profilo «senza vincoli»?**
La mia proposta: toglie tutti i 💰 (C1–C9), **alza** i ⚖️ senza rimuoverli (`MAX_REPLICHE`
da 2 a 4, compagni che parlano da 1 a 2), e non tocca i 🔒. Un profilo che alza *tutto* al
massimo produrrebbe un gioco più caro **e peggiore**, il che non è ciò che serve.

**(b) Quanto deve essere libera la creazione di profili?**
Tre livelli possibili:
1. solo i due preset, si sceglie dal menu;
2. i due preset + un profilo «Personale» che l'utente modifica knob per knob;
3. creazione, denominazione e cancellazione di quanti profili si vuole.

Il 2 costa poco più dell'1 e copre quasi tutti i casi reali. Il 3 vuole una gestione di
elenco nelle Impostazioni.

**(c) Dove vivono i knob?**
Oggi C1 e C9 stanno in `data/bilanciamento.json`, che però è il file della **taratura di
gioco** (delta, coalizioni, soglie). Proposta: spostare i knob di costo in
`data/profili_costo.json`, dove stanno i due preset, e lasciare a `bilanciamento.json` solo
ciò che riguarda l'equilibrio narrativo. Una cosa sola in un posto solo.

**(d) Il profilo deve essere visibile in partita?**
Con «senza vincoli» un turno può passare da 6 a ~10 chiamate e diventare sensibilmente più
lento. Propongo di mostrare il profilo attivo accanto al motore nell'intestazione, com'è già
per il modello.
