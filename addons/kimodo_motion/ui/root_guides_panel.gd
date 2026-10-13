@tool
extends VBoxContainer

signal scene_character_selected(target: Skeleton3D, animation_player: AnimationPlayer)

const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const Service := preload("res://addons/kimodo_motion/guides/root_guide_service.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const PoseService := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const GuidePose := preload("res://addons/kimodo_motion/guides/guide_pose_service.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const Converter := preload("res://addons/kimodo_motion/poses/character_pose_converter.gd")
const Ghost := preload("res://addons/kimodo_motion/guides/authored_pose_ghost.gd")

var dock: Control
var skeleton: Skeleton3D
var player: AnimationPlayer
var guide: Node3D
var path_node: Node3D
var scene_preview: Node3D
var scene_preview_player: AnimationPlayer
var status: Label
var current_frame: Label
var points_list: ItemList
var heading_check: CheckBox
var replace_dialog: ConfirmationDialog
var _pending: Dictionary = {}
var _frames: Array[int] = []
var _bound_scene: WeakRef
var _bound_session_id := ""
var edit_character: CheckBox
var show_ghosts: CheckBox
var pose_details: Label
var _pose_reference: Dictionary = {}
var _last_guide := Transform3D.IDENTITY
var _last_hips := Transform3D.IDENTITY
var _last_time := -1.0
var _last_animation := ""
var _sync_ready := false
var _bone_undo := UndoRedo.new()


func _ready() -> void:
	name = "Guides"
	custom_minimum_size.x = 300
	_label("Root path and optional facing · active session")
	_button("Use selected scene character", use_selection)
	_button("Select root guide in scene", select_guide)
	edit_character = CheckBox.new()
	edit_character.text = "Move character with guide"
	edit_character.tooltip_text = "Edit Hips travel/turning with the guide. Scene-node placement stays fixed. Turn off for route-only editing."
	add_child(edit_character)
	edit_character.toggled.connect(_toggle_character_edit)
	_button("Match guide to queued pose at current frame", match_queued_pose)
	current_frame = _label("Choose a character and scrub its native animation.")
	heading_check = CheckBox.new()
	heading_check.text = "Record facing (+Z arrow)"
	add_child(heading_check)
	_label("Move the guide with Godot's gizmos. Only ground-plane XZ travel is recorded; path lines join authored waypoints, not generated motion.")
	_button("Record waypoint at current frame", record_current)
	_button("Record waypoint and pose at current frame", record_pose_current)
	pose_details = _label("Combined records capture the complete authored pose; ghosts show your intent, which can differ from generated motion.")
	show_ghosts = CheckBox.new()
	show_ghosts.text = "Show authored pose ghosts"
	show_ghosts.button_pressed = true
	add_child(show_ghosts)
	show_ghosts.toggled.connect(func(_visible: bool) -> void: _draw_path())
	points_list = ItemList.new()
	points_list.custom_minimum_size.y = 140
	add_child(points_list)
	points_list.item_selected.connect(_select_point)
	_button("Remove selected record", remove_selected)
	_button("Clear guides / use changed placement", clear_guides)
	_button("Show selected take in scene", show_selected_take)
	_button("Hide scene preview", hide_scene_preview)
	status = _label("Root guides work offline after selecting the session character/profile. Generate from the Generate tab.")
	replace_dialog = ConfirmationDialog.new()
	replace_dialog.title = "Replace root waypoint?"
	replace_dialog.confirmed.connect(_commit_pending)
	replace_dialog.canceled.connect(_cancel_review)
	add_child(replace_dialog)
	if dock != null:
		dock.root_guides_changed.connect(set_intent)
		dock.pose_keyframes_changed.connect(func(_entries: Array) -> void: _refresh_records())
		set_intent(dock._draft.root_guides if dock._draft != null else {})


func _exit_tree() -> void:
	_detach()
	_bone_undo.free()


func _detach() -> void:
	if replace_dialog != null:
		replace_dialog.hide()
	for node in [guide, path_node]:
		if is_instance_valid(node):
			node.free()
	guide = null
	path_node = null
	skeleton = null
	player = null
	_bound_scene = null
	_pending.clear()
	_pose_reference.clear()
	_sync_ready = false
	hide_scene_preview()


func use_selection() -> void:
	if dock == null or dock._editor_plugin == null:
		return
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if nodes.size() != 1:
		_message("Select exactly one scene character, skeleton or AnimationPlayer.")
		return
	var scene := EditorInterface.get_edited_scene_root()
	var anchor: Node = nodes[0]
	while anchor != null:
		var skeletons: Array[Skeleton3D] = []
		var players: Array[AnimationPlayer] = []
		_collect(anchor, skeletons, players)
		if skeletons.size() == 1 and players.size() == 1:
			scene_character_selected.emit(skeletons[0], players[0])
			set_target(skeletons[0], players[0], scene)
			return
		if anchor == scene:
			break
		anchor = anchor.get_parent()
	_message("Choose a character subtree with one Skeleton3D and one AnimationPlayer.")


func set_target(target: Skeleton3D, animation_player: AnimationPlayer, scene: Node) -> void:
	_detach()
	skeleton = target
	player = animation_player
	_bound_scene = weakref(scene)
	var context := _context(scene)
	if not context["ok"]:
		_message(context["message"])
		return
	if dock._draft.root_guides.is_empty():
		context["intent"]["points"] = []
		dock.edit_root_guides(context["intent"])
	elif not _matches(context["intent"], dock._draft.root_guides):
		_message("The saved guides belong to a different scene placement/profile. Clear them explicitly before using this character.")
		return
	guide = Node3D.new()
	guide.name = "KimodoRootGuide"
	scene.add_child(guide)
	# No owner: this editor helper is never saved into the production scene.
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	_mesh(guide, sphere, Transform3D.IDENTITY)
	var arrow := CylinderMesh.new()
	arrow.top_radius = 0
	arrow.bottom_radius = 0.09
	arrow.height = 0.3
	_mesh(guide, arrow, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.08, 0.25)))
	var space: Dictionary = context["intent"]["space"]
	guide.global_transform = Transform3D(Space.decode_transform(space["placement"]).basis.orthonormalized(), Space.model_to_world(space, Space.unvector(space["model_hips_rest"])))
	guide.global_position.y = Space.decode_transform(space["placement"]).origin.y
	_setup_pose_reference()
	if edit_character.button_pressed and not _pose_reference.is_empty():
		_follow_current_pose()
	_prime_sync()
	_draw_path()
	_message("Guide ready. Move/rotate it, scrub the native animation and record a waypoint.")


