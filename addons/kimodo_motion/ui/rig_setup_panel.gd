@tool
class_name KimodoRigSetupPanel
extends VBoxContainer

signal save_requested(mapping: Dictionary, root_policy: String)
signal reset_requested

const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")

var root_policy: OptionButton
var rows: VBoxContainer
var reset_button: Button
var save_button: Button
var status: Label
var _bone_names: Array[String] = []
var _suggestions: Dictionary = {}
var _selectors: Dictionary = {}

func _init() -> void:
	name = "Rig Setup"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()

func configure(
	skeleton: Skeleton3D, result: Dictionary, reset_result: Dictionary = {}
) -> void:
	_bone_names.clear()
	for index in skeleton.get_bone_count():
		_bone_names.append(String(skeleton.get_bone_name(index)))
	_bone_names.sort()
	_suggestions = (reset_result if not reset_result.is_empty() else result).duplicate(true)
	root_policy.select(1 if result["root_motion_policy"] == Profile.ROOT_HIPS_ONLY else 0)
	_rebuild_rows(result["rows"].duplicate(true))
	reset_button.disabled = false
	save_button.disabled = false
	status.modulate = Color(0.95, 0.72, 0.2)
	status.text = "Review every required role, then save a certified project profile."


func clear() -> void:
	for child in rows.get_children():
		child.free()
	_selectors.clear()
	_bone_names.clear()
	_suggestions.clear()
	root_policy.select(0)
	reset_button.disabled = true
	save_button.disabled = true
	status.modulate = Color(0.7, 0.72, 0.76)
	status.text = "Select a character to inspect its rig mapping."

func current_mapping() -> Dictionary:
	var mapping := {}
	for role in _selectors:
		var selector := _selectors[role] as OptionButton
		if selector.selected > 0:
			mapping[String(role)] = selector.get_item_text(selector.selected)
	return mapping

func current_root_policy() -> String:
	return Profile.ROOT_HIPS_ONLY if root_policy.selected == 1 else Profile.ROOT_SEPARATE

func show_error(message: String) -> void:
	status.modulate = Color(1.0, 0.35, 0.3)
	status.text = message

func show_saved(path: String) -> void:
	status.modulate = Color(0.25, 0.85, 0.45)
	status.text = "Certified profile saved: %s" % path

func _build() -> void:
	var heading := Label.new()
	heading.text = "Rig Setup"
	heading.add_theme_font_size_override("font_size", 16)
	add_child(heading)
	var explanation := Label.new()
	explanation.text = "Review how Godot humanoid roles map to this character. Suggestions are evidence, not hidden automation."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(explanation)
	var policy_row := HBoxContainer.new()
	add_child(policy_row)
	var policy_label := Label.new()
	policy_label.text = "Root motion"
	policy_row.add_child(policy_label)
	root_policy = OptionButton.new()
	root_policy.name = "RigRootPolicy"
	root_policy.add_item("Separate Root + Hips")
	root_policy.add_item("Hips is skeleton root")
	root_policy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	policy_row.add_child(root_policy)
	var columns := Label.new()
	columns.text = "Canonical role / confidence / target / evidence"
	columns.modulate = Color(0.75, 0.78, 0.82)
	add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var actions := HBoxContainer.new()
	add_child(actions)
	reset_button = Button.new()
	reset_button.name = "ResetRigSuggestions"
	reset_button.text = "Reset Suggestions"
	reset_button.disabled = true
	reset_button.pressed.connect(func() -> void:
		reset_requested.emit()
		if not _suggestions.is_empty():
			root_policy.select(1 if _suggestions["root_motion_policy"] == Profile.ROOT_HIPS_ONLY else 0)
			_rebuild_rows(_suggestions["rows"].duplicate(true))
	)
	actions.add_child(reset_button)
	save_button = Button.new()
	save_button.name = "SaveRigProfile"
	save_button.text = "Save Profile"
	save_button.disabled = true
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(func() -> void: save_requested.emit(current_mapping(), current_root_policy()))
	actions.add_child(save_button)
	status = Label.new()
	status.name = "RigSetupStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)

func _rebuild_rows(suggestion_rows: Dictionary) -> void:
	for child in rows.get_children():
		child.free()
	_selectors.clear()
	var roles: Array[String] = []
	for role in suggestion_rows:
		roles.append(String(role))
	roles.sort_custom(func(a: String, b: String) -> bool:
		if a == "Root": return true
		if b == "Root": return false
		if a == "Hips": return true
		if b == "Hips": return false
		return a < b
	)
	for role in roles:
		var data: Dictionary = suggestion_rows[role]
		var row := VBoxContainer.new()
		rows.add_child(row)
		var heading := HBoxContainer.new()
		row.add_child(heading)
		var label := Label.new()
		label.text = role + (" *" if data["required"] else "")
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(label)
		var confidence := Label.new()
		confidence.text = "conflict" if data["conflict"] else data["confidence"]
		confidence.modulate = Color(1.0, 0.45, 0.35) if data["conflict"] else Color(0.55, 0.78, 0.95)
		confidence.tooltip_text = data["evidence"]
		heading.add_child(confidence)
		var selector := OptionButton.new()
		selector.name = "RigRole_" + role
		selector.add_item("— Unmapped —")
		for bone_name in _bone_names:
			selector.add_item(bone_name)
		var target := String(data["target"])
		selector.select(_bone_names.find(target) + 1 if not target.is_empty() else 0)
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.tooltip_text = data["evidence"]
		row.add_child(selector)
		_selectors[role] = selector
		var evidence := Label.new()
		evidence.text = data["evidence"]
		evidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		evidence.modulate = Color(0.66, 0.68, 0.72)
		evidence.add_theme_font_size_override("font_size", 12)
		row.add_child(evidence)
		selector.item_selected.connect(func(_index: int) -> void:
			data["confidence"] = "manual"
			data["evidence"] = "Artist-selected override"
			confidence.text = "manual"
			confidence.modulate = Color(0.55, 0.78, 0.95)
			evidence.text = "Artist-selected override"
		)
		var separator := HSeparator.new()
		row.add_child(separator)
