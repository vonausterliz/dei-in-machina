# Gateway LLM — coda, throttling, cache, backoff

Applicazione **separata dal gioco** che sta davanti ai provider LLM e fa rispettare i
limiti dei piani gratuiti. Parla il protocollo OpenAI, quindi il gioco (o qualunque altro
client) ci punta cambiando solo `base_url`.

**Tutta la logica del free tier vive qui.** Per toglierla: spegni il gateway e riporta il
gioco sul profilo del provider diretto. Nessuna traccia nel codice di gioco.

## Avvio

```bash
export MISTRAL_API_KEY=...      # le chiavi stanno QUI, non nel gioco
export GEMINI_API_KEY=...

./gateway.sh start     # in background (log in gateway.log)
./gateway.sh restart   # ferma e riavvia
./gateway.sh fg        # in primo piano, per vedere il log dal vivo
./gateway.sh stato     # quote residue e cache
./gateway.sh stop
./gateway.sh libero    # avvia SENZA throttling (piano a pagamento).
                       # «libero» = senza freni, NON «libera la porta».
```

Poi nel gioco scegli il provider **«Gateway (free tier)»**.

## Cosa fa, per ogni richiesta

1. **Cache** — stesso payload già chiesto di recente → risposta immediata, zero quota.
2. **Coda** — una coda FIFO per provider, servita da un solo worker: mai due richieste in
   volo verso lo stesso provider.
3. **Throttling** — rispetta *insieme* tre vincoli: intervallo minimo tra richieste
   (il limite di *velocità*), tetto al minuto (RPM), tetto al giorno (RPD).
4. **Backoff** — su `429`/`5xx` ritenta con attesa esponenziale (1s, 2s, 4s…), dando
   la precedenza all'header `Retry-After` quando il provider lo manda.

## Limiti configurati (`limiti.json`)

| Provider | Intervallo minimo | Al minuto | Al giorno |
|---|---|---|---|
| `mistral` | 1,1 s | 28 | — |
| `google`  | 4,2 s | 14 | 1400 |
| `openrouter` | 3,1 s | 18 | **50** |
| `anthropic` | 1,4 s | 45 | — |
| `openai`  | — | — | — |
| `ollama`  | — | — | — |

Valori **prudenziali** (un margine sotto i limiti dichiarati, perché le finestre del
provider non coincidono mai al millisecondo con le nostre). Se i limiti cambiano, si
ritocca solo questo file: `min_intervallo_s`, `rpm`, `rpd`.

Per disattivare il throttling senza toccare nulla d'altro: `"throttling_attivo": false`
in `limiti.json`, oppure `./gateway.sh libero`.

**`"gratuito": false`** dice che quel provider non ha un piano gratuito: non cambia nulla nel
comportamento, lo fa scrivere all'avvio. Anthropic è così — davanti a lui il gateway non fa
risparmiare, fa da coda, cache e ritentativo.

## A chi va la richiesta

Tre strade, in ordine di autorevolezza:

1. **La query string** `?provider=anthropic`, su `/chat/completions` e su `/models`. È
   l'unica cosa che non si può confondere con un nome di modello: comanda su tutto.
2. **Il prefisso del modello**: `mistral/mistral-small-latest` → Mistral. Resta come ripiego
   per i client che non mandano la query.
3. **Niente prefisso e niente barra**: `provider_predefinito`.

**Non si ripiega mai su un altro provider.** Un provider chiesto e non configurato dà
`400` con un messaggio che dice quali ci sono e dove aggiungerlo — e lo stesso vale per un
prefisso sconosciuto: `mistralai/mistral-small:free` senza `?provider=` è un errore, non un
invito a scegliere per conto altrui (per OpenRouter il nome giusto è
`openrouter/mistralai/mistral-small:free`, e il gateway spezza solo sulla prima barra).

> **Perché la regola è così rigida.** Prima si ripiegava sul predefinito. Con Anthropic
> selezionato nel gioco e non configurato qui, le chiamate finivano a Mistral e l'elenco dei
> modelli mostrava quelli di Mistral etichettati come suoi. Un errore di configurazione — che
> si vede e si aggiusta in dieci secondi — diventava la risposta di un altro modello, che non
> si vede affatto.

