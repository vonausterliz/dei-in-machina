# Contratto dell'Interprete — «Dei in machina»

**Versione 0.1**

L'Interprete è la prima chiamata LLM di ogni turno. Prende il testo libero di Ulisse e restituisce **solo** un envelope JSON strutturato. È il ponte tra ciò che l'umano scrive e i `trigger` definiti in `pantheon.json`: se qui e nel pantheon non si parla la stessa lingua, gli dèi non si svegliano mai.

---

## 1. Vocabolario dei tag (chiuso)

Sono gli unici tag che l'Interprete può emettere nel campo `tag`. Chiuso = se nulla calza, `tag: []`. Ogni tag ha un significato fisso: la **coerenza** del tagging è ciò che rende il gioco "nascosto ma leale" (stessa azione → stesso tag → stessa logica divina).

### Condotta (come agisce, moralmente)
- `tracotanza` — arroganza che sfida gli dèi o i limiti umani (hubris)
- `vanto` — vantarsi, proclamare il proprio nome o merito
- `astuzia` — soluzione ingegnosa (la *metis*), non violenta
- `inganno` — astuzia usata per raggirare
- `misura` — moderazione, prudenza, autocontrollo
- `coraggio` — audacia di fronte al pericolo
- `violenza` — forza bruta, aggressione fisica
- `empieta` — offesa al sacro o agli dèi (include il sacrilegio: profanare ciò che è consacrato)
- `rispetto` — deferenza verso dèi, morti, ospiti, norme

