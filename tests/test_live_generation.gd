extends SceneTree

const CapabilitiesClient := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const JENNY := preload("res://tests/characters/fixtures/Jenny03.glb")

var _session_path := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var url := CapabilitiesClient.DEFAULT_URL
	var output_path := ""
	var native_directory := ""
	var native_name := "goal8_live"
	var humanoid_directory := ""
	var humanoid_name := "goal10_live_humanoid"
	var diffusion_step_count := 100
	var take_count := 2
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
		elif arguments[index] == "--humanoid-dir" and index + 1 < arguments.size():
			humanoid_directory = arguments[index + 1]
		elif arguments[index] == "--humanoid-name" and index + 1 < arguments.size():
			humanoid_name = arguments[index + 1]
		elif arguments[index] == "--steps" and index + 1 < arguments.size():
			diffusion_step_count = int(arguments[index + 1])
		elif arguments[index] == "--takes" and index + 1 < arguments.size():
			take_count = int(arguments[index + 1])

	var capabilities := CapabilitiesClient.new()
	root.add_child(capabilities)
	var generation := GenerationClient.new()
	generation.timeout_seconds = 180.0
	root.add_child(generation)
	var dock := Dock.new()
	dock.configure(capabilities, generation)
	root.add_child(dock)
	await process_frame
	(dock.find_child("NewSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	_session_path = dock._draft_path
	dock._on_character_target_changed(JENNY)

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
	steps.value = diffusion_step_count
	var takes: SpinBox = dock.find_child("TakeCount", true, false)
	takes.value = take_count
	var generate_button: Button = dock.find_child("GenerateAction", true, false)
	var generation_started := Time.get_ticks_msec()
	generate_button.emit_signal("pressed")
	await _wait_until_not(generation, GenerationClient.GenerationState.GENERATING, 190.0)
	if generation.state != GenerationClient.GenerationState.READY:
		_fail("live generation failed: %s %s" % [generation.message, generation.technical_details])
		return

	var preview: Control = dock.find_child("MotionPreview", true, false)
	if not preview.has_motion() or preview.skeleton().get_bone_count() != 77:
		_fail("live result did not reach the dock preview as SOMA-77")
		return
	var take_selector := dock.find_child("TakeSelection", true, false) as OptionButton
	if dock._take_set.size() != take_count or take_selector.item_count != take_count:
		_fail("live response did not expose the requested %d takes" % take_count)
		return
	if take_count > 1:
		var first_hash: String = dock._take_set.at(0).content_sha256
		var second_hash: String = dock._take_set.at(1).content_sha256
		if first_hash == second_hash:
			_fail("live multi-take response returned identical decoded motions")
			return
		take_selector.select(1)
		take_selector.emit_signal("item_selected", 1)
		if dock._take_set.active_index != 1 or not preview.has_motion():
			_fail("live take switching did not preserve a valid preview")
			return
	var retarget_button := dock.find_child("RetargetHumanoid", true, false) as Button
	if retarget_button.disabled:
		_fail("humanoid retarget did not enable after live generation")
		return
	retarget_button.emit_signal("pressed")
	var humanoid: Control = dock.find_child("HumanoidPreview", true, false)
	if not humanoid.has_motion() or humanoid.skeleton().get_bone_count() != 56:
		_fail("live result did not retarget to the 56-bone humanoid preview")
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
	if not humanoid_directory.is_empty():
		var humanoid_dir: LineEdit = dock.find_child("HumanoidTakeDirectory", true, false)
		var humanoid_take_name: LineEdit = dock.find_child("HumanoidTakeName", true, false)
		humanoid_dir.text = humanoid_directory
		humanoid_take_name.text = humanoid_name
		var humanoid_save := dock.find_child("SaveHumanoidTake", true, false) as Button
		if humanoid_save.disabled:
			_fail("humanoid save did not enable after live retarget")
			return
		humanoid_save.emit_signal("pressed")
		var humanoid_scene := humanoid_directory.path_join(humanoid_name + ".tscn")
		var humanoid_library := humanoid_directory.path_join(humanoid_name + ".res")
		if not FileAccess.file_exists(humanoid_scene) or not FileAccess.file_exists(humanoid_library):
			_fail("live humanoid preview did not save native assets")
			return
	print(
		"PASS: live dock generate/retarget/save — prompt=%s steps=%d takes=%d elapsed=%.2fs bytes=%d source_bones=%d humanoid_bones=%d playing=%s"
		% [prompt.text, int(steps.value), take_count, float(Time.get_ticks_msec() - generation_started) / 1000.0, generation.last_response_bytes.size(), preview.skeleton().get_bone_count(), humanoid.skeleton().get_bone_count(), preview.is_playing()]
	)
	dock.queue_free()
	capabilities.queue_free()
	generation.queue_free()
	await process_frame
	_cleanup_session()
	quit(0)


func _wait_until_not(client: Node, busy_state: int, timeout: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while client.state == busy_state and Time.get_ticks_msec() < deadline:
		await process_frame


func _fail(message: String) -> void:
	printerr("FAIL: ", message)
	_cleanup_session()
	quit(1)


func _cleanup_session() -> void:
	if not _session_path.is_empty() and FileAccess.file_exists(_session_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path))
