@tool
class_name AiMotionDock
extends VBoxContainer

const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const GenerationClient := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const GenerationOptions := preload("res://addons/kimodo_motion/domain/generation_options.gd")
const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const SessionController := preload(
	"res://addons/kimodo_motion/domain/motion_session_controller.gd"
)
const TransientTakeSet := preload("res://addons/kimodo_motion/domain/transient_take_set.gd")
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const Preview := preload("res://addons/kimodo_motion/ui/soma77_preview.gd")
const GenerationTakePanel := preload("res://addons/kimodo_motion/ui/generation_take_panel.gd")
const MotionPreviewPanel := preload("res://addons/kimodo_motion/ui/motion_preview_panel.gd")
const MotionOutputPanel := preload("res://addons/kimodo_motion/ui/motion_output_panel.gd")
const SessionShell := preload("res://addons/kimodo_motion/ui/session_shell.gd")
const NativeAnimationBaker := preload(
	"res://addons/kimodo_motion/animation/native_animation_baker.gd"
)
const HumanoidRetargetBaker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_retarget_baker.gd"
)
const HumanoidFixture := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_fixture.gd"
)
const HumanoidCharacterBaker := preload(
	"res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd"
)

var _client: Node
var _generation_client: Node
var _editor_plugin: EditorPlugin
# Kept as aliases during the lossless Goal 13 migration; both now hold a KimodoSession.
var _draft: Resource
var _draft_path := ""
var _restoring_draft := false
var _session_controller: Node
var _session_landing: Control
var _session_active_bar: Control
var _session_title_edit: LineEdit
var _session_resource_picker: Control
var _session_recent: OptionButton
var _session_status: Label
var _session_active_label: Label
var _session_save_state: Label
var _recent_sessions: Array[Dictionary] = []
var _workspace_start_index := 0
var _workspace_default_visibility: Dictionary = {}
var _workspace_tabs: TabContainer
var _draft_status: Label
var _session_details_button: Button
var _draft_details: RichTextLabel
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
var _take_count_edit: SpinBox
var _generate_button: Button
var _generation_status: Label
var _generation_details_button: Button
var _generation_details_text: RichTextLabel
var _take_selection: OptionButton
var _take_set: RefCounted
var _preview: Control
var _humanoid_preview: Control
var _character_preview: Control
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
var _character_target_picker: Control
var _character_clear_button: Button
var _character_preview_button: Button
var _character_status: Label
var _character_directory_edit: LineEdit
var _character_name_edit: LineEdit
var _character_save_button: Button
var _character_save_status: Label
var _save_directory_edit: LineEdit
var _save_name_edit: LineEdit
var _save_button: Button
var _save_status: Label
var _humanoid_fixture: PackedScene
var _character_target: PackedScene


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
	_session_controller = SessionController.new()
	_session_controller.name = "SessionController"
	add_child(_session_controller)
	_session_controller.save_state_changed.connect(_on_session_save_state_changed)
	_take_set = TransientTakeSet.new()
	_build_ui()
	_bind_session_inputs()
	_refresh_recent_sessions()
	_capture_workspace_visibility()
	_set_workspace_visible(false)
	_bind_client()
	_bind_generation_client()
	set_process(true)


