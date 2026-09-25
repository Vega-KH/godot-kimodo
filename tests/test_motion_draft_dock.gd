extends SceneTree

const Capabilities := preload(
	"res://addons/kimodo_motion/transport/mmcp_capabilities.gd"
)
const CapabilitiesClient := preload(
	"res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd"
)
const GenerationClient := preload(
	"res://addons/kimodo_motion/transport/mmcp_generation_client.gd"
)
const MotionResponse := preload(
	"res://addons/kimodo_motion/transport/mmcp_motion_response.gd"
)
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const JENNY_PATH := "res://tests/characters/fixtures/Jenny03.glb"
const JENNY_SCENE := preload(JENNY_PATH)
const CAPABILITIES_PATH := "res://tests/fixtures/soma77_capabilities.json"
const MOTION_PATH := "res://tests/fixtures/soma77_mmcp_1_0.gltf"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var initial_root_child_count := root.get_child_count()
	var base_directory := "res://tests/.goal13_dock_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()
	]
	var fixture_hash := FileAccess.get_sha256(JENNY_PATH)
	var capability_text := FileAccess.get_file_as_string(CAPABILITIES_PATH)
	var parsed_capabilities := Capabilities.parse_json_text(capability_text)
	_check(parsed_capabilities["ok"], "capability fixture parses")
	var response_bytes := FileAccess.get_file_as_bytes(MOTION_PATH)
	var parsed_motion := MotionResponse.parse(response_bytes, 30, 30.0)
	_check(parsed_motion["ok"], "motion fixture parses")
	if not parsed_capabilities["ok"] or not parsed_motion["ok"]:
		_finish()
		return

	var capability_client := CapabilitiesClient.new()
	var generation_client := GenerationClient.new()
	root.add_child(capability_client)
	root.add_child(generation_client)
	var dock := Dock.new()
	dock.configure(capability_client, generation_client)
	root.add_child(dock)
	await process_frame

	var target_picker := dock.find_child("CharacterTarget", true, false)
	var prompt := dock.find_child("MotionPrompt", true, false) as TextEdit
	_check(_tree_position(dock, target_picker) < _tree_position(dock, prompt), "target appears before prompt")
	dock._on_character_target_changed(JENNY_SCENE)
	_check(dock._character_target == JENNY_SCENE, "Jenny is selected before generation")
	_check(dock._draft.target_scene_path == JENNY_PATH, "open draft owns the selected target")
	var target_signature: String = dock._draft.target_skeleton_signature
	_check(target_signature.length() == 64, "draft records target skeleton signature")

	prompt.text = "A person waves with their right hand."
	(dock.find_child("DurationFrames", true, false) as SpinBox).value = 30
	(dock.find_child("GenerationSeed", true, false) as SpinBox).value = 2468
	(dock.find_child("DiffusionSteps", true, false) as SpinBox).value = 100
	capability_client.capabilities = parsed_capabilities["capabilities"]
	capability_client.last_response_json = capability_text
	capability_client.state = CapabilitiesClient.ConnectionState.READY
	var request_json := '{"prompt":"A person waves with their right hand.","seed":2468}'
	generation_client.last_request_json = request_json
	generation_client.last_response_bytes = response_bytes.duplicate()
	generation_client._latest_motion = parsed_motion["motion"]
	generation_client.state = GenerationClient.GenerationState.READY
	dock._on_motion_ready()
	_check(dock._draft.generation_records.size() == 1, "validated result records provenance")
	var record: Dictionary = dock._draft.active_generation_record()
	_check(record["request_json"] == request_json, "dock preserves exact request JSON")
	_check(record["model_id"] == "kimodo-soma-rp", "dock records returned model identity")
	_check(record["response_sha256"] == FileAccess.get_sha256(MOTION_PATH), "dock records response hash")

	var native_directory := base_directory.path_join("native")
	(dock.find_child("NativeTakeDirectory", true, false) as LineEdit).text = native_directory
	(dock.find_child("NativeTakeName", true, false) as LineEdit).text = "wave"
	(dock.find_child("SaveNativeTake", true, false) as Button).emit_signal("pressed")
	var native_scene := native_directory.path_join("wave.tscn")
	var native_library := native_directory.path_join("wave.res")
	_check(FileAccess.file_exists(native_scene), "native scene saves")
	_check(FileAccess.file_exists(native_library), "native library saves")
	_check(dock._draft.artifacts.has("soma77_scene"), "scene artifact is attached to draft")
	_check(dock._draft.artifacts.has("soma77_library"), "library artifact is attached to draft")

	var immutable_record: Dictionary = dock._draft.active_generation_record()
	prompt.text = "A person sits down."
	var draft_directory := base_directory.path_join("drafts")
	(dock.find_child("MotionDraftDirectory", true, false) as LineEdit).text = draft_directory
	(dock.find_child("MotionDraftName", true, false) as LineEdit).text = "jenny_wave"
	(dock.find_child("SaveAsMotionDraft", true, false) as Button).emit_signal("pressed")
	var draft_path := draft_directory.path_join("jenny_wave.tres")
	_check(FileAccess.file_exists(draft_path), "draft saves through the dock")
	_check(dock._draft.prompt == "A person sits down.", "editable intent updates before save")
	_check(dock._draft.active_generation_record() == immutable_record, "saved intent does not rewrite provenance")

	var saved_draft_id: String = dock._draft.draft_id
	(dock.find_child("NewMotionDraft", true, false) as Button).emit_signal("pressed")
	_check(dock._draft.draft_id != saved_draft_id, "New replaces the active draft identity")
	_check(not dock._preview.has_motion(), "New clears generated source motion")
	_check(
		(dock.find_child("SaveNativeTake", true, false) as Button).disabled,
		"New disables stale native-save actions",
	)
	_check(
		(dock.find_child("NativeTakeStatus", true, false) as Label).text
		== "Generate a validated motion before saving.",
		"New clears stale native-save status",
	)

	dock.queue_free()
	capability_client.queue_free()
	generation_client.queue_free()
	await process_frame

	var offline_capability_client := CapabilitiesClient.new()
	var offline_generation_client := GenerationClient.new()
	root.add_child(offline_capability_client)
	root.add_child(offline_generation_client)
	var reopened := Dock.new()
	reopened.configure(offline_capability_client, offline_generation_client)
	root.add_child(reopened)
	await process_frame
	var draft_picker := reopened.find_child("MotionDraftResource", true, false) as Control
	if draft_picker is EditorResourcePicker:
		(draft_picker as EditorResourcePicker).edited_resource = ResourceLoader.load(
			draft_path, "KimodoMotionDraft", ResourceLoader.CACHE_MODE_IGNORE
		)
	else:
		(draft_picker as LineEdit).text = draft_path
	(reopened.find_child("LoadMotionDraft", true, false) as Button).emit_signal("pressed")
	_check(reopened._draft_path == draft_path, "offline dock loads the saved draft")
	_check(reopened._draft.prompt == "A person sits down.", "offline load restores editable intent")
	_check(reopened._draft.target_scene_path == JENNY_PATH, "offline load restores target path")
	_check(reopened._character_target == JENNY_SCENE, "offline load restores compatible target")
	_check(reopened._draft.target_skeleton_signature == target_signature, "target identity round-trips")
	_check(reopened._draft.generation_records.size() == 1, "offline load restores provenance")
	_check(not reopened._preview.has_motion(), "offline load does not restore transient preview motion")
	_check(
		(reopened.find_child("SaveNativeTake", true, false) as Button).disabled,
		"offline load keeps save actions disabled until generation",
	)
	_check(
		offline_capability_client.state == CapabilitiesClient.ConnectionState.DISCONNECTED,
		"loading a draft does not contact the backend",
	)
	_check(
		offline_generation_client.state == GenerationClient.GenerationState.IDLE,
		"loading a draft does not regenerate",
	)
	var details := reopened.find_child("MotionDraftDetails", true, false) as RichTextLabel
	_check(details.get_parsed_text().contains("kimodo-soma-rp"), "read-only provenance is displayed")
	_check(details.get_parsed_text().contains(native_scene), "artifact link is displayed")
	_check(FileAccess.get_sha256(JENNY_PATH) == fixture_hash, "draft dock never modifies Jenny")

	reopened.queue_free()
	offline_capability_client.queue_free()
	offline_generation_client.queue_free()
	await process_frame
	_remove_tree(base_directory)
	_check(
		root.get_child_count() == initial_root_child_count,
		"draft dock lifecycle leaves no additional nodes behind",
	)
	_finish()


func _tree_position(root_node: Node, wanted: Node) -> int:
	var flattened: Array[Node] = []
	_flatten(root_node, flattened)
	return flattened.find(wanted)


func _flatten(node: Node, output: Array[Node]) -> void:
	output.append(node)
	for child in node.get_children():
		_flatten(child, output)


func _remove_tree(directory: String) -> void:
	var absolute := ProjectSettings.globalize_path(directory)
	_remove_absolute_tree(absolute)


func _remove_absolute_tree(directory: String) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		return
	for child_directory in access.get_directories():
		_remove_absolute_tree(directory.path_join(child_directory))
	for file_name in access.get_files():
		DirAccess.remove_absolute(directory.path_join(file_name))
	DirAccess.remove_absolute(directory)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: target-first draft provenance, artifact save, and offline dock reload")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
