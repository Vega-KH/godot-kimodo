@tool
class_name KimodoPoseLibraryPanel
extends VBoxContainer

signal character_pose_applied(target: Skeleton3D)

const Pose := preload("res://addons/kimodo_motion/poses/pose_asset.gd")
const Service := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const AnimationHash := preload("res://addons/kimodo_motion/domain/acceptance_service.gd")
const DIRECTORY := "res://animations/kimodo/poses"

var editor_plugin: EditorPlugin
var skeleton: Skeleton3D
var player: AnimationPlayer
var pose: Resource
var animation_selector: OptionButton
var pose_list: ItemList
var bone_list: ItemList
var title_edit: LineEdit
var frame_label: Label
var position_check: CheckBox
var rotation_check: CheckBox
var scale_check: CheckBox
var root_check: CheckBox
var status: Label
var target_label: Label
var save_dialog: FileDialog
var open_dialog: FileDialog
var replace_dialog: ConfirmationDialog
var _preview_before: Resource
var _preview_target: WeakRef
var _fallback_undo := UndoRedo.new()
var _pending_key: Dictionary = {}
var _library_paths: Array[String] = []
var _library_directory := DIRECTORY
var _observed_animation: StringName
var _observed_time := -1.0
var prepare_constraint: Callable
var queue_constraint: Callable
var remove_constraint: Callable
var constraint_list: ItemList
var constraint_dialog: ConfirmationDialog
var conversion_details: TextEdit
var _constraint_entry: Dictionary = {}
var _constraint_frames: Array[int] = []
var _preview_player: WeakRef
var _preview_was_playing := false


func _ready() -> void:
	name = "Pose Library"
	custom_minimum_size.x = 330
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var content := VBoxContainer.new()
	var common := content
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	_button(content, "Use selected character", _use_selection)
	target_label = _label(content, "Select a character, Skeleton3D or AnimationPlayer.")
	title_edit = LineEdit.new()
	title_edit.placeholder_text = "Pose name / editable animation name"
	content.add_child(title_edit)
	animation_selector = OptionButton.new()
	animation_selector.disabled = true
	animation_selector.tooltip_text = "Follows the animation being edited in Godot's Animation panel."
	content.add_child(animation_selector)
	frame_label = _label(content, "Open this AnimationPlayer in Godot's Animation panel and select a frame.")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 460
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	common.add_child(tabs)
	var library_content := _tab(tabs, "Library")
	var edit_content := _tab(tabs, "Capture")
	var timeline_content := _tab(tabs, "Constraints")
	content = edit_content
	_label(content, "Selected bones (Ctrl/Shift for multiple)")
	bone_list = ItemList.new()
	bone_list.select_mode = ItemList.SELECT_MULTI
	bone_list.custom_minimum_size.y = 120
	content.add_child(bone_list)
	_button(content, "Select all bones", func() -> void:
		for index in bone_list.item_count:
			bone_list.select(index, false)
	)
	var channel_row := HBoxContainer.new()
	content.add_child(channel_row)
	position_check = _check(channel_row, "Position", false)
	rotation_check = _check(channel_row, "Rotation", true)
	scale_check = _check(channel_row, "Scale", false)
	root_check = _check(content, "Include skeleton root channels", false)
	_label(content, "Edit bones in Godot, then capture their current values.")
	_button(content, "Capture current frame", capture_current)
	_button(content, "Capture edits to opened pose channels", capture_pose_edits)
	_button(content, "Save pose as…", _save_as)
	content = library_content
	_button(content, "Open pose…", func() -> void: open_dialog.popup_centered_ratio(0.7))
	_button(content, "Refresh saved poses", refresh_library)
	pose_list = ItemList.new()
	pose_list.custom_minimum_size.y = 120
	pose_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(pose_list)
	pose_list.item_selected.connect(func(index: int) -> void: open_pose(_library_paths[index]))
	_button(content, "Preview pose", preview_pose)
	_button(content, "Cancel preview", cancel_preview)
	_button(content, "Apply pose", apply_pose)
	_button(content, "Apply & Key at current frame", request_key)
	_button(content, "Copy selected animation for editing", copy_animation)
	_button(content, "Save pose as…", _save_as)
	content = timeline_content
	_label(content, "Kimodo full-body constraints (active AI Motion session)")
	_button(content, "Queue current frame…", _prepare_constraint)
	constraint_list = ItemList.new()
	constraint_list.custom_minimum_size.y = 80
	content.add_child(constraint_list)
	_button(content, "Remove selected constraint", func() -> void:
		var selected := constraint_list.get_selected_items()
		if not selected.is_empty() and remove_constraint.is_valid():
			remove_constraint.call(_constraint_frames[selected[0]])
	)
	conversion_details = TextEdit.new()
	conversion_details.editable = false
	conversion_details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	conversion_details.custom_minimum_size.y = 100
	conversion_details.placeholder_text = "Conversion review appears here before queuing a frame."
	content.add_child(conversion_details)
	status = _label(common, "Pose Library works offline. Select a target to begin.")
	save_dialog = FileDialog.new()
	save_dialog.access = FileDialog.ACCESS_RESOURCES
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.add_filter("*.tres", "Pose resource")
	save_dialog.file_selected.connect(_save_path)
	add_child(save_dialog)
	open_dialog = FileDialog.new()
	open_dialog.access = FileDialog.ACCESS_RESOURCES
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.add_filter("*.tres", "Pose resource")
	open_dialog.file_selected.connect(open_pose)
	add_child(open_dialog)
	replace_dialog = ConfirmationDialog.new()
	replace_dialog.title = "Replace keys at this time?"
	replace_dialog.confirmed.connect(_commit_pending_key)
	replace_dialog.canceled.connect(func() -> void: _pending_key.clear())
	add_child(replace_dialog)
	constraint_dialog = ConfirmationDialog.new()
	constraint_dialog.title = "Review full-body Kimodo constraint"
	constraint_dialog.confirmed.connect(_queue_prepared_constraint)
	constraint_dialog.canceled.connect(func() -> void: _constraint_entry.clear())
	add_child(constraint_dialog)
	refresh_library()