func _exit_tree() -> void:
	_release_and_free_take_motions()


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
	subtitle.text = "Project-owned motion sessions"
	subtitle.modulate = Color(0.75, 0.78, 0.82)
	_content.add_child(subtitle)
	_build_session_landing()
	_workspace_start_index = _content.get_child_count()
	var root_content := _content
	_workspace_tabs = TabContainer.new()
	_workspace_tabs.name = "SessionWorkspace"
	_workspace_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_content.add_child(_workspace_tabs)
	var generation_panel := GenerationTakePanel.new()
	_workspace_tabs.add_child(generation_panel)
	_content = generation_panel

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

	_build_target_section()

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
	var takes_label := Label.new()
	takes_label.text = "Takes"
	options_grid.add_child(takes_label)
	_take_count_edit = SpinBox.new()
	_take_count_edit.name = "TakeCount"
	_take_count_edit.min_value = 1
	_take_count_edit.max_value = 2
	_take_count_edit.value = 1
	_take_count_edit.tooltip_text = "Tested range for this release: one or two takes."
	_take_count_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options_grid.add_child(_take_count_edit)

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
	_take_selection = OptionButton.new()
	_take_selection.name = "TakeSelection"
	_take_selection.visible = false
	_take_selection.item_selected.connect(_on_take_selected)
	_content.add_child(_take_selection)

	var preview_panel := MotionPreviewPanel.new()
	_workspace_tabs.add_child(preview_panel)
	_content = preview_panel

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
	_character_preview = Preview.new()
	_character_preview.configure("CharacterPreview", Color.WHITE, false)
	_character_preview.camera_view_changed.connect(_on_camera_view_changed)
	_character_preview.visible = false
	_content.add_child(_character_preview)
	_preview_selection = OptionButton.new()
	_preview_selection.name = "PreviewSelection"
	_preview_selection.add_item("SOMA-77 source")
	_preview_selection.add_item("Godot humanoid")
	_preview_selection.add_item("Skinned character")
	_preview_selection.set_item_disabled(2, true)
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

	var output_panel := MotionOutputPanel.new()
	_workspace_tabs.add_child(output_panel)
	_content = output_panel

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
	var character_title := Label.new()
	character_title.text = "Skinned character preview and output"
	character_title.add_theme_font_size_override("font_size", 15)
	_content.add_child(character_title)
	_character_preview_button = Button.new()
	_character_preview_button.name = "PreviewOnCharacter"
	_character_preview_button.text = "Preview on Character"
	_character_preview_button.disabled = true
	_character_preview_button.pressed.connect(_on_preview_character_pressed)
	_content.add_child(_character_preview_button)
	var character_save_grid := GridContainer.new()
	character_save_grid.columns = 2
	character_save_grid.add_theme_constant_override("h_separation", 12)
	character_save_grid.add_theme_constant_override("v_separation", 5)
	_content.add_child(character_save_grid)
	var character_directory_label := Label.new()
	character_directory_label.text = "Directory"
	character_save_grid.add_child(character_directory_label)
	_character_directory_edit = LineEdit.new()
	_character_directory_edit.name = "CharacterTakeDirectory"
	_character_directory_edit.text = "res://animations/kimodo"
	_character_directory_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_save_grid.add_child(_character_directory_edit)
	var character_name_label := Label.new()
	character_name_label.text = "Name"
	character_save_grid.add_child(character_name_label)
	_character_name_edit = LineEdit.new()
	_character_name_edit.name = "CharacterTakeName"
	_character_name_edit.text = "kimodo_character_motion"
	_character_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_save_grid.add_child(_character_name_edit)
	_character_save_button = Button.new()
	_character_save_button.name = "SaveCharacterTake"
	_character_save_button.text = "Save Character Take"
	_character_save_button.disabled = true
	_character_save_button.pressed.connect(_on_save_character_take_pressed)
	_content.add_child(_character_save_button)
	_character_save_status = Label.new()
	_character_save_status.name = "CharacterTakeStatus"
	_character_save_status.text = "Preview a motion on the selected character before saving."
	_character_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_character_save_status)

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
	_content = root_content


func _build_session_landing() -> void:
	var shell := SessionShell.new()
	_content.add_child(shell)
	shell.new_requested.connect(_on_new_session_pressed)
	shell.open_requested.connect(_on_open_session_pressed)
	shell.recent_requested.connect(_on_open_recent_session_pressed)
	shell.switch_requested.connect(_on_switch_session_pressed)
	_session_landing = shell.landing
	_session_active_bar = shell.active_bar
	_session_title_edit = shell.title_edit
	_session_resource_picker = shell.resource_picker
	_session_recent = shell.recent
	_session_status = shell.status
	_session_active_label = shell.active_label
	_session_save_state = shell.save_state


