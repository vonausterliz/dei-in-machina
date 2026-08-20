extends GutTest

const World = preload("res://scripts/world/ciconi_world.gd")
const Store = preload("res://scripts/world/ciconi_world_store.gd")
const PATH := "user://ciconi_store_tests/ciconi_run.json"


func before_each() -> void:
	_cleanup()


func after_each() -> void:
	_cleanup()


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var absolute := ProjectSettings.globalize_path(PATH + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
	var directory := ProjectSettings.globalize_path("user://ciconi_store_tests")
	DirAccess.remove_absolute(directory)


func _action(state: Dictionary, id: String, verb: String, extra: Dictionary = {}) -> Dictionary:
	var action := {
		"schema": "action/1", "action_id": id,
		"expected_world_version": int(state["world_version"]),
		"actor_id": "odysseus", "verb": verb,
	}
	for key in extra:
		action[key] = extra[key]
	return action


func _append(world, state: Dictionary, record: Dictionary, id: String, verb: String, extra: Dictionary = {}) -> Dictionary:
	var outcome: Dictionary = world.resolve(state, _action(state, id, verb, extra))
	assert_true(bool(outcome.get("committed", false)), "fixture action %s must commit: %s" % [id, outcome.get("reason", "")])
	var stored := Store.append_outcome(record, outcome)
	assert_true(bool(stored.get("ok", false)), "fixture outcome %s must persist: %s" % [id, stored.get("reason", "")])
	return {"state": outcome["state"], "record": stored["record"], "outcome": outcome}


func _long_run() -> Dictionary:
	var world = World.new()
	var state := world.initial_state()
	var record := Store.new_record(Store.seed_id_for_path(), state)
	var step := _append(world, state, record, "store:arrive", "MOVE", {"destination_id": "ismaros_city"})
	state = step["state"]
	record = step["record"]
	step = _append(world, state, record, "store:negotiate", "INFLUENCE", {"target_id": "cicones_leader", "mode": "NEGOTIATE"})
	state = step["state"]
	record = step["record"]
	step = _append(world, state, record, "store:trade", "EXCHANGE", {"target_id": "cicones_leader", "offer": {"resource": "wine", "quantity": 1}, "request": {"resource": "food", "quantity": 1}})
	state = step["state"]
	record = step["record"]
	step = _append(world, state, record, "store:alliance", "INFLUENCE", {"target_id": "cicones_leader", "mode": "FORM_ALLIANCE"})
	state = step["state"]
	record = step["record"]
	step = _append(world, state, record, "store:leave", "MOVE", {"destination_id": "odysseus_ships"})
	state = step["state"]
	record = step["record"]
	for turn_index in range(30):
		step = _append(world, state, record, "store:wait:%d" % turn_index, "WAIT")
		state = step["state"]
		record = step["record"]
	step = _append(world, state, record, "store:return", "MOVE", {"destination_id": "ismaros_city"})
	return {"world": world, "state": step["state"], "record": step["record"]}


func test_round_trip_persists_only_authoritative_run_record() -> void:
	var run := _long_run()
	var saved := Store.save(PATH, run["record"])
	assert_true(bool(saved.get("ok", false)), String(saved.get("reason", "")))
	var loaded := Store.load(PATH)
	assert_true(bool(loaded.get("ok", false)), String(loaded.get("reason", "")))
	assert_false(bool(loaded.get("recovered", true)))
	assert_eq(loaded["record"]["schema"], "ciconi-run/1")
	assert_eq(loaded["record"]["snapshot_hash"], run["record"]["snapshot_hash"])
	assert_eq(loaded["record"]["event_batches"].size(), 36)


func test_replay_after_thirty_plus_turns_matches_committed_snapshot_hash() -> void:
	var run := _long_run()
	var replayed := Store.replay(run["record"])
	assert_true(bool(replayed.get("ok", false)), String(replayed.get("reason", "")))
	assert_eq(run["world"].state_hash(replayed["state"]), run["world"].state_hash(run["state"]))
	assert_eq(Store.snapshot_hash(replayed["state"]), run["record"]["snapshot_hash"])
	assert_eq(int(replayed["state"]["world_version"]), 36)


func test_corrupt_final_file_recovers_previous_valid_backup() -> void:
	var world = World.new()
	var state := world.initial_state()
	var record := Store.new_record(Store.seed_id_for_path(), state)
	var first := _append(world, state, record, "recovery:first", "WAIT")
	state = first["state"]
	record = first["record"]
	assert_true(Store.save(PATH, record)["ok"])
	var second := _append(world, state, record, "recovery:second", "WAIT")
	assert_true(Store.save(PATH, second["record"])["ok"])
	var corrupt := FileAccess.open(PATH, FileAccess.WRITE)
	corrupt.store_string("not json")
	corrupt.close()
	var loaded := Store.load(PATH)
	assert_true(bool(loaded.get("ok", false)), String(loaded.get("reason", "")))
	assert_true(bool(loaded.get("recovered", false)))
	assert_eq(int(loaded["record"]["snapshot"]["world_version"]), 1)


func test_duplicate_and_stale_outcomes_do_not_add_batches() -> void:
	var world = World.new()
	var state := world.initial_state()
	var record := Store.new_record(Store.seed_id_for_path(), state)
	var action := _action(state, "duplicate", "WAIT")
	var accepted := world.resolve(state, action)
	var stored := Store.append_outcome(record, accepted)
	assert_true(stored["ok"])
	record = stored["record"]
	state = accepted["state"]
	var duplicate := world.resolve(state, action)
	stored = Store.append_outcome(record, duplicate)
	assert_true(stored["ok"])
	assert_false(stored["appended"])
	assert_eq(stored["record"]["event_batches"].size(), 1)
	var stale := world.resolve(state, {"schema": "action/1", "action_id": "stale", "expected_world_version": 0, "actor_id": "odysseus", "verb": "WAIT"})
	assert_false(bool(stale.get("committed", true)))
	stored = Store.append_outcome(record, stale)
	assert_true(stored["ok"])
	assert_false(stored["appended"])
	assert_eq(stored["record"]["event_batches"].size(), 1)


func test_presentation_or_prose_fields_are_rejected_from_record() -> void:
	var world = World.new()
	var state := world.initial_state()
	var record := Store.new_record(Store.seed_id_for_path(), state)
	record["narrative"] = {"prose": "La citt\u00e0 canta una guerra che non e' mai avvenuta."}
	var checked := Store.validate_record(record)
	assert_false(bool(checked.get("ok", true)))
	assert_eq(checked["reason"], "presentation_data_is_not_persistable")


func test_loaded_snapshot_hash_rejects_tampered_world_state() -> void:
	var run := _long_run()
	assert_true(Store.save(PATH, run["record"])["ok"])
	var parser := JSON.new()
	assert_eq(parser.parse(FileAccess.get_file_as_string(PATH)), OK)
	var tampered: Dictionary = parser.data
	tampered["snapshot"]["resources"]["food"]["odysseus"] = int(tampered["snapshot"]["resources"]["food"]["odysseus"]) + 1
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(tampered))
	file.close()
	var loaded := Store.load(PATH)
	assert_false(bool(loaded.get("ok", true)))
	assert_ne(String(loaded.get("reason", "")).find("snapshot_hash_mismatch"), -1)


func test_nested_presentation_fields_are_rejected_but_domain_audience_ids_are_allowed() -> void:
	var world = World.new()
	var state := world.initial_state()
	var record := Store.new_record(Store.seed_id_for_path(), state)
	var accepted := world.resolve(state, _action(state, "nested-presentation", "WAIT"))
	var stored := Store.append_outcome(record, accepted)
	assert_true(stored["ok"])
	record = stored["record"]
	record["event_batches"][0]["action"]["parameters"] = {"crew": {"visible": true}, "olympus": {"visible": false}}
	assert_true(Store.validate_record(record)["ok"])
	record["event_batches"][0]["action"]["parameters"]["payload"] = {"narrative": "Falso fatto presentazionale."}
	var checked := Store.validate_record(record)
	assert_false(checked["ok"])
	assert_eq(checked["reason"], "presentation_data_is_not_persistable")
