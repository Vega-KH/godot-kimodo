@tool
class_name KimodoPreviewSavePanel
extends VBoxContainer

signal take_activated(index: int)
signal save_path_selected(kind: int, path: String)

enum SaveKind {
	CHARACTER,
	HUMANOID,
	SOMA77,
}

const Preview := preload("res://addons/kimodo_motion/ui/soma77_preview.gd")
const TransientTakeSet := preload(
	"res://addons/kimodo_motion/domain/transient_take_set.gd"
)

var take_set: RefCounted
var take_selection: OptionButton
var source_preview: Control
var humanoid_preview: Control
var character_preview: Control
var preview_selection: OptionButton
var play_button: Button
var loop_toggle: CheckButton
var scrub_slider: HSlider
var follow_root_toggle: CheckButton
var reset_camera_button: Button
var save_kind: OptionButton
var save_button: Button
var save_status: Label
var save_dialog: FileDialog
var _scrub_dragging := false


func _init() -> void:
	name = "Preview & Save"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	take_set = TransientTakeSet.new()
	_build()
	set_process(true)


func replace_takes(motions: Array[RefCounted]) -> bool:
	clear_takes()
	take_set.replace(motions, source_preview)
	take_selection.clear()
	for index in take_set.size():
		take_selection.add_item(
			"Take %d — %s" % [index + 1, take_set.at(index).animation_name]
		)
	take_selection.visible = not take_set.is_empty()
	if take_set.is_empty():
		return false
	take_selection.select(0)
	return activate_take(0, false)


func activate_take(index: int, notify := true) -> bool:
	if index < 0 or index >= take_set.size():
		return false
	var position: float = source_preview.current_position() if source_preview.has_motion() else 0.0
	var playing: bool = source_preview.is_playing() if source_preview.has_motion() else true
	var view: Dictionary = source_preview.camera_view()
	clear_humanoid()
	if not take_set.activate(index, source_preview):
		return false
	source_preview.visible = true
	source_preview.set_looping(loop_toggle.button_pressed)
	source_preview.set_camera_follow_root(follow_root_toggle.button_pressed)
	source_preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])
	source_preview.seek(minf(position, source_preview.animation_length()))
	source_preview.set_playing(playing)
	play_button.text = "Pause" if playing else "Play"
	scrub_slider.max_value = maxf(source_preview.animation_length(), 0.001)
	scrub_slider.set_value_no_signal(source_preview.current_position())
	(play_button.get_parent() as Control).visible = true
	(follow_root_toggle.get_parent() as Control).visible = true
	take_selection.select(index)
	if notify:
		take_activated.emit(index)
	return true


func clear_takes() -> void:
	clear_humanoid()
	if take_set != null:
		take_set.clear(source_preview)
	if source_preview != null:
		source_preview.clear_motion()
		source_preview.visible = false
	if take_selection != null:
		take_selection.clear()
		take_selection.visible = false
	if play_button != null:
		(play_button.get_parent() as Control).visible = false
	if follow_root_toggle != null:
		(follow_root_toggle.get_parent() as Control).visible = false
	clear_save_status()
	set_save_availability(false, false, false, false)


func all_motions() -> Array:
	return take_set.motions


func active_index() -> int:
	return take_set.active_index


func active_motion() -> RefCounted:
	return take_set.at(take_set.active_index)


func set_humanoid_motion(motion: RefCounted) -> bool:
	clear_humanoid()
	if motion == null or not humanoid_preview.set_motion(motion):
		return false
	_sync_new_preview(humanoid_preview)
	preview_selection.visible = true
	preview_selection.disabled = false
	return true


func set_character_motion(motion: RefCounted) -> bool:
	clear_character()
	if motion == null or not character_preview.set_motion(motion):
		return false
	_sync_new_preview(character_preview)
	preview_selection.visible = true
	preview_selection.disabled = false
	preview_selection.set_item_disabled(2, false)
	preview_selection.select(2)
	_show_preview(2)
	return true


func clear_humanoid() -> void:
	clear_character()
	if humanoid_preview != null:
		humanoid_preview.clear_motion()
		humanoid_preview.visible = false
	if preview_selection != null:
		preview_selection.select(0)
		preview_selection.visible = false
		preview_selection.disabled = true
	if source_preview != null:
		source_preview.visible = source_preview.has_motion()


func clear_character() -> void:
	if character_preview != null:
		character_preview.clear_motion()
		character_preview.visible = false
	if preview_selection != null:
		preview_selection.set_item_disabled(2, true)
		if preview_selection.selected == 2:
			var fallback := 1 if humanoid_preview.has_motion() else 0
			preview_selection.select(fallback)
			_show_preview(fallback)


func has_source() -> bool:
	return source_preview != null and source_preview.has_motion()


func has_humanoid() -> bool:
	return humanoid_preview != null and humanoid_preview.has_motion()


