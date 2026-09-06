@tool
class_name MmcpCapabilitiesClient
extends Node

signal state_changed(state: int, state_name: String, snapshot: Dictionary)

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	READY,
	ERROR,
}

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const DEFAULT_URL := "http://127.0.0.1:8000"
const _LOOPBACK_PATTERN := "^http://(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?/?$"

var timeout_seconds := 10.0
var state := ConnectionState.DISCONNECTED
var capabilities: RefCounted
var message := "Backend connection is idle."
var technical_details := ""
var backend_url := DEFAULT_URL

var _attempt := 0
var _active_request: HTTPRequest
var _active_request_id := 0


func connect_to_backend(url: String = DEFAULT_URL) -> void:
	var normalized := url.strip_edges().trim_suffix("/")
	var validation := _validate_loopback_url(normalized)
	if not validation["ok"]:
		_attempt += 1
		_cancel_active_request()
		_set_state(ConnectionState.ERROR, validation["message"], validation["technical"])
		return

	_attempt += 1
	var token := _attempt
	_cancel_active_request()
	backend_url = normalized
	capabilities = null
	_set_state(ConnectionState.CONNECTING, "Connecting to the Kimodo backend…")

	var request_node := HTTPRequest.new()
	# Use a SceneTreeTimer for an explicit floating-point, event-loop-driven
	# deadline with behavior that is independent of HTTP backend granularity.
	request_node.timeout = 0.0
	# HTTPRequest remains frame-asynchronous without a worker thread. The small
	# capability payload does not justify Windows thread-cancellation races.
	request_node.use_threads = false
	add_child(request_node)
	_active_request = request_node
	_active_request_id = request_node.get_instance_id()
	request_node.request_completed.connect(_on_request_completed.bind(token, request_node))
	var start_error := request_node.request(
		backend_url + "/capabilities",
		["Accept: application/json"],
		HTTPClient.METHOD_GET,
	)
	if start_error != OK:
		_active_request = null
		_active_request_id = 0
		request_node.queue_free()
		_set_state(
			ConnectionState.ERROR,
			"Could not start the backend request.",
			"HTTPRequest.request returned %d" % start_error,
		)
		return
	_arm_timeout(token, request_node)


func _arm_timeout(token: int, request_node: HTTPRequest) -> void:
	await get_tree().create_timer(maxf(timeout_seconds, 0.001)).timeout
	if token != _attempt or state != ConnectionState.CONNECTING:
		return
	_active_request = null
	_active_request_id = 0
	if is_instance_valid(request_node):
		request_node.cancel_request()
		request_node.queue_free()
	_set_state(
		ConnectionState.ERROR,
		"The backend connection timed out.",
		"Client timeout after %.2f seconds" % timeout_seconds,
	)


func disconnect_from_backend() -> void:
	_attempt += 1
	_cancel_active_request()
	capabilities = null
	_set_state(ConnectionState.DISCONNECTED, "Backend disconnected.")


func _exit_tree() -> void:
	_attempt += 1
	_cancel_active_request()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	token: int,
	request_node: HTTPRequest,
) -> void:
	if (
		token != _attempt
		or state != ConnectionState.CONNECTING
		or request_node.get_instance_id() != _active_request_id
	):
		if is_instance_valid(request_node):
			request_node.queue_free()
		return
	_active_request = null
	_active_request_id = 0
	request_node.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		var label := "timed out" if result == HTTPRequest.RESULT_TIMEOUT else "failed"
		_set_state(
			ConnectionState.ERROR,
			"The backend connection %s." % label,
			"HTTPRequest result=%d" % result,
		)
		return
	if response_code != 200:
		_set_state(
			ConnectionState.ERROR,
			"The backend rejected the capability request.",
			"HTTP status %d" % response_code,
		)
		return

	var parsed := Capabilities.parse_json_text(body.get_string_from_utf8())
	if not parsed["ok"]:
		_set_state(
			ConnectionState.ERROR,
			parsed["message"],
			"%s: %s" % [parsed["code"], parsed["technical"]],
		)
		return
	capabilities = parsed["capabilities"]
	_set_state(
		ConnectionState.READY,
		"Connected to %s." % capabilities.model_id,
	)


func _cancel_active_request() -> void:
	if _active_request == null:
		return
	_active_request.cancel_request()
	_active_request.queue_free()
	_active_request = null
	_active_request_id = 0


func _set_state(next_state: int, next_message: String, details: String = "") -> void:
	state = next_state
	message = next_message
	technical_details = details
	state_changed.emit(state, state_name(), snapshot())


func state_name() -> String:
	return ConnectionState.keys()[state].capitalize()


func snapshot() -> Dictionary:
	return {
		"backend_url": backend_url,
		"message": message,
		"technical_details": technical_details,
		"capabilities": capabilities,
	}


static func _validate_loopback_url(url: String) -> Dictionary:
	var regex := RegEx.new()
	regex.compile(_LOOPBACK_PATTERN)
	if regex.search(url) == null:
		return {
			"ok": false,
			"message": "Only a local HTTP backend is supported right now.",
			"technical": "Expected http://127.0.0.1[:port] or http://localhost[:port]",
		}
	var authority := url.trim_prefix("http://").trim_suffix("/")
	if authority.contains(":"):
		var port := authority.get_slice(":", 1).to_int()
		if port < 1 or port > 65535:
			return {
				"ok": false,
				"message": "The backend port is invalid.",
				"technical": "Port must be between 1 and 65535.",
			}
	return {"ok": true}
