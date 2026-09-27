extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Archive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const TEST_DIRECTORY := "res://tests/.goal16_archive"

var _failures: Array[String] = []
var _session_path := ""
var _session_data_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var capabilities_json := FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	var capability_result := Capabilities.parse_json_text(capabilities_json)
	var capabilities: RefCounted = capability_result["capabilities"]
	var response_bytes := _two_take_response()
	var parsed := MotionResponse.parse(response_bytes, 30, 30.0, capabilities.skeleton_payload)
	_check(parsed["ok"], "two-take source parses")
	if not parsed["ok"]:
		_finish()
		return
	var motions: Array = parsed["motions"]
	var session := SessionStore.create_session("Goal 16 archive")
	session.prompt = "Two durable waves"
	var saved := SessionStore.save_as(session, TEST_DIRECTORY, "archive_session")
	_check(saved["ok"], "current session saves")
	if not saved["ok"]:
		_free_motions(motions)
		_finish()
		return
	_session_path = saved["path"]
	_session_data_path = Archive.DATA_ROOT.path_join(session.session_id)
	var request_json := JSON.stringify({"options": {"num_samples": 2, "seed": 1234}})
	var result := Archive.archive_generation(
		session, _session_path, request_json, capabilities_json,
		response_bytes, capabilities, motions
	)
	_check(result["ok"], "two-take generation archives atomically")
	if result["ok"]:
		var record: Dictionary = result["record"]
		_check(session.generation_records.size() == 1, "session records committed generation")
		_check(record["prompt"] == session.prompt, "generation records prompt title")
		_check(record["takes"].size() == 2, "generation records both takes")
		_check(FileAccess.file_exists(record["rig_snapshot_path"]), "versioned rig snapshot exists")
		var escaped := session.duplicate(true)
		escaped.generation_records[0]["takes"][0]["archive_path"] = "res://tests/escaped.res"
		_check(
			SessionStore.validate_session(escaped).contains("outside its owning session"),
			"session validation rejects an archive path outside its owner",
		)
		for index in record["takes"].size():
			var take: Dictionary = record["takes"][index]
			_check(take["payload_status"] == "archived", "take %d is durable" % index)
			_check(take["source_contract_id"] == "soma77", "take %d records source contract" % index)
			_check(take["source_contract_version"] == 1, "take %d records contract version" % index)
			_check(take["source_rig_schema_version"] == 1, "take %d records rig schema" % index)
			_check(FileAccess.file_exists(take["archive_path"]), "take %d library exists" % index)
			_check(ResourceLoader.get_dependencies(take["archive_path"]).is_empty(), "take %d library is self-contained" % index)
			var loaded := Archive.load_motion(take)
			_check(loaded["ok"], "take %d reloads offline" % index)
			if loaded["ok"]:
				_validate_reconstruction(motions[index].scene, loaded["motion"].scene, index)
				loaded["motion"].scene.free()

		for failure_step in ["rig", "take_0", "take_1", "manifest", "session_save"]:
			var before_failure_hash := FileAccess.get_sha256(_session_path)
			var before_failure_count: int = session.generation_records.size()
			var before_directories := _generation_directories(session.session_id)
			var failure := Archive.archive_generation(
				session, _session_path, request_json, capabilities_json,
				response_bytes, capabilities, motions, {"fail_at": failure_step}
			)
			_check(not failure["ok"], "injected %s failure is reported" % failure_step)
			_check(session.generation_records.size() == before_failure_count, "%s failure records no generation" % failure_step)
			_check(FileAccess.get_sha256(_session_path) == before_failure_hash, "%s failure leaves session byte-identical" % failure_step)
			_check(_generation_directories(session.session_id) == before_directories, "%s failure leaves no partial generation" % failure_step)

		var second := Archive.archive_generation(
			session, _session_path, request_json, capabilities_json,
			response_bytes, capabilities, motions
		)
		_check(second["ok"] and not second["rig_created"], "same source rig snapshot is deduplicated")
		if second["ok"]:
			var integrity_take: Dictionary = second["record"]["takes"][0]
			var integrity_path := String(integrity_take["archive_path"])
			var original_bytes := FileAccess.get_file_as_bytes(integrity_path)
			var corrupt_file := FileAccess.open(integrity_path, FileAccess.WRITE)
			corrupt_file.store_buffer(PackedByteArray([0, 1, 2, 3]))
			corrupt_file.close()
			Archive.refresh_availability(session)
			_check(session.generation_records[1]["takes"][0]["availability"] == "corrupt", "external corruption is diagnosed")
			var restore_file := FileAccess.open(integrity_path, FileAccess.WRITE)
			restore_file.store_buffer(original_bytes)
			restore_file.close()
			Archive.refresh_availability(session)
			_check(session.generation_records[1]["takes"][0]["availability"] == "available", "restored archive becomes available")

		var crash_count: int = session.generation_records.size()
		var crash := Archive.archive_generation(
			session, _session_path, request_json, capabilities_json,
			response_bytes, capabilities, motions, {"simulate_crash_after_promotion": true}
		)
		_check(not crash["ok"], "simulated promotion/save crash interrupts commit")
		_check(session.generation_records.size() == crash_count, "orphan is not prematurely claimed")
		var reopened := SessionStore.open(_session_path)
		_check(reopened["ok"], "session opens after orphan promotion")
		if reopened["ok"]:
			_check(reopened["recovered_generations"] == 1, "complete orphan generation is recovered")
			_check(reopened["session"].generation_records.size() == crash_count + 1, "recovered record is durable")

		var delete_session: Resource = reopened["session"] if reopened["ok"] else session
		var delete_take: Dictionary = delete_session.generation_records[0]["takes"][0]
		var deleted_path := String(delete_take["archive_path"])
		var interrupted_delete := ProjectSettings.globalize_path(deleted_path) + ".deleting-interrupted"
		_check(
			DirAccess.rename_absolute(ProjectSettings.globalize_path(deleted_path), interrupted_delete) == OK,
			"interrupted deletion fixture renames source",
		)
		var deletion_recovery := SessionStore.open(_session_path)
		_check(deletion_recovery["ok"], "session opens after interrupted deletion")
		_check(FileAccess.file_exists(deleted_path), "interrupted deletion restores archived source")
		if deletion_recovery["ok"]:
			delete_session = deletion_recovery["session"]
			delete_take = delete_session.generation_records[0]["takes"][0]
		var delete_result := Archive.delete_take(delete_session, _session_path, delete_take["take_id"])
		_check(delete_result["ok"], "explicit source-take deletion succeeds")
		_check(not FileAccess.file_exists(deleted_path), "deleted source file is removed")
		_check(delete_result["take"]["availability"] == "deleted", "deletion keeps a tombstone")
		_check(FileAccess.file_exists(record["takes"][1]["archive_path"]), "sibling source take remains")

	_free_motions(motions)
	_cleanup()
	_finish()


