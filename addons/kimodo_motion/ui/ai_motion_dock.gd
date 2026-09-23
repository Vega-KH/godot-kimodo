@tool
class_name AiMotionDock
extends VBoxContainer

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const GenerationOptions := preload("res://addons/kimodo_motion/domain/generation_options.gd")
const Preview := preload("res://addons/kimodo_motion/ui/soma77_preview.gd")
const NativeAnimationBaker := preload(
	"res://addons/kimodo_motion/animation/native_animation_baker.gd"
)
const HumanoidRetargetBaker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd"
)
const HumanoidFixture := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_fixture.gd"
)

var _client: Node
var _generation_client: Node
var _editor_plugin: EditorPlugin
var _content: VBoxContainer
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
var _prompt_edit: TextEdit
var _duration_edit: SpinBox
var _seed_edit: SpinBox
var _diffusion_steps_edit: SpinBox
var _generate_button: Button
var _generation_status: Label
var _generation_details_button: Button
var _generation_details_text: RichTextLabel
var _preview: Control
var _humanoid_preview: Control
var _preview_selection: OptionButton
var _play_button: Button
var _loop_toggle: CheckButton
var _scrub_slider: HSlider
var _scrub_dragging := false
var _follow_root_toggle: CheckButton
var _reset_camera_button: Button
var _retarget_button: Button
var _retarget_status: Label
var _humanoid_directory_edit: LineEdit
var _humanoid_name_edit: LineEdit
var _humanoid_save_button: Button
var _humanoid_save_status: Label
var _save_directory_edit: LineEdit
var _save_name_edit: LineEdit
var _save_button: Button
var _save_status: Label
var _humanoid_fixture: PackedScene


func configure(
	client: Node,
	generation_client: Node = null,
	editor_plugin: EditorPlugin = null,
	humanoid_fixture: PackedScene = null,
) -> void:
	_client = client
	_generation_client = generation_client
	_editor_plugin = editor_plugin
	_humanoid_fixture = humanoid_fixture
	if is_node_ready():
		_bind_client()
		_bind_generation_client()


