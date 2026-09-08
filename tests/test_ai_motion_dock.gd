extends SceneTree

const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const FIXTURE := "res://tests/fixtures/soma77_capabilities.json"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for cycle in 3:
		var client := Client.new()
		root.add_child(client)
		var generation := GenerationClient.new()
		root.add_child(generation)
		var dock := Dock.new()
		dock.configure(client, generation)
		root.add_child(dock)
		await process_frame
		dock.size = Vector2(330.0, 400.0)
		await process_frame

		var scroll: ScrollContainer = dock.find_child("DockScroll", true, false)
		var status: Label = dock.find_child("ConnectionStatus", true, false)
		var action: Button = dock.find_child("ConnectionAction", true, false)
		var url: LineEdit = dock.find_child("BackendUrl", true, false)
		var generate_action: Button = dock.find_child("GenerateAction", true, false)
		var prompt: TextEdit = dock.find_child("MotionPrompt", true, false)
		var diffusion_steps: SpinBox = dock.find_child("DiffusionSteps", true, false)
		var save_action: Button = dock.find_child("SaveNativeTake", true, false)
		_check(status.text.contains("Disconnected"), "cycle %d begins disconnected" % cycle)
		_check(scroll != null, "dock content is wrapped in a scroll container")
		_check(
			scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
			"vertical scrolling is automatic",
		)
		_check(
			scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"horizontal scrolling stays disabled",
		)
		_check(scroll.get_v_scroll_bar().visible, "vertical scrollbar appears in a short dock")
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await process_frame
		_check(scroll.scroll_vertical > 0, "dock can scroll to controls below the viewport")
		_check(action.text == "Connect", "cycle %d offers Connect" % cycle)
		_check(generate_action.disabled, "generation is disabled while disconnected")
		_check(diffusion_steps.value == 100, "denoising control starts at the quality default")
		_check(save_action.disabled, "native save is disabled without a validated preview")

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
		_check(not generate_action.disabled, "generation is enabled when Ready")

		generation._set_state(GenerationClient.GenerationState.GENERATING, "Generating for test…")
		_check(generate_action.text == "Cancel Generation", "generation can be canceled")
		_check(not prompt.editable, "generation inputs are stable in flight")
		_check(not diffusion_steps.editable, "denoising steps are stable in flight")
		_check(action.disabled, "connection cannot be refreshed during generation")
		generation._set_state(
			GenerationClient.GenerationState.ERROR,
			"Generation failed for test.",
			"HTTP status 500",
		)
		var generation_details_button: Button = dock.find_child(
			"GenerationDetailsToggle", true, false
		)
		var generation_details: RichTextLabel = dock.find_child("GenerationDetails", true, false)
		_check(generation_details_button.visible, "generation technical details are available")
		generation_details_button.emit_signal("pressed")
		_check(generation_details.visible, "generation technical details expand")

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
		generation.queue_free()
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
