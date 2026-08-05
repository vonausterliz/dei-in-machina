# Installazione

*Dei in machina* non ha un installer: è un **progetto Godot 4**. Su Linux e macOS un solo
comando fa tutto — scarica il motore grafico, ne verifica l'integrità e apre il gioco.

| Il tuo sistema | Cosa fare | Stato |
|---|---|---|
| **Linux** x86\_64 | `./avvia.sh` | collaudato |
| **macOS** (Intel o Apple Silicon) | `./avvia.sh` | collaudato |
| **Windows** 10/11 | procedura manuale, [qui sotto](#windows--non-collaudata) | **mai provata** |

Serve anche **un motore di AI** — senza, gli dèi restano muti. È una scelta a parte, spiegata
[più giù](#il-motore-di-ai).

---

## Prima di cominciare

| | |
|---|---|
| **Spazio su disco** | ~13 MB il progetto · ~138 MB Godot · più i modelli, se usi Ollama |
| **Rete** | serve solo al primo avvio, per scaricare Godot |
| **Per scaricare il progetto** | `git`, oppure lo zip da GitHub |

Il gioco **non** installa niente nel sistema e non tocca il registro né le cartelle di
sistema. Tutto sta nella cartella del progetto, tranne le tue preferenze e i salvataggi.

---

## Linux

```bash
git clone https://github.com/vonausterliz/dei-in-machina.git
cd dei-in-machina
./avvia.sh
```

Al primo avvio ci mette un minuto: scarica Godot in `tools/godot/`, **ne verifica l'impronta
SHA-512** contro quella pubblicata da Godot, lo estrae e importa le risorse. Dalla volta dopo
parte subito.

Servono `bash`, `curl`, `unzip` e `sha512sum` — già presenti su qualunque distribuzione.

```bash
./avvia.sh test           # i test: 493 controlli su 49 script
./avvia.sh console        # il gioco nel terminale, senza finestra
./avvia.sh installa-menu  # aggiunge «Dei in machina» al menu delle applicazioni
./avvia.sh --help         # tutti i modi e tutte le opzioni, con esempi
```

L'ultimo comando lo devi lanciare tu: scrive un file `.desktop` in
`~/.local/share/applications/`. Serve perché altrimenti nella barra il gioco si chiama
«godot» — il processo in esecuzione è il motore, non il gioco.

---

## macOS

Identico:

```bash
git clone https://github.com/vonausterliz/dei-in-machina.git
cd dei-in-machina
./avvia.sh
```

Due cose che lo script fa per te:

- scarica la build **universal** di Godot, che va sia su Intel sia su Apple Silicon;
- toglie la **quarantena di Gatekeeper** dal binario scaricato (`xattr -dr
  com.apple.quarantine`), altrimenti macOS si rifiuterebbe di eseguirlo.

Al posto di `sha512sum` usa `shasum -a 512`, che c'è di serie.

Se il sistema si rifiuta di eseguire lo script: `chmod +x avvia.sh`.

---

## Windows — **non collaudata**

> ⚠️ **Nessuno ha mai eseguito il gioco su Windows.** La procedura qui sotto è ricavata da
> cosa fa lo script d'avvio sugli altri sistemi, non da una sessione andata a buon fine. Se la
> segui e funziona — o non funziona — dirlo è il modo più utile di contribuire.
>
> **Cosa fa ben sperare:** il gioco è Godot puro, senza dipendenze da comandi Unix, e Godot
> gira su Windows nativamente. **Cosa potrebbe non funzionare:** non lo sappiamo, ed è
> esattamente il punto.

Lo script `avvia.sh` è bash e su Windows non parte. I passi che fa vanno rifatti a mano, una
volta sola.

### 1 · Scarica il progetto

```powershell
git clone https://github.com/vonausterliz/dei-in-machina.git
cd dei-in-machina
```

Senza `git`, scarica lo zip da GitHub (*Code → Download ZIP*) e scompattalo.

### 2 · Scarica Godot 4.7.1

Dalla [release ufficiale](https://github.com/godotengine/godot/releases/tag/4.7.1-stable),
il file adatto al tuo processore:

| Processore | File |
|---|---|
| Intel / AMD (il caso normale) | `Godot_v4.7.1-stable_win64.exe.zip` |
| ARM (Snapdragon X e simili) | `Godot_v4.7.1-stable_windows_arm64.exe.zip` |

### 3 · Verifica l'impronta — **non saltare questo passo**

Sugli altri sistemi lo script lo fa da sé, e si rifiuta di eseguire un file che non combacia.
Qui tocca a te. In PowerShell:

```powershell
Get-FileHash -Algorithm SHA512 .\Godot_v4.7.1-stable_win64.exe.zip | Format-List
```

Il valore deve essere questo (senza spazi; maiuscole e minuscole non contano):

```
a6b02c527c18ba9936e63562032701432b2dc57d98d6483ceaccb00fe14af16af5773ae8a55e7b4d614edf121c4d9e420d870f804edb1dac16362298a01ce6c4
```

Per la versione ARM64:

```
607ba2ad6dc22081fb6f508929bbbff4b6c8f07257dacc804d81e938ad69ea01f39551815848b20c550a78f9a7cc156ef68c8b252b1f96eeb6e0e3f946799bfa
```

**Se non combacia, fermati.** Può voler dire che la versione è cambiata (allora prendi
l'impronta giusta dal file `SHA512-SUMS.txt` della release) — oppure che il download è stato
manomesso. Nel dubbio, la seconda. Stai per eseguire quel file.

### 4 · Scompatta e prepara

Scompatta lo zip dove preferisci, poi — dalla cartella del progetto — fai importare le
risorse. Due volte, come fa lo script: la prima passata registra le classi, la seconda importa
ciò che dipende da esse.

```powershell
$godot = "C:\percorso\a\Godot_v4.7.1-stable_win64.exe"
& $godot --headless --path . --import
& $godot --headless --path . --import
```

### 5 · Gioca

```powershell
& $godot --path .
```

Oppure apri Godot con un doppio clic, *Import*, scegli il file `project.godot` e premi ▶.

### Cosa non funziona su Windows

| | |
|---|---|
| `avvia.sh`, `gateway.sh`, `sync-mac.sh` | sono script bash |
| `./avvia.sh installa-menu` | scrive un file `.desktop`, che è cosa da Linux |
| Il **Gateway** | lo script no, ma il programma sì: `python llm_gateway\gateway.py` |
| I **test** | `& $godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json` |

Un dettaglio da tenere d'occhio: in *Impostazioni*, il verdetto sui modelli («ci gira / ci
gira ma lento / non ci sta») stima la memoria video chiamando `nvidia-smi`. Su Windows con
driver NVIDIA c'è ed è raggiungibile; se manca, il gioco **non si rompe** — lascia la memoria
video a zero e giudica sulla sola RAM, dicendotelo.

---

## Il motore di AI

Il gioco non ne include nessuno: gli dèi, Omero e i compagni *sono* AI, e senza non c'è
partita. Due strade, e si sceglie in gioco dalla finestra **Impostazioni**.

**Sul tuo computer — [Ollama](https://ollama.com/download).** Gratis, nessuna chiave, nessun
dato che esce di casa. Ha un installer per Linux, macOS e Windows.

```bash
ollama pull mistral-small3.2
```

Il gioco è tarato su questo modello. Su Linux e macOS `avvia.sh` controlla da sé che Ollama
risponda e che il modello ci sia, e lo pre-carica in memoria perché la prima mossa sia pronta.

**In rete — Mistral, Google, OpenAI, Anthropic, OpenRouter.** Serve una tua chiave. Come si
crea quella di Mistral, passo per passo, è nel
[README](README.md#la-chiave-di-mistral-passo-per-passo); il resto — quale modello scegliere,
come provarlo, come restare dentro il piano gratuito col Gateway — è in
[COME_GIOCARE.md](COME_GIOCARE.md#scegliere-il-motore--la-finestra-impostazioni).

---

## Avvio manuale, con un Godot già installato

Se hai già Godot 4.7.x e non vuoi che il progetto se ne scarichi un altro:

```bash
/percorso/di/Godot --path /percorso/di/dei-in-machina
```

Oppure apri Godot, *Import*, scegli `project.godot`, ▶.
Download del motore: [godotengine.org/download](https://godotengine.org/download).

---

## Verificare che sia andato tutto bene

```bash
./avvia.sh test      # su Windows, vedi la tabella qui sopra
```

Devi leggere **493 test, 493 passati, 49 script**. Se il numero di script è inferiore a 45,
qualcosa non compila: la suite resterebbe verde su meno test, ed è una trappola nota — c'è un
controllo apposta che la denuncia.

---

## Spostare o togliere il gioco

**Spostarlo su un altro sistema** — copia la cartella e basta. Il Godot in `tools/godot/` è
quello del sistema su cui l'hai scaricato, ma non dà fastidio: i vari sistemi lo cercano in
posti diversi, quindi al primo avvio il launcher non trova nulla e scarica il suo.

**Toglierlo** — cancella la cartella. Restano solo due cose fuori, ed è dove le cerca il
sistema operativo:

| | |
|---|---|
| Preferenze, chiavi API e salvataggi | Linux `~/.local/share/godot/app_userdata/Dei in machina/` · macOS `~/Library/Application Support/Godot/app_userdata/Dei in machina/` · Windows `%APPDATA%\Godot\app_userdata\Dei in machina\` |
| La voce nel menu applicazioni (solo Linux, se l'avevi installata) | `~/.local/share/applications/dei-in-machina.desktop` |

---

## Se qualcosa non va

I messaggi d'errore del gioco, uno per uno, e cosa provare per ciascuno: **[COME_GIOCARE.md
› Problemi frequenti](COME_GIOCARE.md#problemi-frequenti)**.

Per guardare cosa succede davvero sotto — quale AI è stata chiamata, cosa ha risposto, quanto
ci ha messo — c'è il **tracciato**: si scrive sempre in `user://log/`, e con
`./avvia.sh --debugllm` compare anche a schermo (`--tracellm` aggiunge il dettaglio HTTP,
`--logdei` apre il diario dell'applicazione). `./avvia.sh --help` le elenca tutte.
