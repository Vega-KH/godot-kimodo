@tool
class_name KimodoHistoryPanel
extends VBoxContainer

signal take_activated(generation_index: int, take_id: String)
signal delete_confirmed(take_id: String)

var tree: Tree
var open_button: Button
var delete_button: Button
var status: Label
var confirmation: ConfirmationDialog
var _pending_delete_id := ""


func _ready() -> void:
	name = "History"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()


func set_session(session: Resource) -> void:
	tree.clear()
	var root := tree.create_item()
	open_button.disabled = true
	delete_button.disabled = true
	status.text = "No generated takes yet."
	if session == null or session.generation_records.is_empty():
		return
	var available_count := 0
	for generation_index in session.generation_records.size():
		var record: Dictionary = session.generation_records[generation_index]
		var generation := tree.create_item(root)
		var prompt := String(record.get("prompt", "Generated motion")).strip_edges()
		if prompt.is_empty():
			prompt = "Generated motion"
		generation.set_text(0, prompt)
		var created := String(record.get("generated_at_utc", "")).replace("T", " ").trim_suffix("Z")
		generation.set_text(1, created.left(16))
		generation.set_selectable(0, false)
		generation.set_selectable(1, false)
		generation.set_custom_color(0, Color(0.86, 0.88, 0.92))
		var takes: Array = record.get("takes", [])
		for take_index in takes.size():
			var take: Dictionary = takes[take_index]
			var item := tree.create_item(generation)
			var availability := String(take.get("availability", "unavailable"))
			item.set_text(
				0,
				"Take %d — %s" % [
					take_index + 1,
					String(take.get("sample_name", "motion")),
				],
			)
			item.set_text(1, availability.capitalize())
			item.set_metadata(0, {
				"generation_index": generation_index,
				"take_id": String(take.get("take_id", "")),
				"availability": availability,
			})
			item.set_selectable(0, true)
			item.set_selectable(1, false)
			if availability == "available":
				available_count += 1
			else:
				item.set_custom_color(0, Color(0.62, 0.64, 0.68))
	status.text = "%d generation%s · %d available take%s" % [
		session.generation_records.size(),
		"" if session.generation_records.size() == 1 else "s",
		available_count,
		"" if available_count == 1 else "s",
	]


func select_take(take_id: String) -> void:
	if take_id.is_empty() or tree.get_root() == null:
		return
	var item := tree.get_root().get_first_child()
	while item != null:
		var child := item.get_first_child()
		while child != null:
			var metadata: Variant = child.get_metadata(0)
			if metadata is Dictionary and metadata.get("take_id", "") == take_id:
				child.select(0)
				_update_actions()
				return
			child = child.get_next()
		item = item.get_next()


func _build_ui() -> void:
	var heading := Label.new()
	heading.text = "Generated take history"
	heading.add_theme_font_size_override("font_size", 16)
	add_child(heading)
	var explanation := Label.new()
	explanation.text = "Every successful take is archived as SOMA-77 and converted on demand."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color(0.72, 0.75, 0.8)
	add_child(explanation)
	tree = Tree.new()
	tree.name = "TakeHistory"
	tree.columns = 2
	tree.column_titles_visible = true
	tree.set_column_title(0, "Prompt / take")
	tree.set_column_title(1, "Created / status")
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 120)
	tree.hide_root = true
	tree.custom_minimum_size = Vector2(320.0, 250.0)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(_update_actions)
	tree.item_activated.connect(_activate_selected)
	add_child(tree)
	var actions := HBoxContainer.new()
	add_child(actions)
	open_button = Button.new()
	open_button.name = "OpenHistoricalTake"
	open_button.text = "Preview selected"
	open_button.disabled = true
	open_button.pressed.connect(_activate_selected)
	actions.add_child(open_button)
	delete_button = Button.new()
	delete_button.name = "DeleteHistoricalTake"
	delete_button.text = "Delete source…"
	delete_button.disabled = true
	delete_button.pressed.connect(_request_delete)
	actions.add_child(delete_button)
	status = Label.new()
	status.name = "HistoryStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate = Color(0.72, 0.75, 0.8)
	add_child(status)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Delete archived source take?"
	confirmation.dialog_text = (
		"This removes only the automatic SOMA-77 source archive. "
		+ "Explicitly saved animations and preview scenes are not deleted."
	)
	confirmation.ok_button_text = "Delete source"
	confirmation.confirmed.connect(_confirm_delete)
	add_child(confirmation)


func _selected_metadata() -> Dictionary:
	var selected := tree.get_selected()
	if selected == null:
		return {}
	var metadata: Variant = selected.get_metadata(0)
	return metadata if metadata is Dictionary else {}


func _update_actions() -> void:
	var metadata := _selected_metadata()
	var available: bool = metadata.get("availability", "") == "available"
	open_button.disabled = not available
	delete_button.disabled = not available


func _activate_selected() -> void:
	var metadata := _selected_metadata()
	if metadata.get("availability", "") != "available":
		return
	take_activated.emit(int(metadata["generation_index"]), String(metadata["take_id"]))


func _request_delete() -> void:
	var metadata := _selected_metadata()
	if metadata.get("availability", "") != "available":
		return
	_pending_delete_id = String(metadata["take_id"])
	confirmation.popup_centered()


func _confirm_delete() -> void:
	if _pending_delete_id.is_empty():
		return
	var take_id := _pending_delete_id
	_pending_delete_id = ""
	delete_confirmed.emit(take_id)
