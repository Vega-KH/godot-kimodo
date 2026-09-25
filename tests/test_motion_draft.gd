extends SceneTree

const Draft := preload("res://addons/kimodo_motion/domain/motion_draft.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_draft_store.gd")
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const JENNY_PATH := "res://tests/characters/fixtures/Jenny03.glb"
const JENNY_SCENE := preload(JENNY_PATH)
const CAPABILITIES_PATH := "res://tests/fixtures/soma77_capabilities.json"
const RESPONSE_PATH := "res://tests/fixtures/soma77_mmcp_1_0.gltf"

class FakeCapabilities extends RefCounted:
	var protocol_version := "1.0"
	var model_id := "kimodo-soma-rp"
	var fps := 30.0
	var skeleton_payload: Dictionary

var _failures: Array[String] = []


func _init() -> void:
	var output_directory := "res://tests/.goal13_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()
	]
	var fixture_hash := FileAccess.get_sha256(JENNY_PATH)
	var draft: Resource = Store.create_draft()
	_check(draft.schema_version == Draft.SCHEMA_VERSION, "new draft uses current schema")
	_check(not draft.draft_id.is_empty(), "new draft has a stable ID")
	_check(not draft.created_at_utc.is_empty(), "new draft has a creation time")

	var target_one: Node3D = JENNY_SCENE.instantiate()
	var target_two: Node3D = JENNY_SCENE.instantiate()
	var skeleton_one := _find_first(target_one, "Skeleton3D") as Skeleton3D
	var skeleton_two := _find_first(target_two, "Skeleton3D") as Skeleton3D
	var signature := Store.skeleton_signature(skeleton_one)
	_check(signature.length() == 64, "target signature is SHA-256")
	_check(signature == Store.skeleton_signature(skeleton_two), "target signature is repeatable")
	var target_result := Store.set_target(draft, JENNY_PATH, skeleton_one)
	_check(target_result["ok"], "Jenny target is recorded")
	_check(draft.target_scene_path == JENNY_PATH, "target path stays project-relative")
	_check(draft.target_skeleton_signature == signature, "target signature is stored")
	target_one.free()
	target_two.free()

	Store.sync_editable_intent(draft, "A person waves.", 45, 9876, 120)
	var capability_text := FileAccess.get_file_as_string(CAPABILITIES_PATH)
	var capability_document: Dictionary = JSON.parse_string(capability_text)
	var model: Dictionary = capability_document["models"][0]
	var capabilities := FakeCapabilities.new()
	capabilities.skeleton_payload = model["canonical_skeleton"]
	var request_json := '{"prompt":"A person waves.","seed":9876}'
	var response_bytes := FileAccess.get_file_as_bytes(RESPONSE_PATH)
	var record_result := Store.append_generation_record(
		draft, request_json, capability_text, response_bytes, capabilities
	)
	_check(record_result["ok"], "generation provenance is recorded")
	var recorded: Dictionary = draft.active_generation_record()
	_check(recorded["request_json"] == request_json, "exact request JSON is retained")
	_check(recorded["request_sha256"] == Store.sha256_text(request_json), "request hash is exact")
	_check(recorded["response_sha256"] == Store.sha256_bytes(response_bytes), "response hash is exact")
	_check(recorded["model_id"] == capabilities.model_id, "model identity is retained")
	Store.sync_editable_intent(draft, "A person sits.", 60, 1234, 100)
	_check(
		draft.active_generation_record() == recorded,
		"editing current intent does not rewrite generation provenance",
	)

	var outside := ProjectPaths.validate_directory("res://tests/../../outside-project")
	_check(not outside["ok"] and outside["code"] == "outside_project", "path traversal is rejected")
	var user_path := ProjectPaths.validate_directory("user://goal13")
	_check(not user_path["ok"], "user data is not accepted as project output")

	var directory_result := ProjectPaths.ensure_directory(output_directory)
	_check(directory_result["ok"], "test project directory is created")
	var artifact_path := output_directory.path_join("known_artifact.res")
	var artifact_file := FileAccess.open(artifact_path, FileAccess.WRITE)
	artifact_file.store_string("known artifact")
	artifact_file.close()
	var artifact_result := Store.record_artifact(draft, "soma77_library", artifact_path)
	_check(artifact_result["ok"], "successful artifact is recorded")
	_check(draft.artifacts["soma77_library"]["status"] == "saved", "artifact status is saved")
	_check(
		draft.artifacts["soma77_library"]["generation_record_id"] == recorded["record_id"],
		"artifact links to the generation record that produced it",
	)

	var first_save := Store.save_as(draft, output_directory, "wave draft")
	_check(first_save["ok"], "new draft saves")
	var first_path: String = first_save.get("path", "")
	var first_id: String = draft.draft_id
	var first_created: String = draft.created_at_utc
	var second_save := Store.save_as(draft, output_directory, "wave draft")
	_check(second_save["ok"], "Save As succeeds again")
	_check(second_save.get("path") != first_path, "Save As chooses a unique path")
	var update_save := Store.save(draft, first_path)
	_check(update_save["ok"] and update_save.get("path") == first_path, "Save updates explicit path")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(artifact_path))
	var loaded_result := Store.load_draft(first_path)
	_check(loaded_result["ok"], "draft loads offline")
	if loaded_result["ok"]:
		var loaded: Resource = loaded_result["draft"]
		_check(loaded.draft_id == first_id, "draft ID round-trips")
		_check(loaded.created_at_utc == first_created, "creation time is stable")
		_check(loaded.prompt == "A person sits.", "editable intent round-trips")
		_check(loaded.generation_records.size() == 1, "generation record round-trips")
		_check(
			loaded_result["missing_artifacts"] == ["soma77_library"],
			"missing artifact is reported without rejecting the draft",
		)

	var unsupported := Store.create_draft()
	unsupported.schema_version = 99
	var unsupported_path := output_directory.path_join("unsupported.tres")
	_check(ResourceSaver.save(unsupported, unsupported_path) == OK, "unsupported fixture saves")
	var unsupported_result := Store.load_draft(unsupported_path)
	_check(
		not unsupported_result["ok"] and unsupported_result["message"].contains("Unsupported"),
		"unsupported schema is rejected explicitly",
	)
	_check(FileAccess.get_sha256(JENNY_PATH) == fixture_hash, "draft workflow does not modify Jenny")
	_check(_temporary_files(output_directory).is_empty(), "atomic saves leave no temporary files")

	_remove_test_directory(output_directory)
	_finish()


func _temporary_files(directory: String) -> Array[String]:
	var result: Array[String] = []
	var access := DirAccess.open(ProjectSettings.globalize_path(directory))
	if access == null:
		return result
	for file_name in access.get_files():
		if file_name.contains(".saving-") or file_name.contains(".backup-"):
			result.append(file_name)
	return result


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _remove_test_directory(directory: String) -> void:
	var absolute := ProjectSettings.globalize_path(directory)
	var access := DirAccess.open(absolute)
	if access == null:
		return
	for file_name in access.get_files():
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: MotionDraft round-trip, provenance, path containment, and artifacts")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
