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
const ProjectPaths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const GenerationTakePanel := preload("res://addons/kimodo_motion/ui/generation_take_panel.gd")
const PreviewSavePanel := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
const SessionShell := preload("res://addons/kimodo_motion/ui/session_shell.gd")
const HistoryPanel := preload("res://addons/kimodo_motion/ui/history_panel.gd")
const RigSetupPanel := preload("res://addons/kimodo_motion/ui/rig_setup_panel.gd")
const RigProfile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const RigMatcher := preload("res://addons/kimodo_motion/retargeting/rig_candidate_matcher.gd")
const RigProfileStore := preload("res://addons/kimodo_motion/retargeting/rig_profile_store.gd")
const RigCompatibility := preload("res://addons/kimodo_motion/retargeting/rig_compatibility.gd")
const TakeArchive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const AcceptanceService := preload(
	"res://addons/kimodo_motion/domain/acceptance_service.gd"
)
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
# Historical variable names retained locally; both hold the active KimodoSession.
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
var _generation_panel: Control
var _preview_panel: Control
var _history_panel: Control
var _rig_setup_panel: Control
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
var _follow_root_toggle: CheckButton
var _reset_camera_button: Button
var _character_target_picker: Control
var _character_clear_button: Button
var _character_status: Label
var _save_button: Button
var _save_status: Label
var _humanoid_fixture: PackedScene
var _character_target: PackedScene
var _rig_profile: Resource
var _rig_setup_skeleton: Skeleton3D
var _rig_setup_scene_path := ""
var _rig_setup_signature := ""
var _rig_setup_skeleton_path := NodePath()
var _acceptance_transactions: Array[RefCounted] = []
var _fallback_undo_redo: UndoRedo


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
	if _editor_plugin == null:
		_fallback_undo_redo = UndoRedo.new()
	_build_ui()
	_bind_session_inputs()
	_refresh_recent_sessions()
	_capture_workspace_visibility()
	_set_workspace_visible(false)
	_bind_client()
	_bind_generation_client()


func _exit_tree() -> void:
	_release_and_free_take_motions()
	if _rig_setup_skeleton != null:
		_rig_setup_skeleton.free()
		_rig_setup_skeleton = null
	_rig_setup_scene_path = ""
	_rig_setup_signature = ""
	_rig_setup_skeleton_path = NodePath()
	_rig_setup_panel.clear()
	if _fallback_undo_redo != null:
		_fallback_undo_redo.clear_history(false)
		_fallback_undo_redo.free()
		_fallback_undo_redo = null
	_acceptance_transactions.clear()


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
	_workspace_tabs = TabContainer.new()
	_workspace_tabs.name = "SessionWorkspace"
	_workspace_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(_workspace_tabs)

	_generation_panel = GenerationTakePanel.new()
	_workspace_tabs.add_child(_generation_panel)
	_bind_generation_panel_controls()

	_preview_panel = PreviewSavePanel.new()
	_workspace_tabs.add_child(_preview_panel)
	_bind_preview_panel_controls()

	_history_panel = HistoryPanel.new()
	_workspace_tabs.add_child(_history_panel)
	_history_panel.take_activated.connect(_on_history_take_activated)
	_history_panel.delete_confirmed.connect(_on_history_delete_confirmed)

	_rig_setup_panel = RigSetupPanel.new()
	_workspace_tabs.add_child(_rig_setup_panel)
	_rig_setup_panel.save_requested.connect(_on_save_rig_profile)