func _exit_tree() -> void:
	cancel_preview()
	_disconnect_player()
	_fallback_undo.free()
	_pending_key.clear()


func _use_selection() -> void:
	if editor_plugin == null:
		return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() != 1:
		_message("Select exactly one character node, skeleton or AnimationPlayer.")
		return
	var anchor: Node = selected[0]
	var scene := EditorInterface.get_edited_scene_root()
	while anchor != null:
		var skeletons: Array[Node] = []
		var players: Array[Node] = []
		_collect(anchor, skeletons, players)
		if skeletons.size() == 1 and players.size() == 1:
			set_target(skeletons[0], players[0])
			return
		if anchor == scene:
			break
		anchor = anchor.get_parent()
	_message("The selected character must contain one skeleton and one AnimationPlayer. Select a smaller character subtree.")


func set_target(target: Skeleton3D, animation_player: AnimationPlayer) -> void:
	cancel_preview()
	_disconnect_player()
	_pending_key.clear()
	_constraint_entry.clear()
	replace_dialog.hide()
	constraint_dialog.hide()
	skeleton = target
	player = animation_player
	refresh_library()
	bone_list.clear()
	animation_selector.clear()
	_observed_animation = ""
	_observed_time = -1.0
	if not _target_ready():
		return
	for index in skeleton.get_bone_count():
		bone_list.add_item(skeleton.get_bone_name(index))
	player.animation_list_changed.connect(_refresh_animations, CONNECT_DEFERRED)
	player.animation_libraries_updated.connect(_refresh_animations, CONNECT_DEFERRED)
	_refresh_animations()
	target_label.text = "%s · %s" % [skeleton.name, player.name]
	_message("Target selected. Choose the animation and frame in Godot's Animation panel.")


func _disconnect_player() -> void:
	if is_instance_valid(player):
		for event in [player.animation_list_changed, player.animation_libraries_updated]:
			if event.is_connected(_refresh_animations):
				event.disconnect(_refresh_animations)


func _refresh_animations() -> void:
	if not is_instance_valid(player) or animation_selector == null:
		return
	animation_selector.clear()
	for animation_name in player.get_animation_list():
		animation_selector.add_item(animation_name)
	_sync_timeline()


func _process(_delta: float) -> void:
	_sync_timeline()
	if not is_instance_valid(skeleton) and not _library_paths.is_empty():
		pose_list.clear()
		_library_paths.clear()


