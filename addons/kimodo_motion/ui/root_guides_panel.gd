@tool
extends VBoxContainer

const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const Service := preload("res://addons/kimodo_motion/guides/root_guide_service.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")

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


func _ready() -> void:
	name = "Guides"
	custom_minimum_size.x = 300
	_label("Root path and optional facing · active session")
	_button("Use selected scene character", use_selection)
	_button("Select root guide in scene", select_guide)
	_button("Match guide to queued pose at current frame", match_queued_pose)
	current_frame = _label("Choose a character and scrub its native animation.")
	heading_check = CheckBox.new()
	heading_check.text = "Record facing (+Z arrow)"
	add_child(heading_check)
	_label("Move the guide with Godot's gizmos. Only ground-plane XZ travel is recorded; path lines join authored waypoints, not generated motion.")
	_button("Record waypoint at current frame", record_current)
	points_list = ItemList.new()
	points_list.custom_minimum_size.y = 140
	add_child(points_list)
	points_list.item_selected.connect(_select_point)
	_button("Remove selected waypoint", remove_selected)
	_button("Clear guides / use changed placement", clear_guides)
	_button("Show selected take in scene", show_selected_take)
	_button("Hide scene preview", hide_scene_preview)
	status = _label("Root guides work offline after selecting the session character/profile. Generate from the Generate tab.")
	replace_dialog = ConfirmationDialog.new()
	replace_dialog.title = "Replace root waypoint?"
	replace_dialog.confirmed.connect(_commit_pending)
	replace_dialog.canceled.connect(func() -> void: _pending.clear())
	add_child(replace_dialog)
	if dock != null:
		dock.root_guides_changed.connect(set_intent)
		set_intent(dock._draft.root_guides if dock._draft != null else {})


func _exit_tree() -> void:
	_detach()


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
	if is_instance_valid(scene_preview_player) and is_instance_valid(player) and player.is_animation_active():
		scene_preview_player.seek(clampf(player.current_animation_position, 0, scene_preview_player.get_animation("motion").length), true, true)


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
	var ready := check_current_binding()
	if not ready["ok"]:
		_message(ready["message"])
		return
	var frame := _frame()
	if frame < 0 or frame >= dock._draft.duration_frames or not is_instance_valid(guide):
		_message("Choose a paused native time whose nearest 30 FPS frame is within the session duration.")
		return
	var direction := guide.global_basis * Vector3.FORWARD * -1
	if not guide.global_transform.is_finite() or Vector2(direction.x, direction.z).length_squared() < 0.000001:
		_message("The guide transform/facing is invalid. Keep its +Z arrow horizontal.")
		return
	var position := guide.global_position
	position.y = Space.decode_transform(dock._draft.root_guides["space"]["placement"]).origin.y
	var point := {"frame": frame, "world_position": Space.vector(position), "world_heading": atan2(direction.x, direction.z), "use_heading": heading_check.button_pressed}
	_pending = {"session_id": dock._draft.session_id, "before": dock._draft.root_guides.duplicate(true), "point": point, "time": player.current_animation_position, "animation": player.assigned_animation}
	for existing in dock._draft.root_guides["points"]:
		if existing["frame"] == frame:
			replace_dialog.dialog_text = "Replace the root waypoint at frame %d?" % frame
			replace_dialog.popup_centered()
			return
	_commit_pending()


func _commit_pending() -> void:
	replace_dialog.hide()
	if _pending.is_empty():
		return
	var ready := check_current_binding()
	if not ready["ok"] or dock._draft.session_id != _pending["session_id"] or dock._draft.root_guides != _pending["before"] or not player.active or player.is_playing() or not player.is_animation_active() or player.current_animation_position != _pending["time"] or player.assigned_animation != _pending["animation"]:
		_pending.clear()
		_message("The destination changed while reviewing. Record the waypoint again.")
		return
	var after: Dictionary = _pending["before"].duplicate(true)
	for index in range(after["points"].size() - 1, -1, -1):
		if after["points"][index]["frame"] == _pending["point"]["frame"]:
			after["points"].remove_at(index)
	after["points"].append(_pending["point"])
	_pending.clear()
	var checked := Service.constraints(after, dock._draft.pose_keyframes, dock._draft.duration_frames)
	if not checked["ok"]:
		_message(checked["message"])
		return
	dock.edit_root_guides(after)
	_message("Waypoint recorded. Review the route, then Generate.")


func remove_selected() -> void:
	if dock._draft == null or dock._guide_editing_locked():
		return
	var selected := points_list.get_selected_items()
	if selected.is_empty():
		return
	var after: Dictionary = dock._draft.root_guides.duplicate(true)
	for index in range(after["points"].size() - 1, -1, -1):
		if after["points"][index]["frame"] == _frames[selected[0]]:
			after["points"].remove_at(index)
	dock.edit_root_guides(after)


func clear_guides() -> void:
	if dock != null and dock._draft != null and not dock._guide_editing_locked():
		dock.edit_root_guides({})
		_detach()
		_message("Guides cleared with Undo available. Select the character again to use its current placement.")


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
		points_list.add_item("Frame %d%s" % [point["frame"], " · facing" if point["use_heading"] else ""])
	_draw_path()


func _select_point(index: int) -> void:
	if not is_instance_valid(guide) or dock._draft == null:
		return
	for point in dock._draft.root_guides["points"]:
		if point["frame"] == _frames[index]:
			guide.global_transform = Transform3D(Basis(Vector3.UP, point["world_heading"]), Space.unvector(point["world_position"]))
			heading_check.button_pressed = point["use_heading"]
			select_guide()


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
		var marker := SphereMesh.new()
		marker.radius = 0.035
		marker.height = 0.07
		var position := Space.unvector(point["world_position"])
		_mesh(path_node, marker, Transform3D(Basis.IDENTITY, position))
		var label := Label3D.new()
		label.text = str(point["frame"])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		path_node.add_child(label)
		label.global_position = position + Vector3.UP * 0.15


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
