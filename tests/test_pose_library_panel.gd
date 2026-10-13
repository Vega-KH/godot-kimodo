extends SceneTree

const PosePanel := preload("res://addons/kimodo_motion/ui/pose_library_panel.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Service := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var character := Fixture.create_scene()
	var skeleton := character.get_child(0) as Skeleton3D
	var player := AnimationPlayer.new()
	character.add_child(player)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 2
	animation.take_over_path("res://tests/native_pose_scene.tscn::Animation_test")
	library.add_animation("work", animation)
	player.add_animation_library("", library)
	root.add_child(character)
	var panel := PosePanel.new()
	root.add_child(panel)
	await process_frame
	panel.set_target(skeleton, player)
	player.assigned_animation = "work"
	player.seek(0.123456, false)
	panel.title_edit.text = "Hand"
	var hand := skeleton.find_bone("LeftHand")
	panel.bone_list.select(skeleton.find_bone("Root"))
	_check(panel._channels().is_empty(), "root capture defaults off")
	panel.root_check.button_pressed = true
	_check(panel._channels().has("Root"), "root capture explicitly enabled")
	panel.root_check.button_pressed = false
	panel.bone_list.deselect_all()
	panel.bone_list.select(hand)
	skeleton.set_bone_pose_rotation(hand, Quaternion(Vector3.UP, 0.5))
	panel.capture_current()
	_check(panel.pose != null, "independent panel captures without session/backend")
	_check(panel.pose.sample.track_get_key_value(0, 0).is_equal_approx(skeleton.get_bone_pose_rotation(hand)), "capture preserves manual bone edits instead of resampling")
	skeleton.reset_bone_pose(hand)
	var before := skeleton.get_bone_pose_rotation(hand)
	panel.preview_pose()
	_check(not skeleton.get_bone_pose_rotation(hand).is_equal_approx(before), "temporary preview")
	panel.cancel_preview()
	_check(skeleton.get_bone_pose_rotation(hand).is_equal_approx(before), "preview cancel exact")
	player.seek(1, false)
	panel.request_key()
	_check(player.get_animation("work").get_track_count() == 1, "keys native animation")
	_check(player.get_animation("work").track_get_key_time(0, 0) == 1.0, "keys public timeline position")
	panel._fallback_undo.undo()
	_check(player.get_animation("work") == animation, "key undo restores original resource")
	_check(animation.get_track_count() == 0, "key undo removes added track")
	panel._fallback_undo.redo()
	_check(player.get_animation("work").get_track_count() == 1, "key redo")
	player.assigned_animation = "work"
	player.seek(1, false)
	panel.request_key()
	_check(not panel._pending_key.is_empty(), "collision waits for confirmation")
	panel.replace_dialog.canceled.emit()
	_check(panel._pending_key.is_empty(), "collision cancel unchanged")
	panel.request_key()
	var changed := player.get_animation("work")
	changed.rotation_track_insert_key(0, 0.5, Quaternion.IDENTITY)
	panel._commit_pending_key()
	_check(player.get_animation("work") == changed and changed.track_get_key_count(0) == 2, "stale collision confirmation preserves newer edits")
	panel.request_key()
	player.seek(1.5, false)
	panel._commit_pending_key()
	_check(changed.track_get_key_count(0) == 2, "cursor change invalidates collision confirmation")
	panel.preview_pose()
	player.seek(0.25, false)
	skeleton.set_bone_pose_rotation(hand, Quaternion(Vector3.RIGHT, 0.2))
	panel.cancel_preview()
	_check(skeleton.get_bone_pose_rotation(hand).is_equal_approx(Quaternion(Vector3.RIGHT, 0.2)), "native cursor change does not restore stale preview")
	var fresh := Animation.new()
	fresh.length = 2
	library.add_animation("fresh", fresh)
	player.assigned_animation = "fresh"
	player.seek(0.123456, false)
	await process_frame
	await process_frame
	_check(panel.animation_selector.get_item_text(panel.animation_selector.selected) == "fresh", "new native clip appears and follows without reselecting character")
	panel.request_key()
	_check(is_equal_approx(player.get_animation("fresh").track_get_key_time(0, 0), 0.123456), "current frame preserves cursor precision")
	var prepared_frames: Array[int] = []
	panel.prepare_constraint = func(_skeleton: Skeleton3D, _pose: Resource, frame: int) -> Dictionary:
		prepared_frames.append(frame)
		return {"ok": false, "message": "Constraint frame probe"}
	for seconds in [0.991, 1.009, 0.982, 1.018]:
		player.seek(seconds, false)
		panel._prepare_constraint()
		_check(is_equal_approx(player.current_animation_position, seconds), "constraint rounding preserves native cursor")
	_check(prepared_frames == [30, 30, 29, 31], "constraint queue rounds to nearest 30 FPS frame")
	panel.title_edit.text = "edited"
	panel.copy_animation()
	_check(player.has_animation("pose_edits/edited"), "independent editable animation copy")
	panel._fallback_undo.undo()
	_check(not player.has_animation("pose_edits/edited"), "copy undo")
	player.assigned_animation = "fresh"
	player.seek(0.6, false)
	fresh = player.get_animation("fresh")
	fresh.loop_mode = Animation.LOOP_LINEAR
	fresh.step = 1.0 / 60.0
	fresh.add_marker("keep", 0.8)
	var body_track := fresh.add_track(Animation.TYPE_POSITION_3D)
	fresh.track_set_path(body_track, NodePath("HumanoidSkeleton:Spine"))
	fresh.position_track_insert_key(body_track, 0.2, Vector3(1, 2, 3))
	fresh.track_set_imported(0, true)
	panel.bone_list.select(skeleton.find_bone("RightHand"), false)
	panel.capture_current()
	var original_hash := panel.AnimationHash.animation_hash(fresh)
	panel.request_key()
	_check(player.get_animation("fresh") == fresh and player.current_animation_position == 0.6, "key preserves native resource and cursor")
	_check(fresh.track_get_key_value(fresh.find_track(NodePath("HumanoidSkeleton:Spine"), Animation.TYPE_POSITION_3D), 0) == Vector3(1, 2, 3), "key preserves unrelated tracks")
	_check(fresh.loop_mode == Animation.LOOP_LINEAR and is_equal_approx(fresh.step, 1.0 / 60.0) and fresh.get_marker_time("keep") == 0.8, "key preserves animation settings and markers")
	panel._fallback_undo.undo()
	_check(panel.AnimationHash.animation_hash(fresh) == original_hash, "multi-channel undo restores track order and complete settings")
	panel.set_target(skeleton, player)
	_check(panel.bone_list.get_selected_items().is_empty(), "target change clears bone selection")
	var imported := Animation.new()
	imported.take_over_path("res://tests/imported_character.glb::Animation_test")
	_check(PosePanel._is_imported_animation(imported), "imported scene clip requires independent copy")
	_check(not PosePanel._is_imported_animation(animation), "native scene subresource remains editable")
	var library_directory := "res://tests/.pose-filter-" + Session.create_uuid()
	var rig_a := Service.capture(skeleton, "Rig A hand", {"LeftHand": [Animation.TYPE_ROTATION_3D]})
	var other_skeleton := Fixture.create_skeleton()
	root.add_child(other_skeleton)
	other_skeleton.add_bone("ExtraBranch")
	other_skeleton.set_bone_parent(other_skeleton.get_bone_count() - 1, other_skeleton.find_bone("Hips"))
	var rig_b := Service.capture(other_skeleton, "Rig B hand", {"LeftHand": [Animation.TYPE_ROTATION_3D]})
	var path_a := library_directory.path_join("rig_a.tres")
	var path_b := library_directory.path_join("rig_b.tres")
	_check(Service.save_new(rig_a["pose"], path_a)["ok"] and Service.save_new(rig_b["pose"], path_b)["ok"], "isolated compatible/incompatible pose fixtures save")
	panel._library_directory = library_directory
	panel.set_target(skeleton, player)
	_check(panel._library_paths == [path_a] and panel.pose_list.get_item_text(0) == "Rig A hand", "pose list includes only poses compatible with selected rig")
	panel.set_target(other_skeleton, player)
	_check(panel._library_paths == [path_b], "switching character refreshes compatible poses automatically")
	panel.set_target(null, null)
	_check(panel._library_paths.is_empty() and panel.pose_list.item_count == 0, "no selected character leaves no compatible pose entries")
	panel.set_target(skeleton, player)
	_check(panel._library_paths == [path_a], "rebinding restores compatible pose list")
	other_skeleton.free()
	for filename in DirAccess.get_files_at(library_directory):
		DirAccess.remove_absolute(library_directory.path_join(filename))
	DirAccess.remove_absolute(library_directory)
	panel.free()
	character.free()
	if failures.is_empty():
		print("PASS: separate pose panel preview, key/copy undo and cancellation")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
