# Sicurezza e riservatezza

*Dei in machina* è un gioco che gira sul tuo computer e parla con un modello linguistico
che scegli tu. Non c'è un nostro server, non c'è un account, non c'è telemetria. Quello che
segue è cosa esce dalla tua macchina, dove finiscono le chiavi, e cosa abbiamo messo in
mezzo perché non finiscano dove non devono.

## Cosa esce dal tuo computer

**Con Ollama: nulla.** Il modello gira in locale, il gioco parla con `localhost:11434`.

**Con un servizio in rete** (Mistral, Google, OpenAI, Anthropic, OpenRouter) escono i
*prompt* — cioè, a ogni turno: ciò che hai scritto, la scena in cui ti trovi, il riassunto
della vicenda fin lì, e le battute degli dèi. Sono i tuoi dati di gioco, e vanno a quel
provider secondo le *sue* condizioni, non le nostre. Il gioco non aggiunge nulla di suo: né
identificatori, né statistiche, né segnalazioni di errore.

Non c'è nessun altro traffico. L'unica eccezione è il primo avvio, quando `avvia.sh`
scarica Godot dalle release ufficiali su GitHub.

## Le chiavi API

- Stanno in **`user://impostazioni.json`** — la cartella dati dell'utente del sistema
  operativo, **fuori dal progetto e fuori dal repository**.
- Sono in chiaro, come in qualunque file di configurazione. Non c'è un portachiavi: se il
  tuo profilo utente è compromesso, la chiave lo è.
- Una **variabile d'ambiente** ha la precedenza (`MISTRAL_API_KEY`, `GEMINI_API_KEY`,
  `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`): se preferisci non scriverla
  da nessuna parte, esportala e basta.
- **Il valore di una chiave non viene mai stampato.** Non nella finestra del Log LLM, non
  nel log del Gateway, non in un messaggio d'errore: si dice solo *se* c'è. È voluto —
  incollare un log per chiedere aiuto è la cosa più naturale del mondo, e non deve costarti
  una chiave.

## Il Gateway LLM

`llm_gateway/` è un processo Python separato che rispetta i limiti dei piani gratuiti
(coda, rallentamento, cache, riprova). Se lo usi:

- **Ascolta solo su `127.0.0.1`**: non è raggiungibile dalla rete locale.
- **Non ha autenticazione**, perché non ne ha bisogno legata a quella scelta. Se lo esponi
  fuori dal `localhost` — con un tunnel, un reverse proxy, un container mal configurato —
  stai regalando le tue chiavi a chiunque arrivi a quella porta. Non farlo.
- Le chiavi le legge dal **proprio ambiente**, all'avvio, una volta sola: esportale prima
  di lanciarlo.

## L'interfaccia contro il testo che arriva da fuori

Le viste del gioco interpretano BBCode. Dentro finisce testo che non abbiamo scritto noi —
le battute degli dèi, la voce di Omero, quella dei compagni, e ciò che digiti tu. Un
modello che produce una quadra aprirebbe un marcatore vero.

Non sarebbe esecuzione di codice (`[img]` in Godot carica solo risorse locali, e non c'è
nessun gestore di collegamenti), ma sarebbe **contraffazione dell'interfaccia**: la battuta
di un dio potrebbe travestirsi da voce del gioco, in oro e in grassetto come l'annuncio di
vittoria. In un gioco che si regge sul non far vedere gli dèi non è un difetto cosmetico.

Il testo viene neutralizzato **al confine** — quando entra, non quando si disegna — in
`scripts/data/bbcode.gd`. Un modello ostile per finta lo verifica in
`tests/unit/test_bbcode_ostile.gd`.

## L'unico indirizzo che il gioco apre

Il menu **Aiuto** ha un bottone «Apri su GitHub», e quel bottone chiama `OS.shell_open()` —
cioè consegna un indirizzo al browser del sistema. È l'unico punto del gioco che lo fa, e
l'indirizzo è una **costante** (`Main.REPOSITORY`): non si compone da un file di
configurazione, non da una preferenza, e soprattutto **non da ciò che dice un modello**.

La distinzione conta. Un `shell_open` con un indirizzo costruito da un dato è un modo per far
aprire al giocatore qualcosa che non ha scelto, e un modello che decide dove mandarlo sarebbe
il caso peggiore. Un test lo tiene fermo
(`test_l_indirizzo_del_repository_e_una_costante_https`), e vale come regola per chi tocca
quel file dopo: se un giorno servisse un secondo indirizzo, dev'essere un'altra costante.

## Il binario di Godot

`avvia.sh` scarica un **eseguibile** da internet e lo lancia. Il canale è HTTPS e la fonte
sono le release ufficiali, ma «viene dal posto giusto» non è «è il file giusto». Prima di
estrarlo, il launcher ne verifica la **SHA-512** contro l'impronta pubblicata da Godot per
quella versione. Se non combacia si ferma, e non esegue nulla.

Se aggiorni `GODOT_VER` devi aggiornare anche `SHA_LINUX` / `SHA_MACOS`, che trovi nel
`SHA512-SUMS.txt` della release. Il launcher si ferma finché non lo fai: verificare contro
un valore vecchio è come non verificare.

## Cosa **non** c'è

Per non lasciarlo dedurre dal silenzio:

- Nessuna sandbox attorno al modello. Il modello non esegue codice e non ha strumenti: il
  suo output è **testo**, e finisce solo a schermo e nei prompt successivi.
- Nessuna verifica di firma sui salvataggi. Un file di partita modificato a mano può
  contenere valori arbitrari: è un gioco a giocatore singolo, e barare è affar tuo.
- Nessuna cifratura dei dati locali.
- Il Gateway non limita quanto *tu* spendi: rispetta i limiti di frequenza, non un budget.
  Se giochi su un piano a pagamento, il conto lo tieni tu — `tools/stima_costo/` serve
  proprio a sapere in anticipo di che ordine di grandezza si parla.

## Segnalare un problema

Apri una *issue* sul repository. Se ritieni che il problema sia sfruttabile e vada detto in
privato, apri una issue che dica soltanto «vorrei segnalare una vulnerabilità» senza
dettagli, e ci si sposta da lì.

Questo è un progetto personale, senza un impegno di risposta entro un tempo dato.
