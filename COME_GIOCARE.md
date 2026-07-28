# Come installare e far partire Dei in machina

Non c'è un "installer": è un **progetto Godot 4**. Serve solo Godot (già incluso per Linux)
e, se vuoi i dèi "veri", Ollama con un modello. Senza Ollama gira comunque in **modalità mock**
(deterministica, istantanea) — perfetta per provarlo subito.

---

## Sul PC Linux (dove è stato sviluppato) — parte subito

Dal terminale, dentro la cartella del progetto:

```bash
cd ~/dei_in_machina
./avvia.sh          # apre la finestra grafica (GUI)
```

Oppure senza lo script:
```bash
./tools/godot/godot4 --path .
```

Altre modalità:
```bash
./avvia.sh console  # gioco testuale nel terminale (mock)
./avvia.sh test     # lancia i test (dev)
```

---

## Con i dèi e il narratore VERI (Ollama)

Di default il gioco usa il **mock** (finto, ma completo). Per accendere gli agenti LLM:

1. Installa Ollama: https://ollama.com/download
2. Scarica il modello di test:
   ```bash
   ollama pull mistral-small3.2
   ```
   (Ollama di solito è già in ascolto su http://localhost:11434; se no: `ollama serve`.)
3. Avvia il gioco e, **nella GUI**, spunta la casella **"Ollama (dei reali)"**.
   Da console invece:
   ```bash
   ./avvia.sh console -- ollama mistral-small3.2:latest
   ```

Nota: con i modelli reali un turno è più lento (soprattutto se i dèi litigano).

---

## Sul MacBook M1

Il Godot incluso in `tools/godot/` è per **Linux**: sul Mac serve il Godot per macOS.

1. **Porta il progetto sul Mac** (git clone della cartella, oppure copiala via AirDrop/USB/rsync).
2. **Scarica Godot 4.7.x per macOS** (build *universal*, va bene su M1): https://godotengine.org/download/macos/
   Scompatta e sposta `Godot.app` in Applicazioni.
3. **Apri il progetto**: avvia Godot, "Import", scegli il file `project.godot` della cartella, poi premi ▶ (Play).
   In alternativa da terminale:
   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --path /percorso/della/cartella/dei_in_machina
   ```
4. Per i dèi reali: installa Ollama per Mac, `ollama pull mistral-small3.2`, e spunta "Ollama (dei reali)" nella GUI.

---

## Comandi utili in gioco

- Scrivi liberamente cosa fa e dice Ulisse, premi Invio (o "Agisci").
- **Vista Olimpo**: pulsante che svela il dietro le quinte (dèi svegli, deliberazione, verdetto…).
- Nella console (headless): `:olimpo`, `:stato`, `:esci`.