func has_character() -> bool:
	return character_preview != null and character_preview.has_motion()


func seek_all(time: float) -> void:
	source_preview.seek(time)
	humanoid_preview.seek(time)
	character_preview.seek(time)


func set_save_availability(
	source_ready: bool, humanoid_ready: bool, character_ready: bool, generating: bool
) -> void:
	if save_kind == null:
		return
	save_kind.set_item_disabled(SaveKind.CHARACTER, generating or not character_ready)
	save_kind.set_item_disabled(SaveKind.HUMANOID, generating or not humanoid_ready)
	save_kind.set_item_disabled(SaveKind.SOMA77, generating or not source_ready)
	_update_save_button()


func show_save_result(message: String) -> void:
	save_status.visible = true
	save_status.modulate = Color(0.25, 0.85, 0.45)
	save_status.text = message


func show_save_error(message: String) -> void:
	save_status.visible = true
	save_status.modulate = Color(1.0, 0.35, 0.3)
	save_status.text = message


func clear_save_status() -> void:
	if save_status != null:
		save_status.visible = false
		save_status.text = ""


func submit_save_path(kind: int, path: String) -> void:
	save_path_selected.emit(kind, path)


func _build() -> void:
	var take_row := HBoxContainer.new()
	add_child(take_row)
	var take_label := Label.new()
	take_label.text = "Preview take"
	take_row.add_child(take_label)
	take_selection = OptionButton.new()
	take_selection.name = "TakeSelection"
	take_selection.visible = false
	take_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_selection.item_selected.connect(_on_take_selected)
	take_row.add_child(take_selection)

	source_preview = Preview.new()
	source_preview.configure("MotionPreview", Color(0.1, 0.85, 1.0))
	source_preview.camera_view_changed.connect(_on_camera_view_changed)
	source_preview.visible = false
	add_child(source_preview)
	humanoid_preview = Preview.new()
	humanoid_preview.configure("HumanoidPreview", Color(1.0, 0.25, 0.72))
	humanoid_preview.camera_view_changed.connect(_on_camera_view_changed)
	humanoid_preview.visible = false
	add_child(humanoid_preview)
	character_preview = Preview.new()
	character_preview.configure("CharacterPreview", Color.WHITE, false)
	character_preview.camera_view_changed.connect(_on_camera_view_changed)
	character_preview.visible = false
	add_child(character_preview)

	preview_selection = OptionButton.new()
	preview_selection.name = "PreviewSelection"
	preview_selection.add_item("SOMA-77 source")
	preview_selection.add_item("Godot humanoid")
	preview_selection.add_item("Skinned character")
	preview_selection.set_item_disabled(1, true)
	preview_selection.set_item_disabled(2, true)
	preview_selection.disabled = true
	preview_selection.visible = false
	preview_selection.item_selected.connect(_show_preview)
	add_child(preview_selection)

	var playback_row := HBoxContainer.new()
	playback_row.name = "PlaybackControls"
	playback_row.visible = false
	add_child(playback_row)
	play_button = Button.new()
	play_button.name = "PlayPause"
	play_button.text = "Pause"
	play_button.pressed.connect(_on_play_pause_pressed)
	playback_row.add_child(play_button)
	loop_toggle = CheckButton.new()
	loop_toggle.name = "LoopMotion"
	loop_toggle.text = "Loop"
	loop_toggle.button_pressed = true
	loop_toggle.toggled.connect(_on_loop_toggled)
	playback_row.add_child(loop_toggle)
	scrub_slider = HSlider.new()
	scrub_slider.name = "TimelineScrub"
	scrub_slider.min_value = 0.0
	scrub_slider.max_value = 1.0
	scrub_slider.step = 0.001
	scrub_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub_slider.drag_started.connect(func() -> void: _scrub_dragging = true)
	scrub_slider.drag_ended.connect(_on_scrub_drag_ended)
	scrub_slider.value_changed.connect(_on_scrub_value_changed)
	playback_row.add_child(scrub_slider)

	var camera_row := HBoxContainer.new()
	camera_row.name = "CameraControls"
	camera_row.visible = false
	add_child(camera_row)
	follow_root_toggle = CheckButton.new()
	follow_root_toggle.name = "FollowRoot"
	follow_root_toggle.text = "Follow Root"
	follow_root_toggle.button_pressed = true
	follow_root_toggle.toggled.connect(_on_follow_root_toggled)
	camera_row.add_child(follow_root_toggle)
	reset_camera_button = Button.new()
	reset_camera_button.name = "ResetCamera"
	reset_camera_button.text = "Reset View"
	reset_camera_button.pressed.connect(_on_reset_camera_pressed)
	camera_row.add_child(reset_camera_button)
	var camera_hint := Label.new()
	camera_hint.text = "Drag to orbit · Wheel to zoom"
	camera_hint.modulate = Color(0.7, 0.72, 0.76)
	camera_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_row.add_child(camera_hint)

	add_child(HSeparator.new())
	var save_title := Label.new()
	save_title.text = "Save selected take"
	save_title.add_theme_font_size_override("font_size", 15)
	add_child(save_title)
	var save_row := HBoxContainer.new()
	add_child(save_row)
	save_kind = OptionButton.new()
	save_kind.name = "SaveTakeType"
	save_kind.add_item("Character take", SaveKind.CHARACTER)
	save_kind.add_item("Humanoid take", SaveKind.HUMANOID)
	save_kind.add_item("SOMA-77 native take", SaveKind.SOMA77)
	save_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_kind.item_selected.connect(func(_index: int) -> void: _update_save_button())
	save_row.add_child(save_kind)
	save_button = Button.new()
	save_button.name = "SaveSelectedTake"
	save_button.text = "Save…"
	save_button.disabled = true
	save_button.pressed.connect(_open_save_dialog)
	save_row.add_child(save_button)
	save_status = Label.new()
	save_status.name = "TakeSaveStatus"
	save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_status.visible = false
	add_child(save_status)

	save_dialog = FileDialog.new()
	save_dialog.name = "TakeSaveDialog"
	save_dialog.access = FileDialog.ACCESS_RESOURCES
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.filters = PackedStringArray(["*.tscn ; Godot scene"])
	save_dialog.file_selected.connect(_on_file_selected)
	add_child(save_dialog)