func _build_target_section() -> void:
	_content.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Character target"
	title.add_theme_font_size_override("font_size", 15)
	_content.add_child(title)
	var explanation := Label.new()
	explanation.text = "Choose a compatible project-owned character before generating."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color(0.75, 0.78, 0.82)
	_content.add_child(explanation)

	var target_label := Label.new()
	target_label.text = "Character scene"
	_content.add_child(target_label)
	var target_row := HBoxContainer.new()
	_content.add_child(target_row)
	if Engine.is_editor_hint():
		var editor_picker := EditorResourcePicker.new()
		editor_picker.base_type = "PackedScene"
		editor_picker.resource_changed.connect(_on_character_target_changed)
		_character_target_picker = editor_picker
	else:
		var test_picker := LineEdit.new()
		test_picker.editable = false
		test_picker.placeholder_text = "PackedScene target (editor picker)"
		_character_target_picker = test_picker
	_character_target_picker.name = "CharacterTarget"
	_character_target_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_row.add_child(_character_target_picker)
	_character_clear_button = Button.new()
	_character_clear_button.name = "ClearCharacterTarget"
	_character_clear_button.text = "Clear"
	_character_clear_button.disabled = true
	_character_clear_button.pressed.connect(_on_clear_character_target_pressed)
	target_row.add_child(_character_clear_button)
	_character_status = Label.new()
	_character_status.name = "CharacterStatus"
	_character_status.text = "Select a project-owned compatible PackedScene target."
	_character_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_character_status)

	_draft_status = Label.new()
	_draft_status.name = "SessionStatus"
	_draft_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_draft_status)
	_session_details_button = Button.new()
	_session_details_button.name = "SessionDetailsToggle"
	_session_details_button.text = "Show session details"
	_session_details_button.pressed.connect(_toggle_session_details)
	_content.add_child(_session_details_button)
	_draft_details = RichTextLabel.new()
	_draft_details.name = "SessionDetails"
	_draft_details.bbcode_enabled = true
	_draft_details.fit_content = true
	_draft_details.custom_minimum_size.y = 72.0
	_draft_details.visible = false
	_draft_details.meta_clicked.connect(_on_draft_meta_clicked)
	_content.add_child(_draft_details)


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


func _set_workspace_visible(visible: bool) -> void:
	if _content == null:
		return
	for index in range(_workspace_start_index, _content.get_child_count()):
		var item := _content.get_child(index) as CanvasItem
		item.visible = visible and bool(_workspace_default_visibility.get(item.get_instance_id(), true))
	_session_landing.visible = not visible
	_session_active_bar.visible = visible


func _capture_workspace_visibility() -> void:
	_workspace_default_visibility.clear()
	for index in range(_workspace_start_index, _content.get_child_count()):
		var item := _content.get_child(index) as CanvasItem
		_workspace_default_visibility[item.get_instance_id()] = item.visible


func _refresh_recent_sessions() -> void:
	_recent_sessions = SessionStore.list_sessions()
	_session_recent.clear()
	if _recent_sessions.is_empty():
		_session_recent.add_item("No recent sessions")
		_session_recent.disabled = true
		return
	_session_recent.disabled = false
	for entry in _recent_sessions:
		_session_recent.add_item("%s — %s" % [entry["title"], entry["updated_at_utc"]])


func _on_new_session_pressed() -> void:
	var result: Dictionary = _session_controller.create(_session_title_edit.text)
	if not result["ok"]:
		_set_session_landing_error(result["message"])
		return
	_activate_session(result["session"], result["path"], {})


func _on_open_session_pressed() -> void:
	var path := ""
	if _session_resource_picker is EditorResourcePicker:
		var selected := (_session_resource_picker as EditorResourcePicker).edited_resource
		if selected != null:
			path = selected.resource_path
	elif _session_resource_picker is LineEdit:
		path = (_session_resource_picker as LineEdit).text.strip_edges()
	if path.is_empty():
		_set_session_landing_error("Choose a KimodoSession or Goal 13 MotionDraft resource.")
		return
	_open_session_path(path)


func _on_open_recent_session_pressed() -> void:
	var index := _session_recent.selected
	if index < 0 or index >= _recent_sessions.size():
		_set_session_landing_error("There is no recent session to open.")
		return
	_open_session_path(_recent_sessions[index]["path"])


func _open_session_path(path: String) -> void:
	var result: Dictionary = _session_controller.open(path)
	if not result["ok"]:
		_set_session_landing_error(result["message"])
		return
	_activate_session(result["session"], result["path"], result)