func _sync_timeline() -> void:
	if frame_label == null:
		return
	if not is_instance_valid(player) or not player.active or not player.is_animation_active() or not player.has_animation(player.assigned_animation):
		_clear_preview()
		_observed_animation = ""
		_observed_time = -1.0
		animation_selector.select(-1)
		frame_label.text = "Open this AnimationPlayer in Godot's Animation panel and select a frame."
		return
	var current := player.assigned_animation
	var seconds := player.current_animation_position
	if current != _observed_animation or seconds != _observed_time:
		# Native scrubbing has already evaluated the new frame. Never restore an
		# old preview over it, or resample away the animator's manual bone edits.
		_clear_preview()
		_observed_animation = current
		_observed_time = seconds
	for index in animation_selector.item_count:
		if animation_selector.get_item_text(index) == String(current):
			if animation_selector.selected != index:
				animation_selector.select(index)
			break
	var step := player.get_animation(current).step
	frame_label.text = "Current frame %.3f · %.6f seconds" % [seconds / step, seconds] if step > 0 else "Current time %.6f seconds" % seconds
	if player.is_playing():
		frame_label.text += " · Pause before capturing or keying."


func _timeline_ready() -> bool:
	_sync_timeline()
	if not _target_ready():
		return false
	if not player.active or not player.is_animation_active() or not player.has_animation(player.assigned_animation):
		_message("Open the selected AnimationPlayer in Godot's Animation panel and select a frame first. Direct resource and AnimationTree editing are not supported.")
		return false
	if player.is_playing():
		_message("Pause the animation at the frame to capture or key first.")
		return false
	return true


func _target_ready() -> bool:
	if not is_instance_valid(skeleton) or not is_instance_valid(player):
		_message("Select a character first.")
		return false
	if skeleton.show_rest_only:
		_message("Turn off Show Rest Only on this Skeleton3D to edit and apply poses.")
		return false
	var binding := player.get_node_or_null(player.root_node)
	if binding == null or not binding.is_ancestor_of(skeleton) and binding != skeleton:
		_message("The AnimationPlayer root does not contain this skeleton.")
		return false
	return true


func _path() -> NodePath:
	return player.get_node(player.root_node).get_path_to(skeleton)


func _animation_name() -> StringName:
	return player.assigned_animation if is_instance_valid(player) else StringName()


func _channels() -> Dictionary:
	var result := {}
	for index in bone_list.get_selected_items():
		if skeleton.get_bone_parent(index) < 0 and not root_check.button_pressed:
			continue
		var kinds: Array[int] = []
		if position_check.button_pressed:
			kinds.append(Animation.TYPE_POSITION_3D)
		if rotation_check.button_pressed:
			kinds.append(Animation.TYPE_ROTATION_3D)
		if scale_check.button_pressed:
			kinds.append(Animation.TYPE_SCALE_3D)
		if not kinds.is_empty():
			result[String(skeleton.get_bone_name(index))] = kinds
	return result


func capture_current() -> void:
	if _timeline_ready():
		_take_capture(Service.capture(skeleton, title_edit.text, _channels(), {"animation": String(_animation_name()), "time": player.current_animation_position}))


func capture_pose_edits() -> void:
	if _pose_ready():
		var channels := {}
		for track in pose.sample.get_track_count():
			var bone: String = pose.sample.track_get_path(track).get_subname(0)
			if not channels.has(bone):
				channels[bone] = []
			channels[bone].append(pose.sample.track_get_type(track))
		_take_capture(Service.capture(skeleton, title_edit.text, channels, {"edited_from_pose_id": pose.pose_id}))


func _take_capture(result: Dictionary) -> void:
	if result["ok"]:
		pose = result["pose"]
		_message("Captured '%s' with %d channels. Save as a new pose to keep it." % [pose.title, pose.sample.get_track_count()])
	else:
		_message(result["message"])


func open_pose(path: String) -> void:
	cancel_preview()
	var result := Service.load_pose(path)
	if result["ok"]:
		pose = result["pose"]
		title_edit.text = pose.title
		_message("Opened '%s'. Preview/apply, edit the character, then capture and Save as." % pose.title)
	else:
		_message(result["message"])