func _on_take_selected(index: int) -> void:
	if index == take_set.active_index:
		return
	if activate_take(index, false):
		take_activated.emit(index)


func _sync_new_preview(preview: Control) -> void:
	preview.set_looping(loop_toggle.button_pressed)
	preview.seek(source_preview.current_position())
	preview.set_playing(source_preview.is_playing())
	preview.set_camera_follow_root(follow_root_toggle.button_pressed)
	var view: Dictionary = source_preview.camera_view()
	preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])
	preview_selection.set_item_disabled(1, not humanoid_preview.has_motion())


func _on_play_pause_pressed() -> void:
	var next_playing: bool = not source_preview.is_playing()
	source_preview.set_playing(next_playing)
	humanoid_preview.set_playing(next_playing)
	character_preview.set_playing(next_playing)
	play_button.text = "Pause" if next_playing else "Play"


func _on_loop_toggled(enabled: bool) -> void:
	source_preview.set_looping(enabled)
	humanoid_preview.set_looping(enabled)
	character_preview.set_looping(enabled)


func _on_camera_view_changed(yaw: float, pitch: float, distance: float) -> void:
	source_preview.set_camera_view(yaw, pitch, distance)
	humanoid_preview.set_camera_view(yaw, pitch, distance)
	character_preview.set_camera_view(yaw, pitch, distance)


func _on_follow_root_toggled(enabled: bool) -> void:
	source_preview.set_camera_follow_root(enabled)
	humanoid_preview.set_camera_follow_root(enabled)
	character_preview.set_camera_follow_root(enabled)


func _on_reset_camera_pressed() -> void:
	source_preview.reset_camera_view()
	var view: Dictionary = source_preview.camera_view()
	humanoid_preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])
	character_preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])


func _process(_delta: float) -> void:
	if scrub_slider == null or _scrub_dragging or not source_preview.has_motion():
		return
	scrub_slider.set_value_no_signal(source_preview.current_position())


func _on_scrub_drag_ended(_value_changed: bool) -> void:
	_scrub_dragging = false
	seek_all(scrub_slider.value)


func _on_scrub_value_changed(value: float) -> void:
	if _scrub_dragging:
		seek_all(value)


func _show_preview(index: int) -> void:
	source_preview.visible = index == 0 and source_preview.has_motion()
	humanoid_preview.visible = index == 1 and humanoid_preview.has_motion()
	character_preview.visible = index == 2 and character_preview.has_motion()


func _update_save_button() -> void:
	if save_button == null or save_kind == null:
		return
	var index := save_kind.selected
	save_button.disabled = index < 0 or save_kind.is_item_disabled(index)


func _open_save_dialog() -> void:
	var kind := save_kind.get_selected_id()
	var default_name := "kimodo_character_motion.tscn"
	if kind == SaveKind.HUMANOID:
		default_name = "kimodo_humanoid_motion.tscn"
	elif kind == SaveKind.SOMA77:
		default_name = "kimodo_motion.tscn"
	var preferred_directory := "res://animations/kimodo"
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(preferred_directory)):
		preferred_directory = "res://"
	save_dialog.current_dir = preferred_directory
	save_dialog.current_file = default_name
	save_dialog.popup_centered_ratio(0.8)


func _on_file_selected(path: String) -> void:
	save_path_selected.emit(save_kind.get_selected_id(), path)