func _context(scene: Node = null) -> Dictionary:
	if dock == null or dock._draft == null or dock._rig_profile == null:
		return _error("Open a session and choose its reviewed character/profile first.")
	if not is_instance_valid(skeleton) or not is_instance_valid(player):
		return _error("Use selected scene character first.")
	if dock._guide_editing_locked():
		return _error("Wait for generation before editing guides.")
	if scene == null:
		scene = EditorInterface.get_edited_scene_root() if dock._editor_plugin != null else (_bound_scene.get_ref() if _bound_scene != null else null)
	if scene == null or not scene.is_ancestor_of(skeleton) or not scene.is_ancestor_of(player) or scene.scene_file_path.is_empty():
		return _error("Save and open the character's scene before binding guides.")
	var binding := player.get_node_or_null(player.root_node)
	if binding == null or (binding != skeleton and not binding.is_ancestor_of(skeleton)):
		return _error("This AnimationPlayer does not animate the selected skeleton.")
	if Store.skeleton_signature(skeleton) != dock._draft.target_skeleton_signature:
		return _error("This scene skeleton does not match the session character.")
	# The pinned model's neutral hips position is archived with each guide.
	# Load from capabilities when available, or saved guide reference offline.
	var payload: Dictionary = dock._client.capabilities.skeleton_payload if dock._client != null and dock._client.capabilities != null else {}
	if payload.is_empty():
		return _error("Connect once to establish the canonical rig, or reopen saved guides offline.") if dock._draft.root_guides.is_empty() else _offline_context(scene)
	var rest := Vector3.ZERO
	var found := false
	for joint in payload["joints"]:
		if joint["name"] == "Hips":
			rest = Space.unvector(joint["rest_translation"])
			found = true
	if not found:
		return _error("The backend reference has no Hips joint.")
	var captured := Space.capture(skeleton, dock._rig_profile, rest)
	if not captured["ok"]:
		return captured
	return {"ok": true, "intent": _identity(scene, captured["space"])}


