extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Options := preload("res://addons/kimodo_motion/domain/generation_options.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"

var _failures: Array[String] = []


func _init() -> void:
	var parsed_capabilities := Capabilities.parse_json_text(
		FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	)
	_check(parsed_capabilities["ok"], "capability fixture parses")
	var capabilities: RefCounted = parsed_capabilities["capabilities"]
	var options := Options.new()
	options.prompt = "  A person walks forward.  "
	options.duration_frames = 30
	options.seed = 1234
	var request := options.to_mmcp_request(capabilities)
	_check(options.validate(capabilities.fps)["ok"], "typed generation options validate")
	_check(request["protocol_version"] == "1.0", "request pins negotiated MMCP version")
	_check(request["model"] == "kimodo-soma-rp", "request uses negotiated model")
	_check(request["skeleton"]["joints"].size() == 77, "request sends negotiated skeleton")
	_check(request["segments"][0]["prompt"] == "A person walks forward.", "prompt is trimmed")
	_check(request["segments"][0]["duration_frames"] == 30, "duration is encoded")
	_check(request["options"]["seed"] == 1234, "seed is encoded")
	_check(request["options"]["diffusion_steps"] == 100, "quality denoising default is encoded")
	_check(request["options"]["num_samples"] == 1, "initial request asks for one sample")

	options.prompt = "   "
	_check(not options.validate(capabilities.fps)["ok"], "empty prompts are rejected")
	options.prompt = "walk"
	options.duration_frames = 901
	_check(not options.validate(capabilities.fps)["ok"], "overlong duration is rejected")
	options.duration_frames = 30
	options.diffusion_steps = 101
	_check(not options.validate(capabilities.fps)["ok"], "unsupported denoising steps are rejected")

	var motion_result := MotionResponse.parse(
		FileAccess.get_file_as_bytes(MOTION_FIXTURE),
		30,
		capabilities.fps,
		capabilities.skeleton_payload,
	)
	if not motion_result["ok"]:
		printerr("Motion fixture rejection: ", motion_result)
	_check(motion_result["ok"], "recorded SOMA-77 response validates and decodes")
	if motion_result["ok"]:
		var motion: RefCounted = motion_result["motion"]
		_check(motion.source_rotation_channels == 77, "all source rotations are retained")
		_check(motion.source_translation_channels == 1, "one root translation is retained")
		_check(is_equal_approx(motion.duration_seconds, 29.0 / 30.0), "duration matches request")
		motion.scene.free()

	var malformed := MotionResponse.parse(
		"not json".to_utf8_buffer(), 30, 30.0, capabilities.skeleton_payload
	)
	_check(not malformed["ok"] and malformed["code"] == "invalid_gltf", "malformed glTF is rejected")
	var wrong_joint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MOTION_FIXTURE))
	wrong_joint["nodes"][1]["name"] = "NotSpine1"
	var incompatible := MotionResponse.parse(
		JSON.stringify(wrong_joint).to_utf8_buffer(), 30, 30.0, capabilities.skeleton_payload
	)
	_check(
		not incompatible["ok"] and incompatible["code"] == "invalid_motion",
		"non-SOMA-77 responses are rejected",
	)
	var wrong_hierarchy: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(MOTION_FIXTURE)
	)
	wrong_hierarchy["nodes"][0]["children"][0] = 2
	var incompatible_hierarchy := MotionResponse.parse(
		JSON.stringify(wrong_hierarchy).to_utf8_buffer(),
		30,
		30.0,
		capabilities.skeleton_payload,
	)
	_check(
		not incompatible_hierarchy["ok"] and incompatible_hierarchy["code"] == "invalid_motion",
		"responses with a changed SOMA-77 hierarchy are rejected",
	)
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: typed MMCP generation request and SOMA-77 response contract")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
