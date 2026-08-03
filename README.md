# Dei in machina

Gioco narrativo agentico sull'*Odissea*. Il giocatore **è Ulisse**; gli dèi del poema sono
**agenti LLM nascosti** con agende in conflitto, che competono per il suo ritorno. Omero
racconta le conseguenze senza mai nominarli: il vero gioco è dedurre quali potenze hai
attirato, e come. Godot 4 + GDScript.

**Per giocare:** `./avvia.sh` — vedi [COME_GIOCARE.md](COME_GIOCARE.md).

**Per sviluppare**, in quest'ordine:

1. [CLAUDE.md](CLAUDE.md) — istruzioni, mandato di auto-verifica, norme di lavoro
2. [docs/dei_in_machina_design.md](docs/dei_in_machina_design.md) — il **perché**: design congelato
3. [docs/requisiti.md](docs/requisiti.md) — il **cosa**: tutti i requisiti in un posto solo, con lo stato verificato sul codice
4. [docs/architettura_dettaglio.md](docs/architettura_dettaglio.md) — il **come**: componenti, agenti, attivazione degli dèi, formazione della risposta
5. [STATO_LAVORI.md](STATO_LAVORI.md) — a che punto siamo; tienilo aggiornato

`./avvia.sh test` esegue la suite (303 test).