func _bind_generation_panel_controls() -> void:
	_url_edit = _generation_panel.url_edit
	_action_button = _generation_panel.connection_button
	_status_label = _generation_panel.connection_status
	_model_label = _generation_panel.model_label
	_fps_label = _generation_panel.fps_label
	_joints_label = _generation_panel.joints_label
	_constraints_label = _generation_panel.constraints_label
	_contacts_label = _generation_panel.contacts_label
	_details_button = _generation_panel.technical_details_button
	_details_text = _generation_panel.technical_details
	_character_target_picker = _generation_panel.target_picker
	_character_clear_button = _generation_panel.target_clear_button
	_character_status = _generation_panel.target_status
	_draft_status = _generation_panel.session_status
	_session_details_button = _generation_panel.session_details_button
	_draft_details = _generation_panel.session_details
	_prompt_edit = _generation_panel.prompt_edit
	_duration_edit = _generation_panel.duration_edit
	_seed_edit = _generation_panel.seed_edit
	_diffusion_steps_edit = _generation_panel.diffusion_steps_edit
	_take_count_edit = _generation_panel.take_count_edit
	_generate_button = _generation_panel.generate_button
	_generation_status = _generation_panel.generation_status
	_generation_details_button = _generation_panel.generation_details_button
	_generation_details_text = _generation_panel.generation_details

	_action_button.pressed.connect(_on_action_pressed)
	if _character_target_picker is EditorResourcePicker:
		(_character_target_picker as EditorResourcePicker).resource_changed.connect(
			_on_character_target_changed
		)
	_character_clear_button.pressed.connect(_on_clear_character_target_pressed)
	_draft_details.meta_clicked.connect(_on_draft_meta_clicked)
	_generate_button.pressed.connect(_on_generate_pressed)


func _bind_preview_panel_controls() -> void:
	_take_set = _preview_panel.take_set
	_take_selection = _preview_panel.take_selection
	_preview = _preview_panel.source_preview
	_humanoid_preview = _preview_panel.humanoid_preview
	_character_preview = _preview_panel.character_preview
	_preview_selection = _preview_panel.preview_selection
	_play_button = _preview_panel.play_button
	_loop_toggle = _preview_panel.loop_toggle
	_scrub_slider = _preview_panel.scrub_slider
	_follow_root_toggle = _preview_panel.follow_root_toggle
	_reset_camera_button = _preview_panel.reset_camera_button
	_save_button = _preview_panel.save_button
	_save_status = _preview_panel.save_status
	_preview_panel.take_activated.connect(_on_take_selected)
	_preview_panel.save_path_selected.connect(_on_save_path_selected)
	_preview_panel.accept_requested.connect(_on_accept_requested)


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
		_set_session_landing_error("Choose a current KimodoSession resource.")
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
	_restoring_draft = true
	_prompt_edit.text = session.prompt
	_duration_edit.value = session.duration_frames
	_seed_edit.value = session.seed
	_diffusion_steps_edit.value = session.diffusion_steps
	_take_count_edit.value = session.requested_take_count
	var target_resource: Resource = null
	if not session.target_scene_path.is_empty() and ResourceLoader.exists(session.target_scene_path):
		target_resource = ResourceLoader.load(
			session.target_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE
		)
	if _character_target_picker is EditorResourcePicker:
		(_character_target_picker as EditorResourcePicker).edited_resource = target_resource
	_on_character_target_changed(target_resource)
	_preview_panel.set_accept_destination(session.animation_destination)
	_restoring_draft = false
	_session_active_label.text = session.title
	_draft_status.modulate = Color(0.25, 0.85, 0.45)
	_draft_status.text = "Session ready. Generated takes are archived automatically."
	var recovered := int(load_result.get("recovered_generations", 0))
	if recovered > 0:
		_draft_status.text = "Recovered %d complete archived generation%s." % [
			recovered, "" if recovered == 1 else "s",
		]
	_history_panel.set_session(session)
	_history_panel.select_take(session.selected_take_id)
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
	_preview_panel.set_accept_destination("")
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
	if _generation_client != null:
		_generation_client.reset()
	if _generation_status != null:
		_generation_status.modulate = Color(0.7, 0.72, 0.76)
		_generation_status.text = "No archived take is loaded for preview."
	_update_generation_availability()


func _release_and_free_take_motions() -> void:
	if _preview_panel != null:
		_preview_panel.clear_takes()


func _on_take_selected(index: int) -> void:
	if index < 0 or index >= _take_set.size() or index != _take_set.active_index:
		return
	if not _preview_current_take_on_character():
		_set_draft_error("The selected take could not be previewed on the session character.")
		return
	if _draft != null:
		var takes: Array = _draft.active_take_summaries()
		if index < takes.size():
			_draft.selected_take_id = takes[index].get("take_id", "")
			_session_controller.mark_dirty()
	_update_save_availability()


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
		var available := 0
		for take in takes:
			if take.get("availability", "") == "available":
				available += 1
		_draft_details.append_text(
			"Archived takes: %d available of %d\n" % [available, takes.size()]
		)
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
	if _draft.acceptances.is_empty():
		_draft_details.append_text("\nAccepted animations: none")
	else:
		_draft_details.append_text("\nAccepted animations:\n")
		for acceptance in _draft.acceptances.values():
			_draft_details.append_text(
				"  %s (%s): " % [
					acceptance.get("animation_name", "unnamed"),
					acceptance.get("mode", "add"),
				]
			)
			_append_draft_path(String(acceptance.get("destination_path", "")))
			_draft_details.append_text("\n")


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
		_generation_panel.clear_capability_summary()
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
	_generation_panel.set_connection_details(details)
	_update_generation_availability()


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
	_generation_panel.set_generation_details(details)
	_update_generation_availability()


