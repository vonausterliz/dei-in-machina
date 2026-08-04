# Componenti di terzi

*Dei in machina* è distribuito sotto **GNU AGPL-3.0** (vedi `LICENSE`). Quello che segue
non è tutto suo: qui c'è cosa arriva da altri, con che licenza, e dove trovarne il testo.

| Componente | Dove | Licenza | Testo |
|---|---|---|---|
| **GUT** — Godot Unit Test | `addons/gut/` | MIT | `addons/gut/LICENSE.md` |
| **Cardo** — carattere di David J. Perry | `fonts/` | SIL OFL 1.1 | `fonts/OFL.txt` |
| **Anonymous Pro** e **Courier Prime** — caratteri usati da GUT | `addons/gut/fonts/` | SIL OFL 1.1 | `addons/gut/fonts/OFL.txt` |
| **Godot Engine** 4.7.x | *non incluso* | MIT | scaricato da `avvia.sh` dalle release ufficiali, con verifica dell'impronta |
| Profilo delle coste del Mediterraneo | `data/` | dominio pubblico | ricavato da dati Natural Earth, ridisegnato da `tools/coste/` |
| Brani dei quindici capitoli | `music/` | dello stesso autore del gioco | generati con **ACE-Step 1.5**; i prompt sono in `music/README.md` |

## Cosa vuol dire, in pratica

**GUT** serve solo a far girare i test: non finisce in una partita e non lega chi gioca.
La MIT è compatibile con l'AGPL — il codice MIT può stare dentro un'opera AGPL.

**Cardo** è un carattere, non codice: la OFL permette di distribuirlo insieme al gioco
purché il testo della licenza lo accompagni (è `fonts/OFL.txt`) e purché non lo si venda
da solo. Il nome «Cardo» è un *Reserved Font Name*: una versione modificata del font va
rinominata.

**Godot** non è nel repository. `avvia.sh` lo scarica dalle release ufficiali di GitHub e
**ne verifica l'impronta SHA-512** prima di eseguirlo: se il file non è quello atteso, il
launcher si ferma invece di lanciarlo.

## La musica

I brani dei capitoli sono generati con **ACE-Step 1.5**, e i prompt che li hanno prodotti
stanno in `music/README.md`: sono la partitura di questa colonna sonora — si leggono, si
rieseguono, si modificano. Nessun brano di terzi, nessun campione preso altrove.

Il gioco funziona anche **senza nessun brano**: un momento senza musica resta in silenzio, e
non è un errore.

## Come è stato scritto

Il codice, i test e questa documentazione sono stati scritti **con l'assistenza di Claude
Code** (Anthropic), usato come strumento in tutto il progetto. Le decisioni di design, la
direzione e la revisione sono dell'autore, che risponde di quello che c'è dentro: uno
strumento non è un coautore, e non c'è nulla di terzi che questo introduca nel repository —
il codice prodotto è opera dell'autore e ricade sotto l'AGPL come il resto.

Sta scritto qui e non in novantun messaggi di commit perché è un'informazione che si cerca
una volta, e in fondo a una `git log` non la trova nessuno.

## Il testo dell'*Odissea*

Il poema è di dominio pubblico da qualche millennio. Le traduzioni no: nel gioco **non c'è
nessuna traduzione altrui**. Le intro delle tappe, gli antefatti degli dèi e i commiati
sono scritti per questo progetto; il resto lo genera un modello a runtime, e resta
sulla macchina di chi gioca.

## I modelli linguistici

Il gioco non ne include nessuno. Parla, a scelta di chi gioca, con **Ollama** (che gira
sulla propria macchina) o con un servizio in rete — Mistral, Google, OpenAI, Anthropic,
OpenRouter. Ognuno ha le proprie condizioni d'uso e i propri prezzi, e non c'entrano con
questa licenza: *Dei in machina* è un client, e la chiave è di chi gioca.
