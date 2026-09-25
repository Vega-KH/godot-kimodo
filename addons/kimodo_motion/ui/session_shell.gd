@tool
class_name KimodoSessionShell
extends VBoxContainer

signal new_requested
signal open_requested
signal recent_requested
signal switch_requested

var landing: VBoxContainer
var active_bar: HBoxContainer
var title_edit: LineEdit
var resource_picker: Control
var recent: OptionButton
var status: Label
var active_label: Label
var save_state: Label


func _init() -> void:
	name = "SessionShell"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	landing = VBoxContainer.new()
	landing.name = "SessionLanding"
	add_child(landing)
	var heading := Label.new()
	heading.text = "Start or open a session"
	heading.add_theme_font_size_override("font_size", 15)
	landing.add_child(heading)
	var explanation := Label.new()
	explanation.text = "Generation tools appear after a project-owned session is active."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color(0.75, 0.78, 0.82)
	landing.add_child(explanation)
	var new_row := HBoxContainer.new()
	landing.add_child(new_row)
	title_edit = LineEdit.new()
	title_edit.name = "NewSessionTitle"
	title_edit.placeholder_text = "Session title"
	title_edit.text = "New motion session"
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(title_edit)
	var new_button := Button.new()
	new_button.name = "NewSession"
	new_button.text = "New Session"
	new_button.pressed.connect(func() -> void: new_requested.emit())
	new_row.add_child(new_button)
	var open_row := HBoxContainer.new()
	landing.add_child(open_row)
	if Engine.is_editor_hint():
		var picker := EditorResourcePicker.new()
		picker.base_type = "Resource"
		resource_picker = picker
	else:
		var path_edit := LineEdit.new()
		path_edit.placeholder_text = "res://animations/kimodo/sessions/example.tres"
		resource_picker = path_edit
	resource_picker.name = "SessionResource"
	resource_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_row.add_child(resource_picker)
	var open_button := Button.new()
	open_button.name = "OpenSession"
	open_button.text = "Open"
	open_button.pressed.connect(func() -> void: open_requested.emit())
	open_row.add_child(open_button)
	var recent_row := HBoxContainer.new()
	landing.add_child(recent_row)
	recent = OptionButton.new()
	recent.name = "RecentSessions"
	recent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recent_row.add_child(recent)
	var recent_button := Button.new()
	recent_button.name = "OpenRecentSession"
	recent_button.text = "Open Recent"
	recent_button.pressed.connect(func() -> void: recent_requested.emit())
	recent_row.add_child(recent_button)
	status = Label.new()
	status.name = "SessionLandingStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	landing.add_child(status)

	active_bar = HBoxContainer.new()
	active_bar.name = "ActiveSessionBar"
	active_bar.visible = false
	add_child(active_bar)
	active_label = Label.new()
	active_label.name = "ActiveSessionLabel"
	active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_bar.add_child(active_label)
	save_state = Label.new()
	save_state.name = "SessionSaveState"
	save_state.text = "Saved"
	active_bar.add_child(save_state)
	var switch_button := Button.new()
	switch_button.name = "SwitchSession"
	switch_button.text = "Sessions"
	switch_button.pressed.connect(func() -> void: switch_requested.emit())
	active_bar.add_child(switch_button)
