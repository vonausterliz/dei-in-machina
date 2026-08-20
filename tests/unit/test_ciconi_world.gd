extends GutTest

const World = preload("res://scripts/world/ciconi_world.gd")

func _action(state: Dictionary, id: String, actor: String, verb: String, extra: Dictionary = {}) -> Dictionary:
	var action := {"schema": "action/1", "action_id": id, "expected_world_version": state["world_version"], "actor_id": actor, "verb": verb}
	for key in extra:
		action[key] = extra[key]
	return action

func _resolve(world, state: Dictionary, id: String, actor: String, verb: String, extra: Dictionary = {}) -> Dictionary:
	return world.resolve(state, _action(state, id, actor, verb, extra))

func test_action_normalization_is_an_allowlist_not_a_world_patch_channel():
	var normalized := CiconiContracts.normalized_action({"schema": "action/1", "action_id": "smuggle", "expected_world_version": 0, "actor_id": "odysseus", "verb": "WAIT", "events": [{"type": "CHARACTER_KILLED"}], "world_truth": {"fake": true}, "parameters": {"narrative": "invented"}})
	assert_false(normalized.has("events"))
	assert_false(normalized.has("world_truth"))
	assert_false(normalized.has("parameters"))


func test_json_round_trip_action_keeps_integer_contract_and_replays():
	var state := CiconiWorld.initial_state()
	var transported: Variant = JSON.parse_string(JSON.stringify(_action(state, "json-action", "odysseus", "WAIT")))
	assert_true(transported is Dictionary)
	var outcome := CiconiWorld.resolve(state, transported)
	assert_true(bool(outcome.get("committed", false)), String(outcome.get("reason", "")))
	assert_eq(String(outcome.get("status", "")), "SUCCESS")

func test_rejects_dead_actor_and_stale_version_without_mutating_input():
	var world = World.new()
	var state := world.initial_state()
	state["entities"]["odysseus"]["alive"] = false
	var before := world.state_hash(state)
	var dead := _resolve(world, state, "dead", "odysseus", "WAIT")
	assert_eq(dead["status"], "REJECTED")
	assert_eq(dead["reason"], "dead_actor_cannot_act")
	assert_eq(world.state_hash(state), before)
	state["entities"]["odysseus"]["alive"] = true
	var stale := world.resolve(state, {"schema": "action/1", "action_id": "stale", "expected_world_version": 9, "actor_id": "odysseus", "verb": "WAIT"})
	assert_eq(stale["reason"], "stale_world_version")

func test_transfer_conserves_quantity_and_wait_does_not_recreate_resource():
	var world = World.new()
	var state := world.initial_state()
	var total := int(state["resources"]["food"]["odysseus"]) + int(state["resources"]["food"]["cicones_leader"])
	state = _resolve(world, state, "move", "odysseus", "MOVE", {"destination_id": "ismaros_city"})["state"]
	state = _resolve(world, state, "trade", "odysseus", "EXCHANGE", {"target_id": "cicones_leader", "offer": {"resource": "wine", "quantity": 1}, "request": {"resource": "food", "quantity": 2}})["state"]
	state = _resolve(world, state, "wait", "odysseus", "WAIT")["state"]
	assert_eq(int(state["resources"]["food"]["odysseus"]) + int(state["resources"]["food"]["cicones_leader"]), total)

func test_remote_target_and_multiple_physical_parent_are_rejected():
	var world = World.new()
	var state := world.initial_state()
	var remote := _resolve(world, state, "remote", "odysseus", "ATTACK", {"target_id": "cicones_leader"})
	assert_eq(remote["reason"], "remote_target_cannot_be_interacted_with")
	state["entities"]["odysseus"]["parent_id"] = "ships"
	assert_false(world.validate_state(state).is_empty())
	state = world.initial_state()
	var self_containment := _resolve(world, state, "self-containment", "odysseus", "TRANSFER", {"target_id": "prisoners", "resource": "prisoners", "quantity": 1})
	assert_eq(self_containment["status"], "REJECTED")
	assert_eq(self_containment["reason"], "entity_cannot_contain_itself")
	state["entities"]["odysseus"]["location_id"] = ""
	state["entities"]["odysseus"]["parent_id"] = "prisoners"
	assert_true(world.validate_state(state).any(func(error): return String(error).contains("containment cycle")))

func test_false_claim_is_belief_and_knowledge_not_world_truth():
	var world = World.new()
	var state := world.initial_state()
	state = _resolve(world, state, "arrive", "odysseus", "MOVE", {"destination_id": "ismaros_city"})["state"]
	var result := _resolve(world, state, "lie", "odysseus", "INFLUENCE", {"target_id": "cicones_leader", "mode": "DECEIVE", "claim": {"subject": "odysseus", "predicate": "sent_by", "object": "agamemnon"}})
	assert_eq(result["status"], "SUCCESS")
	assert_eq(result["state"]["world_truth"], {})
	assert_eq(result["state"]["beliefs"].size(), 1)
	assert_eq(result["state"]["knowledge"].size(), 1)
	assert_eq(result["state"]["knowledge"][0]["kind"], "HEARD_CLAIM")
	assert_eq(result["state"]["knowledge"][0]["truth_status"], "UNKNOWN")
	assert_ne(result["state"]["beliefs"][0]["source_event_id"], "")