func _ready() -> void:
	name = "AI Motion"
	custom_minimum_size = Vector2(330.0, 0.0)
	_build_ui()
	_bind_client()
	_bind_generation_client()
	set_process(true)


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "DockScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.name = "DockContents"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	var title := Label.new()
	title.text = "Kimodo Motion Studio"
	title.add_theme_font_size_override("font_size", 18)
	_content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Local motion-generation backend"
	subtitle.modulate = Color(0.75, 0.78, 0.82)
	_content.add_child(subtitle)

	_content.add_child(HSeparator.new())
	var url_label := Label.new()
	url_label.text = "Backend URL"
	_content.add_child(url_label)

	var row := HBoxContainer.new()
	_content.add_child(row)
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
	_content.add_child(_status_label)

	var summary_title := Label.new()
	summary_title.text = "Capability summary"
	summary_title.add_theme_font_size_override("font_size", 15)
	_content.add_child(summary_title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	_content.add_child(grid)
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
	_content.add_child(_details_button)
	_details_text = RichTextLabel.new()
	_details_text.name = "TechnicalDetails"
	_details_text.fit_content = true
	_details_text.custom_minimum_size.y = 72.0
	_details_text.visible = false
	_content.add_child(_details_text)

	_content.add_child(HSeparator.new())
	var generation_title := Label.new()
	generation_title.text = "Generate motion"
	generation_title.add_theme_font_size_override("font_size", 15)
	_content.add_child(generation_title)

	var prompt_label := Label.new()
	prompt_label.text = "Prompt"
	_content.add_child(prompt_label)
	_prompt_edit = TextEdit.new()
	_prompt_edit.name = "MotionPrompt"
	_prompt_edit.text = "A person walks forward."
	_prompt_edit.custom_minimum_size.y = 72.0
	_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_content.add_child(_prompt_edit)

	var options_grid := GridContainer.new()
	options_grid.columns = 2
	options_grid.add_theme_constant_override("h_separation", 12)
	options_grid.add_theme_constant_override("v_separation", 5)
	_content.add_child(options_grid)
	var duration_label := Label.new()
	duration_label.text = "Frames"
	options_grid.add_child(duration_label)
	_duration_edit = SpinBox.new()
	_duration_edit.name = "DurationFrames"
	_duration_edit.min_value = 1
	_duration_edit.max_value = 900
	_duration_edit.value = 30
	_duration_edit.custom_minimum_size.x = 80.0
	_duration_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_grid.add_child(_duration_edit)
	var steps_label := Label.new()
	steps_label.text = "Denoising steps"
	options_grid.add_child(steps_label)
	_diffusion_steps_edit = SpinBox.new()
	_diffusion_steps_edit.name = "DiffusionSteps"
	_diffusion_steps_edit.min_value = 1
	_diffusion_steps_edit.max_value = 200
	_diffusion_steps_edit.value = 100
	_diffusion_steps_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_grid.add_child(_diffusion_steps_edit)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	options_grid.add_child(seed_label)
	_seed_edit = SpinBox.new()
	_seed_edit.name = "GenerationSeed"
	_seed_edit.min_value = 0
	_seed_edit.max_value = 2147483647
	_seed_edit.value = 1234
	_seed_edit.custom_minimum_size.x = 105.0
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_grid.add_child(_seed_edit)

	_generate_button = Button.new()
	_generate_button.name = "GenerateAction"
	_generate_button.text = "Generate"
	_generate_button.disabled = true
	_generate_button.pressed.connect(_on_generate_pressed)
	_content.add_child(_generate_button)

	_generation_status = Label.new()
	_generation_status.name = "GenerationStatus"
	_generation_status.text = "No motion generated yet."
	_generation_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_generation_status)
	_generation_details_button = Button.new()
	_generation_details_button.name = "GenerationDetailsToggle"
	_generation_details_button.text = "Show generation details"
	_generation_details_button.visible = false
	_generation_details_button.pressed.connect(_toggle_generation_details)
	_content.add_child(_generation_details_button)
	_generation_details_text = RichTextLabel.new()
	_generation_details_text.name = "GenerationDetails"
	_generation_details_text.fit_content = true
	_generation_details_text.custom_minimum_size.y = 60.0
	_generation_details_text.visible = false
	_content.add_child(_generation_details_text)

	_preview = Preview.new()
	_preview.configure("MotionPreview", Color(0.1, 0.85, 1.0))
	_preview.camera_view_changed.connect(_on_camera_view_changed)
	_preview.visible = false
	_content.add_child(_preview)
	_humanoid_preview = Preview.new()
	_humanoid_preview.configure("HumanoidPreview", Color(1.0, 0.25, 0.72))
	_humanoid_preview.camera_view_changed.connect(_on_camera_view_changed)
	_humanoid_preview.visible = false
	_content.add_child(_humanoid_preview)
	_preview_selection = OptionButton.new()
	_preview_selection.name = "PreviewSelection"
	_preview_selection.add_item("SOMA-77 source")
	_preview_selection.add_item("Godot humanoid")
	_preview_selection.disabled = true
	_preview_selection.visible = false
	_preview_selection.item_selected.connect(_on_preview_selected)
	_content.add_child(_preview_selection)
	var playback_row := HBoxContainer.new()
	playback_row.name = "PlaybackControls"
	playback_row.visible = false
	_content.add_child(playback_row)
	_play_button = Button.new()
	_play_button.name = "PlayPause"
	_play_button.text = "Pause"
	_play_button.pressed.connect(_on_play_pause_pressed)
	playback_row.add_child(_play_button)
	_loop_toggle = CheckButton.new()
	_loop_toggle.name = "LoopMotion"
	_loop_toggle.text = "Loop"
	_loop_toggle.button_pressed = true
	_loop_toggle.toggled.connect(_on_loop_toggled)
	playback_row.add_child(_loop_toggle)
	_scrub_slider = HSlider.new()
	_scrub_slider.name = "TimelineScrub"
	_scrub_slider.min_value = 0.0
	_scrub_slider.max_value = 1.0
	_scrub_slider.step = 0.001
	_scrub_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub_slider.drag_started.connect(_on_scrub_drag_started)
	_scrub_slider.drag_ended.connect(_on_scrub_drag_ended)
	_scrub_slider.value_changed.connect(_on_scrub_value_changed)
	playback_row.add_child(_scrub_slider)
	var camera_row := HBoxContainer.new()
	camera_row.name = "CameraControls"
	camera_row.visible = false
	_content.add_child(camera_row)
	_follow_root_toggle = CheckButton.new()
	_follow_root_toggle.name = "FollowRoot"
	_follow_root_toggle.text = "Follow Root"
	_follow_root_toggle.button_pressed = true
	_follow_root_toggle.toggled.connect(_on_follow_root_toggled)
	camera_row.add_child(_follow_root_toggle)
	_reset_camera_button = Button.new()
	_reset_camera_button.name = "ResetCamera"
	_reset_camera_button.text = "Reset View"
	_reset_camera_button.pressed.connect(_on_reset_camera_pressed)
	camera_row.add_child(_reset_camera_button)
	var camera_hint := Label.new()
	camera_hint.text = "Drag to orbit · Wheel to zoom"
	camera_hint.modulate = Color(0.7, 0.72, 0.76)
	camera_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_row.add_child(camera_hint)

	_content.add_child(HSeparator.new())
	var retarget_title := Label.new()
	retarget_title.text = "Godot humanoid"
	retarget_title.add_theme_font_size_override("font_size", 15)
	_content.add_child(retarget_title)
	_retarget_button = Button.new()
	_retarget_button.name = "RetargetHumanoid"
	_retarget_button.text = "Retarget to Humanoid"
	_retarget_button.disabled = true
	_retarget_button.pressed.connect(_on_retarget_humanoid_pressed)
	_content.add_child(_retarget_button)
	_retarget_status = Label.new()
	_retarget_status.name = "HumanoidRetargetStatus"
	_retarget_status.text = "Generate a validated motion before retargeting."
	_retarget_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_retarget_status)
	var humanoid_save_grid := GridContainer.new()
	humanoid_save_grid.columns = 2
	humanoid_save_grid.add_theme_constant_override("h_separation", 12)
	humanoid_save_grid.add_theme_constant_override("v_separation", 5)
	_content.add_child(humanoid_save_grid)
	var humanoid_directory_label := Label.new()
	humanoid_directory_label.text = "Directory"
	humanoid_save_grid.add_child(humanoid_directory_label)
	_humanoid_directory_edit = LineEdit.new()
	_humanoid_directory_edit.name = "HumanoidTakeDirectory"
	_humanoid_directory_edit.text = "res://animations/kimodo"
	_humanoid_directory_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	humanoid_save_grid.add_child(_humanoid_directory_edit)
	var humanoid_name_label := Label.new()
	humanoid_name_label.text = "Name"
	humanoid_save_grid.add_child(humanoid_name_label)
	_humanoid_name_edit = LineEdit.new()
	_humanoid_name_edit.name = "HumanoidTakeName"
	_humanoid_name_edit.text = "kimodo_humanoid_motion"
	_humanoid_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	humanoid_save_grid.add_child(_humanoid_name_edit)
	_humanoid_save_button = Button.new()
	_humanoid_save_button.name = "SaveHumanoidTake"
	_humanoid_save_button.text = "Save Humanoid Take"
	_humanoid_save_button.disabled = true
	_humanoid_save_button.pressed.connect(_on_save_humanoid_take_pressed)
	_content.add_child(_humanoid_save_button)
	_humanoid_save_status = Label.new()
	_humanoid_save_status.name = "HumanoidTakeStatus"
	_humanoid_save_status.text = "Retarget the current motion before saving."
	_humanoid_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_humanoid_save_status)

	_content.add_child(HSeparator.new())
	var save_title := Label.new()
	save_title.text = "Save SOMA-77 native take"
	save_title.add_theme_font_size_override("font_size", 15)
	_content.add_child(save_title)
	var save_grid := GridContainer.new()
	save_grid.columns = 2
	save_grid.add_theme_constant_override("h_separation", 12)
	save_grid.add_theme_constant_override("v_separation", 5)
	_content.add_child(save_grid)
	var directory_label := Label.new()
	directory_label.text = "Directory"
	save_grid.add_child(directory_label)
	_save_directory_edit = LineEdit.new()
	_save_directory_edit.name = "NativeTakeDirectory"
	_save_directory_edit.text = "res://animations/kimodo"
	_save_directory_edit.placeholder_text = "res://animations/kimodo"
	_save_directory_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_grid.add_child(_save_directory_edit)
	var name_label := Label.new()
	name_label.text = "Name"
	save_grid.add_child(name_label)
	_save_name_edit = LineEdit.new()
	_save_name_edit.name = "NativeTakeName"
	_save_name_edit.text = "kimodo_motion"
	_save_name_edit.placeholder_text = "kimodo_motion"
	_save_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_grid.add_child(_save_name_edit)
	_save_button = Button.new()
	_save_button.name = "SaveNativeTake"
	_save_button.text = "Save SOMA-77 Native Take"
	_save_button.disabled = true
	_save_button.pressed.connect(_on_save_native_take_pressed)
	_content.add_child(_save_button)
	_save_status = Label.new()
	_save_status.name = "NativeTakeStatus"
	_save_status.text = "Generate a validated motion before saving."
	_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_save_status)


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


