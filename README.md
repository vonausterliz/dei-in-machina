# Dei in machina

> *«Canta, o Musa, l'uomo dall'ingegno multiforme…»*

**Tu sei Ulisse. Gli dèi sono programmi che non vedrai mai.**

*Dei in machina* è un gioco di testo sull'*Odissea*. Scrivi in italiano quello che vuoi fare — non scegli da un menù, non impari comandi — e Omero racconta cosa succede. Ma Omero è reticente: ti dice che il mare si è alzato, mai *chi* l'ha alzato. Sopra la tua testa, in una stanza che non puoi vedere, tredici divinità con obiettivi inconciliabili discutono cosa farti. A dar loro voce sono dei modelli di intelligenza artificiale — gli stessi che muovono i chatbot — ciascuno calato nei panni di un dio diverso.

Atena ti protegge finché sei astuto. Poseidone dorme — e continuerà a dormire, qualunque cosa tu faccia, finché non griderai il tuo nome a suo figlio. Zeus arbitra, quando c'è da arbitrare.

Il gioco vero non è arrivare a Itaca. È capire **chi hai svegliato, e come**.

> **In breve** — Digiti le tue azioni a parole, come parlassi a voce. Un'AI le interpreta, delle regole fisse decidono quali dèi si svegliano, e gli dèi-AI reagiscono ognuno a modo suo. Non vedi mai i loro nomi: la storia che leggi è tutto ciò che hai per dedurre chi sta muovendo i fili.

### Colpo d'occhio

|                       |                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------- |
| **Cos'è**             | Gioco narrativo a turni, a testo libero, per un solo giocatore                         |
| **Come si gioca**     | Scrivi in italiano cosa fa Ulisse; leggi il racconto di Omero                          |
| **La sfida**          | Intuire quale divinità hai risvegliato, e perché                                       |
| **Cosa serve**        | Un motore di AI a tua scelta — sul tuo computer (gratis, con Ollama) o in rete         |
| **Piattaforme**       | Linux · macOS *(Windows non supportato)*                                               |
| **Per cominciare**    | Un solo comando: `./avvia.sh` — scarica e prepara tutto da sé                          |
| **Lingua del gioco**  | Italiano                                                                               |