func _update_generation_availability() -> void:
	if _generate_button == null:
		return
	var generating: bool = (
		_generation_client != null
		and _generation_client.state == GenerationClient.GenerationState.GENERATING
	)
	var connected: bool = _client != null and _client.state == Client.ConnectionState.READY
	var ready_to_generate := connected and _draft != null and _character_target != null and _rig_profile != null
	_generate_button.disabled = not ready_to_generate and not generating
	_generate_button.text = "Cancel Generation" if generating else (
		"Generate Again" if _preview != null and _preview.has_motion() else "Generate"
	)
	_generation_panel.set_intent_editable(not generating)
	_action_button.disabled = generating
	_update_save_availability()


func _on_motion_ready() -> void:
	_release_and_free_take_motions()
	var received_motions: Array[RefCounted] = _generation_client.take_latest_motions()
	if received_motions.is_empty():
		_set_draft_error("The validated response did not contain any takes.")
		return
	_sync_draft_from_ui()
	_session_controller.mark_dirty()
	var archive_result: Dictionary = _session_controller.archive_generation(
		_generation_client.last_request_json,
		_client.last_response_json,
		_generation_client.last_response_bytes,
		_client.capabilities,
		received_motions,
	)
	if not _preview_panel.replace_takes(received_motions):
		_set_draft_error("The validated response could not be opened for preview.")
		return
	if not archive_result["ok"]:
		_set_draft_error(archive_result["message"])
		return
	if not _preview_current_take_on_character():
		_set_draft_error("The generated take could not be previewed on the selected character.")
		return
	_draft_status.modulate = Color(0.25, 0.85, 0.45)
	_draft_status.text = "%d take%s archived and ready." % [
		_take_set.size(), "" if _take_set.size() == 1 else "s",
	]
	_history_panel.set_session(_draft)
	_history_panel.select_take(_draft.selected_take_id)
	_update_draft_details()


func _on_history_take_activated(generation_index: int, take_id: String) -> void:
	if _draft == null or generation_index < 0 or generation_index >= _draft.generation_records.size():
		return
	var take := _find_session_take(take_id)
	if take.is_empty():
		_set_draft_error("The selected archived take is no longer in this session.")
		return
	var loaded := TakeArchive.load_motion(take)
	if not loaded["ok"]:
		_set_draft_error(loaded["message"])
		_history_panel.status.text = loaded["message"]
		return
	_release_and_free_take_motions()
	var motions: Array[RefCounted] = [loaded["motion"]]
	if not _preview_panel.replace_takes(motions):
		if is_instance_valid(loaded["motion"].scene):
			loaded["motion"].scene.free()
		_set_draft_error("The archived take could not be opened for preview.")
		return
	_draft.active_generation_index = generation_index
	_draft.selected_take_id = take_id
	if not _preview_current_take_on_character():
		_set_draft_error("The archived take could not be previewed on the selected character.")
		return
	_session_controller.mark_dirty()
	_draft_status.modulate = Color(0.25, 0.85, 0.45)
	_draft_status.text = "Archived take loaded offline and converted on demand."
	_history_panel.status.text = "Selected source archive is active in Preview & Save."
	_history_panel.select_take(take_id)
	_update_save_availability()
	_update_draft_details()


