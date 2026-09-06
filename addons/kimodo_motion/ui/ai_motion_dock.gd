@tool
class_name AiMotionDock
extends VBoxContainer

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")

var _client: Node
var _url_edit: LineEdit
var _action_button: Button
var _status_label: Label
var _model_label: Label
var _fps_label: Label
var _joints_label: Label
var _constraints_label: Label
var _contacts_label: Label
var _details_button: Button
var _details_text: RichTextLabel


func configure(client: Node) -> void:
	_client = client
	if is_node_ready():
		_bind_client()


func _ready() -> void:
	name = "AI Motion"
	custom_minimum_size = Vector2(330.0, 0.0)
	_build_ui()
	_bind_client()


func _build_ui() -> void:
	var title := Label.new()
	title.text = "Kimodo Motion Studio"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Local motion-generation backend"
	subtitle.modulate = Color(0.75, 0.78, 0.82)
	add_child(subtitle)

	add_child(HSeparator.new())
	var url_label := Label.new()
	url_label.text = "Backend URL"
	add_child(url_label)

	var row := HBoxContainer.new()
	add_child(row)
	_url_edit = LineEdit.new()
	_url_edit.name = "BackendUrl"
	_url_edit.text = Client.DEFAULT_URL
	_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_url_edit.placeholder_text = "http://127.0.0.1:8000"
	row.add_child(_url_edit)
	_action_button = Button.new()
	_action_button.name = "ConnectionAction"
	_action_button.text = "Connect"
	_action_button.pressed.connect(_on_action_pressed)
	row.add_child(_action_button)

	_status_label = Label.new()
	_status_label.name = "ConnectionStatus"
	_status_label.text = "● Disconnected — Backend connection is idle."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	var summary_title := Label.new()
	summary_title.text = "Capability summary"
	summary_title.add_theme_font_size_override("font_size", 15)
	add_child(summary_title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	add_child(grid)
	_model_label = _add_summary_row(grid, "Model", "—", "ModelValue")
	_fps_label = _add_summary_row(grid, "Frame rate", "—", "FpsValue")
	_joints_label = _add_summary_row(grid, "Skeleton", "—", "JointsValue")
	_constraints_label = _add_summary_row(grid, "Constraints", "—", "ConstraintsValue")
	_contacts_label = _add_summary_row(grid, "Contacts", "—", "ContactsValue")

	_details_button = Button.new()
	_details_button.name = "TechnicalDetailsToggle"
	_details_button.text = "Show technical details"
	_details_button.visible = false
	_details_button.pressed.connect(_toggle_details)
	add_child(_details_button)
	_details_text = RichTextLabel.new()
	_details_text.name = "TechnicalDetails"
	_details_text.fit_content = true
	_details_text.custom_minimum_size.y = 72.0
	_details_text.visible = false
	add_child(_details_text)


func _add_summary_row(grid: GridContainer, label_text: String, value: String, node_name: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.modulate = Color(0.75, 0.78, 0.82)
	grid.add_child(label)
	var value_label := Label.new()
	value_label.name = node_name
	value_label.text = value
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value_label)
	return value_label


func _bind_client() -> void:
	if _client == null:
		return
	if not _client.state_changed.is_connected(_on_client_state_changed):
		_client.state_changed.connect(_on_client_state_changed)
	_apply_state(_client.state, _client.state_name(), _client.snapshot())


func _on_action_pressed() -> void:
	if _client == null:
		return
	if _client.state == Client.ConnectionState.CONNECTING:
		_client.disconnect_from_backend()
	else:
		_client.connect_to_backend(_url_edit.text)


func _on_client_state_changed(state: int, state_name: String, snapshot: Dictionary) -> void:
	_apply_state(state, state_name, snapshot)


func _apply_state(state: int, state_name: String, snapshot: Dictionary) -> void:
	if _status_label == null:
		return
	var icon := "●"
	var color := Color(0.7, 0.72, 0.76)
	if state == Client.ConnectionState.CONNECTING:
		icon = "◌"
		color = Color(0.95, 0.72, 0.2)
	elif state == Client.ConnectionState.READY:
		color = Color(0.25, 0.85, 0.45)
	elif state == Client.ConnectionState.ERROR:
		color = Color(1.0, 0.35, 0.3)
	_status_label.text = "%s %s — %s" % [icon, state_name, snapshot["message"]]
	_status_label.modulate = color
	_action_button.text = "Cancel" if state == Client.ConnectionState.CONNECTING else (
		"Refresh" if state == Client.ConnectionState.READY else "Connect"
	)
	_url_edit.editable = state != Client.ConnectionState.CONNECTING

	var model: RefCounted = snapshot["capabilities"]
	if model == null:
		_model_label.text = "—"
		_fps_label.text = "—"
		_joints_label.text = "—"
		_constraints_label.text = "—"
		_contacts_label.text = "—"
	else:
		_model_label.text = model.model_id
		_fps_label.text = "%.0f fps" % model.fps
		_joints_label.text = "SOMA-77 (%d joints)" % model.joint_names.size()
		_constraints_label.text = "%d — %s" % [
			model.constraint_types.size(), ", ".join(model.constraint_types),
		]
		_contacts_label.text = "%d channels" % model.contact_joints.size()

	var details: String = snapshot["technical_details"]
	_details_text.text = details
	_details_button.visible = not details.is_empty()
	if details.is_empty():
		_details_text.visible = false
		_details_button.text = "Show technical details"


func _toggle_details() -> void:
	_details_text.visible = not _details_text.visible
	_details_button.text = (
		"Hide technical details" if _details_text.visible else "Show technical details"
	)
