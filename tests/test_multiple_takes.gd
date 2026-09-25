extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"

var _failures: Array[String] = []


func _init() -> void:
	var capabilities: RefCounted = Capabilities.parse_json_text(
		FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	)["capabilities"]
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var second_animation: Dictionary = document["animations"][0].duplicate(true)
	second_animation["name"] = "sample_1"
	document["animations"].append(second_animation)
	var second_sample: Dictionary = document["extensions"]["MMCP_motion"]["samples"][0].duplicate(true)
	second_sample["name"] = "sample_1"
	document["extensions"]["MMCP_motion"]["samples"].append(second_sample)
	var parsed := MotionResponse.parse(
		JSON.stringify(document).to_utf8_buffer(), 30, 30.0, capabilities.skeleton_payload
	)
	_check(parsed["ok"], "two ordered animations parse")
	if parsed["ok"]:
		var motions: Array = parsed["motions"]
		_check(motions.size() == 2, "parser returns two takes")
		_check(motions[0].animation_name == &"sample_0", "first take keeps sample order")
		_check(motions[1].animation_name == &"sample_1", "second take keeps sample order")
		_check(motions[0].content_sha256.length() == 64, "take has decoded-motion hash")
		for motion in motions:
			motion.scene.free()

	var mismatch: Dictionary = document.duplicate(true)
	mismatch["extensions"]["MMCP_motion"]["samples"][1]["name"] = "wrong"
	var rejected := MotionResponse.parse(
		JSON.stringify(mismatch).to_utf8_buffer(), 30, 30.0, capabilities.skeleton_payload
	)
	_check(not rejected["ok"], "metadata/animation mismatch is rejected")
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: ordered multi-take parsing and metadata correlation")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
