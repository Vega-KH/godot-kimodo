@tool
class_name MmcpGenerationClient
extends Node

signal state_changed(state: int, state_name: String, snapshot: Dictionary)
signal motion_ready

enum GenerationState {
	IDLE,
	GENERATING,
	READY,
	ERROR,
}

const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")

var timeout_seconds := 120.0
var state := GenerationState.IDLE
var message := "No motion generated yet."
var technical_details := ""
var last_request_json := ""
var last_response_bytes := PackedByteArray()

var _attempt := 0
var _active_request: HTTPRequest
var _active_request_id := 0
var _latest_motion: RefCounted


func generate(
	backend_url: String, capabilities: RefCounted, options: RefCounted
) -> void:
	_attempt += 1
	var token := _attempt
	_cancel_active_request()
	if capabilities == null:
		_set_state(GenerationState.ERROR, "Connect to a compatible backend first.")
		return
	var validation: Dictionary = options.validate(capabilities.fps)
	if not validation["ok"]:
		_set_state(GenerationState.ERROR, validation["message"])
		return

	_free_latest_motion()
	var expected_frames: int = options.duration_frames
	var expected_fps: float = capabilities.fps
	var expected_skeleton: Dictionary = capabilities.skeleton_payload.duplicate(true)
	last_request_json = JSON.stringify(options.to_mmcp_request(capabilities))
	last_response_bytes = PackedByteArray()
	_set_state(GenerationState.GENERATING, "Generating motion…")

	var request_node := HTTPRequest.new()
	request_node.timeout = 0.0
	request_node.use_threads = false
	request_node.body_size_limit = 8 * 1024 * 1024
	add_child(request_node)
	_active_request = request_node
	_active_request_id = request_node.get_instance_id()
	request_node.request_completed.connect(
		_on_request_completed.bind(
			token, request_node, expected_frames, expected_fps, expected_skeleton
		)
	)
	var start_error := request_node.request(
		backend_url.trim_suffix("/") + "/generate",
		["Accept: model/gltf+json", "Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		last_request_json,
	)
	if start_error != OK:
		_active_request = null
		_active_request_id = 0
		request_node.queue_free()
		_set_state(
			GenerationState.ERROR,
			"Could not start motion generation.",
			"HTTPRequest.request returned %d" % start_error,
		)
		return
	_arm_timeout(token, request_node)


func cancel_generation() -> void:
	_attempt += 1
	_cancel_active_request()
	if state == GenerationState.GENERATING:
		_set_state(GenerationState.IDLE, "Generation canceled.")


func take_latest_motion() -> RefCounted:
	var motion := _latest_motion
	_latest_motion = null
	return motion


func reset() -> void:
	_attempt += 1
	_cancel_active_request()
	_free_latest_motion()
	last_request_json = ""
	last_response_bytes = PackedByteArray()
	_set_state(GenerationState.IDLE, "No motion generated yet.")


func _exit_tree() -> void:
	_attempt += 1
	_cancel_active_request()
	_free_latest_motion()


func _arm_timeout(token: int, request_node: HTTPRequest) -> void:
	await get_tree().create_timer(maxf(timeout_seconds, 0.001)).timeout
	if token != _attempt or state != GenerationState.GENERATING:
		return
	_active_request = null
	_active_request_id = 0
	if is_instance_valid(request_node):
		request_node.cancel_request()
		request_node.queue_free()
	_set_state(
		GenerationState.ERROR,
		"Motion generation timed out.",
		"Client timeout after %.2f seconds" % timeout_seconds,
	)


func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray,
	token: int,
	request_node: HTTPRequest,
	expected_frames: int,
	expected_fps: float,
	expected_skeleton: Dictionary,
) -> void:
	if (
		token != _attempt
		or state != GenerationState.GENERATING
		or request_node.get_instance_id() != _active_request_id
	):
		if is_instance_valid(request_node):
			request_node.queue_free()
		return
	_active_request = null
	_active_request_id = 0
	request_node.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_state(
			GenerationState.ERROR,
			"The generation request failed.",
			"HTTPRequest result=%d" % result,
		)
		return
	if response_code != 200:
		_set_state(
			GenerationState.ERROR,
			_server_error_message(body, response_code),
			"HTTP status %d" % response_code,
		)
		return
	var content_type := _header_value(headers, "content-type")
	if not content_type.to_lower().begins_with("model/gltf+json"):
		_set_state(
			GenerationState.ERROR,
			"The backend returned an unexpected response format.",
			"Content-Type: %s" % content_type,
		)
		return

	var parsed := MotionResponse.parse(body, expected_frames, expected_fps, expected_skeleton)
	if not parsed["ok"]:
		_set_state(
			GenerationState.ERROR,
			parsed["message"],
			parsed["code"],
		)
		return
	last_response_bytes = body.duplicate()
	_latest_motion = parsed["motion"]
	_set_state(
		GenerationState.READY,
		"Generated %.2f seconds of SOMA-77 motion." % _latest_motion.duration_seconds,
	)
	motion_ready.emit()


func _cancel_active_request() -> void:
	if _active_request == null:
		return
	_active_request.cancel_request()
	_active_request.queue_free()
	_active_request = null
	_active_request_id = 0


func _free_latest_motion() -> void:
	if _latest_motion == null:
		return
	if is_instance_valid(_latest_motion.scene):
		_latest_motion.scene.free()
	_latest_motion = null


func _set_state(next_state: int, next_message: String, details: String = "") -> void:
	state = next_state
	message = next_message
	technical_details = details
	state_changed.emit(state, state_name(), snapshot())


func state_name() -> String:
	return GenerationState.keys()[state].capitalize()


func snapshot() -> Dictionary:
	return {
		"message": message,
		"technical_details": technical_details,
		"has_motion": _latest_motion != null,
	}


static func _header_value(headers: PackedStringArray, wanted_name: String) -> String:
	for header in headers:
		var separator := header.find(":")
		if separator > 0 and header.left(separator).strip_edges().to_lower() == wanted_name:
			return header.substr(separator + 1).strip_edges()
	return ""


static func _server_error_message(body: PackedByteArray, response_code: int) -> String:
	var payload: Variant = JSON.parse_string(body.get_string_from_utf8())
	if payload is Dictionary:
		var error: Variant = payload.get("error")
		if error is Dictionary and error.get("message") is String:
			return error["message"]
		if payload.get("detail") is String:
			return payload["detail"]
		var detail: Variant = payload.get("detail")
		if detail is Array and not detail.is_empty() and detail[0] is Dictionary:
			var validation_message: Variant = detail[0].get("msg")
			if validation_message is String:
				return "The generation request is invalid: %s" % validation_message
	return "The backend rejected motion generation (HTTP %d)." % response_code
