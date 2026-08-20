# Ciconi World Slice — implementation plan

## Scope

Implementare e validare un world slice GDScript esclusivamente per Ciconi/Ismaro:
StructuredAction, WorldState, regole, Outcome, EventBatch, invarianti, relationship,
agreement, belief/knowledge, NarrativeBrief e audience view. Integrare dietro feature flag,
senza alterare il percorso legacy fuori dal POC.

## Non-goals

Altri episodi; Python/Pydantic/SQLite; Evennia; RAG/vector DB; AI Director; multiplayer;
WebSocket; generic rule/plugin/event framework; full combat/economy; secondo LLM judge.

## Architettura

```text
player text -> legacy Interpreter + StructuredAction/1
            -> CiconiWorld.resolve(copy, action)
            -> Outcome + candidate EventBatch
            -> invariant validation
            -> logical commit WorldState N+1
            -> CiconiNarrative.brief/audience_view
            -> Narrator/Crew/Olympus presentation-only
```

Il Level 1 usa stato in memoria e serializzazione di debug. Solo dopo il Semantic Gate il
Level 2 aggiunge persistence semplice, replay, idempotenza e replacement atomico.

## File ownership

| File/area | Owner | Shared? | Merge order |
|---|---|---:|---:|
| `scripts/world/ciconi_contracts.gd`, `ciconi_world.gd`, seed, unit core | Core Agent / Terra high | No | 1 |
| `scripts/world/ciconi_narrative.gd`, unit narrative | Narrative Agent / Terra high | No | 2 |
| scenario/property fixture e gate | Test Agent / Terra medium | No | 3 |
| ADR, plan, decisions, requirements | Lead | No | 0 |
| `autoload/game_manager.gd` | Lead soltanto | No | 4 |
| `scripts/data/stato_partita.gd`, `contratto.gd`, Interpreter/Viaggio bridge | Lead soltanto | No | 4 |
| hardening store/replay | owner unico assegnato dopo Semantic Gate | No | 5 |

Gli agenti leggono `docs/ciconi-world-decisions.md` prima di scrivere. Nessun worktree:
ownership disgiunta nel workspace comune; il Lead integra e committa.

## Dependency graph e wave

```text
Wave 0 read-only -> Wave 1 ADR/contracts/ownership
                         |
             +-----------+-----------+
             |           |           |
       Core (Wave 2) Narrative   Test harness
             +-----------+-----------+
                         |
              Semantic Gate + fixes
                         |
             Hardening store/replay
                         |
             Integration serialized
                         |
          Test/Red Team/Minimalist review
```

## Test gates

Semantic: canonical, diplomatic, emergent; zero invariant violation; belief != truth;
alliance persists; canonical trade does not trigger counterattack; prose and all audience
outputs leave state hash unchanged; all events have rule/cause/visibility.

Hardening: duplicate action idempotent; stale version rejected; save/load and replay hashes
identical; replacement/recovery tests; 30+ turn leave/return; full GUT and golden unchanged.

## Rollback

Feature flag off, no dual-write, distinct POC state namespace, no legacy save conversion,
no golden update. Remove/bypass the isolated branch without touching legacy state.

## Rischi principali

Decision tree mascherato da rules; optional fields incoerenti; prose contamination rimasta;
test nuovi non raccolti da GUT; fixture troppo aderenti alle frasi; accidental canonical
progression; concurrent edits a GameManager; framework creep.