func _offline_context(scene: Node) -> Dictionary:
	var saved: Dictionary = dock._draft.root_guides
	var captured := Space.capture(skeleton, dock._rig_profile, Space.unvector(saved["space"]["model_hips_rest"]))
	return {"ok": true, "intent": _identity(scene, captured["space"])} if captured["ok"] else captured


func _identity(scene: Node, space: Dictionary) -> Dictionary:
	return {"version": 1, "space": space, "scene_path": scene.scene_file_path, "skeleton_path": String(scene.get_path_to(skeleton)), "player_path": String(scene.get_path_to(player)), "target_signature": dock._draft.target_skeleton_signature, "profile_configuration": dock._pose_profile_configuration(), "points": []}


static func _matches(current: Dictionary, saved: Dictionary) -> bool:
	for field in ["space", "scene_path", "skeleton_path", "player_path", "target_signature", "profile_configuration"]:
		if not _equal(current.get(field), saved.get(field)):
			return false
	return true


static func _equal(first: Variant, second: Variant) -> bool:
	# Native .tres float formatting can round the last digits. Accept only
	# serialization-sized drift, while still invalidating meaningful edits.
	if (first is float or first is int) and (second is float or second is int):
		return absf(float(first) - float(second)) <= 0.000001
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size():
			return false
		for key in first:
			if not second.has(key) or not _equal(first[key], second[key]):
				return false
		return true
	if first is Array and second is Array:
		if first.size() != second.size():
			return false
		for index in first.size():
			if not _equal(first[index], second[index]):
				return false
		return true
	return first == second


func check_current_binding() -> Dictionary:
	var context := _context()
	if not context["ok"]:
		return context
	if not _matches(context["intent"], dock._draft.root_guides):
		return _error("Character node placement/profile changed. Keep the character node fixed; move/rotate its Hips bone to author a pose's travel and turning. Restore the recorded node placement, or clear/re-author the guides.")
	return {"ok": true}


func _frame() -> int:
	if not is_instance_valid(player) or not player.active or not player.is_animation_active() or player.is_playing():
		return -1
	var value := player.current_animation_position * 30
	return int(roundf(value))


func _process(_delta: float) -> void:
	if current_frame == null:
		return
	var frame := _frame()
	current_frame.text = "Native frame %d · %s (nearest 30 FPS frame)" % [frame, player.assigned_animation] if frame >= 0 else "Pause and select a frame in the native animation timeline."
	_sync_character()
	_select_ghost_from_editor()
	if is_instance_valid(scene_preview_player) and is_instance_valid(player) and player.is_animation_active():
		scene_preview_player.seek(clampf(player.current_animation_position, 0, scene_preview_player.get_animation("motion").length), true, true)


func _setup_pose_reference() -> void:
	var saved: Dictionary = dock._draft.root_guides.get("pose_reference", {})
	if not saved.is_empty():
		_pose_reference = saved.duplicate(true)
		return
	var payload: Dictionary = dock.pose_reference_payload()
	if payload.is_empty():
		return
	var created := GuidePose.create_reference(skeleton, dock._rig_profile, payload)
	if not created["ok"]:
		_message(created["message"])
		return
	_pose_reference = created["reference"]
	var after: Dictionary = dock._draft.root_guides.duplicate(true)
	after["pose_reference"] = _pose_reference.duplicate(true)
	dock.edit_root_guides(after)


func _hips_global() -> Transform3D:
	return Converter.global_transforms(skeleton, false)[skeleton.find_bone(dock._rig_profile.target_for("Hips"))]


func _prime_sync() -> void:
	_sync_ready = is_instance_valid(guide) and not _pose_reference.is_empty() and is_instance_valid(player) and player.is_animation_active()
	if not _sync_ready:
		return
	_last_guide = guide.global_transform
	_last_hips = _hips_global()
	_last_time = player.current_animation_position
	_last_animation = player.assigned_animation


func _toggle_character_edit(enabled: bool) -> void:
	if not enabled:
		_sync_ready = false
		return
	if _pose_reference.is_empty() or not check_current_binding()["ok"]:
		edit_character.set_pressed_no_signal(false)
		_message("Bind the character and connect once to establish its pose reference before visual editing.")
		return
	_follow_current_pose()
	_prime_sync()


func _follow_current_pose() -> void:
	var current := GuidePose.current_guide(skeleton, dock._rig_profile, dock._draft.root_guides["space"], _pose_reference)
	if current["ok"]:
		guide.global_transform = current["transform"]
	else:
		_message(current["message"])