func _on_history_delete_confirmed(take_id: String) -> void:
	if _draft == null:
		return
	var was_selected: bool = _draft.selected_take_id == take_id
	var result := TakeArchive.delete_take(_draft, _draft_path, take_id)
	if not result["ok"]:
		_set_draft_error(result["message"])
		_history_panel.status.text = result["message"]
		return
	_session_controller.dirty = false
	if was_selected:
		_release_and_free_take_motions()
		_draft.selected_take_id = ""
		var fallback := _first_available_take()
		if not fallback.is_empty():
			_on_history_take_activated(fallback["generation_index"], fallback["take_id"])
	_history_panel.set_session(_draft)
	_history_panel.select_take(_draft.selected_take_id)
	_history_panel.status.text = "Archived source deleted; explicit saved artifacts were kept."
	_update_generation_availability()
	_update_draft_details()


func _find_session_take(take_id: String) -> Dictionary:
	if _draft == null:
		return {}
	for record in _draft.generation_records:
		for take in record.get("takes", []):
			if take.get("take_id", "") == take_id:
				return take.duplicate(true)
	return {}


func _first_available_take() -> Dictionary:
	if _draft == null:
		return {}
	for generation_index in range(_draft.generation_records.size() - 1, -1, -1):
		for take in _draft.generation_records[generation_index].get("takes", []):
			if take.get("availability", "") == "available":
				return {
					"generation_index": generation_index,
					"take_id": String(take.get("take_id", "")),
				}
	return {}


func _accept_source_motion(motion: RefCounted) -> bool:
	if motion == null:
		return false
	var motions: Array[RefCounted] = [motion]
	var accepted: bool = _preview_panel.replace_takes(motions)
	if accepted and _character_target != null:
		accepted = _preview_current_take_on_character()
	_update_generation_availability()
	return accepted


func _accept_source_motion_already_owned() -> bool:
	var accepted: bool = _preview_panel.has_source()
	_update_generation_availability()
	return accepted


func _preview_current_take_on_character() -> bool:
	if _character_target == null or _preview == null or not _preview.has_motion():
		return false
	_on_retarget_humanoid_pressed()
	if _humanoid_preview == null or not _humanoid_preview.has_motion():
		return false
	_on_preview_character_pressed()
	return _character_preview != null and _character_preview.has_motion()


func _on_loop_toggled(enabled: bool) -> void:
	_loop_toggle.button_pressed = enabled
	_preview_panel._on_loop_toggled(enabled)


func _on_follow_root_toggled(enabled: bool) -> void:
	_follow_root_toggle.button_pressed = enabled
	_preview_panel._on_follow_root_toggled(enabled)


func _on_camera_view_changed(yaw: float, pitch: float, distance: float) -> void:
	_preview_panel._on_camera_view_changed(yaw, pitch, distance)


func _seek_previews(time: float) -> void:
	_preview_panel.seek_all(time)


func _on_retarget_humanoid_pressed() -> void:
	_build_humanoid_preview()


func _build_humanoid_preview() -> bool:
	if not _preview_panel.has_source():
		_set_retarget_error("There is no validated generated motion to retarget.")
		return false
	var template_root: Node = (
		_humanoid_fixture.instantiate()
		if _humanoid_fixture != null
		else HumanoidFixture.create_scene()
	)
	if template_root == null:
		_set_retarget_error("The humanoid target fixture could not be created.")
		return false
	if _find_first_node(template_root, "Skeleton3D") == null:
		template_root.free()
		_set_retarget_error("The humanoid target fixture does not contain a Skeleton3D.")
		return false
	var motion: RefCounted = HumanoidRetargetBaker.create_motion(
		_preview.motion_scene(), template_root
	)
	template_root.free()
	if motion == null or not _preview_panel.set_humanoid_motion(motion):
		_set_retarget_error("The current motion could not be retargeted to the humanoid fixture.")
		return false
	_update_save_availability()
	return true


func _set_retarget_error(message: String) -> void:
	_set_draft_error(message)
	_preview_panel.show_save_error(message)


func _clear_humanoid_preview() -> void:
	if _preview_panel != null:
		_preview_panel.clear_humanoid()
	_update_save_availability()


func _update_retarget_availability() -> void:
	_update_save_availability()