func _bind_generation_client() -> void:
	if _generation_client == null:
		_update_generation_availability()
		return
	if not _generation_client.state_changed.is_connected(_on_generation_state_changed):
		_generation_client.state_changed.connect(_on_generation_state_changed)
	if not _generation_client.motion_ready.is_connected(_on_motion_ready):
		_generation_client.motion_ready.connect(_on_motion_ready)
	_apply_generation_state(
		_generation_client.state,
		_generation_client.state_name(),
		_generation_client.snapshot(),
	)


func _on_action_pressed() -> void:
	if _client == null:
		return
	if _client.state == Client.ConnectionState.CONNECTING:
		_client.disconnect_from_backend()
	else:
		_client.connect_to_backend(_url_edit.text)


func _on_client_state_changed(state: int, state_name: String, snapshot: Dictionary) -> void:
	_apply_state(state, state_name, snapshot)
	if (
		state != Client.ConnectionState.READY
		and _generation_client != null
		and _generation_client.state == GenerationClient.GenerationState.GENERATING
	):
		_generation_client.cancel_generation()


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
	_update_generation_availability()


func _toggle_details() -> void:
	_details_text.visible = not _details_text.visible
	_details_button.text = (
		"Hide technical details" if _details_text.visible else "Show technical details"
	)


