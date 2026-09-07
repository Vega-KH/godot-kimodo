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
	var save_button := dock.find_child("SaveNativeTake", true, false) as Button
	_check(save_button.disabled, "save begins disabled")

	var parsed := MotionResponse.parse(
		FileAccess.get_file_as_bytes(MOTION_FIXTURE), 30, 30.0
	)
	_check(parsed["ok"], "validated generated motion parses")
	if not parsed["ok"]:
		_finish()
		return
	var preview: Control = dock.find_child("MotionPreview", true, false)
	_check(preview.set_motion(parsed["motion"]), "validated motion enters preview")
	dock._update_save_availability()
	_check(not save_button.disabled, "save enables for a validated preview")
	var preview_scene: Node = preview.motion_scene()
	var preview_player: AnimationPlayer = preview.animation_player()
	var preview_animation := preview_player.get_animation(preview_player.get_animation_list()[0])

	var relative_directory := "res://tests/.goal8_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()
	]
	var directory_edit := dock.find_child("NativeTakeDirectory", true, false) as LineEdit
	var name_edit := dock.find_child("NativeTakeName", true, false) as LineEdit
	directory_edit.text = relative_directory
	name_edit.text = "combat preview"
	save_button.emit_signal("pressed")
	var status := dock.find_child("NativeTakeStatus", true, false) as Label
	var first_scene_path := relative_directory.path_join("combat preview.tscn")
	var first_library_path := relative_directory.path_join("combat preview.res")
	_check(FileAccess.file_exists(first_scene_path), "native scene is saved")
	_check(FileAccess.file_exists(first_library_path), "native animation library is saved")
	_check(status.text.contains(first_scene_path), "actual native paths are reported")
	_check(preview.motion_scene() == preview_scene, "saving does not replace the active preview")
	_check(is_instance_valid(preview_scene), "saving does not transfer preview ownership")

	save_button.emit_signal("pressed")
	_check(
		FileAccess.file_exists(relative_directory.path_join("combat preview_2.tscn")),
		"duplicate save receives a unique scene name",
	)
	_check(
		FileAccess.file_exists(relative_directory.path_join("combat preview_2.res")),
		"duplicate save receives a unique library name",
	)

	var packed := ResourceLoader.load(
		first_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var saved_scene := packed.instantiate()
	root.add_child(saved_scene)
	var saved_player := _find_first(saved_scene, "AnimationPlayer") as AnimationPlayer
	var saved_animation := saved_player.get_animation("motion")
	_compare_animations(preview_animation, saved_animation)
	var scene_text := FileAccess.get_file_as_string(first_scene_path)
	_check(not scene_text.contains(".gltf"), "saved scene has no glTF dependency")
	_check(not scene_text.contains("addons/"), "saved scene has no addon dependency")

	directory_edit.text = "user://not-project-relative"
	save_button.emit_signal("pressed")
	_check(status.text.contains("res://"), "non-project-relative destination is rejected")
	_check(preview.motion_scene() == preview_scene, "save failure leaves preview intact")

	saved_scene.queue_free()
	dock.queue_free()
	await process_frame
	_remove_test_directory(relative_directory)
	_finish()


func _compare_animations(source: Animation, saved: Animation) -> void:
	var saved_by_key := {}
	for track in saved.get_track_count():
		saved_by_key[_track_key(saved, track)] = track
	for source_track in source.get_track_count():
		var key := _track_key(source, source_track)
		_check(saved_by_key.has(key), "saved animation retains %s" % key)
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
		print("PASS: generated preview saves uniquely and remains independent")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