func _activate_session(session: Resource, path: String, load_result: Dictionary) -> void:
	_draft = session
	_draft_path = path
	_clear_generated_previews()
	_prompt_edit.text = session.prompt
	_duration_edit.value = session.duration_frames
	_seed_edit.value = session.seed
	_diffusion_steps_edit.value = session.diffusion_steps
	_take_count_edit.value = session.requested_take_count
	_restoring_draft = true
	var target_resource: Resource = null
	if not session.target_scene_path.is_empty() and ResourceLoader.exists(session.target_scene_path):
		target_resource = ResourceLoader.load(
			session.target_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE
		)
	if _character_target_picker is EditorResourcePicker:
		(_character_target_picker as EditorResourcePicker).edited_resource = target_resource
	_on_character_target_changed(target_resource)
	_restoring_draft = false
	_session_active_label.text = session.title
	_draft_status.modulate = Color(0.25, 0.85, 0.45)
	_draft_status.text = "Session ready. Unsaved take previews are intentionally transient."
	if not String(load_result.get("migrated_from", "")).is_empty():
		_draft_status.text = "Migrated Goal 13 draft to %s; the original was left unchanged." % path
	_set_workspace_visible(true)
	_update_draft_details()
	_update_generation_availability()
	_refresh_recent_sessions()


func _on_switch_session_pressed() -> void:
	if not _flush_session():
		return
	var result: Dictionary = _session_controller.close()
	if not result["ok"]:
		_set_draft_error(result["message"])
		return
	_draft = null
	_draft_path = ""
	_clear_generated_previews()
	_set_workspace_visible(false)
	_refresh_recent_sessions()


func _set_session_landing_error(message: String) -> void:
	_session_status.modulate = Color(1.0, 0.35, 0.3)
	_session_status.text = message


func _on_session_save_state_changed(state: String, message: String) -> void:
	if _session_save_state == null:
		return
	_session_save_state.text = message
	_session_save_state.modulate = (
		Color(1.0, 0.35, 0.3) if state == "error" else
		Color(0.95, 0.72, 0.2) if state == "saving" else Color(0.25, 0.85, 0.45)
	)


func _bind_session_inputs() -> void:
	_prompt_edit.text_changed.connect(_on_session_input_changed)
	_duration_edit.value_changed.connect(_on_session_value_changed)
	_seed_edit.value_changed.connect(_on_session_value_changed)
	_diffusion_steps_edit.value_changed.connect(_on_session_value_changed)
	_take_count_edit.value_changed.connect(_on_session_value_changed)


func _on_session_input_changed() -> void:
	_mark_session_dirty()


func _on_session_value_changed(_value: float) -> void:
	_mark_session_dirty()


func _mark_session_dirty() -> void:
	if _restoring_draft or _draft == null:
		return
	_sync_draft_from_ui()
	_session_controller.mark_dirty()


func _flush_session() -> bool:
	if _draft == null:
		return false
	_sync_draft_from_ui()
	_session_controller.mark_dirty()
	var result: Dictionary = _session_controller.flush()
	if not result["ok"]:
		_set_draft_error(result["message"])
		return false
	return true


func _clear_generated_previews() -> void:
	_release_and_free_take_motions()
	if _preview != null:
		_preview.clear_motion()
		_preview.visible = false
	_clear_humanoid_preview()
	if _generation_status != null:
		_generation_status.modulate = Color(0.7, 0.72, 0.76)
		_generation_status.text = "No transient takes are loaded for this session."
	if _save_status != null:
		_save_status.modulate = Color(0.7, 0.72, 0.76)
		_save_status.text = "Generate a validated motion before saving."
	var playback_controls := _play_button.get_parent() as Control
	playback_controls.visible = false
	var camera_controls := _follow_root_toggle.get_parent() as Control
	camera_controls.visible = false
	_update_generation_availability()


func _release_and_free_take_motions() -> void:
	_take_set.clear(_preview)
	if _take_selection != null:
		_take_selection.clear()
		_take_selection.visible = false


func _on_take_selected(index: int) -> void:
	if index < 0 or index >= _take_set.size() or index == _take_set.active_index:
		return
	var position: float = _preview.current_position()
	var playing: bool = _preview.is_playing()
	_clear_humanoid_preview()
	if not _take_set.activate(index, _preview):
		_set_draft_error("The selected transient take is no longer available.")
		return
	_preview.visible = true
	_preview.set_looping(_loop_toggle.button_pressed)
	_preview.seek(position)
	_preview.set_playing(playing)
	_play_button.text = "Pause" if playing else "Play"
	if not _preview_current_take_on_character():
		_set_draft_error("The selected take could not be previewed on the session character.")
		return
	if _draft != null:
		var takes: Array = _draft.active_take_summaries()
		if index < takes.size():
			_draft.selected_take_id = takes[index].get("take_id", "")
			_session_controller.mark_dirty()
	_update_save_availability()
	_update_retarget_availability()


