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

var _client: Node
var _generation_client: Node
var _editor_plugin: EditorPlugin
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
var _play_button: Button
var _loop_toggle: CheckButton
var _save_directory_edit: LineEdit
var _save_name_edit: LineEdit
var _save_button: Button
var _save_status: Label


func configure(
	client: Node, generation_client: Node = null, editor_plugin: EditorPlugin = null
) -> void:
	_client = client
	_generation_client = generation_client
	_editor_plugin = editor_plugin
	if is_node_ready():
		_bind_client()
		_bind_generation_client()


func _ready() -> void:
	name = "AI Motion"
	custom_minimum_size = Vector2(330.0, 0.0)
	_build_ui()
	_bind_client()
	_bind_generation_client()


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

	add_child(HSeparator.new())
	var generation_title := Label.new()
	generation_title.text = "Generate motion"
	generation_title.add_theme_font_size_override("font_size", 15)
	add_child(generation_title)

	var prompt_label := Label.new()
	prompt_label.text = "Prompt"
	add_child(prompt_label)
	_prompt_edit = TextEdit.new()
	_prompt_edit.name = "MotionPrompt"
	_prompt_edit.text = "A person walks forward."
	_prompt_edit.custom_minimum_size.y = 72.0
	_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(_prompt_edit)

	var options_grid := GridContainer.new()
	options_grid.columns = 2
	options_grid.add_theme_constant_override("h_separation", 12)
	options_grid.add_theme_constant_override("v_separation", 5)
	add_child(options_grid)
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
	_diffusion_steps_edit.max_value = 100
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
	add_child(_generate_button)

	_generation_status = Label.new()
	_generation_status.name = "GenerationStatus"
	_generation_status.text = "No motion generated yet."
	_generation_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_generation_status)
	_generation_details_button = Button.new()
	_generation_details_button.name = "GenerationDetailsToggle"
	_generation_details_button.text = "Show generation details"
	_generation_details_button.visible = false
	_generation_details_button.pressed.connect(_toggle_generation_details)
	add_child(_generation_details_button)
	_generation_details_text = RichTextLabel.new()
	_generation_details_text.name = "GenerationDetails"
	_generation_details_text.fit_content = true
	_generation_details_text.custom_minimum_size.y = 60.0
	_generation_details_text.visible = false
	add_child(_generation_details_text)

	_preview = Preview.new()
	_preview.visible = false
	add_child(_preview)
	var playback_row := HBoxContainer.new()
	playback_row.name = "PlaybackControls"
	playback_row.visible = false
	add_child(playback_row)
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

	add_child(HSeparator.new())
	var save_title := Label.new()
	save_title.text = "Save native take"
	save_title.add_theme_font_size_override("font_size", 15)
	add_child(save_title)
	var save_grid := GridContainer.new()
	save_grid.columns = 2
	save_grid.add_theme_constant_override("h_separation", 12)
	save_grid.add_theme_constant_override("v_separation", 5)
	add_child(save_grid)
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
	_save_button.text = "Save Native Take"
	_save_button.disabled = true
	_save_button.pressed.connect(_on_save_native_take_pressed)
	add_child(_save_button)
	_save_status = Label.new()
	_save_status.name = "NativeTakeStatus"
	_save_status.text = "Generate a validated motion before saving."
	_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_save_status)


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


func _on_motion_ready() -> void:
	var motion: RefCounted = _generation_client.take_latest_motion()
	if not _preview.set_motion(motion):
		return
	_preview.visible = true
	var controls := _play_button.get_parent() as Control
	controls.visible = true
	_play_button.text = "Pause"
	_update_generation_availability()
	_update_save_availability()


func _on_play_pause_pressed() -> void:
	var next_playing: bool = not _preview.is_playing()
	_preview.set_playing(next_playing)
	_play_button.text = "Pause" if next_playing else "Play"


func _on_loop_toggled(enabled: bool) -> void:
	_preview.set_looping(enabled)


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