func _on_generate_pressed() -> void:
	if _generation_client == null:
		return
	if _generation_client.state == GenerationClient.GenerationState.GENERATING:
		_generation_client.cancel_generation()
		return
	var options := GenerationOptions.new()
	options.prompt = _prompt_edit.text
	options.duration_frames = int(_duration_edit.value)
	options.seed = int(_seed_edit.value)
	options.diffusion_steps = int(_diffusion_steps_edit.value)
	_generation_client.generate(_client.backend_url, _client.capabilities, options)


func _on_generation_state_changed(state: int, state_name: String, snapshot: Dictionary) -> void:
	_apply_generation_state(state, state_name, snapshot)


func _apply_generation_state(state: int, state_name: String, snapshot: Dictionary) -> void:
	if _generation_status == null:
		return
	var color := Color(0.7, 0.72, 0.76)
	if state == GenerationClient.GenerationState.GENERATING:
		color = Color(0.95, 0.72, 0.2)
	elif state == GenerationClient.GenerationState.READY:
		color = Color(0.25, 0.85, 0.45)
	elif state == GenerationClient.GenerationState.ERROR:
		color = Color(1.0, 0.35, 0.3)
	_generation_status.text = "%s — %s" % [state_name, snapshot["message"]]
	_generation_status.modulate = color
	var details: String = snapshot["technical_details"]
	_generation_details_text.text = details
	_generation_details_button.visible = not details.is_empty()
	if details.is_empty():
		_generation_details_text.visible = false
		_generation_details_button.text = "Show generation details"
	_update_generation_availability()


func _update_generation_availability() -> void:
	if _generate_button == null:
		return
	var generating: bool = (
		_generation_client != null
		and _generation_client.state == GenerationClient.GenerationState.GENERATING
	)
	var connected: bool = _client != null and _client.state == Client.ConnectionState.READY
	_generate_button.disabled = not connected and not generating
	_generate_button.text = "Cancel Generation" if generating else (
		"Generate Again" if _preview != null and _preview.has_motion() else "Generate"
	)
	_prompt_edit.editable = not generating
	_duration_edit.editable = not generating
	_seed_edit.editable = not generating
	_diffusion_steps_edit.editable = not generating
	_action_button.disabled = generating
	_update_save_availability()
	_update_retarget_availability()