func _ensure_draft() -> Resource:
	return _draft


func _sync_draft_from_ui() -> void:
	var draft := _ensure_draft()
	if draft == null:
		return
	SessionStore.sync_editable_intent(
		draft,
		_prompt_edit.text,
		int(_duration_edit.value),
		int(_seed_edit.value),
		int(_diffusion_steps_edit.value),
		int(_take_count_edit.value),
	)


func _update_draft_details() -> void:
	if _draft_details == null:
		return
	_draft_details.clear()
	if _draft == null:
		_draft_details.append_text("No session is open.")
		return
	_draft_details.append_text("Session ID: %s\n" % _draft.session_id)
	_draft_details.append_text("Target: ")
	_append_draft_path(_draft.target_scene_path)
	_draft_details.append_text("\n")
	var record: Dictionary = _draft.active_generation_record()
	if record.is_empty():
		_draft_details.append_text("Provenance: no validated generation recorded\n")
	else:
		_draft_details.append_text(
			"Provenance: %s · MMCP %s · %.0f fps · %s\n" % [
				record.get("model_id", "unknown"),
				record.get("protocol_version", "unknown"),
				float(record.get("fps", 0.0)),
				record.get("generated_at_utc", "unknown time"),
			]
		)
		_draft_details.append_text("Request: %s  Response: %s\n" % [
			String(record.get("request_sha256", "")).left(12),
			String(record.get("response_sha256", "")).left(12),
		])
		var takes: Array = record.get("takes", [])
		_draft_details.append_text("Take summaries: %d (payloads are transient)\n" % takes.size())
	var artifact_types: Array[String] = []
	for artifact_type in _draft.artifacts:
		artifact_types.append(String(artifact_type))
	artifact_types.sort()
	if artifact_types.is_empty():
		_draft_details.append_text("Artifacts: none saved")
	else:
		_draft_details.append_text("Artifacts:\n")
		for artifact_type in artifact_types:
			var entry: Variant = _draft.artifacts[artifact_type]
			var artifact_path := String(entry.get("path", "")) if entry is Dictionary else ""
			var availability := "available" if FileAccess.file_exists(artifact_path) else "missing"
			_draft_details.append_text("  %s (%s): " % [artifact_type, availability])
			_append_draft_path(artifact_path)
			_draft_details.append_text("\n")


func _toggle_session_details() -> void:
	_draft_details.visible = not _draft_details.visible
	_session_details_button.text = (
		"Hide session details" if _draft_details.visible else "Show session details"
	)


func _append_draft_path(path: String) -> void:
	if path.is_empty():
		_draft_details.append_text("none")
		return
	_draft_details.push_meta(path)
	_draft_details.append_text(path)
	_draft_details.pop()


func _on_draft_meta_clicked(meta: Variant) -> void:
	var path := String(meta)
	var validation := ProjectPaths.validate_file(path)
	if not validation["ok"] or not FileAccess.file_exists(validation["path"]):
		_set_draft_error("The selected session artifact is unavailable: %s" % path)
		return
	_refresh_saved_resource(validation["path"])


func _set_draft_error(message: String) -> void:
	_draft_status.modulate = Color(1.0, 0.35, 0.3)
	_draft_status.text = message


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
		_take_count_edit.max_value = mini(2, model.max_num_samples)
		_take_count_edit.value = mini(int(_take_count_edit.value), int(_take_count_edit.max_value))

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
	if _draft == null or _character_target == null:
		_set_draft_error("Open a session and choose a compatible character before generating.")
		return
	if not _flush_session():
		return
	var options := GenerationOptions.new()
	options.prompt = _prompt_edit.text
	options.duration_frames = int(_duration_edit.value)
	options.seed = int(_seed_edit.value)
	options.diffusion_steps = int(_diffusion_steps_edit.value)
	options.num_samples = int(_take_count_edit.value)
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
	var ready_to_generate := connected and _draft != null and _character_target != null
	_generate_button.disabled = not ready_to_generate and not generating
	_generate_button.text = "Cancel Generation" if generating else (
		"Generate Again" if _preview != null and _preview.has_motion() else "Generate"
	)
	_prompt_edit.editable = not generating
	_duration_edit.editable = not generating
	_seed_edit.editable = not generating
	_diffusion_steps_edit.editable = not generating
	_take_count_edit.editable = not generating
	_action_button.disabled = generating
	_update_save_availability()
	_update_retarget_availability()


