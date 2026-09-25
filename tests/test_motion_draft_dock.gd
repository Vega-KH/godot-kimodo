extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const JENNY := preload("res://tests/characters/fixtures/Jenny03.glb")
const JENNY_PATH := "res://tests/characters/fixtures/Jenny03.glb"
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"

var _failures: Array[String] = []
var _cleanup_paths: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture_hash := FileAccess.get_sha256(JENNY_PATH)
	var client := Client.new()
	root.add_child(client)
	var generation := GenerationClient.new()
	root.add_child(generation)
	var dock := Dock.new()
	dock.configure(client, generation)
	root.add_child(dock)
	await process_frame

	var landing := dock.find_child("SessionLanding", true, false) as Control
	var generate := dock.find_child("GenerateAction", true, false) as Button
	_check(landing.visible, "dock starts at session chooser")
	_check(not generate.is_visible_in_tree(), "generation UI is hidden before opening a session")
	(dock.find_child("NewSessionTitle", true, false) as LineEdit).text = "Goal 14 dock test"
	(dock.find_child("NewSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	_cleanup_paths.append(dock._draft_path)
	_check(dock._draft != null and dock._draft.title == "Goal 14 dock test", "new session is active")
	_check(FileAccess.file_exists(dock._draft_path), "new session is immediately durable")
	_check(not landing.visible and generate.is_visible_in_tree(), "workspace replaces the chooser")

	dock._on_character_target_changed(JENNY)
	var target_signature: String = dock._draft.target_skeleton_signature
	_check(target_signature.length() == 64, "session records the selected target")
	var prompt := dock.find_child("MotionPrompt", true, false) as TextEdit
	prompt.text = "Two versions of a friendly wave."
	var take_count := dock.find_child("TakeCount", true, false) as SpinBox
	take_count.value = 2
	dock._flush_session()

	var parsed_capabilities := Capabilities.parse_json_text(
		FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	)
	client.capabilities = parsed_capabilities["capabilities"]
	client.last_response_json = FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	client._set_state(Client.ConnectionState.READY, "Connected for test.")
	var response_bytes := _two_take_response()
	var parsed := MotionResponse.parse(
		response_bytes, 30, 30.0, client.capabilities.skeleton_payload
	)
	_check(parsed["ok"], "two-take fixture parses for dock coverage")
	generation.last_request_json = JSON.stringify({"options": {"num_samples": 2, "seed": 1234}})
	generation.last_response_bytes = response_bytes
	generation._latest_motions.assign(parsed["motions"])
	dock._on_motion_ready()
	_check(dock._take_set.size() == 2, "dock retains two transient takes")
	_check(dock._draft.generation_records.size() == 1, "session records generation provenance")
	_check(dock._draft.active_generation_record()["request_seed"] == 1234, "take batch shares the request seed")
	var summaries: Array = dock._draft.active_take_summaries()
	_check(summaries.size() == 2, "session persists two take summaries")
	_check(summaries[0]["payload_status"] == "transient", "take payload is not claimed durable")
	var selector := dock.find_child("TakeSelection", true, false) as OptionButton
	_check(selector.visible and selector.item_count == 2, "take selector exposes both takes")
	var preview: Control = dock.find_child("MotionPreview", true, false)
	var character_preview: Control = dock.find_child("CharacterPreview", true, false)
	_check(character_preview.has_motion() and character_preview.visible, "generated take previews on the session character")
	dock._on_camera_view_changed(0.25, 0.15, 4.0)
	var expected_view: Dictionary = preview.camera_view()
	(dock.find_child("FollowRoot", true, false) as CheckButton).button_pressed = false
	dock._on_follow_root_toggled(false)
	(dock.find_child("LoopMotion", true, false) as CheckButton).button_pressed = false
	dock._on_loop_toggled(false)
	dock._seek_previews(0.4)
	selector.select(1)
	selector.emit_signal("item_selected", 1)
	_check(dock._take_set.active_index == 1, "second take becomes active")
	_check(absf(preview.current_position() - 0.4) < 0.001, "take switch preserves playback time")
	_check(character_preview.has_motion() and character_preview.visible, "take switch rebuilds selected-character preview")
	_check(character_preview.camera_view() == expected_view, "take switch preserves camera state")
	_check(not character_preview.camera_follows_root(), "take switch preserves root-follow state")
	_check(character_preview.animation_player().get_animation("motion").loop_mode == Animation.LOOP_NONE, "take switch preserves loop state")
	_check(dock._draft.selected_take_id == summaries[1]["take_id"], "selected take metadata updates")
	_check(FileAccess.get_sha256(JENNY_PATH) == fixture_hash, "session generation never mutates Jenny")
	var output_directory := "res://tests/.goal14_selected_take_%d" % OS.get_process_id()
	(dock.find_child("NativeTakeDirectory", true, false) as LineEdit).text = output_directory
	(dock.find_child("NativeTakeName", true, false) as LineEdit).text = "selected_take"
	(dock.find_child("SaveNativeTake", true, false) as Button).emit_signal("pressed")
	var saved_scene := output_directory.path_join("selected_take.tscn")
	var saved_library := output_directory.path_join("selected_take.res")
	_cleanup_paths.append(saved_scene)
	_cleanup_paths.append(saved_library)
	_check(FileAccess.file_exists(saved_scene) and FileAccess.file_exists(saved_library), "selected take saves explicitly")
	for artifact in dock._draft.artifacts.values():
		_check(artifact["take_id"] == summaries[1]["take_id"], "saved artifacts belong only to the selected take")

	var session_path: String = dock._draft_path
	(dock.find_child("SwitchSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	_check(landing.visible and dock._draft == null, "switch returns to session chooser")
	_check(dock._take_set.is_empty(), "unsaved take payloads are discarded on close")
	_check(generation.last_request_json.is_empty(), "session switch discards transient request text")
	_check(generation.last_response_bytes.is_empty(), "session switch discards transient response bytes")
	_check((dock.find_child("RecentSessions", true, false) as OptionButton).item_count >= 1, "saved session appears in recent sessions")

	var picker := dock.find_child("SessionResource", true, false) as Control
	if picker is EditorResourcePicker:
		(picker as EditorResourcePicker).edited_resource = ResourceLoader.load(
			session_path, "KimodoSession", ResourceLoader.CACHE_MODE_IGNORE
		)
	else:
		(picker as LineEdit).text = session_path
	(dock.find_child("OpenSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	_check(dock._draft != null and dock._draft.prompt == prompt.text, "offline reopen restores intent")
	_check(dock._draft.active_take_summaries().size() == 2, "offline reopen restores summaries")
	_check(dock._draft.artifacts.size() == 2, "offline reopen restores saved selected-take artifacts")
	_check(dock._take_set.is_empty(), "offline reopen does not invent transient payloads")
	_check((dock.find_child("SaveNativeTake", true, false) as Button).disabled, "save requires a live take")
	_check(FileAccess.get_sha256(JENNY_PATH) == fixture_hash, "offline reopen leaves Jenny unchanged")

	dock.queue_free()
	client.queue_free()
	generation.queue_free()
	await process_frame
	_cleanup()
	_check(root.get_child_count() == 0, "session dock lifecycle leaves no nodes")
	_finish()


func _two_take_response() -> PackedByteArray:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOTION_FIXTURE))
	var animation: Dictionary = document["animations"][0].duplicate(true)
	animation["name"] = "sample_1"
	document["animations"].append(animation)
	var sample: Dictionary = document["extensions"]["MMCP_motion"]["samples"][0].duplicate(true)
	sample["name"] = "sample_1"
	document["extensions"]["MMCP_motion"]["samples"].append(sample)
	return JSON.stringify(document).to_utf8_buffer()


func _cleanup() -> void:
	for path in _cleanup_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var output_directory := "res://tests/.goal14_selected_take_%d" % OS.get_process_id()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(output_directory))


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: session-first dock, transient takes, switching, and offline reopen")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