### Atti verso il divino o l'altro
- `preghiera` — invocare un dio (richiede `dio_invocato`)
- `supplica` — implorare pietà o aiuto (a un dio o a un mortale)
- `sacrificio` — offerta rituale (libagione, vittima)
- `xenia` — l'ospitalità: offrirla o onorarla
- `giuramento` — promessa solenne, patto
- `evocazione` — rito per chiamare i morti o gli spiriti (l'Ade)

### Pulsioni e stati espressi
- `desiderio` — brama (amore, piacere, ricchezza, gloria)
- `curiosita` — voler sapere o vedere; aprire ciò che è chiuso
- `nostalgia` — struggimento per casa
- `stanchezza` — sfinimento, tentazione di arrendersi
- `fame` — bisogno fisico impellente
- `disperazione` — perdita di speranza
- `fiducia` — affidarsi a qualcuno o qualcosa
- `sospetto` — diffidenza, guardarsi da un inganno

### Scelte pratiche
- `intrusione` — entrare dove non si dovrebbe
- `rotta` — scelta di navigazione o direzione. **Da solo non chiude una tappa:** per uscire
  serve anche `tipo: movimento`. Il tag dice *di cosa si parla*, `tipo` dice *se ci si
  muove* — «ai remi dobbiamo arrivare ad itaca!» è `rotta` ma è un incitamento, e aveva
  chiuso Troia al turno 3. `fuga` invece non lo chiede: si scappa anche con le parole
- `sfida` — affrontare direttamente un avversario
- `fuga` — ritirarsi, sottrarsi

> **Polarità.** Alcune coppie sono i due poli della stessa cosa: `rispetto`/`empieta`, e `xenia` (onorata) vs `empieta` (ospitalità violata). Per ora la direzione la porta il `tono` + la `sintesi`; se il tagging risultasse ambiguo, in v0.2 aggiungeremo una polarità esplicita.

---

## 2. Tag d'azione vs condizioni di mondo (precisazione)

Non tutti i `trigger` del pantheon vengono dall'Interprete. Alcuni non sono *cose che Ulisse scrive*, ma **stati del mondo** decisi dalla logica di gioco:

- `volere_di_zeus` (Ermes) — condizione divina, non un'azione dell'umano
- `naufragio` (Ino) — sei nella tempesta: evento, non input
- `passaggio` (Scilla) — sei nello stretto: evento, non input

**Conseguenza sul `pantheon.json`:** conviene spezzare il campo `trigger` in due:
- `trigger_azione` — dal vocabolario qui sopra (li accende l'Interprete)
- `trigger_evento` — condizioni di mondo (li accende il GameManager)

Così un dio come Scilla si sveglia sull'evento (`passaggio`) e la scelta di `rotta` dell'umano ne *modula* l'esito; Ino si sveglia sul `naufragio` e premia la `fiducia`.

---

## 3. Envelope di output (JSON, ogni turno)

L'Interprete restituisce **solo** questo oggetto, senza testo attorno:

```json
{
  "plausibilita": "in_mondo",
  "tipo": "parola",
  "tag": ["vanto", "tracotanza"],
  "dio_invocato": null,
  "bersaglio": "polifemo",
  "tono": "sfida",
  "intensita": 2,
  "sintesi": "Ulisse grida il proprio nome al ciclope accecato."
}
```

Campi:
- `plausibilita` — enum: `in_mondo` | `assurdo_diegetico` | `anacronistico` | `meta_nonsenso`. Guida la validazione/ammonizione.
- `tipo` — enum: `parola` | `azione` | `preghiera` | `rituale` | `movimento`
- `tag` — array dal vocabolario chiuso (anche vuoto)
- `dio_invocato` — `id` del dio (da `pantheon.json`) se preghiera/supplica rivolta a qualcuno di preciso; altrimenti `null` (Ulisse prega alla cieca)
- `bersaglio` — a chi è diretta l'azione (`polifemo`, `ciurma`, `straniero`…) o `null`
- `tono` — breve, libero ma conciso (`sfida`, `umile`, `arrogante`, `disperato`, `calmo`, `astuto`…)
- `intensita` — 1–3 (quanto è forte il gesto); aiuta i dèi a calibrare la risposta
- `sintesi` — parafrasi neutra e breve dell'azione, per il diario e per il Narratore

---

## 4. Regole di coerenza (obbligatorie)

1. **Solo JSON valido**, nessun testo prima o dopo.
2. **Solo tag dal vocabolario chiuso.** Se nulla calza: `tag: []`.
3. **Enumerazioni rispettate** per `plausibilita` e `tipo`.
4. **Parsimonia sui tag punitivi** (`tracotanza`, `empieta`, `violenza`): un falso positivo qui può far scattare un castigo divino. Nel dubbio, non taggare — meglio un dio che non reagisce che un giocatore punito per un'inezia. (Principio "leale".)
5. **I tag si mettono sempre**, anche quando `plausibilita ≠ in_mondo`. A svuotarli, *se e solo se il rifiuto regge*, pensa `Validazione._respingi()`. Fino a v2.43 il prompt li chiedeva vuoti, e un'etichetta sbagliata portava via con sé anche le prove: una tracotanza classificata `anacronistico` tornava senza il tag `tracotanza`, e non c'era più modo di accorgersene a valle. Una regola del genere in un prompt è una preghiera; qui è codice.
6. `dio_invocato` valorizzato **solo** con un destinatario esplicito; altrimenti `null`.
7. La stessa azione deve produrre gli stessi tag a ogni turno: la coerenza è una feature, non un vezzo.


## 5. Estensione Ciconi `world_action` (POC)

Durante Ismaro l envelope puo includere `world_action`: una `StructuredAction action/1` che
descrive soltanto il tentativo. Il bridge impone `actor_id = odysseus`, `action_id` e
`expected_world_version`; l output LLM non puo scegliere l attore, l esito, gli eventi o
una patch di stato. I soli campi ammessi sono `verb`, `mode`, `target_id`, `source_id`,
`destination_id`, `resource`, `quantity`, `claim`, `offer`, `request` e `goal`. Campi
ignoti vengono eliminati dalla normalizzazione canonica.

Il Rule Engine decide `REJECTED|FAILURE|PARTIAL_SUCCESS|SUCCESS`. Fuori dal POC il campo
resta `null` e il contratto legacy continua invariato.