func preview_pose() -> void:
	_sync_timeline()
	if not _pose_ready():
		return
	cancel_preview()
	_preview_before = _current_for_pose()
	_preview_target = weakref(skeleton)
	_preview_player = weakref(player)
	_preview_was_playing = player.is_playing()
	player.pause()
	Service.apply(pose, skeleton)
	_message("Temporary pose preview. Cancel restores the previous channels.")


func cancel_preview() -> void:
	_sync_timeline()
	if _preview_before != null and _preview_target != null:
		var target: Skeleton3D = _preview_target.get_ref()
		if is_instance_valid(target):
			Service.apply(_preview_before, target)
	if _preview_player != null:
		var preview_player: AnimationPlayer = _preview_player.get_ref()
		if is_instance_valid(preview_player) and _preview_was_playing:
			preview_player.play()
	_clear_preview()


func _clear_preview() -> void:
	_preview_before = null
	_preview_target = null
	_preview_player = null
	_preview_was_playing = false


func _pose_ready() -> bool:
	if not _target_ready():
		return false
	if pose == null:
		_message("Capture or open a pose first.")
		return false
	var problem: String = pose.compatibility_error(skeleton)
	if not problem.is_empty():
		_message(problem)
		return false
	return true


func _current_for_pose() -> Resource:
	var channels := {}
	for track in pose.sample.get_track_count():
		var bone: String = pose.sample.track_get_path(track).get_subname(0)
		if not channels.has(bone):
			channels[bone] = []
		channels[bone].append(pose.sample.track_get_type(track))
	return Service.capture(skeleton, "Before pose edit", channels)["pose"]


func _undo() -> Object:
	return editor_plugin.get_undo_redo() if editor_plugin != null else _fallback_undo


func _action(title: String) -> Object:
	var undo := _undo()
	if editor_plugin != null:
		undo.create_action(title, UndoRedo.MERGE_DISABLE, skeleton)
	else:
		undo.create_action(title)
	return undo


func _record(undo: Object, method: String, arguments: Array, backwards := false) -> void:
	var registration := "add_undo_method" if backwards else "add_do_method"
	if editor_plugin != null:
		undo.callv(registration, [self, StringName(method)] + arguments)
	else:
		undo.call(registration, Callable(self, method).bindv(arguments))


func apply_pose() -> void:
	if not _pose_ready():
		return
	cancel_preview()
	player.pause()
	var before := _current_for_pose()
	var after: Resource = pose.duplicate(true)
	var undo := _action("Apply character pose")
	_record(undo, "_apply_snapshot", [weakref(skeleton), after])
	_record(undo, "_apply_snapshot", [weakref(skeleton), before], true)
	undo.commit_action()
	_message("Pose applied. Use Apply & Key to store it in the animation.")


func _apply_snapshot(target_ref: WeakRef, value: Resource) -> void:
	var target: Skeleton3D = target_ref.get_ref()
	if is_instance_valid(target):
		Service.apply(value, target)
		character_pose_applied.emit(target)
		if editor_plugin != null:
			EditorInterface.mark_scene_as_unsaved()


func request_key() -> void:
	if not _timeline_ready() or not _pose_ready():
		return
	cancel_preview()
	var source := player.get_animation(_animation_name())
	if _is_imported_animation(source):
		_message("Copy this imported animation for editing first.")
		return
	var seconds := player.current_animation_position
	var result := Service.keyed_copy(pose, skeleton, source, _path(), seconds)
	if not result["ok"]:
		_message(result["message"])
		return
	_pending_key = {"player": weakref(player), "name": _animation_name(), "time": seconds, "before": source, "before_hash": AnimationHash.animation_hash(source), "after": result["animation"], "pose": pose.duplicate(true), "target": weakref(skeleton), "before_pose": _current_for_pose()}
	if result["collisions"] > 0:
		replace_dialog.dialog_text = "%d pose channels already have a key at %.6f seconds. Replace only those keys?" % [result["collisions"], seconds]
		replace_dialog.popup_centered()
	else:
		_commit_pending_key()


static func _is_imported_animation(animation: Animation) -> bool:
	# Both imported clips and editable native scene subresources use "::".
	# Inspect their source file instead of treating every embedded clip as imported.
	var source_path := animation.resource_path.get_slice("::", 0)
	return source_path.contains(".godot/imported/") or FileAccess.file_exists(source_path + ".import") or source_path.get_extension().to_lower() in ["glb", "gltf", "fbx", "blend", "dae"]


