@tool
class_name KimodoGenerationTakePanel
extends VBoxContainer

var url_edit: LineEdit
var connection_button: Button
var connection_status: Label
var model_label: Label
var fps_label: Label
var joints_label: Label
var constraints_label: Label
var contacts_label: Label
var technical_details_button: Button
var technical_details: RichTextLabel
var target_picker: Control
var target_clear_button: Button
var target_status: Label
var session_status: Label
var session_details_button: Button
var session_details: RichTextLabel
var prompt_edit: TextEdit
var duration_edit: SpinBox
var seed_edit: SpinBox
var diffusion_steps_edit: SpinBox
var take_count_edit: SpinBox
var generate_button: Button
var generation_status: Label
var generation_details_button: Button
var generation_details: RichTextLabel


func _init() -> void:
	name = "Generate"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func set_intent_editable(editable: bool) -> void:
	prompt_edit.editable = editable
	duration_edit.editable = editable
	seed_edit.editable = editable
	diffusion_steps_edit.editable = editable
	take_count_edit.editable = editable


func set_connection_details(text: String) -> void:
	technical_details.text = text
	technical_details_button.visible = not text.is_empty()
	if text.is_empty():
		technical_details.visible = false
		technical_details_button.text = "Show technical details"


func set_generation_details(text: String) -> void:
	generation_details.text = text
	generation_details_button.visible = not text.is_empty()
	if text.is_empty():
		generation_details.visible = false
		generation_details_button.text = "Show generation details"


func clear_capability_summary() -> void:
	model_label.text = "—"
	fps_label.text = "—"
	joints_label.text = "—"
	constraints_label.text = "—"
	contacts_label.text = "—"


func _build() -> void:
	add_child(HSeparator.new())
	var url_label := Label.new()
	url_label.text = "Backend URL"
	add_child(url_label)
	var connection_row := HBoxContainer.new()
	add_child(connection_row)
	url_edit = LineEdit.new()
	url_edit.name = "BackendUrl"
	url_edit.text = "http://127.0.0.1:8000"
	url_edit.placeholder_text = "http://127.0.0.1:8000"
	url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connection_row.add_child(url_edit)
	connection_button = Button.new()
	connection_button.name = "ConnectionAction"
	connection_button.text = "Connect"
	connection_row.add_child(connection_button)
	connection_status = Label.new()
	connection_status.name = "ConnectionStatus"
	connection_status.text = "● Disconnected — Backend connection is idle."
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(connection_status)

	var summary_title := Label.new()
	summary_title.text = "Capability summary"
	summary_title.add_theme_font_size_override("font_size", 15)
	add_child(summary_title)
	var summary_grid := GridContainer.new()
	summary_grid.columns = 2
	summary_grid.add_theme_constant_override("h_separation", 14)
	summary_grid.add_theme_constant_override("v_separation", 5)
	add_child(summary_grid)
	model_label = _add_summary_row(summary_grid, "Model", "—", "ModelValue")
	fps_label = _add_summary_row(summary_grid, "Frame rate", "—", "FpsValue")
	joints_label = _add_summary_row(summary_grid, "Skeleton", "—", "JointsValue")
	constraints_label = _add_summary_row(summary_grid, "Constraints", "—", "ConstraintsValue")
	contacts_label = _add_summary_row(summary_grid, "Contacts", "—", "ContactsValue")
	technical_details_button = Button.new()
	technical_details_button.name = "TechnicalDetailsToggle"
	technical_details_button.text = "Show technical details"
	technical_details_button.visible = false
	technical_details_button.pressed.connect(_toggle_connection_details)
	add_child(technical_details_button)
	technical_details = RichTextLabel.new()
	technical_details.name = "TechnicalDetails"
	technical_details.fit_content = true
	technical_details.custom_minimum_size.y = 72.0
	technical_details.visible = false
	add_child(technical_details)

	_build_target_section()
	add_child(HSeparator.new())
	var generation_title := Label.new()
	generation_title.text = "Generate motion"
	generation_title.add_theme_font_size_override("font_size", 15)
	add_child(generation_title)
	var prompt_label := Label.new()
	prompt_label.text = "Prompt"
	add_child(prompt_label)
	prompt_edit = TextEdit.new()
	prompt_edit.name = "MotionPrompt"
	prompt_edit.text = "A person walks forward."
	prompt_edit.custom_minimum_size.y = 72.0
	prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(prompt_edit)
	var options_grid := GridContainer.new()
	options_grid.columns = 2
	options_grid.add_theme_constant_override("h_separation", 12)
	options_grid.add_theme_constant_override("v_separation", 5)
	add_child(options_grid)
	duration_edit = _add_spin_row(options_grid, "Frames", "DurationFrames", 1, 900, 30)
	diffusion_steps_edit = _add_spin_row(
		options_grid, "Denoising steps", "DiffusionSteps", 1, 200, 100
	)
	seed_edit = _add_spin_row(
		options_grid, "Seed", "GenerationSeed", 0, 2147483647, 1234
	)
	take_count_edit = _add_spin_row(options_grid, "Takes", "TakeCount", 1, 2, 1)
	take_count_edit.tooltip_text = "Tested range for this release: one or two takes."
	generate_button = Button.new()
	generate_button.name = "GenerateAction"
	generate_button.text = "Generate"
	generate_button.disabled = true
	add_child(generate_button)
	generation_status = Label.new()
	generation_status.name = "GenerationStatus"
	generation_status.text = "No motion generated yet."
	generation_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(generation_status)
	generation_details_button = Button.new()
	generation_details_button.name = "GenerationDetailsToggle"
	generation_details_button.text = "Show generation details"
	generation_details_button.visible = false
	generation_details_button.pressed.connect(_toggle_generation_details)
	add_child(generation_details_button)
	generation_details = RichTextLabel.new()
	generation_details.name = "GenerationDetails"
	generation_details.fit_content = true
	generation_details.custom_minimum_size.y = 60.0
	generation_details.visible = false
	add_child(generation_details)