[![La schermata di gioco](https://github.com/vonausterliz/dei-in-machina/raw/main/docs/immagini/schermata.png)](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/immagini/schermata.png)

---

## Un turno, dall'inizio alla fine

Il modo più rapido di capire come funziona è vederne uno.

Sei nell'antro del Ciclope. L'hai accecato, e state scappando. Scrivi:

> *Grido al ciclope il mio vero nome: sono io, Odisseo!*

Ecco cosa succede, nell'ordine.

**1 · La frase viene letta e classificata.** Un'AI legge quello che hai scritto e lo riduce a poche etichette prese da un elenco chiuso — qui `vanto` e `tracotanza`, ad alta intensità. È un giudizio, e potrebbe darne uno diverso: è l'unico punto in cui la libertà di *come* scrivi entra nel meccanismo.

**2 · Da qui comandano le regole, non l'AI.** Nella tappa del Ciclope un `vanto` fa accadere un fatto preciso: *la maledizione di Polifemo*. E quel fatto è ciò che desta Poseidone, che fino a un istante prima **dormiva** e non poteva reagire a nulla — nemmeno all'accecamento di suo figlio. Nessuna AI ha voce in capitolo qui: è una riga di dati, uguale ogni volta.

**3 · Gli dèi svegli reagiscono, e qui non comanda nessuno.** Poseidone dice quello che gli pare, restando in carattere. Se è sveglia anche Atena, i due si ribattono. Ognuno propone *come* agire scegliendo fra i modi che gli appartengono — castigo, aiuto, segno, trappola — e con quanta forza.

**4 · La conseguenza torna a essere una regola.** «Castigo, intensità 2» vale sempre lo stesso: quattro punti di animo in meno, quattro di ira in più, e un compagno che non torna. L'AI sceglie *cosa* fare; quanto pesa è deciso altrove, da numeri fissi.

**5 · Omero racconta.** Senza nominare nessuno. Leggi che il mare si è fatto nero e che un uomo è caduto in acqua. Chi sia stato, lo devi capire tu.

---

## Regole fisse, voci che non si ripetono

Due partite con le stesse mosse non raccontano la stessa storia: a leggere la tua frase c'è un'AI, a risponderti ce n'è un'altra, e nessuna delle due si ripete mai identica. Ma il **nesso fra causa ed effetto** è scritto nelle regole, e non cambia.

| Scritto nelle regole — uguale ogni volta                   | Deciso da un'AI — mai due volte uguale            |
| ---------------------------------------------------------- | ------------------------------------------------- |
| Quali fatti svegliano quale dio, e chi sta ancora dormendo | Come la tua frase viene interpretata              |
| Quanto pesa una certa reazione a una certa intensità       | Se punirti, aiutarti o ignorarti — e con che voce |
| Quando la tappa avanza, e chi muore alla sua tappa         | Cosa si dicono gli dèi fra loro                   |
| Cosa non ti verrà mai proposto come appiglio               | Come Omero racconta ciò che è successo            |

Questa divisione **è** il gioco. Se fosse un'AI a decidere chi si sveglia, non ci sarebbe niente da dedurre: la stessa mossa darebbe esiti diversi per capriccio, e resterebbe un generatore di eventi con un bel lessico. Le regole rendono il mondo **leggibile**; l'AI gli dà una voce che non si esaurisce.

---

## La stanza degli dèi

C'è una finestra sul concilio. Tu la vedi, Ulisse no.

[![La Vista Olimpo](https://github.com/vonausterliz/dei-in-machina/raw/main/docs/immagini/vista-olimpo.png)](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/immagini/vista-olimpo.png)

Gli dèi si destano, parlano, si ribattono, e alla fine **uno agisce**. Chi la spunta non viene annunciato da nessuna scritta: si capisce perché è l'unico che muove la mano. Se qualcuno vuole punirti mentre un altro vuole aiutarti, interviene Zeus e chiude con parole sue.

È una finestra di servizio, non una scorciatoia: quello che leggi lì Ulisse non lo sa, e il racconto continua a non nominare nessuno. Se preferisci il mistero pieno, puoi tenerla chiusa e giocare al buio.

---

## Quindici tappe, da Troia a Itaca

[![La carta del viaggio](https://github.com/vonausterliz/dei-in-machina/raw/main/docs/immagini/carta.png)](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/immagini/carta.png)

Ogni capitolo ha la **sua musica**, suonata con strumenti dell'epoca — lira, kithara, aulos doppio, tamburo a cornice. Ogni brano è costruito per ripartire da capo senza stacchi udibili: niente finale, niente dissolvenza, perché una musica di sottofondo non sa quanto durerà la scena. Aggiungerne uno è semplicissimo: basta posare un file audio nella cartella `music/` col nome del capitolo — per esempio `ciclope.mp3` — senza nessuna configurazione. I testi usati per generarli sono [nel repository](https://github.com/vonausterliz/dei-in-machina/blob/main/music/README.md): la "partitura" si legge e si può rifare.

Le coste sono vere (dati geografici Natural Earth, ridisegnati); la rotta è quella del poema. I compagni hanno un nome e un carattere, e **puoi parlare con loro**: farlo non costa quasi nulla e non fa girare tutto il resto — ma quello che dici a bordo lo sentono anche gli dèi, al turno dopo. Chi deve morire muore alla sua tappa, come sta scritto nel mito: e da quel momento la sua voce sparisce dalla conversazione.

---

## Tre garanzie

**Gli dèi restano nascosti.** Il racconto non nomina mai una divinità — nemmeno per allusione trasparente, nemmeno quando l'AI sarebbe tentata di farlo. Non è affidato alla buona volontà: è controllato in automatico a ogni giro di test.

**Quello che il gioco ti propone, il gioco lo accetta.** Se il gioco ti suggerisce tre possibili appigli sotto il racconto, nessuno di quei tre potrà poi esserti rifiutato come «gesto che non appartiene a questo mondo». E il gioco non ti offrirà mai di aprire l'otre dei venti prima che Eolo te l'abbia dato.

**La spesa è dichiarata in anticipo, non scoperta a fine mese.** Una partita intera, da Troia a Itaca, sono all'incirca **450 richieste all'AI e 1,03 milioni di token** (i token sono i frammenti di testo con cui si misura il lavoro di un'AI). Quasi tutti sono in *ingresso*: il costo di un gioco così è il contesto che si rilegge a ogni turno, più che le parole che genera. Con Ollama, sul tuo computer, paghi in tempo invece che in denaro. Un *profilo di costo*, dal "Frugale" in su, decide quante voci divine parlano a ogni turno. È una **stima**, non un tetto imposto dal gioco: cosa copre e cosa no è spiegato in [Stato del collaudo](#stato-del-collaudo).

---

## Requisiti

### Software

|                                  |                                                                                                                                                 |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **Sistema**                      | Linux x86\_64 · macOS (Intel o Apple Silicon)                                                                                                    |
| **Motore grafico**               | Godot **4.7.x** — non devi installarlo: `avvia.sh` lo scarica al primo avvio (~138 MB) e **ne verifica l'integrità** (impronta SHA-512) prima di eseguirlo |
| **Già nel sistema**              | `bash`, `curl`, `unzip`, `sha512sum` (o `shasum`) — di norma presenti su Linux e macOS                                                          |
| **Per il Gateway** (facoltativo) | `python3` ≥ 3.9, senza librerie esterne                                                                                                          |
| **Spazio su disco**              | ~13 MB il progetto, ~138 MB Godot, più i modelli di AI se usi Ollama                                                                             |

Windows non è supportato dallo script d'avvio. Il progetto è Godot puro e si apre anche con un Godot 4.7 installato a mano, ma è una configurazione non collaudata.

### Chi dà voce agli dèi

Serve **un** motore di AI, a scelta tua. Il gioco non ne include nessuno: gli dèi sono muti finché non ne colleghi uno.

**Sul tuo computer — Ollama.** Nessuna chiave, nessun costo, nessun dato che esce di casa. Il gioco è tarato su **Mistral Small 3.2 (24 B)**: è il modello su cui gli otto testi-guida degli agenti sono stati scritti e misurati.

| Se hai…                | Cosa aspettarti                                                                          |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| **≥ 16 GB di VRAM**    | Mistral Small 3.2 gira sulla scheda video: fluido *(la VRAM è la memoria della scheda grafica)* |
| **8–12 GB di VRAM**    | Va bene un modello più piccolo, da 7–8 B, in versione alleggerita; il 24 B parte, ma lento |
| **Solo RAM (≥ 16 GB)** | Funziona senza scheda video dedicata, ma un turno può richiedere minuti                   |
| **< 8 GB in tutto**    | Meglio affidarsi a un servizio in rete                                                    |

Non devi indovinare da solo: in *Impostazioni* ogni modello che hai installato ha un **verdetto** accanto — ✓ ci gira · ? ci gira ma lento · ✗ non ci sta — calcolato sulla memoria reale della tua macchina, con la spiegazione nel suggerimento.

**In rete — Mistral, Google, OpenAI, Anthropic, OpenRouter.** Serve una tua chiave (una specie di password che il servizio ti dà). Si inserisce in *Impostazioni* e finisce nella cartella dati del tuo utente: **mai dentro il progetto, mai in un commit** su GitHub. In alternativa puoi passarla come variabile d'ambiente, se preferisci non scriverla da nessuna parte.

| Servizio                  | Provato davvero                                            |
| ------------------------- | --------------------------------------------------------- |
| Ollama · Mistral · Google | **sì** — con partite vere, non solo con i test            |
| OpenAI                    | supporto presente, mai provato contro il servizio reale   |
| Anthropic · OpenRouter    | supporto presente, **mai provato** contro il servizio reale |

I servizi non provati sono stati configurati seguendo la documentazione ufficiale, non una risposta vista arrivare davvero. Se ne provi uno e funziona — o non funziona — segnalarlo è il modo più utile di contribuire.

### La chiave di Mistral, passo per passo

È il servizio in rete su cui il gioco è tarato, e il suo piano gratuito basta per giocare.

1. Registrati su **[console.mistral.ai](https://console.mistral.ai)**.
2. Attiva il piano gratuito. Mistral chiede la **verifica del numero di telefono**: finché non la fai, la chiave esiste ma ogni richiesta torna un errore di autorizzazione — un errore che *sembra* una chiave sbagliata, ma non lo è.
3. Vai su **API Keys → Create new key.** Il valore si vede **una volta sola**: copialo subito.
4. Dàlla al gioco in uno dei due modi:
   - *Impostazioni* → provider **Mistral** → incolla nel campo. Finisce nel file `user://impostazioni.json`, fuori dal progetto e fuori da git.
   - Oppure `export MISTRAL_API_KEY=...` da terminale prima di avviare. Questa ha la precedenza sul campo, e se usi il Gateway è **l'unica** strada che funziona.
5. **Aggiorna elenco** → scegli `mistral-small-latest` → **Prova il modello**. Quel pulsante fa una vera richiesta: è l'unico modo di sapere che tutta la catena regge.

Le stesse cose valgono per Google (variabile `GEMINI_API_KEY`, chiave da [aistudio.google.com](https://aistudio.google.com/apikey)).

### Il Gateway: come restare dentro il piano gratuito

*Il Gateway è un piccolo programma-filtro che si mette fra il gioco e il servizio di AI, per non superare i limiti dei piani gratuiti. È facoltativo.*

Sui piani gratuiti il limite vero non è quanto usi in totale, ma **quante richieste fai al secondo**. Un turno pieno ne fa fino a nove, quasi tutte insieme: senza un freno, la maggior parte tornerebbe l'errore `429` (che vuol dire "troppe richieste").

`llm_gateway/` è un programma Python separato (usa solo la libreria standard, nessuna dipendenza) che parla lo stesso linguaggio di OpenAI e sta **davanti** al servizio. Il gioco lo usa cambiando solo l'indirizzo a cui parla: tutta la gestione dei limiti vive lì, e per toglierla basta spegnere il programma.

Per ogni richiesta, in quest'ordine:

1. **Cache** — se è già stata chiesta di recente la stessa identica cosa → risposta immediata, **senza consumare quota** (validità un'ora, fino a 500 risposte tenute da parte).
2. **Coda** — una fila per ogni servizio, servita da un solo addetto: mai due richieste in volo verso lo stesso servizio nello stesso momento.
3. **Freno** — tre vincoli insieme: una distanza minima fra due richieste, un tetto al minuto e un tetto al giorno.
4. **Ritentativo** — se arriva `429` o un errore del servizio (`5xx`), riprova aspettando sempre di più (1s, 2s, 4s…), rispettando l'indicazione `Retry-After` quando il servizio la manda.

I limiti sono nel file `llm_gateway/limiti.json`, tenuti **prudenti** di proposito: le finestre di conteggio del servizio non coincidono al millisecondo con le nostre.

| Servizio            | Distanza minima | Al minuto | Al giorno |
| ------------------- | --------------- | --------- | --------- |
| `mistral`           | 1,1 s           | 28        | —         |
| `google`            | 4,2 s           | 14        | 1400      |
| `openrouter`        | 3,1 s           | 18        | **50**    |
| `anthropic`         | 1,4 s           | 45        | —         |
| `openai` · `ollama` | nessun freno    |           |           |

Quel **50** è una trappola dichiarata: i modelli di OpenRouter col suffisso `:free` hanno un tetto giornaliero *per account*, e una partita intera chiede ~450 richieste. Non ci sta. Il Gateway lo scrive nel log all'avvio, invece di fartelo scoprire a metà viaggio. Anche il fatto che Anthropic non abbia affatto un piano gratuito viene detto all'avvio.

**E il Gateway non passa mai di nascosto a un altro servizio.** Se gliene chiedi uno che non conosce, risponde con un errore che dice quali conosce e dove aggiungerlo. In una versione precedente ripiegava sul servizio predefinito, e così una configurazione sbagliata diventava, senza dirtelo, la risposta di un altro modello: ora una regola ferma tiene il punto (verificata da otto scenari di test con servizi finti).

```
export MISTRAL_API_KEY=...        # le chiavi le tiene il Gateway, non il gioco
cd llm_gateway && ./gateway.sh start
```

Poi, in *Impostazioni*, spunta il **Gateway**. È un *canale di trasporto*, non un servizio a sé: si combina con il modello che hai già scelto.

Una cosa importante da sapere: il Gateway legge le chiavi **dal proprio ambiente**. La chiave scritta in *Impostazioni* non gli arriva: senza `export`, ogni richiesta torna l'errore `401` (chiave mancante o non valida) e sembra un guasto del gioco — ma il log lo dice chiaro: `CHIAVE MANCANTE`.

Il Gateway ascolta **solo sul tuo computer** (`127.0.0.1`), non ha autenticazione e non deve averne: non va mai esposto in rete. Dettagli in **[llm_gateway/README.md](https://github.com/vonausterliz/dei-in-machina/blob/main/llm_gateway/README.md)**.

---

## Stato del collaudo

Detto chiaramente, perché stai per collegarci una chiave che può costare.

**Cos'è verificato.** 472 test automatici su 46 script, eseguiti a ogni modifica, più sei turni di esempio registrati come riferimento e confrontati riga per riga. Coprono tutta la parte a regole fisse — risvegli, calcoli, avanzamento delle tappe, interfaccia — usando una finta AI al posto di quella vera.

**Cosa non è verificato.** Il gioco **non ha alle spalle un lungo collaudo da parte di persone**: non è stato giocato molte volte, da molta gente, con modelli di AI reali. I test dicono che la parte a regole fa quello che deve; non dicono che una partita di settantasei turni con un'AI vera non incappi in qualcosa di storto. I collegamenti provati sul serio, contro il servizio reale, sono **Ollama, Mistral e Google**; **Anthropic e OpenRouter no**.

**Nessuna garanzia.** Il software è fornito «così com'è», senza garanzie di alcun tipo, come previsto dalle sezioni 15 e 16 della licenza AGPL-3.0. Chi lo pubblica **non risponde** di malfunzionamenti, perdita di dati o partite, né di **costi verso i servizi di AI** — compresi consumi imprevisti o eccessivi dovuti a un difetto del software, a un ciclo di richieste che non si ferma o a una configurazione sbagliata.

La chiave è tua, il piano è tuo, la spesa è tua: **tieni d'occhio il consumo** sulla console del tuo servizio e imposta un tetto di spesa dove è possibile. Se questa parte ti preoccupa, gioca con **Ollama**: nessuna chiave, nessuna fattura possibile.

---

## Comincia

Su **Linux** e **macOS**, un comando solo:

```
git clone https://github.com/vonausterliz/dei-in-machina.git
cd dei-in-machina
./avvia.sh
```

È tutto. Lo script riconosce il tuo sistema, scarica la versione giusta di Godot, ne verifica l'integrità, prepara le risorse e apre il gioco. Al primo avvio ci mette un minuto; dalla volta dopo, subito.

```
./avvia.sh test          # esegue tutti i test: 472 controlli su 46 script
./avvia.sh installa-menu # (solo Linux) aggiunge il gioco al menu delle applicazioni
```

Su **Windows** lo script d'avvio non funziona (è bash) e i suoi passi vanno rifatti a mano: la procedura c'è, ma **non è mai stata provata da nessuno**.

| | |
|---|---|
| **Installare** — i tre sistemi, il motore di AI, come togliere tutto | **[INSTALLAZIONE.md](https://github.com/vonausterliz/dei-in-machina/blob/main/INSTALLAZIONE.md)** |
| **Giocare** — le regole, il Gateway, il tracciato delle chiamate, i problemi frequenti | **[COME_GIOCARE.md](https://github.com/vonausterliz/dei-in-machina/blob/main/COME_GIOCARE.md)** |

---

## Sotto il cofano

Il gioco è fatto di otto **agenti**. Un agente è un'AI a cui è affidato un compito preciso: ha un suo testo-guida in un file separato, una risposta attesa e un piano B che non manda mai in pezzi il turno se l'AI sbaglia.

|                       |                                                                     |
| --------------------- | ------------------------------------------------------------------- |
| **Interprete**        | traduce il tuo testo libero in etichette di un elenco chiuso        |
| **Dio-agente**        | uno per ogni dio sveglio: sceglie come reagire, e cosa dire         |
| **Arbitro** (Zeus)    | interviene solo quando gli dèi si contraddicono                     |
| **Narratore** (Omero) | racconta il turno, e non nomina nessuno                             |
| **Suggeritore**       | propone i tre appigli, quando Omero non li ha già dati              |
| **Cronista**          | tiene un riassunto aggiornato della vicenda, per non rileggere tutto |
| **Compagno**          | dà voce a un membro della ciurma                                    |
| **Ricognitore**       | capisce a *chi* stai pregando, quando preghi per allusione          |

Il codice attorno agli agenti è **verificabile senza accendere nessuna AI**. Una finta AI risponde al posto di quella vera — senza rete, senza token, senza attesa — e così l'intera macchina del turno diventa ripetibile: è questo che rende possibili **472 test** per un gioco fatto di AI. Sei turni di esempio, generati con un "seme" fisso (un valore di partenza che rende il caso ripetibile), restano registrati come riferimento, e ogni modifica viene confrontata con essi riga per riga.

Nella cartella `tools/` ci sono gli strumenti per guardarci dentro: stampare la traccia completa di una partita, stimare il costo costruendo i messaggi veri *prima* di spenderli, controllare che i nomi dei modelli dichiarati esistano davvero nei cataloghi dei servizi, fotografare l'interfaccia.

### I documenti

|                                                                                                                                 |                                                                                          |
| ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [docs/dei\_in\_machina\_design.md](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/dei_in_machina_design.md)      | il **perché** — il design, ormai fissato                                                  |
| [docs/architettura\_dettaglio.md](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/architettura_dettaglio.md)      | il **come** — componenti, agenti, i tre cancelli del risveglio, il budget delle richieste |
| [docs/contratto\_interprete.md](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/contratto_interprete.md)          | l'elenco chiuso delle etichette                                                           |
| [docs/guardrail\_anti\_assistente.md](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/guardrail_anti_assistente.md) | il blocco di istruzioni incluso nel testo-guida di *ogni* agente                        |
| [docs/costi.md](https://github.com/vonausterliz/dei-in-machina/blob/main/docs/costi.md)                                         | quanto costa una partita, voce per voce                                                   |
| [music/README.md](https://github.com/vonausterliz/dei-in-machina/blob/main/music/README.md)                                     | la colonna sonora: com'è fatta, e come aggiungerne                                        |

---

## Privacy e sicurezza

- **Nessuna telemetria.** Il gioco non manda niente a nessuno, tranne al motore di AI che *tu* hai scelto.
- **Con Ollama non esce nulla dal tuo computer.**
- Le chiavi API stanno nel file `user://impostazioni.json` (cartella dati del tuo utente), in chiaro come qualunque file di configurazione: fuori dal progetto, fuori dai commit. Né il gioco né il Gateway stampano mai il **valore** di una chiave, solo se c'è o manca.
- Il testo che arriva da un'AI non può alterare l'interfaccia: viene reso innocuo appena entra.

Dettagli, e cosa **non** c'è: **[SECURITY.md](https://github.com/vonausterliz/dei-in-machina/blob/main/SECURITY.md)**.

---

## Licenza

**GNU AGPL-3.0** — vedi [LICENSE](https://github.com/vonausterliz/dei-in-machina/blob/main/LICENSE). In breve: puoi usarlo, studiarlo, modificarlo e ridistribuirlo; se ne pubblichi una versione modificata, o la offri come servizio in rete, devi pubblicarne il codice con la stessa licenza.

Componenti di terzi (GUT, il carattere Cardo, Godot): **[TERZE_PARTI.md](https://github.com/vonausterliz/dei-in-machina/blob/main/TERZE_PARTI.md)**.

---

## In English

**You are Odysseus. The gods are programs you will never see.**

*Dei in machina* is a text-based narrative game about the *Odyssey*, in Italian, built in Godot 4. You type what you want to do in plain prose; Homer narrates the consequences — and Homer is reticent: he tells you the sea rose, never *who* raised it. Above you, thirteen deities with irreconcilable agendas argue about what to do with you, each voiced by an AI model — the same kind that powers chatbots. The real game is deducing **which powers you woke, and how**.

**How a turn works.** An AI reads your sentence and boils it down to a few labels from a fixed vocabulary — that step is a judgement, and it's the only place your freedom of phrasing enters the machine. From there, written rules take over: which facts wake which god, who is still asleep, how much a given reaction costs you, when the voyage advances. The gods then argue in their own voices, one prevails, and the numbers that follow are fixed. Homer narrates, naming no one.

So it is **not** fully random — two playthroughs of the same moves won't tell the same story, but the *link between cause and effect* stays fixed, and that's the point: if an AI decided who wakes, there would be nothing to deduce. Rules make the world legible; the AI gives it a voice that never repeats. (Switch the AI off, use a fixed seed, and the whole turn becomes reproducible — that's how 472 tests exist for a game made of AI.)

Runs on Linux and macOS. Bring your own AI: Ollama locally (nothing leaves your machine) or any of Mistral / Google / OpenAI / Anthropic / OpenRouter. Start with `./avvia.sh`.

**Testing status.** Verification rests on 472 automated tests against a simulated engine, **not** on extended human playtesting. Only the **Ollama, Mistral and Google** integrations have been exercised against the real services; **Anthropic and OpenRouter have not**. The local gateway routes all of them, and never silently falls back to a different provider. The software comes with **no warranty of any kind** (AGPL-3.0, §15–16): no liability is accepted for malfunctions, lost data, or **AI provider costs**, including unexpected or excessive spend caused by a defect or a misconfiguration. Your key, your plan, your bill — watch your usage and set a spending cap. Or play with Ollama, where no bill is possible.

Licensed under the GNU AGPL-3.0. The game and its documentation are in Italian.
