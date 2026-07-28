# Come installare e far partire Dei in machina

Non c'è un "installer": è un **progetto Godot 4**. Il launcher `avvia.sh` rileva il sistema
(Linux o macOS) e usa il Godot giusto, scaricandolo automaticamente al primo avvio se manca.
Stesso comando su entrambi i sistemi. Senza Ollama il gioco gira in **modalità mock**
(deterministica, istantanea): puoi provarlo subito, a costo zero.

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

## Con i dèi e il narratore VERI (Ollama)

Di default il gioco usa il **mock**. Per accendere gli agenti LLM:

1. Installa Ollama: https://ollama.com/download
2. Scarica il modello di test:
   ```bash
   ollama pull mistral-small3.2
   ```
   (Ollama è di solito già in ascolto su http://localhost:11434; se no: `ollama serve`.)
3. Avvia con `./avvia.sh` e nella GUI spunta **"Ollama (dei reali)"**.
   Da console:
   ```bash
   ./avvia.sh console -- ollama mistral-small3.2:latest
   ```

Con i modelli reali un turno è più lento (soprattutto quando i dèi litigano).

---

## Portare il progetto sul MacBook

1. Copia la cartella `dei_in_machina` sul Mac (git clone, AirDrop, USB, rsync…).
   - Il Godot per Linux in `tools/godot/` **non** viene copiato/usato sul Mac: il launcher
     scarica da solo quello per macOS al primo `./avvia.sh`.
2. Apri il Terminale nella cartella e lancia `./avvia.sh`.
   - Se il Mac blocca lo script: `chmod +x avvia.sh` e riprova.

---

## Comandi utili in gioco

- Scrivi liberamente cosa fa e dice Ulisse, premi Invio (o "Agisci").
- **Vista Olimpo**: pulsante che svela il dietro le quinte (dèi svegli, deliberazione, verdetto…).
- Console (headless): `:olimpo`, `:stato`, `:esci`.

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