func _sync_character() -> void:
	if edit_character == null or not edit_character.button_pressed or _pose_reference.is_empty() or not is_instance_valid(guide):
		return
	if _frame() < 0:
		_sync_ready = false
		return
	if not check_current_binding()["ok"]:
		_sync_ready = false
		return
	var hips := _hips_global()
	var time := player.current_animation_position
	if not _sync_ready or time != _last_time or player.assigned_animation != _last_animation or not hips.is_equal_approx(_last_hips):
		# Bone edits/application or native scrubbing wins over a stale handle.
		_follow_current_pose()
	elif not guide.global_transform.is_equal_approx(_last_guide):
		var changed := GuidePose.apply_guide(skeleton, dock._rig_profile, dock._draft.root_guides["space"], _pose_reference, guide.global_transform)
		if changed["ok"]:
			_follow_current_pose()
			if dock._editor_plugin != null:
				EditorInterface.mark_scene_as_unsaved()
		else:
			_message(changed["message"])
	_prime_sync()


func pose_applied(target: Skeleton3D) -> void:
	if target == skeleton and edit_character.button_pressed and is_instance_valid(guide) and not _pose_reference.is_empty() and check_current_binding()["ok"]:
		_follow_current_pose()
		_prime_sync()


func _refresh_records() -> void:
	if dock != null and dock._draft != null:
		set_intent(dock._draft.root_guides)


func _linked_pose(point: Dictionary) -> Dictionary:
	if not point.has("pose_id"):
		return {}
	for entry in dock._draft.pose_keyframes:
		if entry.get("guide_pose_id") == point["pose_id"] and entry["frame"] == point["frame"] and entry["target_signature"] == dock._draft.target_skeleton_signature and _equal(entry.get("profile_configuration"), dock._pose_profile_configuration()):
			return entry
	return {}


func _select_ghost_from_editor() -> void:
	if dock._editor_plugin == null or not is_instance_valid(path_node):
		return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() != 1:
		return
	var node: Node = selected[0]
	while node != null and node != path_node:
		if node.has_meta("kimodo_authored_frame"):
			var frame: int = node.get_meta("kimodo_authored_frame")
			if node.get_meta("kimodo_session_id") == dock._draft.session_id and _frames.has(frame):
				_select_point(_frames.find(frame))
			return
		node = node.get_parent()


func hide_scene_preview() -> void:
	if is_instance_valid(scene_preview):
		scene_preview.free()
	scene_preview = null
	scene_preview_player = null


func show_selected_take() -> void:
	hide_scene_preview()
	if dock._draft == null or not dock._preview_panel.has_character():
		_message("Select a generated/archived character take in Preview & Save first.")
		return
	var record: Dictionary = dock._draft.active_generation_record()
	var authored: Dictionary = record.get("authored_root_guides", {})
	if authored.is_empty():
		_message("This take has no archived scene root-guide placement.")
		return
	var context := _context()
	if not context["ok"] or not is_instance_valid(guide) or not _matches(context["intent"], authored):
		_message("Select the saved scene character at this take's recorded placement/profile before showing it.")
		return
	var source: Node3D = dock._character_preview.motion_scene()
	scene_preview = source.duplicate(0) as Node3D
	scene_preview.name = "KimodoScenePreview"
	var preview_skeleton: Skeleton3D
	var pending: Array[Node] = [scene_preview]
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		if node is Skeleton3D:
			preview_skeleton = node
		if node is AnimationPlayer:
			if node.has_animation("motion") and node.name == "KimodoAnimationPlayer":
				scene_preview_player = node
		if node is MeshInstance3D:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.25, 0.85, 1.0, 0.4)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			node.material_override = material
		for child in node.get_children():
			pending.append(child)
	if preview_skeleton == null or scene_preview_player == null:
		hide_scene_preview()
		_message("The selected take has no character skeleton/motion player.")
		return
	guide.get_parent().add_child(scene_preview)
	var alignment := Space.decode_transform(authored["space"]["placement"]) * preview_skeleton.global_transform.affine_inverse()
	scene_preview.global_transform = alignment * scene_preview.global_transform
	scene_preview_player.assigned_animation = "motion"
	scene_preview_player.pause()
	_message("Temporary cyan preview at the take's archived placement. Scrub the native character timeline to compare; Hide removes it without changing the scene.")


