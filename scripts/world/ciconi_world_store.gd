class_name CiconiWorldStore
extends RefCounted

## Minimal persistence boundary for the Ciconi slice.  It stores committed state plus the
## ordered, structured actions needed to deterministically verify that snapshot.  It is not
## a general event-sourcing framework and deliberately has no narrative/projection fields.

const RUN_SCHEMA := "ciconi-run/1"
const DEFAULT_SEED_ID := "ciconi-ismaros/1"
const FORBIDDEN_PRESENTATION_KEYS: Array[String] = ["prose", "narrative", "narration", "narrator", "narratore", "summary", "brief", "presentation", "audience_view", "factual_memory", "cronaca", "chat", "rendered_text"]

static func new_record(seed_id: String = DEFAULT_SEED_ID, initial_state: Dictionary = {}) -> Dictionary:
	var snapshot := initial_state.duplicate(true)
	return {
		"schema": RUN_SCHEMA,
		"seed_id": seed_id,
		"snapshot": snapshot,
		"snapshot_hash": snapshot_hash(snapshot) if not snapshot.is_empty() else "",
		"event_batches": [],
	}

## Adds one non-idempotent committed Outcome.  Rejected, stale and retried actions never
## become a persisted batch: their absence is itself the desired audit trail for this POC.
static func append_outcome(record: Dictionary, outcome: Dictionary) -> Dictionary:
	var copy := record.duplicate(true)
	if not bool(outcome.get("committed", false)) or bool(outcome.get("idempotent", false)):
		return {"ok": true, "appended": false, "record": copy}
	var state: Dictionary = outcome.get("state", {})
	var event_batch: Dictionary = outcome.get("event_batch", {})
	var action: Dictionary = outcome.get("attempt", {})
	if state.is_empty() or event_batch.is_empty() or action.is_empty():
		return {"ok": false, "reason": "committed_outcome_is_incomplete", "record": copy}
	if int(event_batch.get("base_world_version", -1)) != int(copy.get("snapshot", {}).get("world_version", -1)):
		return {"ok": false, "reason": "batch_base_version_mismatch", "record": copy}
	if String(event_batch.get("action_id", "")) != String(action.get("action_id", "")):
		return {"ok": false, "reason": "batch_action_id_mismatch", "record": copy}
	var batch := event_batch.duplicate(true)
	batch["action"] = action.duplicate(true)
	batch["outcome_status"] = String(outcome.get("status", ""))
	batch["outcome_reason"] = String(outcome.get("reason", ""))
	copy["event_batches"].append(batch)
	copy["snapshot"] = state.duplicate(true)
	copy["snapshot_hash"] = snapshot_hash(copy["snapshot"])
	var checked := validate_record(copy)
	if not checked["ok"]:
		return {"ok": false, "reason": checked["reason"], "record": record.duplicate(true)}
	return {"ok": true, "appended": true, "record": copy}

static func validate_record(record: Dictionary) -> Dictionary:
	if String(record.get("schema", "")) != RUN_SCHEMA:
		return _invalid("unknown_run_schema")
	if String(record.get("seed_id", "")).strip_edges().is_empty():
		return _invalid("missing_seed_id")
	if not (record.get("snapshot", {}) is Dictionary) or not (record.get("event_batches", []) is Array):
		return _invalid("invalid_record_shape")
	if _has_forbidden_presentation_key(record) or _has_forbidden_presentation_key(record.get("snapshot", {})):
		return _invalid("presentation_data_is_not_persistable")
	var snapshot: Dictionary = record["snapshot"]
	if snapshot.is_empty():
		if not record["event_batches"].is_empty() or String(record.get("snapshot_hash", "")) != "":
			return _invalid("empty_snapshot_is_not_initial_record")
		return {"ok": true}
	var state_errors := CiconiWorld.validate_state(snapshot)
	if not state_errors.is_empty():
		return _invalid("invalid_snapshot: " + "; ".join(state_errors))
	if String(record.get("snapshot_hash", "")).is_empty():
		return _invalid("snapshot_hash_missing")
	if String(record.get("snapshot_hash", "")) != snapshot_hash(snapshot):
		return _invalid("snapshot_hash_mismatch")
	var expected_base := 0
	var known_actions: Dictionary = {}
	for batch_value in record["event_batches"]:
		if not (batch_value is Dictionary):
			return _invalid("event_batch_is_not_a_dictionary")
		var batch: Dictionary = batch_value
		if String(batch.get("schema", "")) != CiconiContracts.EVENT_BATCH_SCHEMA:
			return _invalid("unknown_event_batch_schema")
		if not (batch.get("action", {}) is Dictionary):
			return _invalid("event_batch_lacks_action")
		var action: Dictionary = batch["action"]
		if _has_forbidden_presentation_key(action):
			return _invalid("presentation_data_is_not_persistable")
		if String(batch.get("action_id", "")) == "" or String(batch["action_id"]) != String(action.get("action_id", "")):
			return _invalid("event_batch_action_id_mismatch")
		if known_actions.has(batch["action_id"]):
			return _invalid("duplicate_action_batch")
		known_actions[batch["action_id"]] = true
		if int(batch.get("base_world_version", -1)) != expected_base or int(batch.get("committed_world_version", -1)) != expected_base + 1:
			return _invalid("non_monotonic_event_batch")
		if not (batch.get("events", []) is Array) or batch["events"].is_empty():
			return _invalid("event_batch_has_no_events")
		if not CiconiContracts.OUTCOME_STATUSES.has(String(batch.get("outcome_status", ""))) or String(batch.get("outcome_status", "")) == "REJECTED":
			return _invalid("event_batch_has_invalid_outcome_status")
		expected_base += 1
	if int(snapshot.get("world_version", -1)) != expected_base:
		return _invalid("snapshot_version_does_not_match_batches")
	return {"ok": true}

