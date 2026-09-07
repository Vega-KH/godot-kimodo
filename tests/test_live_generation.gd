extends SceneTree

const CapabilitiesClient := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var url := CapabilitiesClient.DEFAULT_URL
	var output_path := ""
	var arguments := OS.get_cmdline_user_args()
	for index in arguments.size():
		if arguments[index] == "--url" and index + 1 < arguments.size():
			url = arguments[index + 1]
		elif arguments[index] == "--output" and index + 1 < arguments.size():
			output_path = arguments[index + 1]

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
	print(
		"PASS: live dock generation — prompt=%s bytes=%d bones=%d playing=%s"
		% [prompt.text, generation.last_response_bytes.size(), preview.skeleton().get_bone_count(), preview.is_playing()]
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
