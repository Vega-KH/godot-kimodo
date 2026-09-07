class_name MmcpCapabilities
extends RefCounted

const Contract := preload("res://addons/kimodo_motion/domain/soma77_contract.gd")

class ModelCapabilities extends RefCounted:
	var protocol_version: String
	var model_id: String
	var fps: float
	var joint_names: Array[String]
	var skeleton_payload: Dictionary
	var constraint_types: Array[String]
	var contact_joints: Array[String]
	var response_formats: Array[String]


static func parse_json_text(text: String) -> Dictionary:
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		return _error(
			"malformed_json",
			"The backend returned malformed JSON.",
			"Line %d: %s" % [parser.get_error_line(), parser.get_error_message()],
		)
	return parse_payload(parser.data)


static func parse_payload(payload: Variant) -> Dictionary:
	if not payload is Dictionary:
		return _error("invalid_capabilities", "Capabilities must be a JSON object.")
	var document: Dictionary = payload
	if document.get("protocol_version") != "1.0":
		return _error(
			"unsupported_protocol",
			"This plugin requires MMCP 1.0.",
			"Received protocol_version=%s" % document.get("protocol_version", "<missing>"),
		)
	if document.get("rotation_format") != "quaternion_xyzw":
		return _error("unsupported_rotation", "Expected quaternion_xyzw rotations.")
	if document.get("coordinate_system") != "right_handed_y_up":
		return _error("unsupported_coordinates", "Expected a right-handed Y-up skeleton.")
	if document.get("units") != "meters":
		return _error("unsupported_units", "Expected motion units in meters.")

	var formats_result := _string_array(document.get("response_formats"), "response_formats")
	if not formats_result["ok"]:
		return formats_result
	var formats: Array[String] = formats_result["value"]
	if not formats.has("gltf_2.0_json"):
		return _error("unsupported_format", "The backend does not provide glTF 2.0 JSON.")

	var models: Variant = document.get("models")
	if not models is Array or models.is_empty():
		return _error("invalid_capabilities", "Capabilities contain no models.")
	var model: Variant = models[0]
	if not model is Dictionary:
		return _error("invalid_capabilities", "The first model entry is invalid.")
	if not model.get("id") is String or String(model["id"]).is_empty():
		return _error("invalid_capabilities", "The model id is missing.")
	if not model.get("fps") is float and not model.get("fps") is int:
		return _error("invalid_capabilities", "The model fps is missing or invalid.")
	if not is_equal_approx(float(model["fps"]), 30.0):
		return _error("unsupported_fps", "The initial plugin requires a 30 fps model.")

	var skeleton: Variant = model.get("canonical_skeleton")
	if not skeleton is Dictionary:
		return _error("invalid_skeleton", "The model has no canonical skeleton.")
	var skeleton_result := _validate_soma77(skeleton)
	if not skeleton_result["ok"]:
		return skeleton_result

	var constraints_result := _string_array(
		model.get("supported_constraints"), "supported_constraints"
	)
	if not constraints_result["ok"]:
		return constraints_result
	var constraints: Array[String] = constraints_result["value"]
	for required in Contract.CONSTRAINT_TYPES:
		if not constraints.has(required):
			return _error(
				"unsupported_model",
				"The backend is missing required constraint support.",
				"Missing constraint type: %s" % required,
			)

	var contacts_result := _string_array(
		model.get("predicted_contact_joints"), "predicted_contact_joints"
	)
	if not contacts_result["ok"]:
		return contacts_result
	var contacts: Array[String] = contacts_result["value"]
	if contacts != Contract.CONTACT_JOINTS:
		return _error(
			"unsupported_model",
			"The backend contact layout is not the expected SOMA-77 layout.",
			"Received: %s" % contacts,
		)

	var capabilities := ModelCapabilities.new()
	capabilities.protocol_version = document["protocol_version"]
	capabilities.model_id = model["id"]
	capabilities.fps = float(model["fps"])
	capabilities.joint_names = skeleton_result["joint_names"]
	capabilities.skeleton_payload = skeleton.duplicate(true)
	capabilities.constraint_types = constraints
	capabilities.contact_joints = contacts
	capabilities.response_formats = formats
	return {"ok": true, "capabilities": capabilities}


static func _validate_soma77(skeleton: Dictionary) -> Dictionary:
	var joints: Variant = skeleton.get("joints")
	if not joints is Array:
		return _error("invalid_skeleton", "Canonical skeleton joints are missing.")
	var names: Array[String] = []
	var seen: Dictionary = {}
	var root_count := 0
	for index in joints.size():
		var joint: Variant = joints[index]
		if not joint is Dictionary or not joint.get("name") is String:
			return _error("invalid_skeleton", "Joint %d is malformed." % index)
		var name: String = joint["name"]
		if seen.has(name):
			return _error("invalid_skeleton", "Canonical skeleton has duplicate joints.", name)
		var parent: Variant = joint.get("parent")
		if parent == null:
			root_count += 1
		elif not parent is String or not seen.has(parent):
			return _error(
				"invalid_skeleton",
				"Canonical skeleton hierarchy is invalid.",
				"Joint %s appears before or without parent %s" % [name, parent],
			)
		seen[name] = true
		names.append(name)
		var rest_translation := _number_array(joint.get("rest_translation"), 3)
		var rest_rotation := _number_array(joint.get("rest_rotation"), 4)
		if not rest_translation or not rest_rotation:
			return _error(
				"invalid_skeleton",
				"Canonical skeleton rest transforms are invalid.",
				"Joint %s must contain finite translation[3] and rotation[4]." % name,
			)
	if root_count != 1:
		return _error("invalid_skeleton", "Canonical skeleton must have exactly one root.")
	if names != Contract.JOINT_NAMES:
		return _error(
			"unsupported_model",
			"The backend canonical skeleton is not SOMA-77.",
			"Received %d joints in a different order." % names.size(),
		)
	return {"ok": true, "joint_names": names}


static func _number_array(value: Variant, expected_size: int) -> bool:
	if not value is Array or value.size() != expected_size:
		return false
	for item in value:
		if (not item is float and not item is int) or not is_finite(float(item)):
			return false
	return true


static func _string_array(value: Variant, field_name: String) -> Dictionary:
	if not value is Array:
		return _error("invalid_capabilities", "%s must be an array." % field_name)
	var strings: Array[String] = []
	for item in value:
		if not item is String:
			return _error("invalid_capabilities", "%s must contain strings." % field_name)
		strings.append(item)
	return {"ok": true, "value": strings}


static func _error(code: String, message: String, technical: String = "") -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
		"technical": technical,
	}
