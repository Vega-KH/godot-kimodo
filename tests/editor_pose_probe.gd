@tool
extends EditorPlugin

# Enabled only by test-pose-editor.ps1 in a newly packaged isolated project.
# Exercises the real editor history and saved-scene resources, not fallback UndoRedo.
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Service := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
var failures: Array[String] = []


func _enter_tree() -> void:
	call_deferred("_run")


func _run() -> void:
	for frame in 20:
		await get_tree().process_frame
	var fixture := Fixture.create_scene()
	var player := AnimationPlayer.new()
	player.name = "PosePlayer"
	fixture.add_child(player)
	player.owner = fixture
	var animation := Animation.new()
	animation.length = 2.0
	var library := AnimationLibrary.new()
	library.add_animation("work", animation)
	player.add_animation_library("", library)
	var packed := PackedScene.new()
	_check(packed.pack(fixture) == OK, "fixture packed")
	_check(ResourceSaver.save(packed, "res://editor_pose_scene.tscn") == OK, "native scene saved")
	fixture.free()
	EditorInterface.open_scene_from_path("res://editor_pose_scene.tscn")
	for frame in 30:
		await get_tree().process_frame
	var scene := EditorInterface.get_edited_scene_root()
	var panel := EditorInterface.get_base_control().find_child("Pose Library", true, false)
	_check(scene != null and panel != null, "edited scene and separate panel available")
	if scene == null or panel == null:
		_finish()
		return
	var skeleton := scene.get_node("HumanoidSkeleton") as Skeleton3D
	player = scene.get_node("PosePlayer") as AnimationPlayer
	EditorInterface.edit_node(player)
	for frame in 10:
		await get_tree().process_frame
	var native_editor := EditorInterface.get_base_control().find_children("*", "AnimationPlayerEditor", true, false)
	_check(native_editor.size() == 1, "native animation editor available")
	if native_editor.is_empty():
		_finish()
		return
	var native_cursor: SpinBox
	for control in native_editor[0].find_children("*", "SpinBox", true, false):
		if control.tooltip_text == "Animation position (in seconds).":
			native_cursor = control
	_check(native_cursor != null, "native animation cursor control available")
	if native_cursor == null:
		_finish()
		return
	# Test-only access to native controls exercises their normal seek signals.
	# Production follows public AnimationPlayer state and never searches this tree.
	var native_track: Node = native_editor[0].find_children("*", "AnimationTrackEditor", true, false)[0]
	native_track.emit_signal("timeline_changed", 0.5, false, false)
	_check(player.assigned_animation == "work" and player.is_animation_active(), "native clip reflected in public player")
	_check(is_equal_approx(player.current_animation_position, 0.5), "native cursor reflected in public player")
	panel.set_target(skeleton, player)
	var hand := skeleton.find_bone("LeftHand")
	var before := skeleton.get_bone_pose_rotation(hand)
	var edited := before * Quaternion(Vector3.RIGHT, 0.5)
	skeleton.set_bone_pose_rotation(hand, edited)
	panel.bone_list.select(hand)
	panel.title_edit.text = "Editor hand"
	panel.capture_current()
	skeleton.set_bone_pose_rotation(hand, before)
	native_track.emit_signal("timeline_changed", 0.5, false, false)
	var original := player.get_animation("work")
	print("EDITOR_POSE_NATIVE_RESOURCE_PATH ", original.resource_path)
	panel.request_key()
	print("EDITOR_FIRST_KEY ", player.assigned_animation, " ", player.current_animation_position, " ", panel.status.text)
	_check(player.get_animation("work").get_track_count() == 1, "saved native scene animation accepts keys")
	_check(skeleton.get_bone_pose_rotation(hand).is_equal_approx(edited), "key action applies edited pose")
	var manager := get_undo_redo()
	var history_id := manager.get_object_history_id(skeleton)
	_check(history_id > 0, "pose action belongs to edited scene history")
	var history := manager.get_history_undo_redo(history_id)
	if history != null and history.has_undo():
		history.undo()
		_check(player.get_animation("work") == original, "real editor undo restores native resource")
		_check(skeleton.get_bone_pose_rotation(hand).is_equal_approx(before), "real editor undo restores pose values")
		history.redo()
		_check(player.get_animation("work").get_track_count() == 1, "real editor redo restores keys")
	else:
		_check(false, "real editor history has pose action")
	for frame in 5:
		await get_tree().process_frame
	_check(is_equal_approx(player.current_animation_position, 0.5), "native cursor stable through key undo redo")
	# A second time, then confirmed replacement at that same time.
	native_track.emit_signal("timeline_changed", 1.0, false, false)
	print("EDITOR_SECOND_CURSOR ", native_cursor.value, " ", player.current_animation_position)
	_check(is_equal_approx(player.current_animation_position, 1.0), "native second cursor updates player")
	panel.request_key()
	print("EDITOR_SECOND_KEY ", player.assigned_animation, " ", player.current_animation_position, " ", panel.status.text)
	for frame in 5:
		await get_tree().process_frame
	_check(is_equal_approx(player.current_animation_position, 1.0), "native cursor stable after key")
	_check(player.get_animation("work").get_track_count() == 1 and player.get_animation("work").track_get_key_count(0) == 2, "second native time keyed")
	panel.request_key()
	_check(not panel._pending_key.is_empty(), "native key collision review")
	panel.replace_dialog.confirmed.emit()
	_check(panel._pending_key.is_empty(), "real editor confirmed replacement")
	_check(EditorInterface.save_scene() == OK, "editor saves keyed scene")
	var saved := (ResourceLoader.load("res://editor_pose_scene.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved_player := saved.get_node("PosePlayer") as AnimationPlayer
	_check(saved_player.get_animation("work").get_track_count() == 1 and saved_player.get_animation("work").track_get_key_count(0) == 2, "saved scene reload retains native pose keys")
	saved.free()
	panel.title_edit.text = "independent"
	panel.copy_animation()
	_check(player.has_animation("pose_edits/independent"), "editor creates independent copy")
	history.undo()
	_check(not player.has_animation("pose_edits/independent"), "real editor undo removes copied animation")
	history.redo()
	_check(player.has_animation("pose_edits/independent"), "real editor redo restores copied animation")
	_check(EditorInterface.save_scene() == OK, "save copied animation")
	for frame in 5:
		await get_tree().process_frame
	# Pick the newly added clip through the native editor dropdown, not Pose Library.
	var native_selector: OptionButton
	var copy_index := -1
	for control in native_editor[0].find_children("*", "OptionButton", true, false):
		for index in control.item_count:
			if control.get_item_text(index) == "pose_edits/independent":
				native_selector = control
				copy_index = index
	_check(native_selector != null, "new copy available in native selector")
	if native_selector == null:
		_finish()
		return
	native_selector.select(copy_index)
	native_selector.item_selected.emit(copy_index)
	native_track.emit_signal("timeline_changed", 1.5, false, false)
	await get_tree().process_frame
	_check(panel.animation_selector.get_item_text(panel.animation_selector.selected) == "pose_edits/independent", "Pose Library follows native selected clip")
	panel.request_key()
	_check(player.get_animation("pose_edits/independent").track_get_key_count(0) == 3, "saved editable copy remains keyable")
	print("EDITOR_COPY_KEY ", native_cursor.value, " ", player.assigned_animation, " ", player.current_animation_position, " ", panel.status.text, " pending ", panel._pending_key.size())
	_check(player.get_animation("work").track_get_key_count(0) == 2, "editing independent copy preserves original native animation")
	history.undo()
	_check(player.get_animation("pose_edits/independent").track_get_key_count(0) == 2, "real editor undo restores saved copy keys")
	_check(EditorInterface.save_scene() == OK, "save final copied scene")
	var dock := EditorInterface.get_base_control().find_child("AI Motion", true, false)
	# The probe emits confirmation signals directly; native button clicks would
	# already have hidden this pose-replacement modal before changing docks.
	panel.replace_dialog.hide()
	var session := Session.create_new("Editor root guides")
	var saved_session := Store.save_as(session, "res://guide_session", "scene_guides")
	_check(saved_session["ok"], "editor guide session saved")
	dock._session_controller.session = session
	dock._session_controller.path = saved_session["path"]
	dock._activate_session(session, saved_session["path"], {})
	dock._client.capabilities = Capabilities.parse_json_text(FileAccess.get_file_as_string("res://guide_capabilities.json"))["capabilities"]
	# This synthetic editor fixture has no skin/mesh. Use its explicit exact-name
	# reviewed profile; private-character compatibility is covered by live tests.
	dock._rig_profile = Profile.exact_names(skeleton, scene.get_path_to(skeleton))["profile"]
	session.target_scene_path = "res://editor_pose_scene.tscn"
	session.target_skeleton_signature = Store.skeleton_signature(skeleton)
	scene.position = Vector3(3, 0, -2)
	scene.rotation.y = 0.6
	var guides: Control = dock._guides_panel
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(skeleton)
	panel.set_target(null, null)
	guides.use_selection()
	_check(panel.skeleton == skeleton and panel.player == player, "motion dock scene selection also binds Pose Library")
	_check(guides.guide != null, "real editor scene guide created")
	if guides.guide == null:
		print("EDITOR_GUIDE_STATUS ", guides.status.text)
		_finish()
		return
	guides.select_guide()
	_check(EditorInterface.get_selection().get_selected_nodes().has(guides.guide), "native scene guide selected for transform gizmo")
	EditorInterface.edit_node(player)
	for frame in 5:
		await get_tree().process_frame
	native_track.emit_signal("timeline_changed", 0.0, false, false)
	guides.record_current()
	native_track.emit_signal("timeline_changed", 0.501, false, false)
	_check(guides._frame() == 15, "native editor scrub rounds to nearest Kimodo frame")
	guides.guide.global_position += Vector3(0.4, 0, 0.5)
	guides.heading_check.button_pressed = true
	guides.record_current()
	_check(session.root_guides["points"].size() == 2, "real editor native root waypoints recorded")
	var guide_history_id := manager.get_object_history_id(session)
	var guide_history := manager.get_history_undo_redo(guide_history_id)
	guide_history.undo()
	_check(session.root_guides["points"].size() == 1, "real editor guide intent undo")
	guide_history.redo()
	_check(session.root_guides["points"].size() == 2, "real editor guide intent redo")
	# Native 3D gizmos store a Node3D transform in scene history. Exercise that
	# same property operation with the real editor manager, including Undo/Redo.
	dock._character_target = load("res://editor_pose_scene.tscn") as PackedScene
	guides.edit_character.button_pressed = true
	var hips := skeleton.find_bone("Hips")
	var hips_before := skeleton.get_bone_global_pose(hips)
	var guide_before: Transform3D = guides.guide.global_transform
	var guide_after := guide_before
	guide_after.origin += Vector3(0.4, 0, -0.2)
	guide_after.basis = Basis(Vector3.UP, 0.35) * guide_after.basis
	manager.create_action("Move root guide probe", UndoRedo.MERGE_DISABLE, guides.guide)
	manager.add_do_property(guides.guide, "global_transform", guide_after)
	manager.add_undo_property(guides.guide, "global_transform", guide_before)
	manager.commit_action()
	for frame in 3:
		await get_tree().process_frame
	_check(not skeleton.get_bone_global_pose(hips).is_equal_approx(hips_before), "native guide transform edits Hips visually")
	var transform_history := manager.get_history_undo_redo(manager.get_object_history_id(guides.guide))
	transform_history.undo()
	for frame in 3:
		await get_tree().process_frame
	_check(skeleton.get_bone_global_pose(hips).is_equal_approx(hips_before), "native guide Undo restores Hips")
	transform_history.redo()
	for frame in 3:
		await get_tree().process_frame
	guides.record_pose_current()
	if not guides._pending.is_empty():
		guides.replace_dialog.confirmed.emit()
	_check(session.pose_keyframes.size() == 1 and session.root_guides["points"].size() == 2, "real editor combined recording")
	guide_history.undo()
	_check(session.pose_keyframes.is_empty() and session.root_guides["points"].size() == 2, "one session Undo restores waypoint and pose together")
	guide_history.redo()
	_check(session.pose_keyframes.size() == 1, "one session Redo restores combined pair")
	_check(guides.path_node.find_child("KimodoAuthoredPose_15", true, false) != null, "real editor authored ghost reconstructed")
	native_track.emit_signal("timeline_changed", 1.0, false, false)
	var authored_ghost: Node = guides.path_node.find_child("KimodoAuthoredPose_15", true, false)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(authored_ghost)
	for frame in 4:
		await get_tree().process_frame
	_check(is_equal_approx(player.current_animation_position, 1.0) and is_equal_approx(native_cursor.value, 1.0), "selecting authored ghost preserves native/public timeline agreement")
	_check(EditorInterface.get_selection().get_selected_nodes().has(guides.guide), "selecting authored ghost returns guide for editing")
	print("EDITOR_AUTHORED_FRAME cursor=", native_cursor.value, " player=", player.current_animation_position)
	_check(dock._session_controller.flush()["ok"], "real editor root guides persist")
	dock._workspace_tabs.current_tab = guides.get_index()
	guides.select_guide()
	for frame in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_check(EditorInterface.get_editor_viewport_3d().get_texture().get_image().save_png("res://guide_viewport.png") == OK, "guide viewport rendered")
	_check(get_viewport().get_texture().get_image().save_png("res://guide_editor.png") == OK, "guide editor panel rendered")
	_check(EditorInterface.save_scene() == OK, "scene saves while helpers present")
	var clean := (ResourceLoader.load("res://editor_pose_scene.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_check(clean.find_child("KimodoRootGuide", true, false) == null and clean.find_child("KimodoRootPath", true, false) == null, "temporary scene helpers excluded from saved scene")
	clean.free()
	_finish()


func _check(condition: bool, description: String) -> void:
	if not condition:
		print("EDITOR_CHECK_FAILED ", description)
		failures.append(description)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: actual editor native pose keys, scene history Undo/Redo and save/reload")
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
