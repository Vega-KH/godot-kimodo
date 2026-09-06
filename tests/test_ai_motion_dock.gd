extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const FIXTURE := "res://tests/fixtures/soma77_capabilities.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for cycle in 3:
		var client := Client.new()
		root.add_child(client)
		var dock := Dock.new()
		dock.configure(client)
		root.add_child(dock)
		await process_frame

		var status: Label = dock.find_child("ConnectionStatus", true, false)
		var action: Button = dock.find_child("ConnectionAction", true, false)
		var url: LineEdit = dock.find_child("BackendUrl", true, false)
		_check(status.text.contains("Disconnected"), "cycle %d begins disconnected" % cycle)
		_check(action.text == "Connect", "cycle %d offers Connect" % cycle)

		client._set_state(Client.ConnectionState.CONNECTING, "Connecting for test…")
		_check(status.text.contains("Connecting"), "connecting state is visible")
		_check(action.text == "Cancel", "connecting state offers cancellation")
		_check(not url.editable, "URL is stable while connecting")

		var parsed := Capabilities.parse_json_text(FileAccess.get_file_as_string(FIXTURE))
		client.capabilities = parsed["capabilities"]
		client._set_state(Client.ConnectionState.READY, "Connected for test.")
		_check(status.text.contains("Ready"), "ready state is visible")
		_check(action.text == "Refresh", "ready state offers refresh")
		_check(_label_text(dock, "ModelValue") == "kimodo-soma-rp", "model summary is shown")
		_check(_label_text(dock, "FpsValue") == "30 fps", "frame-rate summary is shown")
		_check(_label_text(dock, "JointsValue") == "SOMA-77 (77 joints)", "joint summary is shown")
		_check(_label_text(dock, "ConstraintsValue").begins_with("3 —"), "constraints are shown")
		_check(_label_text(dock, "ContactsValue") == "6 channels", "contacts are shown")

		client.capabilities = null
		client._set_state(Client.ConnectionState.ERROR, "Backend refused the request.", "HTTP status 503")
		var details_button: Button = dock.find_child("TechnicalDetailsToggle", true, false)
		var details: RichTextLabel = dock.find_child("TechnicalDetails", true, false)
		_check(status.text.contains("Error"), "error state is visible")
		_check(details_button.visible, "technical details are available on error")
		details_button.emit_signal("pressed")
		_check(details.visible and details.text == "HTTP status 503", "technical details expand")

		dock.queue_free()
		client.queue_free()
		await process_frame

	_check(root.get_child_count() == 0, "dock/client lifecycle leaves no nodes behind")
	_finish()


func _label_text(dock: Node, node_name: String) -> String:
	var label: Label = dock.find_child(node_name, true, false)
	return label.text


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: AI Motion dock states, typed summary, details, and lifecycle")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
