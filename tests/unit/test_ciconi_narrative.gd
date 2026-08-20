extends GutTest

## Presentation-only guardrails: these tests intentionally use Dictionary fixtures so
## CiconiNarrative remains portable across the core's JSON-shaped contracts.

class FakeCiconiChat:
	var responses: Array = []
	var calls := 0
	var messages: Array = []
	var options: Array = []
	func chat(input_messages: Array, input_options: Dictionary) -> Dictionary:
		messages.append(input_messages.duplicate(true))
		options.append(input_options.duplicate(true))
		var index := mini(calls, responses.size() - 1)
		calls += 1
		return responses[index] if index >= 0 else {"ok": false, "content": ""}

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


func test_brief_for_audience_excludes_invisible_events_and_private_records():
	var events := [
		_event("e-public", "TURN_WAITED", "odysseus", "", ["odysseus"]),
		_event("e-secret", "BELIEF_CHANGED", "cicones_leader", "odysseus", ["cicones_leader"]),
	]
	var state := _world(events)
	var brief := CiconiNarrative.brief(state, {"status": "SUCCESS", "state": {"must_not": "leak"}})
	var view := CiconiNarrative.audience_view(brief, state, "player")
	var filtered := CiconiNarrative.brief_for_audience(brief, view)
	assert_eq(filtered.get("committed_events", []).size(), 1)
	assert_eq(String(filtered["committed_events"][0].get("event_id", "")), "e-public")
	assert_eq(filtered.get("relevant_world_state", {}).get("knowledge", []).size(), 0)
	assert_eq(filtered.get("relevant_world_state", {}).get("beliefs", []).size(), 0)
	assert_false(filtered.get("outcome", {}).has("state"), "authoritative state never enters a narrative projection")


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
	var euphemistic_death := CiconiNarrative.validate({"text": "Il capo esalò l ultimo respiro.", "claims": b["required_claims"]}, b)
	assert_false(euphemistic_death["ok"], "declared claims cannot hide an invented death in prose")


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


func _ok_json(candidate: Dictionary) -> Dictionary:
	return {"ok": true, "content": JSON.stringify(candidate), "error": ""}


func _wait_brief() -> Dictionary:
	var state := _world([_event("e-narrate", "TURN_WAITED", "odysseus", "", ["odysseus", "crew", "olympus"])])
	return CiconiNarrative.brief(state)


func test_narratore_ciconi_accepts_valid_declared_facts_in_one_call():
	var brief := _wait_brief()
	var fake := FakeCiconiChat.new()
	fake.responses = [_ok_json({"text": "Ulisse attese sulla riva.", "claims": brief["required_claims"]})]
	var result := await Narratore.new([]).narra_ciconi(brief, fake.chat)
	assert_eq(result["source"], "candidate")
	assert_eq(fake.calls, 1)
	assert_eq(result["text"], "Ulisse attese sulla riva.")


func test_narratore_ciconi_retries_once_after_missing_or_contradictory_claims():
	var brief := _wait_brief()
	var fake := FakeCiconiChat.new()
	fake.responses = [
		_ok_json({"text": "Un Cicone fu ucciso.", "claims": [{"class": "CHARACTER_KILLED"}]}),
		_ok_json({"text": "Ulisse attese sulla riva.", "claims": brief["required_claims"]}),
	]
	var result := await Narratore.new([]).narra_ciconi(brief, fake.chat)
	assert_eq(result["source"], "retry")
	assert_eq(fake.calls, 2)
	assert_true(String(fake.messages[1][1]["content"]).contains("tentativo precedente"))


func test_narratore_ciconi_two_invalid_answers_use_deterministic_fallback():
	var brief := _wait_brief()
	var fake := FakeCiconiChat.new()
	fake.responses = [
		_ok_json({"text": "Ulisse lascia la riva.", "claims": []}),
		_ok_json({"text": "Un uomo cade.", "claims": []}),
	]
	var narrator := Narratore.new([])
	var result := await narrator.narra_ciconi(brief, fake.chat)
	assert_eq(result["source"], "fallback")
	assert_eq(fake.calls, 2)
	assert_eq(result["text"], CiconiNarrative.fallback(brief)["text"])


func test_ciconi_prompt_includes_brief_and_forbids_new_facts():
	var brief := _wait_brief()
	var messages := Narratore.new([]).messaggi_ciconi(brief)
	var prompt := String(messages[1]["content"])
	assert_string_contains(prompt, "NARRATIVE_BRIEF")
	assert_string_contains(prompt, JSON.stringify(brief))
	assert_string_contains(prompt, "Non aggiungere morti, attacchi, partenze, oggetti o accordi")


func test_narratore_ciconi_redacts_divine_name_without_mutating_world():
	var brief := _wait_brief()
	var before_hash := JSON.stringify(brief, "", true)
	var fake := FakeCiconiChat.new()
	fake.responses = [_ok_json({"text": "Atena veglia mentre Ulisse attende.", "claims": brief["required_claims"]})]
	var narrator := Narratore.new(["Atena"])
	var result := await narrator.narra_ciconi(brief, fake.chat)
	assert_eq(fake.calls, 1)
	assert_false(narrator.nomina_un_dio(result["text"]))
	assert_string_contains(result["text"].to_lower(), "un dio")
	assert_eq(JSON.stringify(brief, "", true), before_hash, "narration cannot mutate the brief/world projection")
