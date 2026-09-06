extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const FIXTURE := "res://tests/fixtures/soma77_capabilities.json"
const FIXTURE_SHA256 := "b4f3b573fb9d926c65a76da08f0adaaf3f4c016f79ecbbe2507c040b50c6b219"

var _failures: Array[String] = []


func _init() -> void:
	var text := FileAccess.get_file_as_string(FIXTURE)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(FileAccess.get_file_as_bytes(FIXTURE))
	_check(hashing.finish().hex_encode() == FIXTURE_SHA256, "capability fixture provenance hash")
	var result := Capabilities.parse_json_text(text)
	_check(result["ok"], "recorded capability fixture parses")
	if result["ok"]:
		var model: RefCounted = result["capabilities"]
		_check(model.protocol_version == "1.0", "protocol is MMCP 1.0")
		_check(model.model_id == "kimodo-soma-rp", "model id is typed")
		_check(model.fps == 30.0, "fps is typed")
		_check(model.joint_names.size() == 77, "SOMA-77 joints are typed")
		_check(model.constraint_types.size() == 3, "constraint types are typed")
		_check(model.contact_joints.size() == 6, "contact channels are typed")
		_check(model.response_formats == ["gltf_2.0_json"], "response format is typed")

	_check(
		Capabilities.parse_json_text("{definitely broken")["code"] == "malformed_json",
		"malformed JSON is classified",
	)
	var payload: Dictionary = JSON.parse_string(text)
	var future := payload.duplicate(true)
	future["protocol_version"] = "99.0"
	_check(
		Capabilities.parse_payload(future)["code"] == "unsupported_protocol",
		"future MMCP versions are rejected",
	)
	var wrong_skeleton := payload.duplicate(true)
	wrong_skeleton["models"][0]["canonical_skeleton"]["joints"].pop_back()
	_check(
		Capabilities.parse_payload(wrong_skeleton)["code"] == "unsupported_model",
		"non-SOMA-77 skeletons are rejected",
	)
	var missing_constraint := payload.duplicate(true)
	missing_constraint["models"][0]["supported_constraints"] = ["root_path"]
	_check(
		Capabilities.parse_payload(missing_constraint)["code"] == "unsupported_model",
		"missing constraint support is rejected",
	)

	_check(Client._validate_loopback_url("http://127.0.0.1:8000")["ok"], "IPv4 loopback URL")
	_check(Client._validate_loopback_url("http://localhost")["ok"], "localhost URL")
	_check(not Client._validate_loopback_url("https://127.0.0.1")["ok"], "HTTPS is not implied")
	_check(not Client._validate_loopback_url("http://127.0.0.1.example")["ok"], "lookalike host")
	_check(not Client._validate_loopback_url("http://192.168.1.2:8000")["ok"], "LAN URL")
	_check(not Client._validate_loopback_url("http://127.0.0.1:70000")["ok"], "invalid port")
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: typed MMCP capability and loopback URL validation")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
