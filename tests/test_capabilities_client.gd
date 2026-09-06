extends SceneTree

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const FixtureServer := preload("res://tests/support/local_http_fixture_server.gd")
const FIXTURE := "res://tests/fixtures/soma77_capabilities.json"
const TEST_URL := "http://127.0.0.1:18766"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("transport test: starting")
	var fixture := FileAccess.get_file_as_string(FIXTURE)
	var server := FixtureServer.new()
	root.add_child(server)
	_check(server.start() == OK, "local HTTP fixture server starts")
	var client := Client.new()
	root.add_child(client)

	server.enqueue_json(fixture)
	client.connect_to_backend(TEST_URL)
	await _wait_for_state(client, Client.ConnectionState.READY)
	print("transport test: valid response state=", client.state)
	_check(client.state == Client.ConnectionState.READY, "valid HTTP response reaches Ready")
	_check(client.capabilities.model_id == "kimodo-soma-rp", "HTTP result is typed")
	var stale_request := HTTPRequest.new()
	root.add_child(stale_request)
	client._on_request_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		"{stale".to_utf8_buffer(),
		client._attempt - 1,
		stale_request,
	)
	await process_frame
	_check(client.state == Client.ConnectionState.READY, "stale response cannot replace Ready")
	_check(client.capabilities.model_id == "kimodo-soma-rp", "newest response wins")

	server.enqueue_json("{broken")
	client.connect_to_backend(TEST_URL)
	await _wait_for_state(client, Client.ConnectionState.ERROR)
	print("transport test: malformed response state=", client.state)
	_check(client.technical_details.begins_with("malformed_json"), "malformed response reaches Error")

	server.enqueue_json(fixture, 0.3)
	var cancellation_request_count: int = server.request_count
	client.connect_to_backend(TEST_URL)
	await _wait_for_request_count(server, cancellation_request_count + 1)
	client.disconnect_from_backend()
	await _wait_seconds(0.35)
	print("transport test: cancellation state=", client.state)
	_check(client.state == Client.ConnectionState.DISCONNECTED, "cancel remains Disconnected")

	client.timeout_seconds = 1.0
	server.enqueue_json(fixture, 1.5)
	client.connect_to_backend(TEST_URL)
	await _wait_for_state(client, Client.ConnectionState.ERROR, 2.0)
	print("transport test: timeout state=", client.state)
	_check(client.state == Client.ConnectionState.ERROR, "timeout reaches Error")
	_check(client.message.contains("timed out"), "timeout has an artist-readable message")

	client.timeout_seconds = 0.2
	server.stop()
	client.connect_to_backend(TEST_URL)
	await _wait_for_state(client, Client.ConnectionState.ERROR, 1.0)
	print("transport test: refusal state=", client.state)
	_check(client.state == Client.ConnectionState.ERROR, "connection refusal reaches Error")

	client.disconnect_from_backend()
	client.queue_free()
	server.queue_free()
	await process_frame
	_finish()


func _wait_for_state(client: Node, expected: int, timeout: float = 2.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while client.state != expected and Time.get_ticks_msec() < deadline:
		await process_frame


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _wait_for_request_count(server: Node, expected: int, timeout: float = 1.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while server.request_count < expected and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: async MMCP transport success, errors, cancellation, timeout, and staleness")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