## Rebuilds the snapshot from the fixed seed.  The comparison intentionally includes the
## events and status, so a valid-looking but causally different save cannot be accepted.
static func replay(record: Dictionary, seed_path: String = CiconiWorld.SEED_PATH) -> Dictionary:
	var checked := validate_record(record)
	if not checked["ok"]:
		return {"ok": false, "reason": checked["reason"], "state": {}}
	if String(record["seed_id"]) != seed_id_for_path(seed_path):
		return {"ok": false, "reason": "seed_id_mismatch", "state": {}}
	var state := CiconiWorld.initial_state(seed_path)
	if state.is_empty():
		return {"ok": false, "reason": "seed_load_failed", "state": {}}
	for batch_value in record["event_batches"]:
		var batch: Dictionary = batch_value
		var action: Dictionary = batch["action"]
		if int(action.get("expected_world_version", -1)) != int(batch["base_world_version"]):
			return {"ok": false, "reason": "action_expected_version_mismatch", "state": state}
		var outcome := CiconiWorld.resolve(state, action)
		if not bool(outcome.get("committed", false)) or bool(outcome.get("idempotent", false)):
			return {"ok": false, "reason": "replay_did_not_commit", "state": state}
		if String(outcome.get("status", "")) != String(batch["outcome_status"]):
			return {"ok": false, "reason": "replay_status_mismatch", "state": state}
		if not _same_json(outcome.get("events", []), batch.get("events", [])):
			return {"ok": false, "reason": "replay_events_mismatch", "state": state}
		if int(outcome.get("event_batch", {}).get("committed_world_version", -1)) != int(batch["committed_world_version"]):
			return {"ok": false, "reason": "replay_version_mismatch", "state": state}
		state = outcome["state"]
	if snapshot_hash(state) != String(record.get("snapshot_hash", "")):
		return {"ok": false, "reason": "replay_snapshot_hash_mismatch", "state": state}
	return {"ok": true, "state": state}

## Writes a logically atomic checkpoint.  The previous valid final file remains as `.bak`;
## if a later final file is corrupt, `load` can recover it without consulting any LLM output.
static func save(path: String, record: Dictionary) -> Dictionary:
	if not path.begins_with("user://"):
		return {"ok": false, "reason": "path_must_be_under_user"}
	var checked := validate_record(record)
	if not checked["ok"]:
		return {"ok": false, "reason": checked["reason"]}
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	var make_error := DirAccess.make_dir_recursive_absolute(directory)
	if make_error != OK:
		return {"ok": false, "reason": "cannot_create_directory"}
	var temporary := absolute + ".tmp"
	var backup := absolute + ".bak"
	DirAccess.remove_absolute(temporary)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "cannot_open_temporary_file"}
	file.store_string(JSON.stringify(record, "\t") + "\n")
	file.flush()
	file.close()
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(absolute, backup) != OK:
			DirAccess.remove_absolute(temporary)
			return {"ok": false, "reason": "cannot_rotate_backup"}
	if DirAccess.rename_absolute(temporary, absolute) != OK:
		if FileAccess.file_exists(backup) and not FileAccess.file_exists(absolute):
			DirAccess.rename_absolute(backup, absolute)
		return {"ok": false, "reason": "cannot_replace_final"}
	return {"ok": true, "path": path}

static func load(path: String) -> Dictionary:
	if not path.begins_with("user://"):
		return {"ok": false, "reason": "path_must_be_under_user"}
	var final_record := _read_valid_record(path)
	if final_record["ok"]:
		final_record["recovered"] = false
		return final_record
	var backup_record := _read_valid_record(path + ".bak")
	if backup_record["ok"]:
		backup_record["recovered"] = true
		return backup_record
	return {"ok": false, "reason": "no_valid_record: %s; backup: %s" % [final_record.get("reason", "missing"), backup_record.get("reason", "missing")]}

static func seed_id_for_path(seed_path: String = CiconiWorld.SEED_PATH) -> String:
	return DEFAULT_SEED_ID if seed_path == CiconiWorld.SEED_PATH else "ciconi-custom:" + seed_path

static func _read_valid_record(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "file_missing"}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"ok": false, "reason": "invalid_json"}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_json"}
	var record: Dictionary = parsed
	var checked := validate_record(record)
	if not checked["ok"]:
		return {"ok": false, "reason": checked["reason"]}
	return {"ok": true, "record": record}

static func _has_forbidden_presentation_key(value: Variant) -> bool:
	## `crew` and `olympus` are legitimate IDs; only explicit presentation fields are
	## prohibited. Recurse so an interpreter cannot smuggle prose in parameters/payload.
	if value is Dictionary:
		for key in value:
			if FORBIDDEN_PRESENTATION_KEYS.has(String(key).to_lower()):
				return true
			if _has_forbidden_presentation_key(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _has_forbidden_presentation_key(item):
				return true
	return false

static func _same_json(first: Variant, second: Variant) -> bool:
	return JSON.stringify(first, "", true) == JSON.stringify(second, "", true)

static func snapshot_hash(snapshot: Dictionary) -> String:
	## Hash the JSON transport representation. That makes the digest reproducible after a
	## save/load round trip while still covering the complete committed WorldState.
	var normalized: Variant = JSON.parse_string(JSON.stringify(snapshot))
	return CiconiWorld.state_hash(normalized if normalized is Dictionary else {})

static func _invalid(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
