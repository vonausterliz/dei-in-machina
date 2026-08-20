# ADR-001 — Il canone è lore e attrattore, non script della partita

- **Stato:** Accepted per il POC Ciconi; rollout globale non deciso
- **Data:** 2026-08-20
- **Decision maker:** richiesta esplicita del committente

## Contesto

Il runtime legacy rappresenta il viaggio come quindici episodi in ordine fisso. Alcune
conseguenze canoniche, incluse morti nominali, vengono applicate alla chiusura della tappa.
Questo confonde lore, eventi del poema ed eventi realmente accaduti nella run, e consente
alla scena canonica di contraddire esiti alternativi già narrati.

## Decisione

1. Il canone omerico fornisce lore, geografia, relazioni, condizioni iniziali, regole
   mitologiche, eventi possibili e attrattori narrativi.
2. Un evento canonico non è world truth finché il motore non lo valida e committa.
3. La causalità vive in stato, precondizioni ed eventi, non nella posizione di un episodio.
4. Movimento, morte, ferite, possesso, relazioni, beliefs e agreement cambiano soltanto
   attraverso un `ValidatedOutcome` e il relativo `EventBatch`.
5. Interpreter, Narrator, Crew, Olympus e summary non possono committare fatti.
6. Il POC applica la decisione esclusivamente a Ciconi/Ismaro, dietro feature flag. Il
   comportamento legacy resta invariato altrove e per le run POC-disabled.
7. Python, Evennia, database server e framework general-purpose non fanno parte del POC.

## Conseguenze

Positive: azioni emergenti, causalità auditabile, canone non ferroviario, rollback locale,
narrazione vincolata a fatti committed.

Negative: due policy temporanee (legacy e Ciconi), nuovi contratti, revisione futura di
`Viaggio`, test e contenuti canonici. Il core POC resta dipendente dal runtime Godot.

## Alternative respinte

- Variare soltanto la prosa: non crea world truth.
- Albero manuale di bivi: non scala alle azioni creative.
- LLM come arbitro: non è deterministico né auditabile.
- Python o Evennia NOW: aggiungono infrastruttura prima di validare la semantica.

## Compatibilità e rollback

Il flag è per sessione; nessun dual-write; i save legacy non vengono sovrascritti; la golden
trace legacy non viene rigenerata. Disabilitare il flag riattiva il percorso precedente per
nuove run. L'estensione oltre Ismaro richiede un nuovo Go/No-Go.