func test_duplicate_action_is_idempotent_and_betrayal_breaks_alliance():
	var world = World.new()
	var state := world.initial_state()
	state = _resolve(world, state, "arrive", "odysseus", "MOVE", {"destination_id": "ismaros_city"})["state"]
	state = _resolve(world, state, "negotiate", "odysseus", "INFLUENCE", {"target_id": "cicones_leader", "mode": "NEGOTIATE"})["state"]
	state = _resolve(world, state, "trade", "odysseus", "EXCHANGE", {"target_id": "cicones_leader", "offer": {"resource": "wine", "quantity": 1}, "request": {"resource": "food", "quantity": 1}})["state"]
	var alliance_action := _action(state, "alliance", "odysseus", "INFLUENCE", {"target_id": "cicones_leader", "mode": "FORM_ALLIANCE"})
	var alliance := world.resolve(state, alliance_action)
	state = alliance["state"]
	var duplicate := world.resolve(state, alliance_action)
	assert_true(duplicate["idempotent"])
	assert_eq(duplicate["state"]["world_version"], state["world_version"])
	var collision := world.resolve(state, _action(state, "alliance", "odysseus", "WAIT"))
	assert_eq(collision["status"], "REJECTED")
	assert_eq(collision["reason"], "idempotency_key_reused")
	var betrayal := _resolve(world, state, "betray", "odysseus", "ATTACK", {"target_id": "cicones_leader"})
	var breached := false
	for event in betrayal["events"]:
		breached = breached or event["type"] == "AGREEMENT_BREACHED"
	assert_true(breached)

func test_prisoners_are_one_contained_entity_and_transfer_as_entity_not_resource():
	var world = World.new()
	var state := world.initial_state()
	assert_false(state["resources"].has("prisoners"))
	assert_eq(state["entities"]["prisoners"]["parent_id"], "odysseus")
	state = _resolve(world, state, "arrive-prisoners", "odysseus", "MOVE", {"destination_id": "ismaros_city"})["state"]
	var returned := _resolve(world, state, "return-prisoners", "odysseus", "TRANSFER", {"target_id": "cicones_leader", "resource": "prisoners", "quantity": 1, "goal": "ESTABLISH_TRUCE"})
	assert_eq(returned["status"], "SUCCESS")
	assert_eq(returned["state"]["entities"]["prisoners"]["parent_id"], "cicones_leader")
	var transferred := false
	for event in returned["events"]:
		transferred = transferred or event["type"] == "ENTITY_TRANSFERRED"
	assert_true(transferred)
	var untouched := world.initial_state()
	untouched = _resolve(world, untouched, "arrive-prisoners-quantity", "odysseus", "MOVE", {"destination_id": "ismaros_city"})["state"]
	var invalid_group_quantity := _resolve(world, untouched, "return-two-groups", "odysseus", "TRANSFER", {"target_id": "cicones_leader", "resource": "prisoners", "quantity": 2})
	assert_eq(invalid_group_quantity["status"], "REJECTED")
	assert_eq(invalid_group_quantity["reason"], "entity_quantity_must_be_one")
	assert_eq(invalid_group_quantity["state"]["entities"]["prisoners"]["parent_id"], "odysseus")

func test_move_requires_seeded_adjacency():
	var world = World.new()
	var state := world.initial_state()
	var remote := _resolve(world, state, "non-adjacent", "odysseus", "MOVE", {"destination_id": "cicones_territory"})
	assert_eq(remote["status"], "REJECTED")
	assert_eq(remote["reason"], "destination_not_adjacent")
	var beach_city := _resolve(world, state, "beach-city", "odysseus", "MOVE", {"destination_id": "ismaros_city"})
	assert_eq(beach_city["status"], "SUCCESS")

func test_alliance_proposal_is_partial_and_hostility_is_committed_failure():
	var world = World.new()
	var state := world.initial_state()
	state = _resolve(world, state, "arrive-outcome", "odysseus", "MOVE", {"destination_id": "ismaros_city"})["state"]
	var proposal := _resolve(world, state, "proposal", "odysseus", "INFLUENCE", {"target_id": "cicones_leader", "mode": "FORM_ALLIANCE"})
	assert_eq(proposal["status"], "PARTIAL_SUCCESS")
	assert_true(proposal["committed"])
	state = proposal["state"]
	state["relationships"]["odysseus"] = {"cicones_leader": {"hostility": 50}}
	var rejection := _resolve(world, state, "hostile-proposal", "odysseus", "INFLUENCE", {"target_id": "cicones_leader", "mode": "FORM_ALLIANCE"})
	assert_eq(rejection["status"], "FAILURE")
	assert_true(rejection["committed"])
	var rejected_event := false
	for event in rejection["events"]:
		rejected_event = rejected_event or event["type"] == "AGREEMENT_REJECTED"
	assert_true(rejected_event)

func test_consumed_resource_does_not_reappear_after_waits():
	var world = World.new()
	var state := world.initial_state()
	var before := int(state["resources"]["food"]["odysseus"])
	var consumed := _resolve(world, state, "consume", "odysseus", "TRANSFER", {"resource": "food", "quantity": 2, "goal": "CONSUME"})
	assert_eq(consumed["status"], "SUCCESS")
	var consumed_event := false
	for event in consumed["events"]:
		consumed_event = consumed_event or event["type"] == "RESOURCE_CONSUMED"
	assert_true(consumed_event)
	state = consumed["state"]
	for index in range(3):
		state = _resolve(world, state, "wait-consume-%d" % index, "odysseus", "WAIT")["state"]
	assert_eq(state["resources"]["food"]["odysseus"], before - 2)