func _on_character_target_changed(resource: Resource) -> void:
	if not _restoring_draft and _draft != null and not _flush_session():
		return
	_clear_character_preview()
	_character_target = null
	_rig_profile = null
	_rig_setup_panel.clear()
	if _rig_setup_skeleton != null:
		_rig_setup_skeleton.free()
		_rig_setup_skeleton = null
	_character_clear_button.disabled = resource == null
	if resource == null:
		_character_status.modulate = Color(0.7, 0.72, 0.76)
		_character_status.text = "Select a project-owned compatible PackedScene target."
		if not _restoring_draft and _draft != null:
			SessionStore.set_target(_draft, "", null)
			_draft.rig_profile_path = ""
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
	var error := _validate_character_structure(instance)
	if not error.is_empty():
		instance.free()
		_set_character_error(error)
		return
	var skeleton := _find_first_node(instance, "Skeleton3D") as Skeleton3D
	var scene_path := (resource as PackedScene).resource_path
	var signature := SessionStore.skeleton_signature(skeleton)
	if not _restoring_draft:
		if _draft == null:
			instance.free()
			_set_character_error("Open a session before selecting a character.")
			return
		var target_changed: bool = _draft.target_scene_path != scene_path or _draft.target_skeleton_signature != signature
		var target_result := SessionStore.set_target(_draft, scene_path, skeleton)
		if not target_result["ok"]:
			instance.free()
			_set_character_error(target_result["message"])
			return
		if target_changed:
			_draft.rig_profile_path = ""
	var bone_count := skeleton.get_bone_count()
	var skinned_meshes := 0
	for found in instance.find_children("*", "MeshInstance3D", true, false):
		if (found as MeshInstance3D).skin != null:
			skinned_meshes += 1
	_character_target = resource as PackedScene
	_rig_setup_skeleton = skeleton.duplicate() as Skeleton3D
	_rig_setup_scene_path = scene_path
	_rig_setup_signature = signature
	_rig_setup_skeleton_path = instance.get_path_to(skeleton)
	var suggestions: Dictionary = RigMatcher.suggest(_rig_setup_skeleton)
	var profile_result := {}
	if _draft != null and not _draft.rig_profile_path.is_empty():
		profile_result = RigProfileStore.load_current(_draft.rig_profile_path, skeleton, signature)
	if profile_result.get("ok", false):
		_rig_profile = profile_result["profile"]
	elif profile_result.get("code", "") != "stale_profile":
		var exact := RigProfile.exact_names(skeleton, instance.get_path_to(skeleton))
		if exact["ok"]:
			_rig_profile = exact["profile"]
			_rig_profile.target_scene_path = scene_path
			_rig_profile.target_scene_signature = FileAccess.get_sha256(scene_path)
			_rig_profile.certify(skeleton, signature)
	if _rig_profile != null:
		error = HumanoidCharacterBaker.validate_target(instance, _rig_profile)
		if not error.is_empty():
			_rig_profile = null
			instance.free()
			_set_character_error(error)
			return
		_character_status.modulate = Color(0.25, 0.85, 0.45)
		_character_status.text = "Compatible target: %d bones, %d skinned meshes%s." % [bone_count, skinned_meshes, " with saved rig profile" if profile_result.get("ok", false) else ""]
		_rig_setup_panel.configure(
			_rig_setup_skeleton,
			RigMatcher.reviewed(_rig_profile, suggestions),
			suggestions,
		)
	else:
		_rig_setup_panel.configure(_rig_setup_skeleton, suggestions)
		_workspace_tabs.current_tab = _rig_setup_panel.get_index()
		_character_status.modulate = Color(0.95, 0.72, 0.2)
		_character_status.text = ("The saved rig profile is stale. Review Rig Setup." if profile_result.get("code", "") == "stale_profile" else "This skeleton needs a reviewed rig profile. Open Rig Setup.")
	instance.free()
	if not _restoring_draft:
		_session_controller.mark_dirty()
		_session_controller.flush()
	if _preview_panel.has_source() and _rig_profile != null:
		if not _preview_panel.has_humanoid() and not _build_humanoid_preview():
			return
		if not _build_character_preview():
			return
	_update_draft_details()
	_update_character_availability()
	_update_generation_availability()


