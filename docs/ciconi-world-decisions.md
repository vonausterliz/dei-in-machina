# Ciconi World Slice — decision log

Documento breve e normativo per gli implementer. Le conversazioni agentiche non sono fonte
di verità.

## Termini

- **Attempt:** ciò che Ulisse prova a fare.
- **StructuredAction:** interpretazione versionata, senza esito.
- **Outcome:** rejected/failure/partial_success/success deciso dalle regole.
- **EventBatch:** eventi candidati di una singola azione; diventa autorevole solo al commit.
- **WorldState:** stato committed corrente, con `world_version` monotona.
- **World truth:** fatti derivati soltanto da stato/eventi committed.
- **Knowledge:** proposition appresa con source event.
- **Belief:** stance soggettiva e confidence; può essere falsa.
- **Agreement:** patto esplicito; alliance non deriva da una soglia di trust.
- **NarrativeBrief:** projection post-commit, presentation-only.

## Contratti stabilizzati

`action/1` richiede: `action_id`, `expected_world_version`, `actor_id`, `verb`; supporta
`mode`, `target_id`, `resource`, `quantity`, `destination_id`, `claim`, `offer`, `request`,
`goal`. Primitive: MOVE, ATTACK, TRANSFER, EXCHANGE, INFLUENCE, COMMUNICATE, WAIT.

`outcome/1` separa `attempt` da `applied_facts`; status: REJECTED, FAILURE,
PARTIAL_SUCCESS, SUCCESS. Solo status non-REJECTED con eventi validi può avanzare la world
version.

`event/1` richiede: `event_id`, `world_version`, `type`, `actor_id`, `target_id`, `rule_id`,
`caused_by`, `observers`, `payload`.

## Invarianti

1. Entità fisica con al massimo un parent/location.
2. Dead actor non agisce.
3. Quantità risorsa mai negativa; transfer conserva il totale.
4. Versioni ed eventi monotoni.
5. Ogni fatto committed ha provenance.
6. Relationship cambia solo mediante evento.
7. Knowledge/belief nuovo ha source event o inference rule.
8. Alliance è Agreement attivo, non `trust > X`.
9. Lore non modifica stato.
10. Prosa/chat/summary non entrano nel reducer.

## World seed minimo

Location: `ismaros_beach`, `ismaros_city`, `odysseus_ships`, `cicones_territory`.
Entity/group: `odysseus`, `crew`, `cicones_leader`, `cicones_warriors`, `ships`,
`prisoners`. Resource: `food`, `wine`, `weapons`, `goods`. Faction: Achaeans, Cicones.

Relationship direzionale: trust, fear, respect, hostility, debt in [-100, 100].

## Regole di scope

- Nessun branch per frase o turno di scenario.
- Counterattack richiede attack/loot committed e condizioni correnti; non deriva dal canone.
- Semantic evaluator assente nel POC iniziale.
- RNG esclusivamente seminato e auditabile.
- Nessun nuovo Autoload.
- Nessuna mutation LLM.
- `GameManager` ha un solo owner nella wave di integrazione.

## Open issues

- Mapping live-LLM delle StructuredAction va benchmarkato; il Semantic Gate usa fixture/mock.
- Safe streaming è differito; il testo viene validato prima del rilascio.
- Estensione globale e porting Python richiedono decisione post-POC.
