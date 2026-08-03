# Come installare e far partire Dei in machina

Non c'è un "installer": è un **progetto Godot 4**. Il launcher `avvia.sh` rileva il sistema
(Linux o macOS) e usa il Godot giusto, scaricandolo automaticamente al primo avvio se manca.
Stesso comando su entrambi i sistemi.

Per giocare **serve un modello**: gli dèi, Omero e i compagni *sono* agenti LLM, e senza non
c'è partita. Puoi usare un modello locale (Ollama, gratis, gira anche su un portatile) o un
provider esterno con il tier gratuito. La scelta si fa nella finestra **Impostazioni**, in
gioco — vedi sotto.

---

## Avvio (Linux e macOS) — un solo comando

Dentro la cartella del progetto:

```bash
./avvia.sh            # apre la finestra grafica (GUI)
./avvia.sh console    # gioco testuale nel terminale (headless)
./avvia.sh test       # esegue i test (dev)
```

- Al **primo** avvio, se Godot non è già presente, lo scarica in `tools/godot/` (una volta sola,
  ~140 MB). Serve connessione internet solo quella prima volta.
- Su macOS il launcher toglie anche la "quarantena" di Gatekeeper dal Godot scaricato.
- Requisiti: `bash`, `curl`, `unzip` (già presenti sia su Linux sia su macOS).

Se preferisci fare a mano, vedi in fondo "Avvio manuale".

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

**Gateway** (spunta opzionale): fa passare le chiamate da una coda locale che rispetta i
limiti del piano gratuito. È un *trasporto*, non un provider: si combina con qualunque
modello tu abbia scelto, e le chiavi le tiene lui.

Con i modelli reali un turno è più lento, soprattutto quando gli dèi litigano: una contesa
piena vale fino a nove chiamate.

---

## Quanto consuma

Una partita intera, da Troia a Itaca, sta intorno a **450 chiamate** e **~1 milione di
token** (di cui appena ~48.000 in uscita: il grosso è il contesto che gli agenti rileggono).
Sul tier gratuito ci sta comodamente; è il motivo per cui il gioco è costruito per fare
**meno chiamate**, non per farle più in fretta.

---

## Portare il progetto sul MacBook

1. Copia la cartella `dei_in_machina` sul Mac (git clone, AirDrop, USB, rsync…).
   - Il Godot per Linux in `tools/godot/` **non** viene copiato/usato sul Mac: il launcher
     scarica da solo quello per macOS al primo `./avvia.sh`.
2. Apri il Terminale nella cartella e lancia `./avvia.sh`.
   - Se il Mac blocca lo script: `chmod +x avvia.sh` e riprova.

---

## Come si gioca

Scrivi liberamente **cosa fa e dice Ulisse**, e premi Invio (o "Agisci"). Sotto la narrazione
trovi tre appigli: sono suggerimenti contestuali, non le uniche mosse possibili — la quarta
strada è sempre scrivere di tuo.

Quattro finestre, apribili dai pulsanti in alto:

- **Olimpo** — gli dèi che si parlano fra loro, si contraddicono, e Zeus che chiude la
  contesa. Si **assiste** e basta: Ulisse non li sente davvero.
- **Ciurma** — qui invece **si scrive**. Parlare ai compagni non fa girare il mondo: costa
  una sola chiamata e il turno non avanza. Ma le tue parole non si perdono — al prossimo
  turno vero arrivano all'Interprete, agli dèi e a Omero, così un proposito detto a voce può
  svegliare qualcuno. Chiama qualcuno per nome (o con `@`) e risponde lui.
- **Log LLM** — la traccia tecnica: chi si è destato, cosa ha proposto, quanto ci ha messo.
- **Impostazioni** — motore, provider, modello, chiavi.

Le tre viste sono allineate dallo stesso ritmo: il momento del giorno e l'azione che hai
appena compiuto fanno da intestazione ovunque.

Console (headless): `:olimpo`, `:stato`, `:esci`.

---

## Avvio manuale (senza launcher)

Se hai già Godot 4.7.x installato:

```bash
# Linux/macOS, dal terminale:
/percorso/di/Godot --path /percorso/della/cartella/dei_in_machina
```

Oppure apri Godot, "Import", scegli il file `project.godot`, premi ▶.
Download di Godot: https://godotengine.org/download (macOS: build *universal*, ok su M1).

---

## In futuro: distribuirlo ad altri

Per dare il gioco a chi **non** ha Godot, la strada è l'**export nativo** di Godot
(eseguibile Linux, `.app`/`.dmg` per macOS, `.exe` per Windows): l'utente non installa nulla.
Da fare quando servirà (per macOS serve firmare l'app per evitare l'avviso di Gatekeeper).
