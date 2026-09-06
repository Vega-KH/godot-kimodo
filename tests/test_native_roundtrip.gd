extends SceneTree

const Loader := preload("res://addons/kimodo_motion/transport/mmcp_gltf_loader.gd")
const Baker := preload("res://addons/kimodo_motion/animation/native_animation_baker.gd")
const SOURCE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const SAMPLE_TIMES := [0.0, 0.25, 0.5, 29.0 / 30.0]
const ROTATION_TOLERANCE_RADIANS := 0.001
const POSITION_TOLERANCE_METERS := 0.000001

var _failures: Array[String] = []


func _init() -> void:
	var imported: Node = Loader.load_from_buffer(FileAccess.get_file_as_bytes(SOURCE))
	_check(imported != null, "source fixture imports")
	if imported == null:
		_finish()
		return
	root.add_child(imported)
	var source_player := _find_first(imported, "AnimationPlayer") as AnimationPlayer
	var source_skeleton := _find_first(imported, "Skeleton3D") as Skeleton3D
	var source_animation := source_player.get_animation(source_player.get_animation_list()[0])

	var output_directory := "user://goal5_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var first := Baker.bake(imported, output_directory, "walk")
	_check(not first.is_empty(), "first native bake succeeds")
	if first.is_empty():
		_finish()
		return
	var first_scene_hash := _sha256(FileAccess.get_file_as_bytes(first["scene_path"]))
	var first_library_hash := _sha256(FileAccess.get_file_as_bytes(first["library_path"]))

	var second := Baker.bake(imported, output_directory, "walk")
	_check(second["stem"] == "walk_2", "existing output produces a unique name")
	_check(first["scene_path"] != second["scene_path"], "scene output is not overwritten")
	_check(first["library_path"] != second["library_path"], "library output is not overwritten")
	_check(
		_sha256(FileAccess.get_file_as_bytes(first["scene_path"])) == first_scene_hash,
		"first scene remains byte-identical after the second bake",
	)
	_check(
		_sha256(FileAccess.get_file_as_bytes(first["library_path"])) == first_library_hash,
		"first library remains byte-identical after the second bake",
	)

	var packed := ResourceLoader.load(
		first["scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var reloaded := packed.instantiate()
	root.add_child(reloaded)
	var native_skeleton := _find_first(reloaded, "Skeleton3D") as Skeleton3D
	var native_player := _find_first(reloaded, "AnimationPlayer") as AnimationPlayer
	_check(native_skeleton.get_bone_count() == 77, "reloaded scene retains 77 bones")
	for index in source_skeleton.get_bone_count():
		_check(
			native_skeleton.get_bone_rest(index).is_equal_approx(
				source_skeleton.get_bone_rest(index)
			),
			"bone %d rest round-trip" % index,
		)
		_check(
			native_skeleton.get_bone_pose(index).is_equal_approx(
				source_skeleton.get_bone_pose(index)
			),
			"bone %d initial pose round-trip" % index,
		)
	_check(native_player.get_animation_list() == PackedStringArray(["motion"]), "stable animation name")
	var native_animation := native_player.get_animation("motion")
	_check(native_animation.get_track_count() == 69, "reloaded animation retains 69 native tracks")
	_check(
		is_equal_approx(native_animation.length, source_animation.length),
		"reloaded animation retains duration",
	)
	_compare_animations(source_animation, native_animation)

	reloaded.queue_free()
	imported.queue_free()
	_finish()


func _compare_animations(source: Animation, native: Animation) -> void:
	var native_by_key := {}
	for track in native.get_track_count():
		native_by_key[_track_key(native, track)] = track
	for source_track in source.get_track_count():
		var key := _track_key(source, source_track)
		_check(native_by_key.has(key), "native animation retains track %s" % key)
		if not native_by_key.has(key):
			continue
		var native_track: int = native_by_key[key]
		for time in SAMPLE_TIMES:
			var before: Variant = _sample(source, source_track, time)
			var after: Variant = _sample(native, native_track, time)
			if before is Quaternion:
				var angular_error: float = before.normalized().angle_to(after.normalized())
				_check(
					angular_error <= ROTATION_TOLERANCE_RADIANS,
					"%s rotation round-trip error %.9f" % [key, angular_error],
				)
			else:
				var position_error: float = before.distance_to(after)
				_check(
					position_error <= POSITION_TOLERANCE_METERS,
					"%s position round-trip error %.9f" % [key, position_error],
				)


func _track_key(animation: Animation, track: int) -> String:
	var path := animation.track_get_path(track)
	return "%d:%s" % [animation.track_get_type(track), path.get_subname(0)]


func _sample(animation: Animation, track: int, time: float) -> Variant:
	if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
		return animation.rotation_track_interpolate(track, time)
	return animation.position_track_interpolate(track, time)


func _sha256(data: PackedByteArray) -> PackedByteArray:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return hashing.finish()


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: native bake is unique, non-destructive, and numerically stable")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
