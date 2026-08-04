# Dei in machina

> *«Canta, o Musa, l'uomo dall'ingegno multiforme…»*

**Tu sei Ulisse. Gli dèi sono agenti che non vedrai mai.**

Scrivi in italiano quello che vuoi fare — non scegli da un menù, non impari comandi. Omero
racconta cosa succede. Ma Omero è reticente: ti dice che il mare si è alzato, mai *chi* l'ha
alzato. Sopra la tua testa, in una stanza che non puoi vedere, tredici divinità con agende
inconciliabili discutono cosa farti. Atena ti protegge finché sei astuto. Poseidone dorme,
e si sveglia solo quando accechi suo figlio. Zeus arbitra, quando c'è da arbitrare.

Il gioco vero non è arrivare a Itaca. È capire **chi hai svegliato, e come**.

![La schermata di gioco](docs/immagini/schermata.png)

---

## Cosa lo rende diverso

Non è «un LLM che fa il master». È una macchina deterministica in cui i modelli fanno una
cosa sola: **la voce e il capriccio**.

| Decide il codice (GDScript) | Decide il modello |
|---|---|
| Chi si sveglia, e a cosa | *Come* reagisce: con scherno, con pietà, con rancore |
| Quanto cambia il mondo — i numeri | Cosa si dicono gli dèi fra loro |
| Quando la tappa avanza | Come Omero racconta |
| Cosa può esserti proposto | Cosa pensa un compagno che ha paura |

Il motivo è semplice: un modello rispetta una regola *quasi sempre*, e «quasi sempre» in un
gioco vuol dire un difetto ogni poche partite. Così la coerenza sta nel codice, la varietà
nel modello. Poseidone si sveglia sull'accecamento perché lo dice una riga di GDScript, non
perché glielo abbiamo chiesto per favore in un prompt.

### La stanza degli dèi

C'è una finestra sul concilio. Il giocatore la vede, Ulisse no.

![La Vista Olimpo](docs/immagini/vista-olimpo.png)

Gli dèi si destano, parlano, **si ribattono**, e alla fine uno agisce. Chi la spunta non
viene annunciato: si vede, perché è l'unico che muove la mano. Se puniscono e aiutano
insieme, interviene Zeus e chiude con parole sue.

Nessuna di quelle battute costa una chiamata in più: le proposte hanno già un campo «dice»,
e il botta e risposta è già nel meccanismo. Qui si raccolgono e si mostrano.

### Quindici tappe, da Troia a Itaca

![La carta del viaggio](docs/immagini/carta.png)

Le coste sono vere (Natural Earth, ridisegnate); la rotta è quella del poema. Chi deve
morire muore alla sua tappa, come sta scritto — e da quel momento la sua voce sparisce
dalla conversazione della ciurma.

---

## Le tre regole che tengono in piedi tutto

**1 · Gli dèi sono nascosti, e restano nascosti.** La narrazione rivolta a chi gioca non
nomina *mai* un dio. Non è una raccomandazione nel prompt: è un test che scandaglia
l'output e fallisce se compare un nome divino.

**2 · Ciò che il gioco offre, il gioco lo accetta.** Fra gli appigli suggeriti era comparso
«sguaina il bronzo e rispondi all'affronto» — perfettamente omerico — e cliccarlo dava
«quel gesto non appartiene a questo mondo». Un gioco non può rifiutare ciò che ha appena
proposto: ora è impossibile per costruzione.

**3 · Il costo è un vincolo di design.** Una partita intera, da Troia a Itaca, sono circa
**450 chiamate e 1,03 milioni di token**, con un rapporto ingresso/uscita di 20:1 — il
costo è il contesto che si rilegge, non ciò che si scrive. Prima di aggiungere una chiamata
per turno si misura con `tools/stima_costo/`. Chi gioca sceglie un *profilo di costo*, dal
Frugale in su.

---

## Requisiti

### Software

| | |
|---|---|
| **Sistema** | Linux x86_64 · macOS (Intel o Apple Silicon) |
| **Motore** | Godot **4.7.x** — non serve installarlo: `avvia.sh` lo scarica al primo avvio (~138 MB) e **ne verifica l'impronta SHA-512** prima di eseguirlo |
| **Nel sistema** | `bash`, `curl`, `unzip`, `sha512sum` (o `shasum`) — già presenti su Linux e macOS |
| **Per il Gateway** (facoltativo) | `python3` ≥ 3.9, nessuna libreria esterna |
| **Spazio** | ~13 MB il progetto, ~138 MB Godot, più i modelli se usi Ollama |

Windows non è supportato dal launcher. Il progetto è Godot puro: aprendolo con un Godot 4.7
installato a mano dovrebbe girare, ma nessuno l'ha provato.

### Chi dà voce agli dèi

Serve **un** motore linguistico, a scelta. Il gioco non ne include nessuno.

**Sul tuo computer — Ollama.** Nessuna chiave, nessun costo, nessun dato che esce di casa.
Il gioco è tarato su **Mistral Small 3.2 (24 B)**: è il modello su cui gli otto prompt sono
stati scritti e misurati.

| Se hai… | Cosa aspettarti |
|---|---|
| **≥ 16 GB di VRAM** | Mistral Small 3.2 gira sulla scheda: fluido |
| **8–12 GB di VRAM** | Un modello da 7–8 B quantizzato va bene; il 24 B parte, ma lento |
| **Solo RAM (≥ 16 GB)** | Funziona, ma un turno può richiedere minuti |
| **< 8 GB in tutto** | Meglio un servizio in rete |

