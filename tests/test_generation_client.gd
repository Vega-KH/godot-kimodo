extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Options := preload("res://addons/kimodo_motion/domain/generation_options.gd")
const Preview := preload("res://addons/kimodo_motion/ui/soma77_preview.gd")
const FixtureServer := preload("res://tests/support/local_http_fixture_server.gd")
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const TEST_URL := "http://127.0.0.1:18767"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var capabilities_result := Capabilities.parse_json_text(
		FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	)
	var capabilities: RefCounted = capabilities_result["capabilities"]
	var options := Options.new()
	var fixture := FileAccess.get_file_as_string(MOTION_FIXTURE)
	var server := FixtureServer.new()
	root.add_child(server)
	_check(server.start(18767) == OK, "generation fixture server starts")
	var client := GenerationClient.new()
	root.add_child(client)
	var preview := Preview.new()
	root.add_child(preview)
	await process_frame

	server.enqueue_json(fixture, 0.0, 200, "model/gltf+json")
	client.generate(TEST_URL, capabilities, options)
	await _wait_for_state(client, GenerationClient.GenerationState.READY)
	_check(client.state == GenerationClient.GenerationState.READY, "valid response reaches Ready")
	var encoded: Dictionary = JSON.parse_string(client.last_request_json)
	_check(encoded["segments"][0]["prompt"] == options.prompt, "transport sends typed prompt")
	_check(encoded["skeleton"]["joints"].size() == 77, "transport sends negotiated skeleton")
	var first_motion: RefCounted = client.take_latest_motion()
	_check(preview.set_motion(first_motion), "preview accepts generated motion")
	_check(preview.skeleton().get_bone_count() == 77, "preview owns a SOMA-77 skeleton")
	_check(preview.is_playing(), "preview starts playing")
	preview.set_playing(false)
	_check(not preview.is_playing(), "preview pauses")
	preview.set_looping(false)
	_check(
		preview.animation_player().get_animation(preview.animation_player().get_animation_list()[0]).loop_mode
		== Animation.LOOP_NONE,
		"preview loop control updates the animation",
	)
	var first_scene := preview.motion_scene()

	server.enqueue_json(fixture, 0.0, 200, "model/gltf+json; charset=utf-8")
	client.generate(TEST_URL, capabilities, options)
	await _wait_for_state(client, GenerationClient.GenerationState.READY)
	var replacement: RefCounted = client.take_latest_motion()
	_check(preview.set_motion(replacement), "preview accepts replacement motion")
	_check(not is_instance_valid(first_scene), "replacement frees the previous preview")

	var stale_request := HTTPRequest.new()
	root.add_child(stale_request)
	client._on_request_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(["Content-Type: model/gltf+json"]),
		"invalid".to_utf8_buffer(),
		client._attempt - 1,
		stale_request,
		30,
		30.0,
		capabilities.skeleton_payload,
	)
	await process_frame
	_check(client.state == GenerationClient.GenerationState.READY, "stale response cannot replace Ready")

	server.enqueue_json('{"error":{"message":"Prompt rejected for test."}}', 0.0, 400)
	client.generate(TEST_URL, capabilities, options)
	await _wait_for_state(client, GenerationClient.GenerationState.ERROR)
	_check(client.message == "Prompt rejected for test.", "server errors are artist-readable")

	server.enqueue_json("not glTF", 0.0, 200, "model/gltf+json")
	client.generate(TEST_URL, capabilities, options)
	await _wait_for_state(client, GenerationClient.GenerationState.ERROR)
	_check(client.technical_details == "invalid_gltf", "invalid glTF is classified")

	server.enqueue_json(fixture, 0.3, 200, "model/gltf+json")
	var cancel_count: int = server.request_count
	client.generate(TEST_URL, capabilities, options)
	await _wait_for_request_count(server, cancel_count + 1)
	client.cancel_generation()
	await _wait_seconds(0.35)
	_check(client.state == GenerationClient.GenerationState.IDLE, "canceled request stays idle")

	client.timeout_seconds = 0.2
	server.enqueue_json(fixture, 0.4, 200, "model/gltf+json")
	client.generate(TEST_URL, capabilities, options)
	await _wait_for_state(client, GenerationClient.GenerationState.ERROR, 1.0)
	_check(client.message.contains("timed out"), "slow generation reaches bounded timeout")

	preview.queue_free()
	client.queue_free()
	server.queue_free()
	await process_frame
	_check(root.get_child_count() == 0, "generation and preview lifecycle leaves no nodes")
	_finish()


func _wait_for_state(client: Node, expected: int, timeout := 3.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while client.state != expected and Time.get_ticks_msec() < deadline:
		await process_frame


func _wait_for_request_count(server: Node, expected: int, timeout := 1.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while server.request_count < expected and Time.get_ticks_msec() < deadline:
		await process_frame


func _wait_seconds(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: async generation, errors, cancellation, staleness, and preview lifecycle")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