func _build_target_section() -> void:
	add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Character target"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)
	var explanation := Label.new()
	explanation.text = "Choose a compatible project-owned character before generating."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color(0.75, 0.78, 0.82)
	add_child(explanation)
	var target_label := Label.new()
	target_label.text = "Character scene"
	add_child(target_label)
	var target_row := HBoxContainer.new()
	add_child(target_row)
	if Engine.is_editor_hint():
		var editor_picker := EditorResourcePicker.new()
		editor_picker.base_type = "PackedScene"
		target_picker = editor_picker
	else:
		var test_picker := LineEdit.new()
		test_picker.editable = false
		test_picker.placeholder_text = "PackedScene target (editor picker)"
		target_picker = test_picker
	target_picker.name = "CharacterTarget"
	target_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(target_picker)
	target_clear_button = Button.new()
	target_clear_button.name = "ClearCharacterTarget"
	target_clear_button.text = "Clear"
	target_clear_button.disabled = true
	target_row.add_child(target_clear_button)
	target_status = Label.new()
	target_status.name = "CharacterStatus"
	target_status.text = "Select a project-owned compatible PackedScene target."
	target_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(target_status)
	session_status = Label.new()
	session_status.name = "SessionStatus"
	session_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(session_status)
	session_details_button = Button.new()
	session_details_button.name = "SessionDetailsToggle"
	session_details_button.text = "Show session details"
	session_details_button.pressed.connect(_toggle_session_details)
	add_child(session_details_button)
	session_details = RichTextLabel.new()
	session_details.name = "SessionDetails"
	session_details.bbcode_enabled = true
	session_details.fit_content = true
	session_details.custom_minimum_size.y = 72.0
	session_details.visible = false
	add_child(session_details)


func _add_summary_row(
	grid: GridContainer, label_text: String, value: String, node_name: String
) -> Label:
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


func _add_spin_row(
	grid: GridContainer,
	label_text: String,
	node_name: String,
	minimum: float,
	maximum: float,
	initial: float,
) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var spin := SpinBox.new()
	spin.name = node_name
	spin.min_value = minimum
	spin.max_value = maximum
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(spin)
	return spin


func _toggle_connection_details() -> void:
	technical_details.visible = not technical_details.visible
	technical_details_button.text = (
		"Hide technical details" if technical_details.visible else "Show technical details"
	)


func _toggle_generation_details() -> void:
	generation_details.visible = not generation_details.visible
	generation_details_button.text = (
		"Hide generation details" if generation_details.visible else "Show generation details"
	)


func _toggle_session_details() -> void:
	session_details.visible = not session_details.visible
	session_details_button.text = (
		"Hide session details" if session_details.visible else "Show session details"
	)