Non devi indovinare: in *Impostazioni* ogni modello installato ha un **verdetto** accanto —
✓ ci gira · ? ci gira ma lento · ✗ non ci sta — calcolato sulla memoria vera della tua
macchina, con la ragione nel tooltip.

**In rete — Mistral, Google, OpenAI, Anthropic, OpenRouter.** Serve una chiave tua. Va in
*Impostazioni*, e finisce nella cartella dati dell'utente: **mai nel progetto, mai in un
commit**. Una variabile d'ambiente ha la precedenza, se preferisci non scriverla da nessuna
parte.

Sui piani gratuiti il collo di bottiglia sono le richieste al secondo. Per quello c'è
`llm_gateway/`: un processo separato che mette in coda, rallenta, mette in cache e riprova
da solo. Ascolta **solo su `127.0.0.1`** e tiene le chiavi nel proprio ambiente.

---

## Comincia

```bash
git clone <questo repo> dei_in_machina
cd dei_in_machina
./avvia.sh
```

È tutto. Il launcher riconosce il sistema, scarica il Godot giusto, ne verifica l'impronta,
importa le risorse e apre il gioco. Al primo avvio ci mette un minuto; dopo, subito.

```bash
./avvia.sh test          # la suite: 431 test, 44 script
./avvia.sh installa-menu # (Linux) mette il gioco nel menu applicazioni
```

Guida completa, Ollama compreso: **[COME_GIOCARE.md](COME_GIOCARE.md)**.

---

## Sotto il cofano

Otto agenti, ognuno con un prompt in un file esterno e un ripiego che non rompe mai il
turno: **Interprete** (traduce il testo libero in un vocabolario chiuso), **Dio-agente**,
**Arbitro** (Zeus), **Narratore** (Omero), **Suggeritore**, **Cronista**, **Compagno**,
**Ricognitore**.

Attorno, ciò che li rende governabili:

- **Mock deterministico** — l'intera macchina del turno gira senza rete, senza token e
  senza latenza. È la ragione per cui 431 test possono esistere.
- **Golden trace** — sei turni canonici a seme fisso, registrati e confrontati per
  percorso: *cambiato / COMPARSO / SPARITO*. È il presidio contro la classe di guasto più
  frequente qui: non codice che sbaglia, codice che **manca**.
- **Strumenti che guardano** — `tools/` contiene un dumper di traccia, uno stimatore di
  costi che costruisce i messaggi veri, un verificatore dei nomi dei modelli contro i
  cataloghi vivi, e due strumenti che *fotografano* l'interfaccia. Ciò che si giudica a
  occhio va guardato: un pannello può costruirsi senza errori ed essere illeggibile.

### I documenti

| | |
|---|---|
| [docs/dei_in_machina_design.md](docs/dei_in_machina_design.md) | il **perché** — il design, congelato |
| [docs/requisiti.md](docs/requisiti.md) | il **cosa** — tutti i requisiti, con lo stato verificato sul codice |
| [docs/architettura_dettaglio.md](docs/architettura_dettaglio.md) | il **come** — componenti, agenti, i tre cancelli del risveglio, il budget delle chiamate |
| [docs/contratto_interprete.md](docs/contratto_interprete.md) | il vocabolario chiuso dei tag |
| [docs/guardrail_anti_assistente.md](docs/guardrail_anti_assistente.md) | il blocco incluso nel prompt di *ogni* agente |
| [STATO_LAVORI.md](STATO_LAVORI.md) | il diario: a che punto siamo, cosa resta |
| [CLAUDE.md](CLAUDE.md) | come si lavora qui, e perché |

---

## Privacy e sicurezza

- **Nessuna telemetria.** Il gioco non manda niente a nessuno, tranne al motore che *tu*
  hai scelto.
- **Con Ollama non esce nulla dal tuo computer.**
- Le chiavi API stanno in `user://impostazioni.json` (cartella dati dell'utente), in chiaro
  come qualunque file di configurazione: fuori dal progetto, fuori dai commit. Né il gioco
  né il Gateway stampano mai il **valore** di una chiave, solo se c'è.
- Il testo che arriva da un modello non può scrivere marcatori nell'interfaccia: viene
  neutralizzato al confine.

Dettagli e come segnalare un problema: **[SECURITY.md](SECURITY.md)**.

---

## Licenza

**GNU AGPL-3.0** — vedi [LICENSE](LICENSE). In breve: puoi usarlo, studiarlo, modificarlo e
ridistribuirlo; se ne pubblichi una versione modificata, o la offri come servizio in rete,
devi pubblicarne il codice con la stessa licenza.

Componenti di terzi (GUT, il carattere Cardo, Godot): **[TERZE_PARTI.md](TERZE_PARTI.md)**.

---

<details>
<summary><b>In English</b></summary>

**You are Odysseus. The gods are agents you will never see.**

*Dei in machina* is a narrative game about the *Odyssey*, in Italian, built in Godot 4.
You type what you want to do in free text; Homer narrates the consequences — and Homer is
reticent: he tells you the sea rose, never *who* raised it. Above you, thirteen deities with
irreconcilable agendas argue about what to do with you. The real game is deducing **which
powers you woke, and how**.

The design rule: **the prompt is a prayer, the code is the guarantee.** Deterministic
GDScript decides who wakes, how much the world changes and when the voyage advances; the
language models supply only voice and caprice. That split is what makes a game driven by
LLMs testable — 431 tests run against a deterministic mock, with no network and no tokens.

Runs on Linux and macOS. Bring your own model: Ollama locally (nothing leaves your machine)
or any of Mistral / Google / OpenAI / Anthropic / OpenRouter. Start with `./avvia.sh`.

Licensed under the GNU AGPL-3.0. The game and its documentation are in Italian.

</details>
