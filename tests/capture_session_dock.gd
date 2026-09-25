extends SceneTree

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const JENNY := preload("res://tests/characters/fixtures/Jenny03.glb")


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


func _argument_value(flag: String) -> String:
	var arguments := OS.get_cmdline_user_args()
	var index := arguments.find(flag)
	return arguments[index + 1] if index >= 0 and index + 1 < arguments.size() else ""