func select_guide() -> void:
	if is_instance_valid(guide) and dock._editor_plugin != null:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(guide)
		EditorInterface.edit_node(guide)
		EditorInterface.set_main_screen_editor("3D")


func match_queued_pose() -> void:
	var ready := check_current_binding()
	if not ready["ok"] or not is_instance_valid(guide):
		_message(ready.get("message", "Select the guide character first."))
		return
	var frame := _frame()
	for entry in dock._draft.pose_keyframes:
		if entry["frame"] == frame:
			var pose: Dictionary = entry["constraint"]
			var q: Array = pose["joint_rotations"]["Hips"]
			var lateral := Quaternion(q[0], q[1], q[2], q[3]) * Vector3.LEFT
			var space: Dictionary = dock._draft.root_guides["space"]
			var position := Space.model_to_world(space, Space.unvector(pose["root_position"]))
			position.y = Space.decode_transform(space["placement"]).origin.y
			guide.global_transform = Transform3D(Basis(Vector3.UP, Space.model_heading_to_world(space, atan2(lateral.z, -lateral.x))), position)
			_message("Guide matches the queued pose's root and facing. Record it to store the waypoint.")
			return
	_message("No full-body pose is queued at this native frame. Queue it in Pose Library first.")


func record_current() -> void:
	_record_current(false)


func record_pose_current() -> void:
	_record_current(true)


func _record_current(with_pose: bool) -> void:
	var ready := check_current_binding()
	if not ready["ok"]:
		_message(ready["message"])
		return
	var frame := _frame()
	if frame < 0 or frame >= dock._draft.duration_frames or not is_instance_valid(guide):
		_message("Choose a paused native time whose nearest 30 FPS frame is within the session duration.")
		return
	_sync_character()
	var entry := {}
	if with_pose:
		var captured := _capture_complete()
		if not captured["ok"]:
			_message(captured["message"])
			return
		var prepared: Dictionary = dock.prepare_pose_keyframe(skeleton, captured["pose"], frame)
		if not prepared["ok"]:
			_message(prepared["message"])
			return
		entry = prepared["entry"]
		entry["guide_pose_id"] = Session.create_uuid()
		# Record the pose's exact converted root/facing, including calibrated
		# neutral offsets. The authored ghost still uses the original channels.
		var root := Space.model_to_world(dock._draft.root_guides["space"], Space.unvector(entry["constraint"]["root_position"]))
		var q: Array = entry["constraint"]["joint_rotations"]["Hips"]
		var lateral := Quaternion(q[0], q[1], q[2], q[3]) * Vector3.LEFT
		root.y = Space.decode_transform(dock._draft.root_guides["space"]["placement"]).origin.y
		guide.global_transform = Transform3D(Basis(Vector3.UP, Space.model_heading_to_world(dock._draft.root_guides["space"], atan2(lateral.z, -lateral.x))), root)
		_prime_sync()
		var residuals: Dictionary = prepared["residuals"]
		pose_details.text = "Authored pose → SOMA position differences (m): hands %.4f / %.4f; feet %.4f / %.4f. Ghosts retain your actual pose." % [residuals["LeftHand"], residuals["RightHand"], residuals["LeftFoot"], residuals["RightFoot"]]
	var direction := guide.global_basis * Vector3.FORWARD * -1
	if not guide.global_transform.is_finite() or Vector2(direction.x, direction.z).length_squared() < 0.000001:
		_message("The guide transform/facing is invalid. Keep its +Z arrow horizontal.")
		return
	var position := guide.global_position
	position.y = Space.decode_transform(dock._draft.root_guides["space"]["placement"]).origin.y
	var point := {"frame": frame, "world_position": Space.vector(position), "world_heading": atan2(direction.x, direction.z), "use_heading": heading_check.button_pressed}
	if with_pose:
		point["pose_id"] = entry["guide_pose_id"]
	_pending = {"session_id": dock._draft.session_id, "before": dock._draft.root_guides.duplicate(true), "before_poses": dock._draft.pose_keyframes.duplicate(true), "entry": entry, "point": point, "time": player.current_animation_position, "animation": player.assigned_animation, "guide": guide.global_transform}
	var collision := false
	for existing in dock._draft.root_guides["points"]:
		if existing["frame"] == frame:
			collision = true
	for existing in dock._draft.pose_keyframes:
		if with_pose and existing["frame"] == frame:
			collision = true
	if collision:
		replace_dialog.dialog_text = "Replace the waypoint%s at frame %d? A previous linked pose is removed with its waypoint. Independent poses are replaced only when recording a new complete pose." % [" and complete pose" if with_pose else "", frame]
		replace_dialog.popup_centered()
		return
	_commit_pending()


