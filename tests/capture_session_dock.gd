extends SceneTree

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Archive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const JENNY := preload("res://tests/characters/fixtures/Jenny03.glb")
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_directory := _argument_value("--capture-dir")
	if output_directory.is_empty():
		printerr("Pass --capture-dir <absolute directory>.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output_directory)
	root.size = Vector2i(480, 1000)
	var client := Client.new()
	root.add_child(client)
	var generation := GenerationClient.new()
	root.add_child(generation)
	var dock := Dock.new()
	dock.configure(client, generation)
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle()
	_capture(output_directory.path_join("session_landing.png"))
	(dock.find_child("NewSessionTitle", true, false) as LineEdit).text = "Jenny wave studies"
	(dock.find_child("NewSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	dock._on_character_target_changed(JENNY)
	await _settle()
	_capture(output_directory.path_join("session_generate.png"))
	var session_data_path := Archive.DATA_ROOT.path_join(dock._draft.session_id)
	if not _archive_fixture(dock, client, generation, "Two versions of a friendly wave"):
		quit(1)
		return
	if not _archive_fixture(dock, client, generation, "A celebratory fist pump"):
		quit(1)
		return
	var take_selector := dock.find_child("TakeSelection", true, false) as OptionButton
	take_selector.select(1)
	take_selector.emit_signal("item_selected", 1)
	dock._preview_panel.set_accept_destination("res://animations/jenny_motion_library.res")
	dock._preview_panel.accept_name.text = "friendly_wave"
	(dock.find_child("SessionWorkspace", true, false) as TabContainer).current_tab = 1
	await create_timer(0.6).timeout
	await _settle()
	_capture(output_directory.path_join("session_preview_save.png"))
	(dock.find_child("SessionWorkspace", true, false) as TabContainer).current_tab = 2
	await _settle()
	_capture(output_directory.path_join("session_history.png"))
	var session_path: String = dock._draft_path
	dock.queue_free()
	client.queue_free()
	generation.queue_free()
	await process_frame
	if FileAccess.file_exists(session_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))
	_remove_tree(session_data_path)
	quit(0)


func _archive_fixture(dock: Control, client: Node, generation: Node, prompt: String) -> bool:
	var before_count: int = dock._draft.generation_records.size()
	var capabilities_json := FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	var capability_result := Capabilities.parse_json_text(capabilities_json)
	client.capabilities = capability_result["capabilities"]
	client.last_response_json = capabilities_json
	var response_bytes := _two_take_response()
	var parsed := MotionResponse.parse(
		response_bytes, 30, 30.0, client.capabilities.skeleton_payload
	)
	if not parsed["ok"]:
		printerr("Could not build history capture: %s" % parsed["message"])
		return false
	(dock.find_child("MotionPrompt", true, false) as TextEdit).text = prompt
	generation.last_request_json = JSON.stringify({
		"options": {"num_samples": 2, "seed": 1234},
	})
	generation.last_response_bytes = response_bytes
	generation._latest_motions.assign(parsed["motions"])
	dock._on_motion_ready()
	return dock._draft.generation_records.size() == before_count + 1


func _settle() -> void:
	for _frame in 4:
		await process_frame


func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	if image.save_png(path) != OK:
		push_error("Could not save UI capture: %s" % path)


func _two_take_response() -> PackedByteArray:
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOTION_FIXTURE))
	var animation: Dictionary = document["animations"][0].duplicate(true)
	animation["name"] = "sample_1"
	document["animations"].append(animation)
	var sample: Dictionary = document["extensions"]["MMCP_motion"]["samples"][0].duplicate(true)
	sample["name"] = "sample_1"
	document["extensions"]["MMCP_motion"]["samples"].append(sample)
	return JSON.stringify(document).to_utf8_buffer()


func _argument_value(flag: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	var index := arguments.find(flag)
	return arguments[index + 1] if index >= 0 and index + 1 < arguments.size() else ""


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
