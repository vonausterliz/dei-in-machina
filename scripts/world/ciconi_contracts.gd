class_name CiconiContracts
extends RefCounted

## Contratti piccoli e chiusi per il solo slice Ciconi.  Sono dati, non comandi:
## nessun campo ricevuto dall'interprete ha il potere di applicare un fatto.

const ACTION_SCHEMA := "action/1"
const OUTCOME_SCHEMA := "outcome/1"
const EVENT_SCHEMA := "event/1"
const EVENT_BATCH_SCHEMA := "event-batch/1"

const VERBS: Array[String] = ["MOVE", "ATTACK", "TRANSFER", "EXCHANGE", "INFLUENCE", "COMMUNICATE", "WAIT"]
const INFLUENCE_MODES: Array[String] = ["NEGOTIATE", "PERSUADE", "DECEIVE", "THREATEN", "FORM_ALLIANCE"]
const OUTCOME_STATUSES: Array[String] = ["REJECTED", "FAILURE", "PARTIAL_SUCCESS", "SUCCESS"]
const RELATIONSHIP_AXES: Array[String] = ["trust", "fear", "respect", "hostility", "debt"]

static func validate_action(action: Dictionary, state: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	if action.get("schema", ACTION_SCHEMA) != ACTION_SCHEMA:
		errors.append("schema must be action/1")
	for field in ["action_id", "expected_world_version", "actor_id", "verb"]:
		if not action.has(field):
			errors.append("missing %s" % field)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	if not (action["action_id"] is String) or String(action["action_id"]).strip_edges().is_empty():
		errors.append("action_id must be a non-empty string")
	if typeof(action["expected_world_version"]) != TYPE_INT or int(action["expected_world_version"]) < 0:
		errors.append("expected_world_version must be a non-negative integer")
	if not (action["actor_id"] is String) or String(action["actor_id"]).strip_edges().is_empty():
		errors.append("actor_id must be a non-empty string")
	if not VERBS.has(String(action["verb"])):
		errors.append("verb is not a supported primitive")
	if not state.is_empty() and not state.get("entities", {}).has(String(action.get("actor_id", ""))):
		errors.append("actor_id is not a known entity")
	if action.get("verb", "") == "INFLUENCE" and not INFLUENCE_MODES.has(String(action.get("mode", ""))):
		errors.append("INFLUENCE requires a supported mode")
	for id_field in ["target_id", "source_id", "destination_id"]:
		if action.has(id_field) and not (action[id_field] is String):
			errors.append("%s must be a string" % id_field)
	if action.has("quantity") and (typeof(action["quantity"]) != TYPE_INT or int(action["quantity"]) <= 0):
		errors.append("quantity must be a positive integer")
	return {"ok": errors.is_empty(), "errors": errors}

static func normalized_action(action: Dictionary) -> Dictionary:
	var result: Dictionary = action.duplicate(true)
	result["schema"] = ACTION_SCHEMA
	result["action_id"] = String(result.get("action_id", ""))
	result["actor_id"] = String(result.get("actor_id", ""))
	result["verb"] = String(result.get("verb", "")).to_upper()
	if result.has("mode"):
		result["mode"] = String(result["mode"]).to_upper()
	for id_field in ["target_id", "source_id", "destination_id", "resource", "goal"]:
		if result.has(id_field):
			result[id_field] = String(result[id_field])
	return result

static func event(event_id: String, world_version: int, type: String, actor_id: String, target_id: String, rule_id: String, caused_by: String, observers: Array, payload: Dictionary) -> Dictionary:
	return {
		"schema": EVENT_SCHEMA,
		"event_id": event_id,
		"world_version": world_version,
		"type": type,
		"actor_id": actor_id,
		"target_id": target_id,
		"rule_id": rule_id,
		"caused_by": caused_by,
		"observers": observers.duplicate(),
		"payload": payload.duplicate(true),
	}