func _capture_complete() -> Dictionary:
	var channels := {}
	for index in skeleton.get_bone_count():
		channels[String(skeleton.get_bone_name(index))] = PoseService.KINDS
	return PoseService.capture(skeleton, "Authored guide pose", channels)


func _complete_channels() -> Array:
	var channels: Array = []
	for index in skeleton.get_bone_count():
		var bone := String(skeleton.get_bone_name(index))
		var q := skeleton.get_bone_pose_rotation(index)
		channels.append({"bone": bone, "kind": Animation.TYPE_POSITION_3D, "value": Space.vector(skeleton.get_bone_pose_position(index))})
		channels.append({"bone": bone, "kind": Animation.TYPE_ROTATION_3D, "value": [q.x, q.y, q.z, q.w]})
		channels.append({"bone": bone, "kind": Animation.TYPE_SCALE_3D, "value": Space.vector(skeleton.get_bone_pose_scale(index))})
	return channels


func _commit_pending() -> void:
	replace_dialog.hide()
	if _pending.is_empty():
		return
	if _pending.get("operation") == "clear":
		if dock._draft != null and not dock._guide_editing_locked() and dock._draft.session_id == _pending["session_id"] and dock._draft.root_guides == _pending["before"] and dock._draft.pose_keyframes == _pending["before_poses"]:
			_clear_now()
		else:
			_message("The session changed while reviewing. Clear again.")
		_pending.clear()
		return
	var ready := check_current_binding()
	if not ready["ok"] or dock._draft.session_id != _pending["session_id"] or dock._draft.root_guides != _pending["before"] or dock._draft.pose_keyframes != _pending["before_poses"] or not player.active or player.is_playing() or not player.is_animation_active() or player.current_animation_position != _pending["time"] or player.assigned_animation != _pending["animation"] or not guide.global_transform.is_equal_approx(_pending["guide"]):
		_pending.clear()
		_message("The destination changed while reviewing. Record the waypoint again.")
		return
	var entry: Dictionary = _pending["entry"]
	if not entry.is_empty() and entry["authored_channels"] != _complete_channels():
		_pending.clear()
		_message("The character pose changed while reviewing. Record again.")
		return
	var after: Dictionary = _pending["before"].duplicate(true)
	var entries: Array[Dictionary] = _pending["before_poses"].duplicate(true)
	for index in range(after["points"].size() - 1, -1, -1):
		if after["points"][index]["frame"] == _pending["point"]["frame"]:
			_remove_linked_entry(entries, after["points"][index])
			after["points"].remove_at(index)
	if not entry.is_empty():
		for index in range(entries.size() - 1, -1, -1):
			if entries[index]["frame"] == entry["frame"]:
				entries.remove_at(index)
		entries.append(entry)
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["frame"] < b["frame"])
	after["points"].append(_pending["point"])
	_pending.clear()
	var checked := Service.constraints(after, entries, dock._draft.duration_frames)
	if not checked["ok"]:
		_message(checked["message"])
		return
	checked = dock.edit_guide_pose_state(after, entries)
	_message("Waypoint%s recorded. Review the authored sequence, then Generate." % [" and complete pose" if not entry.is_empty() else ""] if checked["ok"] else checked["message"])


func _cancel_review() -> void:
	_pending.clear()
	replace_dialog.hide()


static func _remove_linked_entry(entries: Array[Dictionary], point: Dictionary) -> void:
	if not point.has("pose_id"):
		return
	for index in range(entries.size() - 1, -1, -1):
		if entries[index].get("guide_pose_id") == point["pose_id"] and entries[index]["frame"] == point["frame"]:
			entries.remove_at(index)


