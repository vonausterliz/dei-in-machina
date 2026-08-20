extends GutTest

## Semantic-gate scenarios.  These fixtures deliberately contain StructuredAction values,
## never player prose: interpretation is not part of the world authority.

const CiconiWorldScript = preload("res://scripts/world/ciconi_world.gd")


func _world():
	return CiconiWorldScript.new()


func _action(state: Dictionary, id: String, actor_id: String, verb: String, extra := {}) -> Dictionary:
	var action := {
		"schema": "action/1",
		"action_id": id,
		"expected_world_version": int(state["world_version"]),
		"actor_id": actor_id,
		"verb": verb,
	}
	for key in extra:
		action[key] = extra[key]
	return action


func _resolve(world, state: Dictionary, id: String, actor_id: String, verb: String, extra := {}) -> Dictionary:
	var outcome: Dictionary = world.resolve(state, _action(state, id, actor_id, verb, extra))
	assert_ne(String(outcome.get("status", "")), "REJECTED", "action %s must be valid: %s" % [id, outcome.get("reason", "")])
	assert_true(bool(outcome.get("committed", false)), "valid outcome must commit")
	assert_eq(String(outcome.get("schema", "")), "outcome/1")
	assert_eq(int(outcome.get("state", {}).get("world_version", -1)), int(state["world_version"]) + 1)
	for event in outcome.get("events", []):
		assert_ne(String(event.get("rule_id", "")), "", "every committed event has a rule")
		assert_ne(String(event.get("caused_by", "")), "", "every committed event has provenance")
	return outcome


func _event_types(outcome: Dictionary) -> Array:
	var types: Array = []
	for event in outcome.get("events", []):
		types.append(String(event.get("type", "")))
	return types


func _relationship(state: Dictionary, from_id: String, to_id: String, axis: String) -> int:
	return int(state.get("relationships", {}).get(from_id, {}).get(to_id, {}).get(axis, 0))


func _active_agreement(state: Dictionary, kind: String, parties: Array) -> Dictionary:
	for agreement in state.get("agreements", {}).values():
		if String(agreement.get("kind", "")) == kind and bool(agreement.get("active", false)):
			var actual: Array = agreement.get("parties", [])
			if actual.has(parties[0]) and actual.has(parties[1]):
				return agreement
	return {}


func test_canonical_attack_loot_wait_counterattack_escape_is_causal():
	var world = _world()
	var state: Dictionary = world.initial_state()

	var outcome := _resolve(world, state, "canonical:move", "odysseus", "MOVE", {"destination_id": "ismaros_city"})
	state = outcome["state"]
	outcome = _resolve(world, state, "canonical:attack", "odysseus", "ATTACK", {"target_id": "cicones_leader"})
	state = outcome["state"]
	assert_has(_event_types(outcome), "CHARACTER_HARMED")
	outcome = _resolve(world, state, "canonical:loot", "odysseus", "TRANSFER", {
		"source_id": "cicones_leader", "target_id": "odysseus", "resource": "goods", "quantity": 2, "goal": "LOOT"
	})
	state = outcome["state"]
	assert_has(_event_types(outcome), "ITEM_TRANSFERRED")
	outcome = _resolve(world, state, "canonical:wait", "odysseus", "WAIT")
	state = outcome["state"]
	assert_false(_event_types(outcome).has("COUNTERATTACK_STARTED"), "lore never schedules an automatic counterattack")

	# The response is a separate, causal action by the Ciconi, not a canonical timer.
	outcome = _resolve(world, state, "canonical:counterattack", "cicones_warriors", "ATTACK", {"target_id": "odysseus"})
	state = outcome["state"]
	assert_has(_event_types(outcome), "CHARACTER_HARMED")
	assert_true(_relationship(state, "cicones_warriors", "odysseus", "hostility") > 0)
	outcome = _resolve(world, state, "canonical:escape", "odysseus", "MOVE", {"destination_id": "odysseus_ships"})
	assert_eq(String(outcome["state"]["entities"]["odysseus"]["location_id"]), "odysseus_ships")


