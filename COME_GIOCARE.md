# Come giocare a Dei in machina

Questa è la guida al **gioco**: come si avvia, come si sceglie il motore di AI, come si legge
quello che succede, e cosa fare quando qualcosa non va.

Per **installarlo** — i tre sistemi, Windows compreso, e come togliere tutto — c'è un
documento a parte: **[INSTALLAZIONE.md](INSTALLAZIONE.md)**.

Per giocare **serve un motore di AI**: gli dèi, Omero e i compagni *sono* AI, e senza non c'è
partita. Puoi usarne uno sul tuo computer (Ollama, gratis) o un servizio in rete col suo piano
gratuito. La scelta si fa in gioco, dalla finestra **Impostazioni** — vedi sotto.

---

## Avvio

Su Linux e macOS, dentro la cartella del progetto:

```bash
./avvia.sh            # apre la finestra di gioco
./avvia.sh console    # il gioco nel terminale, senza finestra
./avvia.sh test       # i test (sviluppo)
```

Al primo avvio scarica Godot in `tools/godot/` (una volta sola, ~138 MB) e ne verifica
l'impronta prima di eseguirlo. Su Windows lo script non funziona: vedi
[INSTALLAZIONE.md](INSTALLAZIONE.md#windows--non-collaudata).

---

## Scegliere il motore — la finestra Impostazioni

In gioco, il pulsante **Impostazioni**. Due strade:

### A) Ollama in locale (gratis, nessuna chiave)

1. Installa Ollama: https://ollama.com/download
2. Scarica un modello:
   ```bash
   ollama pull mistral-small3.2
   ```
   (Ollama è di solito già in ascolto su http://localhost:11434; se no: `ollama serve`.)
3. In Impostazioni scegli **Ollama (locale)** e il modello.

Da console: `./avvia.sh console -- ollama mistral-small3.2:latest`

### B) Un provider esterno (Mistral, Google…)

1. In Impostazioni scegli **Provider esterno** e il provider.
2. Incolla la chiave API nel campo del provider (viene salvata **fuori dal repo**, nelle tue
   preferenze utente — non finisce mai in git).
3. **Aggiorna elenco** → scegli il modello. L'elenco mostra solo i modelli che sanno scrivere
   testo: sintesi vocale, immagini ed embedding restano fuori.
4. **Prova il modello.** Fa due domande separate — *il server risponde?* e *il modello
   genera davvero?* — con una generazione vera da un token. Serve: capita che un provider
   continui a elencare un modello che ha già ritirato, e senza questa prova te ne accorgeresti
   solo a metà partita, con Omero muto.

**La chiave di Mistral in due minuti.** Registrati su
[console.mistral.ai](https://console.mistral.ai), attiva il piano gratuito — chiede la
**verifica del numero di telefono**, e finché non la fai la chiave esiste ma ogni chiamata
torna un errore che *sembra* una chiave sbagliata — poi **API Keys → Create new key**. Il
valore si vede **una volta sola**. Per Google la chiave è su
[aistudio.google.com](https://aistudio.google.com/apikey). Il passo per passo completo è nel
[README](README.md#la-chiave-di-mistral-passo-per-passo).

Con i modelli reali un turno è più lento, soprattutto quando gli dèi litigano: una contesa
piena vale fino a nove chiamate.

**Non tutti i provider sono collaudati.** Ollama, Mistral e Google sì, contro il servizio
vero. OpenAI, Anthropic e OpenRouter hanno il profilo pronto ma non sono mai stati provati.

---

## Il Gateway LLM: restare dentro il piano gratuito

Sui piani gratuiti il limite che ti ferma non è quanto consumi, è **quante richieste al
secondo** fai. Un turno pieno ne manda fino a nove quasi insieme: senza un freno, la maggior
parte torna `429 Too Many Requests` e il turno si sbriciola.

Il Gateway è un processo Python separato (`llm_gateway/`, solo libreria standard) che sta
**fra il gioco e il provider** e mette ordine. Il gioco non sa nemmeno che c'è: gli parla
come parlerebbe a OpenAI.

### Come si accende

**1. Esporta le chiavi.** Questo è il passo che si salta, ed è quello che conta:

```bash
export MISTRAL_API_KEY=...
export GEMINI_API_KEY=...        # solo se usi Google
```

> ⚠️ **La chiave scritta in *Impostazioni* al Gateway non arriva.** Il Gateway legge dal
> **proprio** ambiente, e la finestra Impostazioni scrive nelle preferenze del gioco. Senza
> `export`, il Gateway parte lo stesso e ogni richiesta torna `401`: nel gioco sembra un
> guasto del gioco. Nel log lo dice — `CHIAVE MANCANTE` accanto al provider.

**2. Avvialo.**

```bash
cd llm_gateway
./gateway.sh start      # in background, log in gateway.log
./gateway.sh stato      # quote residue e cache
./gateway.sh fg         # in primo piano, per vedere il log dal vivo
./gateway.sh stop
```

Se le chiavi le esporti *dopo* averlo avviato, il Gateway non le vede: `./gateway.sh restart`.

**3. Nel gioco**, *Impostazioni* → spunta **Gateway**. È un *trasporto*, non un provider: si
combina con il modello che hai già scelto.

### Cosa fa, per ogni richiesta

1. **Cache** — richiesta identica già fatta di recente → risposta immediata, **zero quota**
   (un'ora di validità, 500 voci).
2. **Coda** — una fila per provider, servita da un solo lavoratore: mai due richieste in volo
   verso lo stesso servizio.
3. **Freno** — tre vincoli insieme: distanza minima fra due richieste (il limite di
   *velocità*), tetto al minuto, tetto al giorno.
4. **Ritentativo** — su `429` o `5xx` riprova con attesa che raddoppia (1s, 2s, 4s…),
   obbedendo all'header `Retry-After` se il provider lo manda.

I limiti stanno in `llm_gateway/limiti.json`, tenuti **sotto** quelli dichiarati dal provider:
le finestre di conteggio non coincidono mai al millisecondo con le nostre.

| Provider | Distanza minima | Al minuto | Al giorno |
|---|---|---|---|
| `mistral` | 1,1 s | 28 | — |
| `google` | 4,2 s | 14 | 1400 |
| `openrouter` | 3,1 s | 18 | **50** |
| `anthropic` | 1,4 s | 45 | — |
| `openai` · `ollama` | nessun freno | | |

Se cambi piano e i freni non ti servono più: `./gateway.sh libero`, oppure
`"throttling_attivo": false` in `limiti.json`. Coda, cache e ritentativi restano.

### Due cose da sapere

**Anthropic non ha un piano gratuito.** Passa dal Gateway come tutti gli altri — la spunta
funziona, le chiavi le tiene lui — ma davanti ad Anthropic il Gateway non fa risparmiare
nulla: fa da coda, da cache e da ritentativo, e si paga a consumo comunque. All'avvio lo
scrive: `⚠ SEMPRE A PAGAMENTO`.

**Il tetto di OpenRouter è 50 al giorno**, per account, sui modelli col suffisso `:free`.
Una partita intera ne chiede ~450: non ci sta. Il Gateway lo scrive nel log all'avvio invece
di fartelo scoprire a metà viaggio.

### Se il provider non è configurato

Il Gateway **non ripiega mai su un altro**. Se gli chiedi un provider che non ha in
`limiti.json`, risponde con un errore che dice quali conosce e dove aggiungerlo:

```
provider «cohere» non configurato nel gateway. Conosco: anthropic, google,
mistral, ollama, openai, openrouter. Aggiungilo a limiti.json, oppure togli la
spunta «Gateway» nel gioco per andare diretto al provider.
```

Prima ripiegava sul predefinito, ed era il difetto peggiore possibile: una configurazione
mancante — che si vede e si aggiusta — diventava la risposta di un altro modello, che non si
vede affatto. Un test lo tiene fermo: `llm_gateway/prova_instradamento.py`.

Il Gateway ascolta **solo su `127.0.0.1`**, non ha autenticazione e non deve averne: non va
esposto in rete. Se la porta 8800 è occupata: `PORTA=8801 ./gateway.sh start`. Dettagli in
[llm_gateway/README.md](llm_gateway/README.md).

---

## Quanto consuma

Una partita intera, da Troia a Itaca, sta intorno a **450 chiamate** e **~1 milione di
token** (di cui appena ~48.000 in uscita: il grosso è il contesto che gli agenti rileggono).
Sul tier gratuito ci sta comodamente; è il motivo per cui il gioco è costruito per fare
**meno chiamate**, non per farle più in fretta.

---

## Come si gioca

Scrivi liberamente **cosa fa e dice Ulisse**, e premi Invio (o "Agisci"). Sotto la narrazione
trovi tre appigli: sono suggerimenti contestuali, non le uniche mosse possibili — la quarta
strada è sempre scrivere di tuo.

I tre appigli sono suggerimenti, non scelte: cliccarne uno lo mette nel campo e parte. Puoi
sempre scrivere altro — ed è lì, nel campo libero, che si fanno le cose che nessuno ti ha
suggerito.

Dal menu **Partita** puoi salvare e riprendere: una partita intera dura ~76 turni, non è
detto che tu la faccia in una sera.

Nella colonna di destra, sempre sotto gli occhi:

- **Carta del viaggio** — dove sei, e cosa hai già passato.
- **Vista Olimpo** — gli dèi che si parlano fra loro, si contraddicono, e Zeus che chiude
  la contesa. Si **assiste** e basta: Ulisse non li sente davvero. Chi la spunta non viene
  annunciato — si vede, perché è l'unico che agisce.
- **La ciurma** — qui invece **si scrive**. Parlare ai compagni non fa girare il mondo:
  costa una sola chiamata e il turno non avanza. Ma le tue parole non si perdono — al
  prossimo turno vero arrivano all'Interprete, agli dèi e a Omero, così un proposito detto
  a voce può svegliare qualcuno. Chiama qualcuno per nome (o con `@`) e risponde lui.

Ognuno dei tre ha una **lente** in alto a destra: lo apre grande quanto la schermata. Si
chiude con `Esc` o cliccando fuori.

In fondo alla pagina, su una riga: astuzia, animo, ciurma, tracotanza — e il capitolo in
corso. Sotto **Settings** ci sono motore, provider, modello, chiavi — e le *Informazioni*,
con la versione. Il tracciato delle chiamate al modello si scrive su file, e si vede a
schermo con `./avvia.sh --debugllm`: vedi sotto.

Il menu **Aiuto** ha le regole in breve e i problemi più comuni, più un collegamento a questi
documenti. Nel gioco c'è il minimo che serve a giocare; il resto sta qui.

Le viste sono allineate dallo stesso ritmo: il momento del giorno e l'azione che hai appena
compiuto fanno da intestazione ovunque.

Console (headless): `:olimpo`, `:stato`, `:salva`, `:carica`, `:tappa <id>`, `:esci`.

---

## Problemi frequenti

Quando qualcosa non va col modello, il gioco **apre una finestra** che dice cos'è successo e
ha un bottone *Apri Settings*. Non scrive più nulla nella narrazione: lì c'è solo la storia.
Ecco cosa vuol dire ciascun messaggio.

### «*Nessun provider configurato*»

La cartella `config/providers/` è vuota o illeggibile. Non dovrebbe succedere in un clone
integro del progetto: se è capitato, hai spostato o cancellato quei file.

### «*Manca la chiave API per «X»*»

Il gioco non trova la chiave di quel provider. Due posti dove può stare, e il secondo vince:

1. *Settings* → il campo del provider (finisce in `user://impostazioni.json`);
2. una variabile d'ambiente — `MISTRAL_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`,
   `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`.

**Se usi il Gateway, il campo di Settings non serve a niente**: le chiamate le fa lui, con le
*sue* chiavi, lette dal proprio ambiente all'avvio. Vedi la sezione sul Gateway qui sopra.

### «*X non risponde*»

Il server non si è fatto sentire affatto.

| Con | Prova |
|---|---|
| **Ollama** | è in esecuzione? `ollama serve`, poi `curl localhost:11434/api/tags` |
| **Un provider in rete** | rete e chiave: un `401` è la chiave, un timeout è la rete |
| **Il Gateway** | è acceso? `cd llm_gateway && ./gateway.sh stato` |

### «*X non elenca nessun modello disponibile*»

Il server risponde ma la sua lista è vuota. Con Ollama vuol dire che non hai ancora scaricato
niente: `ollama pull mistral-small3.2`. Con un provider in rete, quasi sempre è una chiave
valida ma senza i permessi giusti — o un piano non ancora attivato (Mistral richiede la
verifica del telefono).

### «*Il modello «X» è elencato da Y ma non risponde*»

Il caso più insidioso, e capita davvero: il provider continua a elencare un modello che ha
già ritirato. Il menu *Modello* in Settings contiene l'elenco che il provider ha appena
restituito — scegline un altro e premi **Prova il modello**.

### «*Nessun motore attivo*»

Hai premuto *Agisci* con i dèi simulati. Il gioco si ferma apposta: si sono giocati quattro
turni credendo che gli dèi pensassero, e non pensavano. Accendi un motore da Settings.

### Il modello risponde, ma male

Nessuna finestra si apre, perché tecnicamente funziona tutto. Guarda il **tracciato** (vedi
View): la tabella «sintomo → cosa cercare» qui sotto dice dove.

Un caso ha una spiegazione precisa: se gli dèi sembrano fuori parte o Omero nomina una
divinità, quasi sempre il modello è troppo piccolo. Il gioco è tarato su **Mistral Small 3.2
(24 B)**, e i prompt sono stati scritti e misurati su quello.

### Il gioco parte muto

Se all'avvio vedi un errore audio nel terminale (su macOS, `AudioOutputUnitStart failed`), il
driver audio di sistema non è partito e la musica non si sente. Non riguarda il gioco: chiudi
le altre applicazioni che usano l'audio, controlla l'uscita nelle impostazioni di sistema, e
rilancia. Tutto il resto funziona lo stesso.

---

## Il tracciato delle chiamate al modello

**Si scrive sempre, in un file.** A ogni avvio, in `user://log/llm-AAAAMMGG-hhmmss-mmm.log`
— su Linux `~/.local/share/godot/app_userdata/Dei in machina/log/`. Gli ultimi dieci si
tengono, i più vecchi si buttano. È il file da allegare quando qualcosa non torna: la
finestra si chiude, il file resta.

**La finestra si chiede all'avvio**, e solo così:

```bash
./avvia.sh --debugllm
```

Non è più una voce di menu. Non serve a chi gioca — serve a chi indaga — e una finestra di
traffico HTTP fra le voci di un menu invita ad aprirla per curiosità e a ritrovarsela davanti
alla narrazione.

### Come si legge

```
12:21:27.114  ── connessione ──
12:21:27.114       CONN  provider=OpenRouter  modello=deepseek/deepseek-chat-v3.1:free
12:21:27.114       CONN  endpoint=https://openrouter.ai/api/v1/chat/completions
12:21:27.114       CONN  gateway=no (diretto al provider)
12:21:27.114       CONN  chiave=presente (variabile OPENROUTER_API_KEY)
12:21:28.001  ── turno 12 — Grido al ciclope il mio vero nome: sono io, Odisseo! ──
12:21:28.010  #001 REQ   turno=12  agente=Interprete  msg=2  in≈1.9k tok  temp=0.2  json
12:21:28.010  #001       ↑ Grido al ciclope il mio vero nome: sono io, Odisseo!
12:21:30.870  #001 RES   HTTP 200  2860 ms  token in=1842 out=96 tot=1938  fine=stop
12:21:30.871  #001       ↓ {"plausibilita":"in_mondo","tag":["vanto","tracotanza"],…}
12:21:30.880  #002 REQ   turno=12  agente=Poseidone  msg=3  in≈3.2k tok  temp=0.9
12:21:38.880  #002 WAIT  in corso da 8 s…
12:21:39.880  #002 RETRY  tentativo 2/5 fra 1.0 s — HTTP 429 rate limit
12:21:45.090  #002 RES   HTTP 200  14210 ms  token in=3204 out=512 tot=3716  fine=length  ⚠ TRONCATA
12:21:45.100  #003 ERR   HTTP 402: chiave rifiutata. La chiede il provider — Insufficient credits
```

| | |
|---|---|
| **`── connessione ──`** | dove si sta parlando *davvero*. È la prima riga da guardare quando il gioco è lento: dice provider, modello, se passi dal Gateway e se una chiave c'è |
| **`── turno N ──`** | il confine fra un turno e l'altro, con quello che hai scritto |
| **`#001`** | il numero della chiamata. Le chiamate di un turno partono quasi insieme e tornano in ordine sparso: è questo che ricuce una risposta alla sua domanda |
| **`REQ`** | chi chiama, quanti messaggi, quanti token stimati (`≈`), temperatura, se pretende JSON |
| **`RES`** | codice, **millisecondi**, e i token **dichiarati dal provider** — quelli fatturati |
| **`fine=length`** | la risposta è stata **troncata** dal tetto di token, non conclusa dal modello. È la spiegazione di un JSON che arriva a metà |
| **`WAIT`** | la richiesta è ancora in volo. Senza, un modello lento e un modello morto si somigliano |
| **`RETRY`** | un ritentativo. Se non si vedesse, un turno lento sembrerebbe una chiamata lenta |
| **`ERR`** | il messaggio **del provider**, non la nostra parafrasi |
| **`···`** | le righe degli agenti: cosa ha estratto l'Interprete, cosa ha proposto un dio |

**Il valore di una chiave non compare mai** — solo se c'è e da quale variabile verrebbe. Un
log si incolla in una segnalazione, e non deve costare un segreto.

### Quando aprirlo

| Cosa vedi nel gioco | Cosa cercare nel tracciato |
|---|---|
| Tutto lentissimo | la riga `CONN`: stai parlando con chi credi? Poi i `ms` di ogni `RES` |
| Un turno lento, gli altri no | una `RES` con molti ms, o dei `RETRY` |
| Gli dèi non reagiscono | la `RES` dell'Interprete: che etichette ha estratto |
| Una risposta finisce a metà | `fine=length` |
| «Il provider non risponde» | la riga `ERR`, col messaggio vero |
| Consumo più alto del previsto | i `token` per chiamata, sommati per turno |

---

## Aggiungere la musica

Il gioco ha un brano per **momento**: la schermata d'apertura, ognuno dei quindici
capitoli, la traversata fra un capitolo e l'altro, e i tre finali. Ne arriva già uno,
sull'apertura; gli altri sono in silenzio finché non li riempi tu.

**Basta mettere il file nella cartella `music/` e chiamarlo come il momento.** Nient'altro.

```
music/troia.mp3        → suona alla partenza da Troia
music/ciclope.ogg      → suona nell'antro del Ciclope
music/fine_itaca.mp3   → suona quando torni a casa
```

Valgono `.mp3`, `.ogg` e `.wav`; maiuscole e minuscole non contano. **Non serve reimportare
niente né riaprire l'editor**: i brani si leggono dal disco quando servono.

Gli identificatori dei momenti sono questi:

| Capitolo | Nome del file | | Capitolo | Nome del file |
|---|---|---|---|---|
| La partenza da Troia | `troia` | | Il canto delle Sirene | `sirene` |
| I Ciconi di Ismaro | `ciconi` | | Scilla e Cariddi | `scilla` |
| La terra dei Lotofagi | `lotofagi` | | L'isola del Sole | `trinacia` |
| L'antro del Ciclope | `ciclope` | | L'isola di Calipso | `ogigia` |
| L'isola di Eolo | `eolo` | | La tempesta | `naufragio` |
| Il porto dei Lestrigoni | `laestrigoni` | | La terra dei Feaci | `scheria` |
| Il palazzo di Circe | `circe` | | Itaca | `itaca` |
| La soglia dell'Ade | `ade` | | | |

E i momenti che non sono capitoli: `splash` (l'apertura), `traversata` (fra una tappa e
l'altra), `fine_morte`, `fine_prigionia_eterna`, `fine_itaca`.

**Se ti serve di più**, in `data/musica.json` puoi scrivere il nome del file per esteso
(utile quando ha un nome suo, come `Intro.mp3`) e regolare due cose per ogni momento:
`ciclo` — se il brano ricomincia da capo quando finisce, e `volume_db` — quanto forte,
rispetto al volume generale. Quello che è scritto lì vince sempre sul nome del file.

---

## Avvio manuale, e installazione su altri sistemi

Se hai già un Godot 4.7.x installato e non vuoi che il progetto se ne scarichi un altro, o se
stai partendo da Windows: **[INSTALLAZIONE.md](INSTALLAZIONE.md)**.

---

## In futuro: distribuirlo ad altri

Per dare il gioco a chi **non** ha Godot, la strada è l'**export nativo** di Godot
(eseguibile Linux, `.app`/`.dmg` per macOS, `.exe` per Windows): l'utente non installa nulla.
Da fare quando servirà (per macOS serve firmare l'app per evitare l'avviso di Gatekeeper).