func _on_motion_ready() -> void:
	var motion: RefCounted = _generation_client.take_latest_motion()
	_accept_source_motion(motion)


func _accept_source_motion(motion: RefCounted) -> bool:
	_clear_humanoid_preview()
	if not _preview.set_motion(motion):
		_update_retarget_availability()
		_update_save_availability()
		return false
	_preview.visible = true
	var controls := _play_button.get_parent() as Control
	controls.visible = true
	var camera_controls := _follow_root_toggle.get_parent() as Control
	camera_controls.visible = true
	_play_button.text = "Pause"
	_scrub_slider.max_value = maxf(_preview.animation_length(), 0.001)
	_scrub_slider.value = 0.0
	_update_generation_availability()
	_update_save_availability()
	_update_retarget_availability()
	return true


func _on_play_pause_pressed() -> void:
	var next_playing: bool = not _preview.is_playing()
	_preview.set_playing(next_playing)
	_humanoid_preview.set_playing(next_playing)
	_play_button.text = "Pause" if next_playing else "Play"


func _on_loop_toggled(enabled: bool) -> void:
	_preview.set_looping(enabled)
	_humanoid_preview.set_looping(enabled)


func _on_camera_view_changed(yaw: float, pitch: float, distance: float) -> void:
	_preview.set_camera_view(yaw, pitch, distance)
	_humanoid_preview.set_camera_view(yaw, pitch, distance)


func _on_follow_root_toggled(enabled: bool) -> void:
	_preview.set_camera_follow_root(enabled)
	_humanoid_preview.set_camera_follow_root(enabled)


func _on_reset_camera_pressed() -> void:
	_preview.reset_camera_view()
	var view: Dictionary = _preview.camera_view()
	_humanoid_preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])


func _process(_delta: float) -> void:
	if _scrub_slider == null or _scrub_dragging or not _preview.has_motion():
		return
	_scrub_slider.set_value_no_signal(_preview.current_position())


func _on_scrub_drag_started() -> void:
	_scrub_dragging = true


func _on_scrub_drag_ended(_value_changed: bool) -> void:
	_scrub_dragging = false
	_seek_previews(_scrub_slider.value)


func _on_scrub_value_changed(value: float) -> void:
	if _scrub_dragging:
		_seek_previews(value)


func _seek_previews(time: float) -> void:
	_preview.seek(time)
	_humanoid_preview.seek(time)


func _on_preview_selected(index: int) -> void:
	_preview.visible = index == 0 and _preview.has_motion()
	_humanoid_preview.visible = index == 1 and _humanoid_preview.has_motion()


func _on_retarget_humanoid_pressed() -> void:
	if _preview == null or not _preview.has_motion():
		_set_retarget_error("There is no validated generated motion to retarget.")
		return
	var template_root: Node = (
		_humanoid_fixture.instantiate()
		if _humanoid_fixture != null
		else HumanoidFixture.create_scene()
	)
	if template_root == null:
		_set_retarget_error("The humanoid target fixture could not be created.")
		return
	if _find_first_node(template_root, "Skeleton3D") == null:
		template_root.free()
		_set_retarget_error("The humanoid target fixture does not contain a Skeleton3D.")
		return
	var motion: RefCounted = HumanoidRetargetBaker.create_motion(
		_preview.motion_scene(), template_root
	)
	template_root.free()
	if motion == null or not _humanoid_preview.set_motion(motion):
		_set_retarget_error("The current motion could not be retargeted to the humanoid fixture.")
		return
	_humanoid_preview.set_looping(_loop_toggle.button_pressed)
	_humanoid_preview.seek(_preview.current_position())
	_humanoid_preview.set_playing(_preview.is_playing())
	_preview_selection.visible = true
	_preview_selection.disabled = false
	_preview_selection.select(1)
	_on_preview_selected(1)
	_retarget_status.modulate = Color(0.25, 0.85, 0.45)
	_retarget_status.text = "Humanoid preview ready (56-bone Godot profile, 24 tracks)."
	_humanoid_save_status.modulate = Color(0.7, 0.72, 0.76)
	_humanoid_save_status.text = "Humanoid preview is ready to save."
	_update_retarget_availability()