func _on_save_rig_profile(mapping: Dictionary, root_policy: String) -> void:
	if _draft == null or _character_target == null or _rig_setup_skeleton == null:
		_rig_setup_panel.show_error("Choose a character in an active session first.")
		return
	var frames: Dictionary = _rig_setup_panel.current_hand_frames()
	var issues := RigMatcher.diagnose(_rig_setup_skeleton, mapping, root_policy, frames)
	if not issues.is_empty():
		_rig_setup_panel.show_error("; ".join(issues))
		return
	var created := RigProfile.create(mapping, _rig_setup_skeleton_path, _rig_setup_skeleton, root_policy, "leg_height", frames)
	if not created["ok"]:
		_rig_setup_panel.show_error(created["message"])
		return
	var profile: Resource = created["profile"]
	profile.target_scene_path = _rig_setup_scene_path
	profile.target_scene_signature = FileAccess.get_sha256(_rig_setup_scene_path)
	var certified: Dictionary = profile.certify(_rig_setup_skeleton, _rig_setup_signature)
	if not certified["ok"]:
		_rig_setup_panel.show_error(certified["message"])
		return
	var path := RigProfileStore.suggested_path(_rig_setup_scene_path)
	var saved := RigProfileStore.save(profile, path)
	if not saved["ok"]:
		_rig_setup_panel.show_error(saved["message"])
		return
	_rig_profile = profile
	_draft.target_scene_path = _rig_setup_scene_path
	_draft.target_skeleton_signature = _rig_setup_signature
	_draft.rig_profile_path = saved["path"]
	_session_controller.mark_dirty()
	var flushed: Dictionary = _session_controller.flush()
	if not flushed["ok"]:
		_rig_profile = null
		_rig_setup_panel.show_error(flushed["message"])
		return
	var suggestions: Dictionary = RigMatcher.suggest(_rig_setup_skeleton)
	_rig_setup_panel.configure(
		_rig_setup_skeleton,
		RigMatcher.reviewed(profile, suggestions),
		suggestions,
	)
	_rig_setup_panel.show_saved(saved["path"])
	_character_status.modulate = Color(0.25, 0.85, 0.45)
	_character_status.text = "Compatible target with certified rig profile."
	if _preview_panel.has_source():
		if not _preview_panel.has_humanoid() and not _build_humanoid_preview():
			return
		if not _build_character_preview():
			return
	_workspace_tabs.current_tab = _generation_panel.get_index()
	_update_draft_details()
	_update_generation_availability()


func _validate_character_structure(character_root: Node) -> String:
	var compatibility := RigCompatibility.inspect(character_root)
	if not compatibility["ok"]:
		return compatibility["message"]
	if character_root.get_node_or_null(HumanoidCharacterBaker.PLAYER_NODE_NAME) != null:
		return "Character target already owns the reserved %s node" % HumanoidCharacterBaker.PLAYER_NODE_NAME
	return ""


func _on_clear_character_target_pressed() -> void:
	if _character_target_picker is EditorResourcePicker:
		(_character_target_picker as EditorResourcePicker).edited_resource = null
	_on_character_target_changed(null)


func _on_preview_character_pressed() -> void:
	_build_character_preview()


func _build_character_preview() -> bool:
	if _character_target == null:
		_set_character_error("Select a compatible character scene first.")
		return false
	if not _preview_panel.has_humanoid():
		_set_character_error("The generated take has no humanoid conversion.")
		return false
	var character_root := _character_target.instantiate() as Node3D
	if character_root == null:
		_set_character_error("The selected character scene could not be instantiated.")
		return false
	var motion: RefCounted = HumanoidCharacterBaker.create_motion(
		_humanoid_preview.motion_scene(), character_root, _rig_profile
	)
	if motion == null:
		character_root.free()
		_set_character_error("The humanoid motion could not be applied to this character.")
		return false
	if not _preview_panel.set_character_motion(motion):
		_set_character_error("The character preview could not accept the retargeted motion.")
		return false
	_character_status.modulate = Color(0.25, 0.85, 0.45)
	_character_status.text = "Character preview ready with editable animation 'motion'."
	_update_save_availability()
	return true


func _clear_character_preview() -> void:
	if _preview_panel != null:
		_preview_panel.clear_character()
	if _character_status != null and _character_target != null:
		_character_status.modulate = Color(0.7, 0.72, 0.76)
		_character_status.text = "Compatible target selected."
	_update_save_availability()


func _update_character_availability() -> void:
	_update_save_availability()


func _set_character_error(message: String) -> void:
	_character_status.modulate = Color(1.0, 0.35, 0.3)
	_character_status.text = message
	_rig_setup_panel.show_error(message)
	_preview_panel.show_save_error(message)
	_update_character_availability()
	_update_generation_availability()