func test_diplomatic_trade_creates_persistent_explicit_alliance_without_counterattack():
	var world = _world()
	var state: Dictionary = world.initial_state()
	var outcome := _resolve(world, state, "diplomatic:arrive", "odysseus", "MOVE", {"destination_id": "ismaros_city"})
	state = outcome["state"]
	outcome = _resolve(world, state, "diplomatic:negotiate", "odysseus", "INFLUENCE", {
		"target_id": "cicones_leader", "mode": "NEGOTIATE", "goal": "ESTABLISH_ALLIANCE"
	})
	state = outcome["state"]
	outcome = _resolve(world, state, "diplomatic:trade", "odysseus", "EXCHANGE", {
		"target_id": "cicones_leader", "offer": {"resource": "wine", "quantity": 1}, "request": {"resource": "food", "quantity": 2}
	})
	state = outcome["state"]
	assert_false(_event_types(outcome).has("CHARACTER_HARMED"))
	assert_true(_relationship(state, "odysseus", "cicones_leader", "trust") > 0)
	outcome = _resolve(world, state, "diplomatic:alliance", "odysseus", "INFLUENCE", {
		"target_id": "cicones_leader", "mode": "FORM_ALLIANCE", "goal": "ESTABLISH_ALLIANCE"
	})
	state = outcome["state"]
	var alliance := _active_agreement(state, "ALLIANCE", ["odysseus", "cicones_leader"])
	assert_ne(alliance, {}, "alliance is an explicit active agreement, never a trust threshold")
	assert_has(_event_types(outcome), "AGREEMENT_ACTIVATED")

	# Repeated non-violent turns must preserve the committed alternative timeline.
	for turn_index in range(3):
		outcome = _resolve(world, state, "diplomatic:wait:%d" % turn_index, "odysseus", "WAIT")
		state = outcome["state"]
	assert_ne(_active_agreement(state, "ALLIANCE", ["odysseus", "cicones_leader"]), {})
	assert_eq(_relationship(state, "odysseus", "cicones_leader", "hostility"), 0)


func test_emergent_fixtures_preserve_false_claim_as_belief_not_world_truth():
	var world = _world()
	var state: Dictionary = world.initial_state()
	var outcome := _resolve(world, state, "emergent:arrive", "odysseus", "MOVE", {"destination_id": "ismaros_city"})
	state = outcome["state"]

	# Fixture equivalent of: "Fingo che Agamennone mi abbia mandato."
	outcome = _resolve(world, state, "emergent:false-mandate", "odysseus", "INFLUENCE", {
		"target_id": "cicones_leader", "mode": "DECEIVE",
		"claim": {"subject": "odysseus", "predicate": "sent_by", "object": "agamemnon"}
	})
	state = outcome["state"]
	assert_has(_event_types(outcome), "CLAIM_UTTERED")
	assert_false(bool(state.get("facts", {}).get("odysseus:sent_by:agamemnon", false)), "a spoken lie cannot become world truth")
	assert_true(state.get("beliefs", []).size() > 0)
	assert_true(state.get("knowledge", []).size() > 0)
	for belief in state.get("beliefs", []):
		assert_ne(String(belief.get("source_event_id", "")), "")
	for knowledge in state.get("knowledge", []):
		assert_ne(String(knowledge.get("source_event_id", "")), "")


func test_leave_thirty_turns_and_return_recovers_alliance_debt_belief_and_causal_events():
	var world = _world()
	var state: Dictionary = world.initial_state()
	var outcome := _resolve(world, state, "long:arrive", "odysseus", "MOVE", {"destination_id": "ismaros_city"})
	state = outcome["state"]
	# These structured fixtures correspond to returning prisoners for a truce and offering help for food.
	outcome = _resolve(world, state, "long:return-prisoners", "odysseus", "TRANSFER", {
		"target_id": "cicones_leader", "resource": "prisoners", "quantity": 1, "goal": "ESTABLISH_TRUCE"
	})
	state = outcome["state"]
	assert_has(_event_types(outcome), "AGREEMENT_ACTIVATED")
	outcome = _resolve(world, state, "long:help-for-food", "odysseus", "INFLUENCE", {
		"target_id": "cicones_leader", "mode": "NEGOTIATE", "goal": "HELP_FOR_FOOD"
	})
	state = outcome["state"]
	assert_true(_relationship(state, "cicones_leader", "odysseus", "debt") != 0)
	outcome = _resolve(world, state, "long:alliance", "odysseus", "INFLUENCE", {
		"target_id": "cicones_leader", "mode": "FORM_ALLIANCE", "goal": "ESTABLISH_ALLIANCE"
	})
	state = outcome["state"]
	assert_ne(_active_agreement(state, "ALLIANCE", ["odysseus", "cicones_leader"]), {})
	outcome = _resolve(world, state, "long:leave", "odysseus", "MOVE", {"destination_id": "odysseus_ships"})
	state = outcome["state"]
	for turn_index in range(30):
		outcome = _resolve(world, state, "long:wait:%d" % turn_index, "odysseus", "WAIT")
		state = outcome["state"]
	outcome = _resolve(world, state, "long:return", "odysseus", "MOVE", {"destination_id": "ismaros_city"})
	state = outcome["state"]
	assert_ne(_active_agreement(state, "ALLIANCE", ["odysseus", "cicones_leader"]), {})
	assert_true(_relationship(state, "cicones_leader", "odysseus", "debt") != 0)
	assert_true(state.get("beliefs", []).size() > 0)
	assert_true(state.get("events", []).size() >= 38)
	for event in state.get("events", []):
		assert_ne(String(event.get("caused_by", "")), "")