func remove_selected() -> void:
	if dock._draft == null or dock._guide_editing_locked():
		return
	var selected := points_list.get_selected_items()
	if selected.is_empty():
		return
	var after: Dictionary = dock._draft.root_guides.duplicate(true)
	var entries: Array[Dictionary] = dock._draft.pose_keyframes.duplicate(true)
	for index in range(after["points"].size() - 1, -1, -1):
		if after["points"][index]["frame"] == _frames[selected[0]]:
			_remove_linked_entry(entries, after["points"][index])
			after["points"].remove_at(index)
	var changed: Dictionary = dock.edit_guide_pose_state(after, entries)
	_message("Record removed with its linked pose. Undo is available." if changed["ok"] else changed["message"])


func clear_guides() -> void:
	if dock != null and dock._draft != null and not dock._guide_editing_locked():
		for point in dock._draft.root_guides.get("points", []):
			if not _linked_pose(point).is_empty():
				_pending = {"operation": "clear", "session_id": dock._draft.session_id, "before": dock._draft.root_guides.duplicate(true), "before_poses": dock._draft.pose_keyframes.duplicate(true)}
				replace_dialog.dialog_text = "Clear all waypoints and their linked complete poses? Independent Pose Library constraints are kept. Undo restores the records."
				replace_dialog.popup_centered()
				return
		_clear_now()


func _clear_now() -> void:
	var entries: Array[Dictionary] = dock._draft.pose_keyframes.duplicate(true)
	for point in dock._draft.root_guides.get("points", []):
		_remove_linked_entry(entries, point)
	var changed: Dictionary = dock.edit_guide_pose_state({}, entries)
	if changed["ok"]:
		_detach()
		_message("Guides and linked poses cleared with Undo available. Independent constraints kept. Select the character again to use its current placement.")
	else:
		_message(changed["message"])


func set_intent(intent: Dictionary) -> void:
	if points_list == null:
		return
	points_list.clear()
	_frames.clear()
	if intent.is_empty():
		_detach()
		_bound_session_id = ""
		return
	if not _bound_session_id.is_empty() and _bound_session_id != dock._draft.session_id:
		_detach()
	_bound_session_id = dock._draft.session_id
	var points: Array = intent["points"].duplicate(true)
	points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["frame"] < b["frame"])
	for point in points:
		_frames.append(point["frame"])
		points_list.add_item("Frame %d%s%s" % [point["frame"], " · pose" if not _linked_pose(point).is_empty() else " · waypoint", " · facing" if point["use_heading"] else ""])
	_draw_path()


func _select_point(index: int) -> void:
	if not is_instance_valid(guide) or dock._draft == null or index < 0 or index >= _frames.size() or not check_current_binding()["ok"] or _frame() < 0:
		return
	for point in dock._draft.root_guides["points"]:
		if point["frame"] == _frames[index]:
			var entry := _linked_pose(point)
			if not entry.is_empty():
				_restore_recorded_pose(entry)
			guide.global_transform = Transform3D(Basis(Vector3.UP, point["world_heading"]), Space.unvector(point["world_position"]))
			heading_check.button_pressed = point["use_heading"]
			points_list.select(index)
			if entry.is_empty() and edit_character.button_pressed:
				_prime_sync()
				var moved := GuidePose.guide_edit(skeleton, dock._rig_profile, dock._draft.root_guides["space"], _pose_reference, guide.global_transform) if not _pose_reference.is_empty() else {"ok": false}
				if moved["ok"]:
					var local: Transform3D = moved["pose"]
					var q := local.basis.get_rotation_quaternion()
					var bone := String(skeleton.get_bone_name(moved["bone"]))
					_record_bone_channels([
						{"bone": bone, "kind": Animation.TYPE_POSITION_3D, "value": Space.vector(local.origin)},
						{"bone": bone, "kind": Animation.TYPE_ROTATION_3D, "value": [q.x, q.y, q.z, q.w]},
						{"bone": bone, "kind": Animation.TYPE_SCALE_3D, "value": Space.vector(local.basis.get_scale())},
					])
			_prime_sync()
			select_guide()
			_message("Record %d restored at current frame %d. Record here to copy it, or scrub to %d before replacing the original." % [point["frame"], _frame(), point["frame"]])
			return


func _restore_recorded_pose(entry: Dictionary) -> void:
	_record_bone_channels(entry["authored_channels"])