func _validate_reconstruction(source_root: Node, target_root: Node, take_index: int) -> void:
	var source_skeleton := _find_first(source_root, "Skeleton3D") as Skeleton3D
	var target_skeleton := _find_first(target_root, "Skeleton3D") as Skeleton3D
	_check(target_skeleton.get_bone_count() == source_skeleton.get_bone_count(), "take %d rig bone count matches" % take_index)
	for index in source_skeleton.get_bone_count():
		_check(target_skeleton.get_bone_name(index) == source_skeleton.get_bone_name(index), "take %d bone %d name matches" % [take_index, index])
		_check(target_skeleton.get_bone_parent(index) == source_skeleton.get_bone_parent(index), "take %d bone %d parent matches" % [take_index, index])
		_check(target_skeleton.get_bone_rest(index).is_equal_approx(source_skeleton.get_bone_rest(index)), "take %d bone %d rest matches" % [take_index, index])
	var source_player := _find_first(source_root, "AnimationPlayer") as AnimationPlayer
	var target_player := _find_first(target_root, "AnimationPlayer") as AnimationPlayer
	var source_animation := source_player.get_animation(source_player.get_animation_list()[0])
	var target_animation := target_player.get_animation("motion")
	_check(source_animation.get_track_count() == target_animation.get_track_count(), "take %d track count matches" % take_index)
	for track in source_animation.get_track_count():
		_check(source_animation.track_get_type(track) == target_animation.track_get_type(track), "take %d track %d type matches" % [take_index, track])
		_check(source_animation.track_get_path(track).get_subname(0) == target_animation.track_get_path(track).get_subname(0), "take %d track %d bone matches" % [take_index, track])
		_check(source_animation.track_get_key_count(track) == target_animation.track_get_key_count(track), "take %d track %d keys match" % [take_index, track])
		for key in source_animation.track_get_key_count(track):
			_check(is_equal_approx(source_animation.track_get_key_time(track, key), target_animation.track_get_key_time(track, key)), "take %d track %d key time matches" % [take_index, track])
			_check(source_animation.track_get_key_value(track, key).is_equal_approx(target_animation.track_get_key_value(track, key)), "take %d track %d key value matches" % [take_index, track])


func _two_take_response() -> PackedByteArray:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOTION_FIXTURE))
	var animation: Dictionary = document["animations"][0].duplicate(true)
	animation["name"] = "sample_1"
	document["animations"].append(animation)
	var sample: Dictionary = document["extensions"]["MMCP_motion"]["samples"][0].duplicate(true)
	sample["name"] = "sample_1"
	document["extensions"]["MMCP_motion"]["samples"].append(sample)
	return JSON.stringify(document).to_utf8_buffer()


func _generation_directories(session_id: String) -> Array[String]:
	var result: Array[String] = []
	var path := Archive.DATA_ROOT.path_join(session_id).path_join("generations")
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for child in directory.get_directories():
		if not child.begins_with(".staging-"):
			result.append(child)
	result.sort()
	return result


func _cleanup() -> void:
	_remove_tree(TEST_DIRECTORY)
	_remove_tree(_session_data_path)


func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for filename in directory.get_files():
		DirAccess.remove_absolute(absolute.path_join(filename))
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(absolute)


func _free_motions(motions: Array) -> void:
	for motion in motions:
		if motion != null and is_instance_valid(motion.scene):
			motion.scene.free()


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: durable take archive, exact reconstruction, rollback, recovery, and deletion")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