func _commit_pending_key() -> void:
	if _pending_key.is_empty():
		return
	var destination: AnimationPlayer = _pending_key["player"].get_ref()
	if not is_instance_valid(destination) or destination != player or not destination.is_animation_active() or destination.is_playing() or destination.assigned_animation != _pending_key["name"] or destination.current_animation_position != _pending_key["time"] or not destination.has_animation(_pending_key["name"]) or destination.get_animation(_pending_key["name"]) != _pending_key["before"] or AnimationHash.animation_hash(_pending_key["before"]) != _pending_key["before_hash"]:
		_pending_key.clear()
		_message("The destination changed while confirming. Choose it again.")
		return
	var target: Skeleton3D = _pending_key["target"].get_ref()
	if not is_instance_valid(target) or target != skeleton or not _pending_key["pose"].compatibility_error(target).is_empty():
		_pending_key.clear()
		_message("The target rig changed while confirming. Select it again.")
		return
	destination.pause()
	var before: Animation = _pending_key["before"].duplicate(true)
	var channels: Array = []
	for track in _pending_key["pose"].sample.get_track_count():
		channels.append({"path": NodePath("%s:%s" % [_path(), _pending_key["pose"].sample.track_get_path(track).get_subname(0)]), "kind": _pending_key["pose"].sample.track_get_type(track)})
	var undo := _action("Apply and key character pose")
	_record(undo, "_write_animation_tracks", [_pending_key["before"], _pending_key["after"], channels])
	_record(undo, "_write_animation_tracks", [_pending_key["before"], before, channels], true)
	_record(undo, "_apply_snapshot", [_pending_key["target"], _pending_key["pose"]])
	_record(undo, "_apply_snapshot", [_pending_key["target"], _pending_key["before_pose"]], true)
	undo.commit_action()
	_pending_key.clear()
	_message("Pose keyed into native animation. Undo/Redo is available.")


func _write_animation_tracks(destination: Animation, snapshot: Animation, channels: Array) -> void:
	# Keep the resource bound to the native editor. Removing/readding its library
	# entry makes Godot reselect the clip and can reset the native cursor.
	# Copy only included tracks, preserving all other tracks/settings/markers.
	for channel in channels:
		var old_index := destination.find_track(channel["path"], channel["kind"])
		if old_index >= 0:
			destination.remove_track(old_index)
		var source_index := snapshot.find_track(channel["path"], channel["kind"])
		if source_index >= 0:
			snapshot.copy_track(source_index, destination)
			var new_index := destination.get_track_count() - 1
			destination.track_set_imported(new_index, snapshot.track_is_imported(source_index))
			if old_index >= 0:
				destination.track_move_to(new_index, old_index)
	destination.emit_changed()
	if editor_plugin != null:
		EditorInterface.mark_scene_as_unsaved()


func copy_animation() -> void:
	if not _timeline_ready():
		return
	var new_name := title_edit.text.strip_edges().validate_node_name()
	if new_name.is_empty() or new_name.contains("/") or player.has_animation("pose_edits/" + new_name):
		_message("Enter a new animation name in the name field.")
		return
	var before := player.get_animation_library("pose_edits") if player.has_animation_library("pose_edits") else null
	var after := before.duplicate(true) as AnimationLibrary if before != null else AnimationLibrary.new()
	after.add_animation(new_name, player.get_animation(_animation_name()).duplicate(true))
	var undo := _action("Copy animation for pose editing")
	_record(undo, "_set_edit_library", [weakref(player), after])
	_record(undo, "_set_edit_library", [weakref(player), before], true)
	undo.commit_action()
	_refresh_animations()
	_message("Editable copy created in pose_edits/%s. Select it in Godot's Animation panel and save the scene to keep it." % new_name)


func _set_edit_library(player_ref: WeakRef, value: AnimationLibrary) -> void:
	var destination: AnimationPlayer = player_ref.get_ref()
	if not is_instance_valid(destination):
		return
	if destination.has_animation_library("pose_edits"):
		destination.remove_animation_library("pose_edits")
	if value != null:
		destination.add_animation_library("pose_edits", value)
	if destination == player:
		_refresh_animations()
	if editor_plugin != null:
		EditorInterface.mark_scene_as_unsaved()


