class_name CiconiWorld
extends RefCounted

## Pure deterministic authority for the Ismaro proof of concept.  This class accepts only
## action/1 dictionaries and returns a copy-on-write candidate; presentation code has no
## entry point that can mutate a WorldState.

const SEED_PATH := "res://data/world/ciconi_seed.json"

static func initial_state(seed_path: String = SEED_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(seed_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CiconiWorld: invalid seed at %s" % seed_path)
		return {}
	var entities: Dictionary = {}
	for id in parsed.get("entities", {}):
		var entity: Dictionary = parsed["entities"][id].duplicate(true)
		entity["id"] = String(id)
		entities[String(id)] = entity
	return {
		"schema": "ciconi-world/1",
		"world_version": 0,
		"turn": 0,
		"locations": parsed.get("locations", []).duplicate(),
		"connections": parsed.get("connections", {}).duplicate(true),
		"entities": entities,
		"resources": parsed.get("resources", {}).duplicate(true),
		"relationships": {},
		"agreements": {},
		"knowledge": [],
		"beliefs": [],
		"events": [],
		"processed_actions": {},
		"world_truth": {},
	}

static func resolve(state: Dictionary, action: Dictionary) -> Dictionary:
	# The input dictionary is never mutated, including rejected inputs.
	var normalized := CiconiContracts.normalized_action(action)
	var checked := CiconiContracts.validate_action(normalized, state)
	if not checked["ok"]:
		return _rejected(state, normalized, "; ".join(checked["errors"]))
	var action_id: String = normalized["action_id"]
	if state.get("processed_actions", {}).has(action_id):
		var replay: Dictionary = state["processed_actions"][action_id].duplicate(true)
		replay["state"] = state.duplicate(true)
		replay["idempotent"] = true
		return replay
	if int(normalized["expected_world_version"]) != int(state.get("world_version", -1)):
		return _rejected(state, normalized, "stale_world_version")
	var actor: Dictionary = state["entities"].get(normalized["actor_id"], {})
	if not actor.get("alive", false):
		return _rejected(state, normalized, "dead_actor_cannot_act")

	var candidate: Dictionary = state.duplicate(true)
	var events: Array = []
	var resolution := _apply(candidate, normalized, events)
	var outcome_status := "SUCCESS"
	var outcome_reason := ""
	if resolution.begins_with("partial:"):
		outcome_status = "PARTIAL_SUCCESS"
		outcome_reason = resolution.trim_prefix("partial:")
	elif resolution.begins_with("failure:"):
		outcome_status = "FAILURE"
		outcome_reason = resolution.trim_prefix("failure:")
	elif resolution != "":
		return _rejected(state, normalized, resolution)
	if events.is_empty():
		return _rejected(state, normalized, "action_produced_no_facts")
	candidate["world_version"] = int(state["world_version"]) + 1
	candidate["turn"] = int(state.get("turn", 0)) + 1
	# Candidate events carry the version they will have *if* the atomic validation succeeds.
	for event in events:
		event["world_version"] = candidate["world_version"]
		candidate["events"].append(event)
	var invariant_errors := validate_state(candidate)
	if not invariant_errors.is_empty():
		return _rejected(state, normalized, "invariant_violation: " + "; ".join(invariant_errors))
	var batch := {
		"schema": CiconiContracts.EVENT_BATCH_SCHEMA,
		"action_id": action_id,
		"base_world_version": state["world_version"],
		"committed_world_version": candidate["world_version"],
		"events": events.duplicate(true),
	}
	var result := {
		"schema": CiconiContracts.OUTCOME_SCHEMA,
		"status": outcome_status,
		"reason": outcome_reason,
		"attempt": normalized.duplicate(true),
		"applied_facts": events.duplicate(true),
		"events": events.duplicate(true),
		"event_batch": batch,
		"committed": true,
		"idempotent": false,
	}
	# Do not store a state inside the state: it would make a recursive value.  Replaying a
	# duplicate action returns the current committed state and the original outcome facts.
	candidate["processed_actions"][action_id] = result.duplicate(true)
	result["state"] = candidate
	return result

static func validate_state(state: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if state.get("schema", "") != "ciconi-world/1":
		errors.append("unknown world schema")
	if int(state.get("world_version", -1)) < 0 or int(state.get("turn", -1)) < 0:
		errors.append("negative version or turn")
	var locations: Array = state.get("locations", [])
	for origin in state.get("connections", {}):
		if not locations.has(origin):
			errors.append("connection has unknown origin")
		for destination in state["connections"][origin]:
			if not locations.has(destination):
				errors.append("connection has unknown destination")
	for entity_id in state.get("entities", {}):
		var entity: Dictionary = state["entities"][entity_id]
		var has_location := String(entity.get("location_id", "")) != ""
		var has_parent := String(entity.get("parent_id", "")) != ""
		if has_location and not locations.has(entity["location_id"]):
			errors.append("entity %s has unknown location" % entity_id)
		if has_location and has_parent:
			errors.append("entity %s has more than one physical parent" % entity_id)
		if not has_location and not has_parent:
			errors.append("entity %s has no physical parent" % entity_id)
		if has_parent and not state["entities"].has(entity["parent_id"]):
			errors.append("entity %s has unknown parent" % entity_id)
	for resource in state.get("resources", {}):
		for owner_id in state["resources"][resource]:
			if int(state["resources"][resource][owner_id]) < 0:
				errors.append("negative %s for %s" % [resource, owner_id])
	var known_event_ids: Dictionary = {}
	for event in state.get("events", []):
		if String(event.get("event_id", "")) == "" or String(event.get("rule_id", "")) == "" or String(event.get("caused_by", "")) == "":
			errors.append("event lacks provenance")
		if known_event_ids.has(event.get("event_id", "")):
			errors.append("duplicate event id")
		known_event_ids[event.get("event_id", "")] = true
		if int(event.get("world_version", -1)) > int(state.get("world_version", -1)):
			errors.append("event has future version")
	for record in state.get("knowledge", []) + state.get("beliefs", []):
		if String(record.get("source_event_id", "")) == "" or not known_event_ids.has(record["source_event_id"]):
			errors.append("knowledge or belief lacks source event")
	for from_id in state.get("relationships", {}):
		for to_id in state["relationships"][from_id]:
			for axis in CiconiContracts.RELATIONSHIP_AXES:
				var value := int(state["relationships"][from_id][to_id].get(axis, 0))
				if value < -100 or value > 100:
					errors.append("relationship outside bounds")
	return errors

static func state_hash(state: Dictionary) -> String:
	var canonical := JSON.stringify(state, "", true)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical.to_utf8_buffer())
	return context.finish().hex_encode()

static func _apply(state: Dictionary, action: Dictionary, events: Array) -> String:
	match action["verb"]:
		"MOVE":
			return _move(state, action, events)
		"ATTACK":
			return _attack(state, action, events)
		"TRANSFER":
			return _transfer(state, action, events)
		"EXCHANGE":
			return _exchange(state, action, events)
		"INFLUENCE":
			return _influence(state, action, events)
		"COMMUNICATE":
			return _communicate(state, action, events)
		"WAIT":
			_add_event(state, action, events, "TURN_WAITED", action["actor_id"], "", "time.wait", {"turn": int(state.get("turn", 0)) + 1})
			return ""
	return "unsupported_verb"

static func _move(state: Dictionary, action: Dictionary, events: Array) -> String:
	var destination: String = action.get("destination_id", action.get("target_id", ""))
	if not state["locations"].has(destination):
		return "unknown_destination"
	var actor: Dictionary = state["entities"][action["actor_id"]]
	if actor.get("parent_id", "") != "":
		return "contained_entity_cannot_move_independently"
	if actor.get("location_id", "") == destination:
		return "already_at_destination"
	var origin: String = actor.get("location_id", "")
	if not state.get("connections", {}).get(origin, []).has(destination):
		return "destination_not_adjacent"
	actor["location_id"] = destination
	_add_event(state, action, events, "ENTITY_MOVED", action["actor_id"], destination, "movement.relocate", {"from_location_id": origin, "to_location_id": destination})
	return ""

static func _attack(state: Dictionary, action: Dictionary, events: Array) -> String:
	var target_id: String = action.get("target_id", "")
	if not state["entities"].has(target_id):
		return "unknown_target"
	var target: Dictionary = state["entities"][target_id]
	if not target.get("alive", false):
		return "target_is_dead"
	if not _same_location(state, action["actor_id"], target_id):
		return "remote_target_cannot_be_interacted_with"
	var rule_id := "combat.attack"
	if _has_prior_cross_faction_attack(state, action["actor_id"], target_id):
		rule_id = "combat.counterattack_authorized"
	_add_event(state, action, events, "CHARACTER_HARMED", action["actor_id"], target_id, rule_id, {"severity": 1})
	_change_relationship(state, action, events, action["actor_id"], target_id, "hostility", 25, rule_id)
	_breach_agreements_between(state, action, events, action["actor_id"], target_id)
	return ""

static func _transfer(state: Dictionary, action: Dictionary, events: Array) -> String:
	var source_id: String = action.get("source_id", action["actor_id"])
	var target_id: String = action.get("target_id", action.get("destination_id", ""))
	var resource: String = action.get("resource", "")
	var quantity := int(action.get("quantity", 0))
	if String(action.get("goal", "")) == "CONSUME":
		return _consume(state, action, events, source_id, resource, quantity)
	if not state["entities"].has(source_id) or not state["entities"].has(target_id):
		return "unknown_transfer_party"
	if quantity <= 0:
		return "invalid_transfer"
	if not _same_location(state, action["actor_id"], source_id) or not _same_location(state, source_id, target_id):
		return "remote_target_cannot_be_interacted_with"
	if state["entities"].has(resource):
		return _transfer_entity(state, action, events, source_id, target_id, resource, quantity)
	if not state["resources"].has(resource):
		return "invalid_transfer"
	if int(state["resources"][resource].get(source_id, 0)) < quantity:
		return "insufficient_resource"
	if source_id != action["actor_id"] and not _has_prior_attack_from_faction(state, action["actor_id"], source_id):
		return "no_permission_for_forced_transfer"
	_apply_transfer(state, action, events, source_id, target_id, resource, quantity, "resource.transfer")
	return ""

static func _consume(state: Dictionary, action: Dictionary, events: Array, source_id: String, resource: String, quantity: int) -> String:
	if source_id != action["actor_id"] or quantity <= 0 or not state["resources"].has(resource):
		return "invalid_consumption"
	if int(state["resources"][resource].get(source_id, 0)) < quantity:
		return "insufficient_resource"
	state["resources"][resource][source_id] = int(state["resources"][resource][source_id]) - quantity
	_add_event(state, action, events, "RESOURCE_CONSUMED", action["actor_id"], "", "resource.consume", {"resource": resource, "quantity": quantity, "owner_id": source_id})
	return ""

static func _transfer_entity(state: Dictionary, action: Dictionary, events: Array, source_id: String, target_id: String, entity_id: String, quantity: int) -> String:
	var entity: Dictionary = state["entities"][entity_id]
	if entity.get("parent_id", "") != source_id:
		return "entity_not_owned_by_source"
	if source_id != action["actor_id"] and not _has_prior_attack_from_faction(state, action["actor_id"], source_id):
		return "no_permission_for_forced_transfer"
	entity["parent_id"] = target_id
	entity["location_id"] = ""
	_add_event(state, action, events, "ENTITY_TRANSFERRED", action["actor_id"], target_id, "entity.transfer", {"entity_id": entity_id, "quantity": quantity, "from_id": source_id, "to_id": target_id})
	if entity_id == "prisoners" and String(action.get("goal", "")) in ["TRUCE", "ESTABLISH_TRUCE"] and state["entities"][target_id].get("faction", "") == "Cicones":
		_activate_agreement(state, action, events, "TRUCE", [action["actor_id"], target_id], {"returned_prisoners": quantity}, "diplomacy.truce_for_return")
		_change_relationship(state, action, events, action["actor_id"], target_id, "trust", 10, "diplomacy.truce_for_return")
		_change_relationship(state, action, events, target_id, action["actor_id"], "trust", 10, "diplomacy.truce_for_return")
		_change_relationship(state, action, events, action["actor_id"], target_id, "hostility", -20, "diplomacy.truce_for_return")
	return ""

static func _exchange(state: Dictionary, action: Dictionary, events: Array) -> String:
	var target_id: String = action.get("target_id", "")
	if not state["entities"].has(target_id):
		return "unknown_target"
	if not _same_location(state, action["actor_id"], target_id):
		return "remote_target_cannot_be_interacted_with"
	var offer: Dictionary = action.get("offer", {})
	var request: Dictionary = action.get("request", {})
	var offer_resource: String = String(offer.get("resource", ""))
	var request_resource: String = String(request.get("resource", ""))
	var offer_quantity := int(offer.get("quantity", 0))
	var request_quantity := int(request.get("quantity", 0))
	if not state["resources"].has(offer_resource) or not state["resources"].has(request_resource) or offer_quantity <= 0 or request_quantity <= 0:
		return "invalid_exchange"
	if int(state["resources"][offer_resource].get(action["actor_id"], 0)) < offer_quantity or int(state["resources"][request_resource].get(target_id, 0)) < request_quantity:
		return "insufficient_resource"
	_apply_transfer(state, action, events, action["actor_id"], target_id, offer_resource, offer_quantity, "exchange.transfer")
	_apply_transfer(state, action, events, target_id, action["actor_id"], request_resource, request_quantity, "exchange.transfer")
	_change_relationship(state, action, events, action["actor_id"], target_id, "trust", 7, "exchange.good_faith")
	_change_relationship(state, action, events, target_id, action["actor_id"], "trust", 7, "exchange.good_faith")
	_change_relationship(state, action, events, action["actor_id"], target_id, "respect", 2, "exchange.good_faith")
	return ""

static func _influence(state: Dictionary, action: Dictionary, events: Array) -> String:
	var target_id: String = action.get("target_id", "")
	if not state["entities"].has(target_id):
		return "unknown_target"
	if not _same_location(state, action["actor_id"], target_id):
		return "remote_target_cannot_be_interacted_with"
	if action.has("claim"):
		_record_claim(state, action, events, target_id)
	var mode: String = action["mode"]
	if mode == "THREATEN":
		_change_relationship(state, action, events, action["actor_id"], target_id, "fear", 10, "influence.threaten")
		_change_relationship(state, action, events, target_id, action["actor_id"], "hostility", 8, "influence.threaten")
		return ""
	if mode == "DECEIVE":
		return "" if action.has("claim") else "deception_requires_claim"
	if mode == "FORM_ALLIANCE":
		return _alliance(state, action, events, target_id)
	var delta := 3 if mode == "NEGOTIATE" else 2
	_change_relationship(state, action, events, action["actor_id"], target_id, "trust", delta, "influence." + mode.to_lower())
	if mode == "NEGOTIATE":
		_change_relationship(state, action, events, target_id, action["actor_id"], "trust", delta, "influence." + mode.to_lower())
	if String(action.get("goal", "")) == "HELP_FOR_FOOD":
		var terms := {"help": true, "requested_resource": action.get("request", {}).get("resource", "food"), "requested_quantity": int(action.get("request", {}).get("quantity", 1))}
		# A promise of assistance is a social fact, not an invented transfer of food.
		_change_relationship(state, action, events, target_id, action["actor_id"], "debt", 5, "diplomacy.assistance_promise")
		var agreement_error := _propose_or_activate(state, action, events, "ASSISTANCE_FOR_FOOD", target_id, terms)
		if agreement_error == "":
			_record_belief_from_latest_event(state, action, events, target_id, {"subject": action["actor_id"], "predicate": "offers", "object": "help_for_food"})
		return agreement_error
	if String(action.get("goal", "")) == "ESTABLISH_ALLIANCE":
		return _propose_or_activate(state, action, events, "ALLIANCE", target_id, {})
	return ""

static func _communicate(state: Dictionary, action: Dictionary, events: Array) -> String:
	var target_id: String = action.get("target_id", "")
	if not state["entities"].has(target_id):
		return "unknown_target"
	if not _same_location(state, action["actor_id"], target_id):
		return "remote_target_cannot_be_interacted_with"
	if action.has("claim"):
		_record_claim(state, action, events, target_id)
	else:
		_add_event(state, action, events, "COMMUNICATION_SENT", action["actor_id"], target_id, "communication.send", {})
	return ""

static func _record_belief_from_latest_event(state: Dictionary, action: Dictionary, events: Array, target_id: String, proposition: Dictionary) -> void:
	var belief: Dictionary = proposition.duplicate(true)
	belief["believer_id"] = target_id
	belief["confidence"] = 70
	belief["source_event_id"] = events.back()["event_id"]
	state["beliefs"].append(belief)
	_add_event(state, action, events, "BELIEF_CHANGED", action["actor_id"], target_id, "belief.from_offer", belief)

static func _record_claim(state: Dictionary, action: Dictionary, events: Array, target_id: String) -> void:
	var claim: Dictionary = action["claim"].duplicate(true)
	_add_event(state, action, events, "CLAIM_UTTERED", action["actor_id"], target_id, "communication.claim", claim)
	var claim_event: Dictionary = events.back()
	var proposition := {"subject": claim.get("subject", action["actor_id"]), "predicate": claim.get("predicate", ""), "object": claim.get("object", "")}
	var knowledge := {"kind": "HEARD_CLAIM", "knower_id": target_id, "claim": proposition, "truth_status": "UNKNOWN", "source_event_id": claim_event["event_id"]}
	state["knowledge"].append(knowledge)
	_add_event(state, action, events, "KNOWLEDGE_LEARNED", action["actor_id"], target_id, "knowledge.heard_claim", knowledge)
	var belief := proposition.duplicate(true)
	belief["believer_id"] = target_id
	belief["confidence"] = 35 if action.get("mode", "") == "DECEIVE" else 50
	belief["source_event_id"] = claim_event["event_id"]
	state["beliefs"].append(belief)
	_add_event(state, action, events, "BELIEF_CHANGED", action["actor_id"], target_id, "belief.from_claim", belief)

static func _alliance(state: Dictionary, action: Dictionary, events: Array, target_id: String) -> String:
	var hostility := maxi(_relationship(state, action["actor_id"], target_id, "hostility"), _relationship(state, target_id, action["actor_id"], "hostility"))
	if hostility >= 40:
		_add_event(state, action, events, "AGREEMENT_REJECTED", action["actor_id"], target_id, "agreement.rejected_hostility", {"kind": "ALLIANCE", "hostility": hostility})
		return "failure:alliance_rejected_by_hostility"
	if int(_relationship(state, action["actor_id"], target_id, "trust")) < 10 or int(_relationship(state, target_id, action["actor_id"], "trust")) < 10:
		_propose_agreement(state, action, events, "ALLIANCE", [action["actor_id"], target_id], {}, "agreement.alliance_proposal")
		return "partial:alliance_proposed"
	_activate_agreement(state, action, events, "ALLIANCE", [action["actor_id"], target_id], {}, "agreement.alliance_acceptance")
	return ""

static func _propose_or_activate(state: Dictionary, action: Dictionary, events: Array, kind: String, target_id: String, terms: Dictionary) -> String:
	if int(_relationship(state, action["actor_id"], target_id, "trust")) >= 10 and int(_relationship(state, target_id, action["actor_id"], "trust")) >= 10:
		_activate_agreement(state, action, events, kind, [action["actor_id"], target_id], terms, "agreement.acceptance")
		return ""
	_propose_agreement(state, action, events, kind, [action["actor_id"], target_id], terms, "agreement.proposal")
	return "partial:agreement_proposed"

static func _propose_agreement(state: Dictionary, action: Dictionary, events: Array, kind: String, parties: Array, terms: Dictionary, rule_id: String) -> String:
	var agreement_id := _agreement_id(kind, parties)
	state["agreements"][agreement_id] = {"id": agreement_id, "kind": kind, "parties": parties.duplicate(), "terms": terms.duplicate(true), "active": false, "proposed_by": action["actor_id"], "source_event_id": ""}
	_add_event(state, action, events, "AGREEMENT_PROPOSED", action["actor_id"], String(parties[1]), rule_id, {"agreement_id": agreement_id, "kind": kind, "parties": parties.duplicate(), "terms": terms.duplicate(true)})
	state["agreements"][agreement_id]["source_event_id"] = events.back()["event_id"]
	return ""

static func _activate_agreement(state: Dictionary, action: Dictionary, events: Array, kind: String, parties: Array, terms: Dictionary, rule_id: String) -> void:
	var agreement_id := _agreement_id(kind, parties)
	state["agreements"][agreement_id] = {"id": agreement_id, "kind": kind, "parties": parties.duplicate(), "terms": terms.duplicate(true), "active": true, "proposed_by": action["actor_id"], "source_event_id": ""}
	_add_event(state, action, events, "AGREEMENT_ACTIVATED", action["actor_id"], String(parties[1]), rule_id, {"agreement_id": agreement_id, "kind": kind, "parties": parties.duplicate(), "terms": terms.duplicate(true)})
	state["agreements"][agreement_id]["source_event_id"] = events.back()["event_id"]

static func _apply_transfer(state: Dictionary, action: Dictionary, events: Array, source_id: String, target_id: String, resource: String, quantity: int, rule_id: String) -> void:
	state["resources"][resource][source_id] = int(state["resources"][resource].get(source_id, 0)) - quantity
	state["resources"][resource][target_id] = int(state["resources"][resource].get(target_id, 0)) + quantity
	_add_event(state, action, events, "ITEM_TRANSFERRED", action["actor_id"], target_id, rule_id, {"resource": resource, "quantity": quantity, "from_id": source_id, "to_id": target_id})

static func _breach_agreements_between(state: Dictionary, action: Dictionary, events: Array, actor_id: String, target_id: String) -> void:
	for agreement_id in state["agreements"].keys():
		var agreement: Dictionary = state["agreements"][agreement_id]
		if agreement.get("active", false) and agreement.get("parties", []).has(actor_id) and agreement.get("parties", []).has(target_id):
			agreement["active"] = false
			_add_event(state, action, events, "AGREEMENT_BREACHED", actor_id, target_id, "agreement.breach_by_attack", {"agreement_id": agreement_id, "kind": agreement.get("kind", "")})

static func _change_relationship(state: Dictionary, action: Dictionary, events: Array, from_id: String, to_id: String, axis: String, delta: int, rule_id: String) -> void:
	if not state["relationships"].has(from_id):
		state["relationships"][from_id] = {}
	if not state["relationships"][from_id].has(to_id):
		state["relationships"][from_id][to_id] = {}
	var previous := int(state["relationships"][from_id][to_id].get(axis, 0))
	var current := clampi(previous + delta, -100, 100)
	state["relationships"][from_id][to_id][axis] = current
	_add_event(state, action, events, "RELATIONSHIP_CHANGED", from_id, to_id, rule_id, {"from_id": from_id, "to_id": to_id, "axis": axis, "delta": current - previous, "value": current})

static func _add_event(state: Dictionary, action: Dictionary, events: Array, type: String, event_actor_id: String, target_id: String, rule_id: String, payload: Dictionary) -> void:
	var ordinal: int = state.get("events", []).size() + events.size() + 1
	var observers: Array = [event_actor_id]
	if target_id != "" and target_id != event_actor_id:
		observers.append(target_id)
	events.append(CiconiContracts.event("%s:e%d" % [action["action_id"], ordinal], int(state.get("world_version", 0)) + 1, type, event_actor_id, target_id, rule_id, action["action_id"], observers, payload))

static func _same_location(state: Dictionary, first_id: String, second_id: String) -> bool:
	var first_location := _effective_location(state, first_id)
	return first_location != "" and first_location == _effective_location(state, second_id)

static func _effective_location(state: Dictionary, entity_id: String) -> String:
	var current_id := entity_id
	var visited: Dictionary = {}
	while state["entities"].has(current_id) and not visited.has(current_id):
		visited[current_id] = true
		var entity: Dictionary = state["entities"][current_id]
		if String(entity.get("location_id", "")) != "":
			return String(entity["location_id"])
		current_id = String(entity.get("parent_id", ""))
	return ""

static func _has_prior_cross_faction_attack(state: Dictionary, actor_id: String, target_id: String) -> bool:
	var actor_faction: String = String(state["entities"][actor_id].get("faction", ""))
	var target_faction: String = String(state["entities"][target_id].get("faction", ""))
	for event in state.get("events", []):
		if event.get("type", "") != "CHARACTER_HARMED":
			continue
		var prior_actor := String(event.get("actor_id", ""))
		var prior_target := String(event.get("target_id", ""))
		if state["entities"].has(prior_actor) and state["entities"].has(prior_target) and state["entities"][prior_actor].get("faction", "") == target_faction and state["entities"][prior_target].get("faction", "") == actor_faction:
			return true
	return false

static func _has_prior_attack_from_faction(state: Dictionary, actor_id: String, target_id: String) -> bool:
	var actor_faction: String = String(state["entities"][actor_id].get("faction", ""))
	var target_faction: String = String(state["entities"][target_id].get("faction", ""))
	for event in state.get("events", []):
		if event.get("type", "") == "CHARACTER_HARMED" and state["entities"].has(event.get("actor_id", "")) and state["entities"].has(event.get("target_id", "")):
			if state["entities"][event["actor_id"]].get("faction", "") == actor_faction and state["entities"][event["target_id"]].get("faction", "") == target_faction:
				return true
	return false

static func _relationship(state: Dictionary, from_id: String, to_id: String, axis: String) -> int:
	return int(state.get("relationships", {}).get(from_id, {}).get(to_id, {}).get(axis, 0))

static func _agreement_id(kind: String, parties: Array) -> String:
	var sorted_parties: Array = parties.duplicate()
	sorted_parties.sort()
	return "%s:%s" % [kind.to_lower(), ":".join(sorted_parties)]

static func _rejected(state: Dictionary, action: Dictionary, reason: String) -> Dictionary:
	return {"schema": CiconiContracts.OUTCOME_SCHEMA, "status": "REJECTED", "reason": reason, "attempt": action.duplicate(true), "applied_facts": [], "events": [], "event_batch": {"schema": CiconiContracts.EVENT_BATCH_SCHEMA, "action_id": action.get("action_id", ""), "base_world_version": state.get("world_version", -1), "committed_world_version": state.get("world_version", -1), "events": []}, "committed": false, "idempotent": false, "state": state.duplicate(true)}
