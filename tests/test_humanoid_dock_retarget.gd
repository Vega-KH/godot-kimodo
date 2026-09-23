extends SceneTree

const MotionResponse := preload(
	"res://addons/kimodo_motion/transport/mmcp_motion_response.gd"
)
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const SAMPLE_TIMES := [0.0, 0.25, 0.5, 29.0 / 30.0]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dock := Dock.new()
	root.add_child(dock)
	await process_frame
	var retarget := dock.find_child("RetargetHumanoid", true, false) as Button
	var save := dock.find_child("SaveHumanoidTake", true, false) as Button
	var selector := dock.find_child("PreviewSelection", true, false) as OptionButton
	var source: Control = dock.find_child("MotionPreview", true, false)
	var humanoid: Control = dock.find_child("HumanoidPreview", true, false)
	_check(retarget.disabled, "retarget begins disabled")
	_check(save.disabled, "humanoid save begins disabled")
	_check(not selector.visible, "preview selector begins hidden")
	_check(not dock._accept_source_motion(null), "invalid source is rejected")
	_check(not source.has_motion(), "invalid source does not create preview state")

	_check(dock._accept_source_motion(_parse_motion()), "validated motion enters the dock")
	_check(not retarget.disabled, "retarget enables for a validated source")
	var source_scene: Node = source.motion_scene()
	retarget.emit_signal("pressed")
	_check(humanoid.has_motion(), "retarget action creates an in-memory humanoid preview")
	_check(source.motion_scene() == source_scene, "retargeting preserves the source preview")
	_check(humanoid.skeleton().get_bone_count() == 56, "preview uses the 56-bone profile")
	_check(_animation(humanoid).get_track_count() == 24, "preview has 24 target tracks")
	_check(selector.visible and not selector.disabled, "preview selector becomes available")
	_check(not save.disabled, "humanoid save enables after retargeting")
	_check(humanoid.visible and not source.visible, "retarget result is selected")

	selector.select(0)
	selector.emit_signal("item_selected", 0)
	_check(source.visible and not humanoid.visible, "source preview can be selected")
	selector.select(1)
	selector.emit_signal("item_selected", 1)
	_check(humanoid.visible and not source.visible, "humanoid preview can be selected")
	dock._seek_previews(0.5)
	_check(absf(source.current_position() - 0.5) < 0.001, "scrub seeks the source")
	_check(absf(humanoid.current_position() - 0.5) < 0.001, "scrub seeks the humanoid")
	var loop_toggle := dock.find_child("LoopMotion", true, false) as CheckButton
	loop_toggle.button_pressed = false
	loop_toggle.emit_signal("toggled", false)
	_check(_animation(source).loop_mode == Animation.LOOP_NONE, "loop state reaches source")
	_check(_animation(humanoid).loop_mode == Animation.LOOP_NONE, "loop state reaches humanoid")
	var play := dock.find_child("PlayPause", true, false) as Button
	play.emit_signal("pressed")
	_check(not source.is_playing() and not humanoid.is_playing(), "pause controls both previews")

	var preview_scene: Node = humanoid.motion_scene()
	var preview_animation := _animation(humanoid)
	var relative_directory := "res://tests/.goal10_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()
	]
	var directory := dock.find_child("HumanoidTakeDirectory", true, false) as LineEdit
	var take_name := dock.find_child("HumanoidTakeName", true, false) as LineEdit
	directory.text = relative_directory
	take_name.text = "dock humanoid"
	save.emit_signal("pressed")
	var first_scene := relative_directory.path_join("dock humanoid.tscn")
	var first_library := relative_directory.path_join("dock humanoid.res")
	var save_status := dock.find_child("HumanoidTakeStatus", true, false) as Label
	_check(FileAccess.file_exists(first_scene), "humanoid scene is saved")
	_check(FileAccess.file_exists(first_library), "humanoid library is saved")
	_check(save_status.text.contains(first_scene), "saved paths are reported")
	_check(humanoid.motion_scene() == preview_scene, "save preserves preview ownership")
	save.emit_signal("pressed")
	_check(
		FileAccess.file_exists(relative_directory.path_join("dock humanoid_2.tscn")),
		"duplicate save uses a unique scene name",
	)
	_check(
		FileAccess.file_exists(relative_directory.path_join("dock humanoid_2.res")),
		"duplicate save uses a unique library name",
	)

	var packed := ResourceLoader.load(
		first_scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var saved_scene := packed.instantiate()
	root.add_child(saved_scene)
	var saved_skeleton := _find_first(saved_scene, "Skeleton3D") as Skeleton3D
	var saved_player := _find_first(saved_scene, "AnimationPlayer") as AnimationPlayer
	_check(saved_skeleton.get_bone_count() == 56, "saved scene reloads its target skeleton")
	_compare_animations(preview_animation, saved_player.get_animation("motion"))

	directory.text = "user://not-project-relative"
	save.emit_signal("pressed")
	_check(save_status.text.contains("res://"), "invalid humanoid destination is rejected")
	_check(humanoid.motion_scene() == preview_scene, "save failure preserves the preview")

	var old_humanoid_scene: Node = humanoid.motion_scene()
	_check(dock._accept_source_motion(_parse_motion()), "a replacement source is accepted")
	_check(not is_instance_valid(old_humanoid_scene), "replacement frees the derived preview")
	_check(not humanoid.has_motion(), "replacement clears humanoid state")
	_check(save.disabled and not selector.visible, "replacement resets humanoid controls")

	var invalid_root := Node3D.new()
	invalid_root.name = "InvalidFixture"
	var invalid_fixture := PackedScene.new()
	_check(invalid_fixture.pack(invalid_root) == OK, "invalid fixture packs for error coverage")
	invalid_root.free()
	var invalid_dock := Dock.new()
	invalid_dock.configure(null, null, null, invalid_fixture)
	root.add_child(invalid_dock)
	await process_frame
	_check(invalid_dock._accept_source_motion(_parse_motion()), "invalid-fixture source loads")
	var invalid_source: Control = invalid_dock.find_child("MotionPreview", true, false)
	var invalid_source_scene: Node = invalid_source.motion_scene()
	var invalid_retarget := invalid_dock.find_child("RetargetHumanoid", true, false) as Button
	invalid_retarget.emit_signal("pressed")
	var error_status := invalid_dock.find_child("HumanoidRetargetStatus", true, false) as Label
	_check(error_status.text.contains("Skeleton3D"), "invalid fixture gets a local retarget error")
	_check(invalid_source.motion_scene() == invalid_source_scene, "fixture error preserves source")

	saved_scene.queue_free()
	dock.queue_free()
	invalid_dock.queue_free()
	await process_frame
	_remove_test_directory(relative_directory)
	_check(root.get_child_count() == 0, "dock previews leave no nodes behind")
	_finish()


func _parse_motion() -> RefCounted:
	var parsed := MotionResponse.parse(
		FileAccess.get_file_as_bytes(MOTION_FIXTURE), 30, 30.0
	)
	_check(parsed["ok"], "motion fixture parses")
	return parsed["motion"] if parsed["ok"] else null


func _animation(preview: Control) -> Animation:
	var player: AnimationPlayer = preview.animation_player()
	return player.get_animation(player.get_animation_list()[0])


func _compare_animations(source: Animation, saved: Animation) -> void:
	var saved_by_key := {}
	for track in saved.get_track_count():
		saved_by_key[_track_key(saved, track)] = track
	for source_track in source.get_track_count():
		var key := _track_key(source, source_track)
		_check(saved_by_key.has(key), "saved humanoid retains %s" % key)
		if not saved_by_key.has(key):
			continue
		for time in SAMPLE_TIMES:
			var before: Variant = _sample(source, source_track, time)
			var after: Variant = _sample(saved, saved_by_key[key], time)
			if before is Quaternion:
				_check(
					before.normalized().angle_to(after.normalized()) <= 0.001,
					"%s rotation matches" % key,
				)
			else:
				_check(before.distance_to(after) <= 0.000001, "%s position matches" % key)


func _track_key(animation: Animation, track: int) -> String:
	var path := animation.track_get_path(track)
	return "%d:%s" % [animation.track_get_type(track), path.get_subname(0)]


func _sample(animation: Animation, track: int, time: float) -> Variant:
	if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
		return animation.rotation_track_interpolate(track, time)
	return animation.position_track_interpolate(track, time)


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _remove_test_directory(directory: String) -> void:
	var absolute := ProjectSettings.globalize_path(directory)
	var access := DirAccess.open(absolute)
	if access == null:
		return
	for file_name in access.get_files():
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: dock retarget preview, playback, unique save, reload, and cleanup")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