func _record_bone_channels(channels: Array) -> void:
	var checked := GuidePose.channel_error(channels, skeleton)
	if not checked.is_empty():
		_message(checked)
		return
	var included := {}
	for channel in channels:
		included["%s:%d" % [channel["bone"], channel["kind"]]] = true
	var before := _complete_channels().filter(func(channel: Dictionary) -> bool: return included.has("%s:%d" % [channel["bone"], channel["kind"]]))
	var target := weakref(skeleton)
	if dock._editor_plugin != null:
		var undo: Object = dock._editor_plugin.get_undo_redo()
		undo.create_action("Restore authored guide pose", UndoRedo.MERGE_DISABLE, skeleton)
		undo.add_do_method(self, "_restore_bones", target, channels.duplicate(true))
		undo.add_undo_method(self, "_restore_bones", target, before)
		undo.commit_action()
	else:
		_bone_undo.create_action("Restore authored guide pose")
		_bone_undo.add_do_method(Callable(self, "_restore_bones").bind(target, channels.duplicate(true)))
		_bone_undo.add_undo_method(Callable(self, "_restore_bones").bind(target, before))
		_bone_undo.commit_action()


func _restore_bones(target_ref: WeakRef, channels: Array) -> void:
	var target: Skeleton3D = target_ref.get_ref()
	if not is_instance_valid(target):
		return
	GuidePose.restore_channels(target, channels)
	if target == skeleton and is_instance_valid(guide) and not _pose_reference.is_empty() and check_current_binding()["ok"]:
		_follow_current_pose()
		_prime_sync()
	if dock._editor_plugin != null:
		EditorInterface.mark_scene_as_unsaved()


func _draw_path() -> void:
	if is_instance_valid(path_node):
		path_node.free()
	path_node = null
	if not is_instance_valid(guide) or dock._draft == null:
		return
	path_node = Node3D.new()
	path_node.name = "KimodoRootPath"
	guide.get_parent().add_child(path_node)
	path_node.global_transform = Transform3D.IDENTITY
	var points: Array = dock._draft.root_guides["points"].duplicate(true)
	points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["frame"] < b["frame"])
	var mesh := ImmediateMesh.new()
	if points.size() > 1:
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for index in points.size() - 1:
			mesh.surface_add_vertex(Space.unvector(points[index]["world_position"]))
			mesh.surface_add_vertex(Space.unvector(points[index + 1]["world_position"]))
		mesh.surface_end()
		_mesh(path_node, mesh, Transform3D.IDENTITY)
	for point in points:
		var position := Space.unvector(point["world_position"])
		var entry := _linked_pose(point)
		var ghost_visible := not entry.is_empty() and show_ghosts.button_pressed
		var label_position := position + Vector3.UP * 0.15
		if ghost_visible and dock._character_target != null:
			var created := Ghost.create(dock._character_target, entry, path_node, Space.decode_transform(dock._draft.root_guides["space"]["placement"]))
			if created["ok"]:
				var ghost_skeleton: Skeleton3D = created["skeleton"]
				var head: int = ghost_skeleton.find_bone(dock._rig_profile.target_for("Head"))
				if head >= 0:
					label_position.y = (ghost_skeleton.global_transform * ghost_skeleton.get_bone_global_pose(head).origin).y + 0.25
			else:
				_message(created["message"])
		elif entry.is_empty():
			var marker := CylinderMesh.new()
			marker.top_radius = 0
			marker.bottom_radius = 0.05
			marker.height = 0.18
			_mesh(path_node, marker, Transform3D(Basis(Vector3.UP, point["world_heading"]) * Basis(Vector3.RIGHT, PI / 2), position + Vector3.UP * 0.07))
		var label := Label3D.new()
		label.text = str(point["frame"])
		label.modulate = Color(1.0, 0.75, 0.35) if not entry.is_empty() else Color(0.4, 0.95, 1.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visible = entry.is_empty() or show_ghosts.button_pressed
		path_node.add_child(label)
		label.global_position = label_position


static func _mesh(parent: Node3D, mesh: Mesh, transform: Transform3D) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.85, 0.95)
	instance.material_override = material
	parent.add_child(instance)
	instance.transform = transform


static func _collect(node: Node, skeletons: Array[Skeleton3D], players: Array[AnimationPlayer]) -> void:
	if node is Skeleton3D:
		skeletons.append(node)
	if node is AnimationPlayer:
		players.append(node)
	for child in node.get_children():
		_collect(child, skeletons, players)


func _button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.tooltip_text = text
	button.pressed.connect(callback)
	add_child(button)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label


func _message(text: String) -> void:
	if status != null:
		status.text = text


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
