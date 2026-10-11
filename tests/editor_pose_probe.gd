@tool
extends EditorPlugin

# Enabled only by test-pose-editor.ps1 in a newly packaged isolated project.
# Exercises the real editor history and saved-scene resources, not fallback UndoRedo.
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Service := preload("res://addons/kimodo_motion/poses/pose_service.gd")
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
