extends SceneTree

const CapabilitiesClient := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var url := CapabilitiesClient.DEFAULT_URL
	var output_path := ""
	var native_directory := ""
	var native_name := "goal8_live"
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		if arguments[index] == "--url" and index + 1 < arguments.size():
			url = arguments[index + 1]
		elif arguments[index] == "--output" and index + 1 < arguments.size():
			output_path = arguments[index + 1]
		elif arguments[index] == "--native-dir" and index + 1 < arguments.size():
			native_directory = arguments[index + 1]
		elif arguments[index] == "--native-name" and index + 1 < arguments.size():
			native_name = arguments[index + 1]

	var capabilities := CapabilitiesClient.new()
	root.add_child(capabilities)
	var generation := GenerationClient.new()
	generation.timeout_seconds = 180.0
	root.add_child(generation)
	var dock := Dock.new()
	dock.configure(capabilities, generation)
	root.add_child(dock)
	await process_frame

	var url_edit: LineEdit = dock.find_child("BackendUrl", true, false)
	url_edit.text = url
	var connect_button: Button = dock.find_child("ConnectionAction", true, false)
	connect_button.emit_signal("pressed")
	await _wait_until_not(capabilities, CapabilitiesClient.ConnectionState.CONNECTING, 30.0)
	if capabilities.state != CapabilitiesClient.ConnectionState.READY:
		_fail("live connection failed: %s %s" % [capabilities.message, capabilities.technical_details])
		return

	var prompt: TextEdit = dock.find_child("MotionPrompt", true, false)
	prompt.text = "A person walks forward."
	var duration: SpinBox = dock.find_child("DurationFrames", true, false)
	duration.value = 30
	var seed: SpinBox = dock.find_child("GenerationSeed", true, false)
	seed.value = 1234
	var steps: SpinBox = dock.find_child("DiffusionSteps", true, false)
	steps.value = 100
	var generate_button: Button = dock.find_child("GenerateAction", true, false)
	generate_button.emit_signal("pressed")
	await _wait_until_not(generation, GenerationClient.GenerationState.GENERATING, 190.0)
	if generation.state != GenerationClient.GenerationState.READY:
		_fail("live generation failed: %s %s" % [generation.message, generation.technical_details])
		return

	var preview: Control = dock.find_child("MotionPreview", true, false)
	if not preview.has_motion() or preview.skeleton().get_bone_count() != 77:
		_fail("live result did not reach the dock preview as SOMA-77")
		return
	if not output_path.is_empty():
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		if output == null:
			_fail("could not write live response to %s" % output_path)
			return
		output.store_buffer(generation.last_response_bytes)
		output.close()
	if not native_directory.is_empty():
		var directory: LineEdit = dock.find_child("NativeTakeDirectory", true, false)
		var take_name: LineEdit = dock.find_child("NativeTakeName", true, false)
		directory.text = native_directory
		take_name.text = native_name
		var save_button: Button = dock.find_child("SaveNativeTake", true, false)
		if save_button.disabled:
			_fail("native save did not enable after live generation")
			return
		save_button.emit_signal("pressed")
		var scene_path := native_directory.path_join(native_name + ".tscn")
		var library_path := native_directory.path_join(native_name + ".res")
		if not FileAccess.file_exists(scene_path) or not FileAccess.file_exists(library_path):
			_fail("live preview did not save native assets")
			return
	print(
		"PASS: live dock generation/save — prompt=%s steps=%d bytes=%d bones=%d playing=%s"
		% [prompt.text, int(steps.value), generation.last_response_bytes.size(), preview.skeleton().get_bone_count(), preview.is_playing()]
	)
	dock.queue_free()
	capabilities.queue_free()
	generation.queue_free()
	await process_frame
	quit(0)


func _wait_until_not(client: Node, busy_state: int, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while client.state == busy_state and Time.get_ticks_msec() < deadline:
		await process_frame


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	quit(1)