func _on_save_path_selected(kind: int, requested_path: String) -> void:
	var extension := (
		"tscn" if kind == PreviewSavePanel.SaveKind.CHARACTER_PREVIEW else "res"
	)
	var validation := ProjectPaths.validate_file(requested_path, extension)
	if not validation["ok"]:
		_set_save_error(validation["message"])
		return
	var output_path: String = validation["path"]
	var directory := output_path.get_base_dir()
	var take_name := output_path.get_file().get_basename().strip_edges()
	if take_name.is_empty():
		_set_save_error("Choose a non-empty filename.")
		return
	if FileAccess.file_exists(output_path):
		_set_save_error("Choose a new filename; Kimodo never overwrites an existing output.")
		return
	if kind == PreviewSavePanel.SaveKind.CHARACTER_ANIMATION:
		_save_character_animation(directory, take_name)
	elif kind == PreviewSavePanel.SaveKind.HUMANOID_ANIMATION:
		_save_humanoid_animation(directory, take_name)
	elif kind == PreviewSavePanel.SaveKind.SOMA77_ANIMATION:
		_save_soma77_animation(directory, take_name)
	elif kind == PreviewSavePanel.SaveKind.CHARACTER_PREVIEW:
		_save_character_preview(directory, take_name)
	else:
		_set_save_error("Choose a supported output type.")


func _save_character_animation(directory: String, take_name: String) -> void:
	if not _preview_panel.has_character():
		_set_save_error("There is no converted character animation to save.")
		return
	var result := HumanoidCharacterBaker.save_library(
		_character_preview.motion_scene(), directory, take_name
	)
	if result.is_empty():
		_set_save_error("Godot could not save the character animation.")
		return
	_preview_panel.show_save_result(
		"Saved %s with animation '%s'." % [result["library_path"], result["animation_name"]]
	)
	_record_draft_artifact("character_animation", result["library_path"])
	_refresh_saved_resource(result["library_path"])


func _save_humanoid_animation(directory: String, take_name: String) -> void:
	if not _preview_panel.has_humanoid():
		_set_save_error("There is no converted humanoid take to save.")
		return
	var result := HumanoidRetargetBaker.save_library(
		_humanoid_preview.motion_scene(), directory, take_name
	)
	if result.is_empty():
		_set_save_error("Godot could not save the humanoid take.")
		return
	_preview_panel.show_save_result(
		"Saved %s" % result["library_path"]
	)
	_record_draft_artifact("humanoid_animation", result["library_path"])
	_refresh_saved_resource(result["library_path"])


func _save_soma77_animation(directory: String, take_name: String) -> void:
	if not _preview_panel.has_source():
		_set_save_error("There is no validated generated take to save.")
		return
	var result := NativeAnimationBaker.save_library(
		_preview.motion_scene(), directory, take_name
	)
	if result.is_empty():
		_set_save_error("Godot could not save the SOMA-77 take.")
		return
	_preview_panel.show_save_result(
		"Saved %s" % result["library_path"]
	)
	_record_draft_artifact("soma77_animation", result["library_path"])
	_refresh_saved_resource(result["library_path"])


func _save_character_preview(directory: String, take_name: String) -> void:
	if not _preview_panel.has_character():
		_set_save_error("There is no converted character preview to save.")
		return
	var result := HumanoidCharacterBaker.save_preview_scene(
		_character_preview.motion_scene(), directory, take_name
	)
	if result.is_empty():
		_set_save_error("Godot could not save the character preview.")
		return
	_preview_panel.show_save_result("Saved %s" % result["scene_path"])
	_record_draft_artifact("character_preview", result["scene_path"])
	_refresh_saved_resource(result["scene_path"])


func _set_character_save_error(message: String) -> void:
	_set_save_error(message)


func _record_draft_artifact(artifact_type: String, path: String) -> void:
	if _draft == null:
		return
	_sync_draft_from_ui()
	var take_id: String = _draft.selected_take_id if _draft != null else ""
	var rig_layer := "selected_character"
	if artifact_type == "humanoid_animation":
		rig_layer = "godot_humanoid"
	elif artifact_type == "soma77_animation":
		rig_layer = "soma77"
	var artifact_form := "preview_scene" if artifact_type == "character_preview" else "animation_library"
	var metadata := {
		"rig_layer": rig_layer,
		"artifact_form": artifact_form,
		"target_skeleton_signature": _draft.target_skeleton_signature if rig_layer == "selected_character" else "",
	}
	var result := SessionStore.record_artifact(
		_draft, artifact_type, path, take_id, metadata
	)
	if not result["ok"]:
		_set_draft_error(result["message"])
		return
	_session_controller.mark_dirty()
	_session_controller.flush()
	_update_draft_details()