## Provider che non parlano OpenAI

Un provider può dichiarare le intestazioni che gli servono, con `$CHIAVE` al posto della
chiave vera. È la stessa convenzione dei profili del gioco (`config/providers/*.json`):

```json
"intestazioni": {
  "x-api-key": "$CHIAVE",
  "anthropic-version": "2023-06-01"
}
```

Anthropic è il caso che l'ha resa necessaria: il suo layer di compatibilità accetta
`/chat/completions` col `Bearer`, ma `/models` pretende `x-api-key` e il Bearer lo rifiuta
con un 401. Le intestazioni si aggiungono a quella di autorizzazione, e sono **le stesse**
per chat ed elenco: erano scritte in due punti, e con Anthropic le due copie avrebbero
dovuto divergere.

## Verificato

**L'instradamento**, con `python3 prova_instradamento.py` — due provider finti su localhost
che registrano chi ha ricevuto cosa e con quali intestazioni. Diciassette controlli:
Anthropic instradato e con le sue intestazioni, il prefisso tolto una volta sola, l'elenco
modelli del provider giusto, un provider sconosciuto respinto con `400` senza che nessuno
risponda al posto suo, e il nome nudo che continua ad andare al predefinito come prima.
Si esegue in un secondo, senza rete e senza chiavi vere.

**I tempi**, con un provider finto che registra gli istanti d'arrivo:

- **throttling**: 5 richieste simultanee → intervalli di 1,00 s; con `rpm: 4` la quinta
  ha atteso la scadenza della finestra (57 s);
- **cache**: seconda richiesta identica servita all'istante, senza consumare quota;
- **backoff**: `429` con `Retry-After: 1` → un solo ritentativo dopo 1 s, poi `200`.

## Perché non LiteLLM

Valutato davvero (installato e ispezionato): fa quasi tutto — rate limit, retry, cache,
API unificata — ma pesa **670 MB** con 109 pacchetti, e soprattutto esprime i limiti come
`rpm` su finestra di un minuto: potrebbe mandare 30 richieste in raffica e poi fermarsi,
sforando il limite di **velocità** di Mistral (~1 al secondo). Questo gateway è ~350 righe
di stdlib, si avvia all'istante e copre esattamente i vincoli che ci servono.
Se un domani servissero fallback tra provider, load balancing o contabilità dei token,
LiteLLM tornerebbe la scelta giusta: basterebbe sostituire questo processo, il gioco non
cambierebbe di una riga.

## Le chiavi le tiene il gateway, non il gioco

Passando di qui il gioco non manda nessuna chiave: le mette il gateway, leggendole dal
**suo** ambiente (`MISTRAL_API_KEY`, `GEMINI_API_KEY`, …). Vanno esportate *prima* di
avviarlo:

```bash
export MISTRAL_API_KEY=...
./gateway.sh restart
```

Senza, il gateway parte lo stesso — lo scrive nel log, `CHIAVE MANCANTE` accanto a ogni
provider, e ora anche `start` lo ripete — ma ogni richiesta torna **401**, e nel gioco
sembra un problema del gioco. Metterla in Settings non serve: quella strada la salta.

## Se `stop` dice «non attivo» ma la porta è occupata

Non può più succedere, ma vale la pena sapere perché succedeva. `stop` si fidava solo del
pidfile, e il pidfile vive **solo sulla macchina dove il gateway gira** (è in `.gitignore`).
`sync-mac.sh` rsync-a con `--delete` e non lo escludeva: ogni sincronizzazione lo portava
via, e da quel momento `stop` non sapeva più chi fermare mentre il processo continuava a
tenersi la porta. `start` falliva per sempre con un traceback di Python.

Ora `sync-mac.sh` lo esclude, e i comandi guardano **chi ascolta sulla porta** invece del
pidfile — che è la domanda vera. Se sulla porta c'è un processo che non è il gateway, lo
dicono e non lo toccano: si può usare un'altra porta con `PORTA=8801 ./gateway.sh start`.
