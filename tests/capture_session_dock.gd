extends SceneTree

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const JENNY := preload("res://tests/characters/fixtures/Jenny03.glb")
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"


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
	var parsed := MotionResponse.parse(_two_take_response(), 30, 30.0)
	if not parsed["ok"]:
		printerr("Could not build preview capture: %s" % parsed["message"])
		quit(1)
		return
	dock._preview_panel.replace_takes(parsed["motions"])
	if not dock._preview_current_take_on_character():
		printerr("Could not build character preview capture.")
		quit(1)
		return
	var take_selector := dock.find_child("TakeSelection", true, false) as OptionButton
	take_selector.select(1)
	take_selector.emit_signal("item_selected", 1)
	(dock.find_child("SessionWorkspace", true, false) as TabContainer).current_tab = 1
	await _settle()
	_capture(output_directory.path_join("session_preview_save.png"))
	var session_path: String = dock._draft_path
	dock.queue_free()
	client.queue_free()
	generation.queue_free()
	await process_frame
	if FileAccess.file_exists(session_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))
	quit(0)


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