func _set_retarget_error(message: String) -> void:
	_retarget_status.modulate = Color(1.0, 0.35, 0.3)
	_retarget_status.text = message


func _clear_humanoid_preview() -> void:
	if _humanoid_preview != null:
		_humanoid_preview.clear_motion()
		_humanoid_preview.visible = false
	if _preview_selection != null:
		_preview_selection.select(0)
		_preview_selection.visible = false
		_preview_selection.disabled = true
	if _preview != null:
		_preview.visible = _preview.has_motion()
	if _humanoid_save_status != null:
		_humanoid_save_status.modulate = Color(0.7, 0.72, 0.76)
		_humanoid_save_status.text = "Retarget the current motion before saving."
	_update_retarget_availability()


func _update_retarget_availability() -> void:
	if _retarget_button == null:
		return
	var generating: bool = (
		_generation_client != null
		and _generation_client.state == GenerationClient.GenerationState.GENERATING
	)
	_retarget_button.disabled = generating or _preview == null or not _preview.has_motion()
	_humanoid_save_button.disabled = (
		generating or _humanoid_preview == null or not _humanoid_preview.has_motion()
	)


func _on_save_humanoid_take_pressed() -> void:
	var directory := _humanoid_directory_edit.text.strip_edges()
	var take_name := _humanoid_name_edit.text.strip_edges()
	if not directory.begins_with("res://"):
		_set_humanoid_save_error("Directory must be project-relative and begin with res://.")
		return
	if take_name.is_empty():
		_set_humanoid_save_error("Take name cannot be empty.")
		return
	if _humanoid_preview == null or not _humanoid_preview.has_motion():
		_set_humanoid_save_error("There is no retargeted humanoid motion to save.")
		return
	var result := HumanoidRetargetBaker.save_motion(
		_humanoid_preview.motion_scene(), directory, take_name
	)
	if result.is_empty():
		_set_humanoid_save_error(
			"Godot could not save the humanoid take. See the Output panel for details."
		)
		return
	_humanoid_save_status.modulate = Color(0.25, 0.85, 0.45)
	_humanoid_save_status.text = "Saved %s and %s" % [
		result["scene_path"], result["library_path"]
	]
	_refresh_saved_resource(result["scene_path"])


func _set_humanoid_save_error(message: String) -> void:
	_humanoid_save_status.modulate = Color(1.0, 0.35, 0.3)
	_humanoid_save_status.text = message


func _on_save_native_take_pressed() -> void:
	var directory := _save_directory_edit.text.strip_edges()
	var take_name := _save_name_edit.text.strip_edges()
	if not directory.begins_with("res://"):
		_set_save_error("Directory must be project-relative and begin with res://.")
		return
	if take_name.is_empty():
		_set_save_error("Take name cannot be empty.")
		return
	if _preview == null or not _preview.has_motion():
		_set_save_error("There is no validated generated motion to save.")
		return
	var result := NativeAnimationBaker.bake(_preview.motion_scene(), directory, take_name)
	if result.is_empty():
		_set_save_error("Godot could not save the native take. See the Output panel for details.")
		return
	_save_status.modulate = Color(0.25, 0.85, 0.45)
	_save_status.text = "Saved %s and %s" % [result["scene_path"], result["library_path"]]
	_refresh_saved_resource(result["scene_path"])


func _set_save_error(message: String) -> void:
	_save_status.modulate = Color(1.0, 0.35, 0.3)
	_save_status.text = message


func _update_save_availability() -> void:
	if _save_button == null:
		return
	_save_button.disabled = _preview == null or not _preview.has_motion()


func _refresh_saved_resource(scene_path: String) -> void:
	if _editor_plugin == null or not is_instance_valid(_editor_plugin):
		return
	var editor_interface := _editor_plugin.get_editor_interface()
	editor_interface.get_resource_filesystem().scan()
	editor_interface.get_file_system_dock().navigate_to_path(scene_path)


func _toggle_generation_details() -> void:
	_generation_details_text.visible = not _generation_details_text.visible
	_generation_details_button.text = (
		"Hide generation details"
		if _generation_details_text.visible
		else "Show generation details"
	)


func _find_first_node(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first_node(child, type_name)
		if found != null:
			return found
	return null
