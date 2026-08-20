extends GutTest

## Presentation-only guardrails: these tests intentionally use Dictionary fixtures so
## CiconiNarrative remains portable across the core's JSON-shaped contracts.

func _event(event_id: String, event_type: String, actor: String, target: String,
		observers: Array, payload: Dictionary = {}) -> Dictionary:
	return {
		"schema": "event/1", "event_id": event_id, "world_version": 3,
		"type": event_type, "actor_id": actor, "target_id": target,
		"rule_id": "test_rule", "caused_by": "action-1", "observers": observers,
		"payload": payload,
	}


func _world(events: Array) -> Dictionary:
	return {
		"world_version": 3, "turn": 8, "events": events,
		"entities": {"odysseus": {"location_id": "ismaros_beach"}},
		"resources": {"goods": {"quantity": 10}},
		"relationships": {"odysseus": {"cicones_leader": {"trust": 25}}},
		"agreements": [{"kind": "ALLIANCE", "parties": ["odysseus", "cicones_leader"], "active": true}],
		"knowledge": [{"knower_id": "cicones_leader", "source_event_id": "e-claim", "claim": "sent_by_agamemnon"}],
		"beliefs": [{"holder_id": "cicones_leader", "source_event_id": "e-claim", "claim": "sent_by_agamemnon", "confidence": 60}],
	}


func test_brief_uses_only_committed_events_and_keeps_false_claim_as_utterance():
	var events := [_event("e-claim", "CLAIM_UTTERED", "odysseus", "cicones_leader", ["odysseus", "cicones_leader"], {
		"claim": {"subject": "odysseus", "predicate": "sent_by", "object": "agamemnon"}})]
	var b := CiconiNarrative.brief(_world(events), {"status": "SUCCESS"})
	assert_eq(b["world_version"], 3)
	assert_eq(b["required_claims"].size(), 1)
	assert_eq(b["required_claims"][0]["predicate"], "uttered_claim_to")
	assert_ne(b["required_claims"][0]["predicate"], "sent_by", "claim content must not become truth")


func test_audience_views_share_version_but_filter_events_and_knowledge_by_source():
	var events := [
		_event("e-public", "TURN_WAITED", "odysseus", "", ["crew"]),
		_event("e-claim", "CLAIM_UTTERED", "odysseus", "cicones_leader", ["odysseus", "cicones_leader"]),
	]
	var state := _world(events)
	var b := CiconiNarrative.brief(state)
	var crew := CiconiNarrative.audience_view(b, state, "crew")
	var player := CiconiNarrative.audience_view(b, state, "player")
	var olympus := CiconiNarrative.audience_view(b, state, "olympus")
	assert_eq(crew["world_version"], player["world_version"])
	assert_eq(player["world_version"], olympus["world_version"])
	assert_eq(crew["events"].size(), 1)
	assert_eq(player["events"].size(), 1)
	assert_eq(olympus["events"].size(), 0)
	assert_eq(player["relationships"].size(), 1, "player receives the directional relation that involves Odysseus")
	assert_eq(crew["knowledge"].size(), 0, "crew must not learn the leader's secret")


func test_brief_accepts_the_core_event_batch_dictionary():
	var event := _event("e-batch", "TURN_WAITED", "odysseus", "", ["odysseus"])
	var state := _world([])
	var b := CiconiNarrative.brief(state, {}, {"schema": "event-batch/1", "events": [event]})
	assert_eq(b["committed_events"].size(), 1)
	assert_eq(b["required_claims"][0]["predicate"], "waited")


func test_factual_memory_is_deterministic_and_derived_from_events_not_prose():
	var state := _world([_event("e-1", "ITEM_TRANSFERRED", "odysseus", "cicones_leader", ["odysseus"], {"resource": "goods", "quantity": 2})])
	var a := CiconiNarrative.factual_memory(state)
	var b := CiconiNarrative.factual_memory(state)
	assert_eq(a, b)
	assert_string_contains(a["entries"][0], "ITEM_TRANSFERRED")
	assert_false(a.has("narration"))


func test_validate_requires_committed_facts_and_rejects_forbidden_invented_death():
	var state := _world([_event("e-1", "ITEM_TRANSFERRED", "odysseus", "cicones_leader", ["odysseus"], {"resource": "goods", "quantity": 2})])
	var b := CiconiNarrative.brief(state)
	var missing := CiconiNarrative.validate({"text": "Scambiarono merci.", "claims": []}, b)
	assert_false(missing["ok"])
	var invented := CiconiNarrative.validate({"text": "Un Cicone fu ucciso.", "claims": [
		{"class": "CHARACTER_KILLED", "subject": "odysseus", "predicate": "killed", "object": "cicones_leader"}]}, b)
	assert_false(invented["ok"])


func test_failed_narrator_retry_uses_deterministic_fallback_with_required_facts():
	var state := _world([_event("e-1", "TURN_WAITED", "odysseus", "", ["odysseus"])])
	var b := CiconiNarrative.brief(state)
	var selected := CiconiNarrative.choose(
		{"text": "Ulisse salpo'.", "claims": []},
		{"text": "Un uomo mori'.", "claims": []}, b)
	assert_eq(selected["source"], "fallback")
	assert_string_contains(selected["text"], "TURN_WAITED")
	assert_true(selected["validation"]["ok"])


func test_all_presentation_projections_leave_world_state_unchanged():
	var state := _world([_event("e-1", "TURN_WAITED", "odysseus", "", ["odysseus", "crew", "olympus"])])
	var before := state.duplicate(true)
	var before_hash := JSON.stringify(state, "", true)
	var b := CiconiNarrative.brief(state)
	CiconiNarrative.audience_view(b, state, "player")
	CiconiNarrative.audience_view(b, state, "crew")
	CiconiNarrative.audience_view(b, state, "olympus")
	CiconiNarrative.factual_memory(state)
	CiconiNarrative.choose({"text": "", "claims": []}, {"text": "", "claims": []}, b)
	assert_eq(state, before, "narrator, crew and olympus projections cannot mutate truth")
	assert_eq(JSON.stringify(state, "", true), before_hash, "presentation cannot change the committed state hash")
