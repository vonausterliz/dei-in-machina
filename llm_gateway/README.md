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
| `openai`  | — | — | — |
| `ollama`  | — | — | — |

Valori **prudenziali** (un margine sotto i limiti dichiarati, perché le finestre del
provider non coincidono mai al millisecondo con le nostre). Se i limiti cambiano, si
ritocca solo questo file: `min_intervallo_s`, `rpm`, `rpd`.

Per disattivare il throttling senza toccare nulla d'altro: `"throttling_attivo": false`
in `limiti.json`, oppure `./gateway.sh libero`.

## Scelta del modello

Il campo `model` può avere il prefisso del provider:

- `mistral/mistral-small-latest` → va a Mistral
- `google/gemini-2.0-flash` → va a Gemini
- `mistral-small-latest` (senza prefisso) → va al `provider_predefinito`

## Verificato

Provato con un provider finto che registra i tempi d'arrivo:

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