func _on_motion_ready() -> void:
	_release_and_free_take_motions()
	var received_motions: Array[RefCounted] = _generation_client.take_latest_motions()
	_take_set.replace(received_motions, _preview)
	if _take_set.is_empty():
		_set_draft_error("The validated response did not contain any takes.")
		return
	_sync_draft_from_ui()
	var provenance_result := SessionStore.append_generation_record(
		_draft,
		_generation_client.last_request_json,
		_client.last_response_json,
		_generation_client.last_response_bytes,
		_client.capabilities,
		_take_set.motions,
	)
	if not provenance_result["ok"]:
		_set_draft_error(provenance_result["message"])
		_release_and_free_take_motions()
	else:
		_take_selection.clear()
		for index in _take_set.size():
			_take_selection.add_item("Take %d — %s" % [index + 1, _take_set.at(index).animation_name])
		_take_selection.visible = _take_set.size() > 1
		if not _take_set.activate(0, _preview):
			_release_and_free_take_motions()
			return
		if not _accept_source_motion_already_owned():
			_release_and_free_take_motions()
			return
		if not _preview_current_take_on_character():
			_set_draft_error("The generated take could not be previewed on the selected character.")
			return
		_take_selection.select(0)
		_draft_status.modulate = Color(0.25, 0.85, 0.45)
		_draft_status.text = "%d transient take%s ready; provenance autosaved." % [
			_take_set.size(), "" if _take_set.size() == 1 else "s",
		]
		_session_controller.mark_dirty()
		_flush_session()
		_update_draft_details()


func _accept_source_motion(motion: RefCounted) -> bool:
	_clear_humanoid_preview()
	if not _preview.set_motion(motion):
		_update_retarget_availability()
		_update_save_availability()
		return false
	return _accept_source_motion_already_owned()


func _accept_source_motion_already_owned() -> bool:
	_clear_humanoid_preview()
	if not _preview.has_motion():
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


func _preview_current_take_on_character() -> bool:
	if _character_target == null or _preview == null or not _preview.has_motion():
		return false
	_on_retarget_humanoid_pressed()
	if _humanoid_preview == null or not _humanoid_preview.has_motion():
		return false
	_on_preview_character_pressed()
	return _character_preview != null and _character_preview.has_motion()


func _on_play_pause_pressed() -> void:
	var next_playing: bool = not _preview.is_playing()
	_preview.set_playing(next_playing)
	_humanoid_preview.set_playing(next_playing)
	_character_preview.set_playing(next_playing)
	_play_button.text = "Pause" if next_playing else "Play"


func _on_loop_toggled(enabled: bool) -> void:
	_preview.set_looping(enabled)
	_humanoid_preview.set_looping(enabled)
	_character_preview.set_looping(enabled)


func _on_camera_view_changed(yaw: float, pitch: float, distance: float) -> void:
	_preview.set_camera_view(yaw, pitch, distance)
	_humanoid_preview.set_camera_view(yaw, pitch, distance)
	_character_preview.set_camera_view(yaw, pitch, distance)


func _on_follow_root_toggled(enabled: bool) -> void:
	_preview.set_camera_follow_root(enabled)
	_humanoid_preview.set_camera_follow_root(enabled)
	_character_preview.set_camera_follow_root(enabled)


func _on_reset_camera_pressed() -> void:
	_preview.reset_camera_view()
	var view: Dictionary = _preview.camera_view()
	_humanoid_preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])
	_character_preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])


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
	_character_preview.seek(time)


func _on_preview_selected(index: int) -> void:
	_preview.visible = index == 0 and _preview.has_motion()
	_humanoid_preview.visible = index == 1 and _humanoid_preview.has_motion()
	_character_preview.visible = index == 2 and _character_preview.has_motion()


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
	if motion == null:
		_set_retarget_error("The current motion could not be retargeted to the humanoid fixture.")
		return
	_clear_character_preview()
	if not _humanoid_preview.set_motion(motion):
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
	_clear_character_preview()
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
	if _retarget_status != null:
		_retarget_status.modulate = Color(0.7, 0.72, 0.76)
		_retarget_status.text = (
			"Retarget the current generated motion."
			if _preview != null and _preview.has_motion()
			else "Generate a validated motion before retargeting."
		)
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
	_update_character_availability()