func _save_as() -> void:
	if pose == null:
		_message("Capture or open a pose first.")
		return
	save_dialog.current_path = _library_directory.path_join(pose.title.validate_filename() + ".tres")
	save_dialog.popup_centered_ratio(0.7)


func _save_path(path: String) -> void:
	var result := Service.save_new(pose, path)
	_message("Pose saved: " + path if result["ok"] else result["message"])
	if result["ok"]:
		refresh_library()
		if editor_plugin != null:
			EditorInterface.get_resource_filesystem().scan()


func refresh_library() -> void:
	pose_list.clear()
	_library_paths.clear()
	if not is_instance_valid(skeleton):
		return
	# Windows can open an artist-created "Poses" folder as "poses", but resource
	# paths must retain its actual case to avoid warnings and broken exports.
	if OS.get_name() == "Windows" and DirAccess.dir_exists_absolute(_library_directory.get_base_dir()):
		for folder in DirAccess.get_directories_at(_library_directory.get_base_dir()):
			if folder.to_lower() == _library_directory.get_file().to_lower():
				_library_directory = _library_directory.get_base_dir().path_join(folder)
				break
	var directory := DirAccess.open(_library_directory)
	if directory == null:
		return
	var files := directory.get_files()
	files.sort()
	for file in files:
		if file.get_extension() != "tres" or file.contains(".pending-"):
			continue
		var path := _library_directory.path_join(file)
		var result := Service.load_pose(path)
		if result["ok"] and result["pose"].compatibility_error(skeleton).is_empty():
			_library_paths.append(path)
			pose_list.add_item(result["pose"].title)


func set_constraint_entries(entries: Array) -> void:
	if constraint_list == null:
		return
	constraint_list.clear()
	_constraint_frames.clear()
	for entry in entries:
		_constraint_frames.append(int(entry["frame"]))
		constraint_list.add_item("Frame %d · full body" % entry["frame"])


func _prepare_constraint() -> void:
	if not _timeline_ready() or not prepare_constraint.is_valid():
		return
	var frame_value := player.current_animation_position * 30.0
	var channels := {}
	for index in skeleton.get_bone_count():
		channels[String(skeleton.get_bone_name(index))] = Service.KINDS
	var captured := Service.capture(skeleton, "Authored constraint", channels)
	if not captured["ok"]:
		_message(captured["message"])
		return
	var result: Dictionary = prepare_constraint.call(skeleton, captured["pose"], int(roundf(frame_value)))
	if not result["ok"]:
		_message(result["message"])
		return
	_constraint_entry = result["entry"]
	var residuals: Dictionary = result["residuals"]
	var excluded: Array = _constraint_entry["conversion"]["excluded_character_bones"]
	conversion_details.text = "Frame %d. Full body constrains FK positions, root height/path and heading.\nDetail bones retained locally: %s" % [_constraint_entry["frame"], ", ".join(excluded)]
	constraint_dialog.dialog_text = (
		"Queue the current complete character pose at frame %d? This replaces any queued constraint at that frame.\n\n"
		+ "SOMA-30 body rotations will define FK position constraints. Finger detail stays in your character pose and is not sent. Scene placement is separate.\n\n"
		+ "Position differences from proportion transfer (meters):\nLeft hand %.4f · Right hand %.4f\nLeft foot %.4f · Right foot %.4f\n\n"
		+ "This is a snapshot. Recapture after further editing. Generate from AI Motion when ready."
	) % [_constraint_entry["frame"], residuals["LeftHand"], residuals["RightHand"], residuals["LeftFoot"], residuals["RightFoot"]]
	constraint_dialog.popup_centered(Vector2i(480, 360))


func _queue_prepared_constraint() -> void:
	if _constraint_entry.is_empty() or not queue_constraint.is_valid():
		return
	var result: Dictionary = queue_constraint.call(_constraint_entry)
	_constraint_entry.clear()
	_message(result["message"])


func _message(text: String) -> void:
	if status != null:
		status.text = text


static func _collect(node: Node, skeletons: Array[Node], players: Array[Node]) -> void:
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	for child in node.get_children():
		_collect(child, skeletons, players)


static func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


static func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return content


static func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.pressed.connect(callback)
	parent.add_child(button)


static func _check(parent: Node, text: String, checked: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = checked
	parent.add_child(check)
	return check