func _set_save_error(message: String) -> void:
	_preview_panel.show_save_error(message)


func _on_accept_requested(
	destination_path: String, animation_name: String, replace_existing: bool
) -> void:
	if _draft == null or _draft_path.is_empty():
		_preview_panel.show_accept_error("Open a session before accepting animation.")
		return
	if not _preview_panel.has_character() or _character_target == null:
		_preview_panel.show_accept_error("Preview an available take on a character first.")
		return
	if not _flush_session():
		_preview_panel.show_accept_error("The session could not be saved before acceptance.")
		return
	var result := AcceptanceService.prepare(
		_draft,
		_draft_path,
		_character_preview.motion_scene(),
		_character_target,
		destination_path,
		animation_name,
		replace_existing,
	)
	if not result["ok"]:
		if result.get("code", "") == "name_collision":
			_preview_panel.confirm_replace(
				String(result.get("path", destination_path)),
				String(result.get("animation_name", animation_name)),
			)
		else:
			_preview_panel.show_accept_error(result["message"])
		return
	var transaction: RefCounted = result["transaction"]
	_acceptance_transactions.append(transaction)
	transaction.state_changed.connect(_on_acceptance_state_changed)
	transaction.apply_after()
	if not transaction.last_result["ok"]:
		_acceptance_transactions.erase(transaction)
		return
	var action_name := "%s Kimodo animation '%s'" % [
		"Replace" if result["mode"] == "replace" else "Accept",
		result["record"]["animation_name"],
	]
	if _editor_plugin != null and is_instance_valid(_editor_plugin):
		var editor_undo := _editor_plugin.get_undo_redo()
		editor_undo.create_action(action_name, UndoRedo.MERGE_DISABLE, _draft)
		editor_undo.add_do_method(transaction, &"apply_after")
		editor_undo.add_undo_method(transaction, &"apply_before")
		editor_undo.commit_action(false)
	else:
		_fallback_undo_redo.create_action(action_name)
		_fallback_undo_redo.add_do_method(Callable(transaction, "apply_after"))
		_fallback_undo_redo.add_undo_method(Callable(transaction, "apply_before"))
		_fallback_undo_redo.commit_action(false)


func _on_acceptance_state_changed(state: String, result: Dictionary) -> void:
	if not result["ok"]:
		_preview_panel.show_accept_error(result["message"])
		return
	_session_controller.dirty = false
	if state == "accepted":
		_preview_panel.set_accept_destination(result["path"])
		_preview_panel.show_accept_result(
			"Accepted '%s'. Use Godot Undo to restore the prior library."
			% result["animation_name"]
		)
		_refresh_saved_resource(result["path"])
	else:
		var undo_message := "Acceptance undone. Redo restores '%s'." % result["animation_name"]
		if result.get("created_destination", false):
			undo_message = (
				"Acceptance undone. The empty library was retained; Redo restores '%s'."
				% result["animation_name"]
			)
		_preview_panel.show_accept_result(undo_message)
	_update_draft_details()


func _update_save_availability() -> void:
	if _preview_panel == null:
		return
	var generating: bool = (
		_generation_client != null
		and _generation_client.state == GenerationClient.GenerationState.GENERATING
	)
	_preview_panel.set_save_availability(
		_preview_panel.has_source(),
		_preview_panel.has_humanoid(),
		_preview_panel.has_character(),
		generating,
	)
	_preview_panel.set_accept_availability(
		_preview_panel.has_character() and _draft != null and not _draft.selected_take_id.is_empty(),
		generating,
	)


func _refresh_saved_resource(scene_path: String) -> void:
	if _editor_plugin == null or not is_instance_valid(_editor_plugin):
		return
	var editor_interface := _editor_plugin.get_editor_interface()
	editor_interface.get_resource_filesystem().scan()
	editor_interface.get_file_system_dock().navigate_to_path(scene_path)


func _find_first_node(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first_node(child, type_name)
		if found != null:
			return found
	return null