func _on_save_humanoid_take_pressed() -> void:
	var directory := _humanoid_directory_edit.text.strip_edges()
	var take_name := _humanoid_name_edit.text.strip_edges()
	var directory_result := ProjectPaths.validate_directory(directory)
	if not directory_result["ok"]:
		_set_humanoid_save_error(directory_result["message"])
		return
	directory = directory_result["path"]
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
	_record_draft_artifact("humanoid_scene", result["scene_path"])
	_record_draft_artifact("humanoid_library", result["library_path"])
	_refresh_saved_resource(result["scene_path"])


func _set_humanoid_save_error(message: String) -> void:
	_humanoid_save_status.modulate = Color(1.0, 0.35, 0.3)
	_humanoid_save_status.text = message


func _on_character_target_changed(resource: Resource) -> void:
	if not _restoring_draft and _draft != null and not _flush_session():
		return
	_clear_character_preview()
	_character_target = null
	_character_clear_button.disabled = resource == null
	if resource == null:
		_character_status.modulate = Color(0.7, 0.72, 0.76)
		_character_status.text = "Select a project-owned compatible PackedScene target."
		if not _restoring_draft and _draft != null:
			SessionStore.set_target(_draft, "", null)
			_session_controller.mark_dirty()
			_session_controller.flush()
			_update_draft_details()
		_update_character_availability()
		_update_generation_availability()
		return
	if not resource is PackedScene:
		_set_character_error("Character target must be a PackedScene resource.")
		return
	var instance := (resource as PackedScene).instantiate()
	if not instance is Node3D:
		instance.free()
		_set_character_error("Character target root must be a Node3D.")
		return
	var error := HumanoidCharacterBaker.validate_target(instance)
	if not error.is_empty():
		instance.free()
		_set_character_error(error)
		return
	var skeleton := _find_first_node(instance, "Skeleton3D") as Skeleton3D
	var scene_path := (resource as PackedScene).resource_path
	var signature := SessionStore.skeleton_signature(skeleton)
	if _restoring_draft:
		if (
			not _draft.target_skeleton_signature.is_empty()
			and _draft.target_skeleton_signature != signature
		):
			instance.free()
			_set_character_error("The session target skeleton has changed since it was recorded.")
			return
	else:
		if _draft == null:
			instance.free()
			_set_character_error("Open a session before selecting a character.")
			return
		var target_result := SessionStore.set_target(_draft, scene_path, skeleton)
		if not target_result["ok"]:
			instance.free()
			_set_character_error(target_result["message"])
			return
	var bone_count := skeleton.get_bone_count()
	var skinned_meshes := 0
	for found in instance.find_children("*", "MeshInstance3D", true, false):
		if (found as MeshInstance3D).skin != null:
			skinned_meshes += 1
	instance.free()
	_character_target = resource as PackedScene
	_character_status.modulate = Color(0.25, 0.85, 0.45)
	_character_status.text = "Compatible target: %d bones, %d skinned meshes." % [
		bone_count, skinned_meshes,
	]
	if not _restoring_draft:
		_session_controller.mark_dirty()
		_session_controller.flush()
	_update_draft_details()
	_update_character_availability()
	_update_generation_availability()


func _on_clear_character_target_pressed() -> void:
	if _character_target_picker is EditorResourcePicker:
		(_character_target_picker as EditorResourcePicker).edited_resource = null
	_on_character_target_changed(null)


func _on_preview_character_pressed() -> void:
	if _character_target == null:
		_set_character_error("Select a compatible character scene first.")
		return
	if _humanoid_preview == null or not _humanoid_preview.has_motion():
		_set_character_error("Retarget the current motion to the Godot humanoid first.")
		return
	var character_root := _character_target.instantiate() as Node3D
	if character_root == null:
		_set_character_error("The selected character scene could not be instantiated.")
		return
	var motion: RefCounted = HumanoidCharacterBaker.create_motion(
		_humanoid_preview.motion_scene(), character_root
	)
	if motion == null:
		character_root.free()
		_set_character_error("The humanoid motion could not be applied to this character.")
		return
	if not _character_preview.set_motion(motion):
		_set_character_error("The character preview could not accept the retargeted motion.")
		return
	_character_preview.set_looping(_loop_toggle.button_pressed)
	_character_preview.seek(_preview.current_position())
	_character_preview.set_playing(_preview.is_playing())
	_character_preview.set_camera_follow_root(_follow_root_toggle.button_pressed)
	var view: Dictionary = _preview.camera_view()
	_character_preview.set_camera_view(view["yaw"], view["pitch"], view["distance"])
	_preview_selection.visible = true
	_preview_selection.disabled = false
	_preview_selection.set_item_disabled(2, false)
	_preview_selection.select(2)
	_on_preview_selected(2)
	_character_status.modulate = Color(0.25, 0.85, 0.45)
	_character_status.text = "Character preview ready with editable animation 'motion'."
	_character_save_status.modulate = Color(0.7, 0.72, 0.76)
	_character_save_status.text = "Character preview is ready to save."
	_update_character_availability()


func _clear_character_preview() -> void:
	if _character_preview != null:
		_character_preview.clear_motion()
		_character_preview.visible = false
	if _preview_selection != null and _preview_selection.selected == 2:
		if _humanoid_preview != null and _humanoid_preview.has_motion():
			_preview_selection.select(1)
			_on_preview_selected(1)
		else:
			_preview_selection.select(0)
	if _preview_selection != null:
		_preview_selection.set_item_disabled(2, true)
	if _character_save_status != null:
		_character_save_status.modulate = Color(0.7, 0.72, 0.76)
		_character_save_status.text = "Preview a motion on the selected character before saving."
	if _character_status != null and _character_target != null:
		_character_status.modulate = Color(0.7, 0.72, 0.76)
		_character_status.text = "Compatible target selected; preview the current humanoid motion."
	_update_character_availability()


func _update_character_availability() -> void:
	if _character_preview_button == null:
		return
	var generating: bool = (
		_generation_client != null
		and _generation_client.state == GenerationClient.GenerationState.GENERATING
	)
	_character_preview_button.disabled = (
		generating
		or _character_target == null
		or _humanoid_preview == null
		or not _humanoid_preview.has_motion()
	)
	_character_save_button.disabled = (
		generating or _character_preview == null or not _character_preview.has_motion()
	)


func _on_save_character_take_pressed() -> void:
	var directory := _character_directory_edit.text.strip_edges()
	var take_name := _character_name_edit.text.strip_edges()
	var directory_result := ProjectPaths.validate_directory(directory)
	if not directory_result["ok"]:
		_set_character_save_error(directory_result["message"])
		return
	directory = directory_result["path"]
	if take_name.is_empty():
		_set_character_save_error("Take name cannot be empty.")
		return
	if _character_preview == null or not _character_preview.has_motion():
		_set_character_save_error("There is no skinned character motion to save.")
		return
	var result := HumanoidCharacterBaker.save_motion(
		_character_preview.motion_scene(), directory, take_name
	)
	if result.is_empty():
		_set_character_save_error(
			"Godot could not save the character take. See the Output panel for details."
		)
		return
	_character_save_status.modulate = Color(0.25, 0.85, 0.45)
	_character_save_status.text = "Saved %s with animation '%s'." % [
		result["scene_path"], result["animation_name"],
	]
	_record_draft_artifact("character_scene", result["scene_path"])
	_refresh_saved_resource(result["scene_path"])


func _set_character_error(message: String) -> void:
	_character_status.modulate = Color(1.0, 0.35, 0.3)
	_character_status.text = message
	_update_character_availability()


func _set_character_save_error(message: String) -> void:
	_character_save_status.modulate = Color(1.0, 0.35, 0.3)
	_character_save_status.text = message


func _on_save_native_take_pressed() -> void:
	var directory := _save_directory_edit.text.strip_edges()
	var take_name := _save_name_edit.text.strip_edges()
	var directory_result := ProjectPaths.validate_directory(directory)
	if not directory_result["ok"]:
		_set_save_error(directory_result["message"])
		return
	directory = directory_result["path"]
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
	_record_draft_artifact("soma77_scene", result["scene_path"])
	_record_draft_artifact("soma77_library", result["library_path"])
	_refresh_saved_resource(result["scene_path"])


func _record_draft_artifact(artifact_type: String, path: String) -> void:
	if _draft == null:
		return
	_sync_draft_from_ui()
	var take_id: String = _draft.selected_take_id if _draft != null else ""
	var result := SessionStore.record_artifact(_draft, artifact_type, path, take_id)
	if not result["ok"]:
		_set_draft_error(result["message"])
		return
	_session_controller.mark_dirty()
	_session_controller.flush()
	_update_draft_details()


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
