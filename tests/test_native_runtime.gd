extends SceneTree

const NATIVE_SCENE := "res://tests/native/generated/soma77_walk.tscn"
const EXPECTED_NAMES := [
	"Hips", "Spine1", "Spine2", "Chest", "Neck1", "Neck2", "Head", "HeadEnd", "Jaw",
	"LeftEye", "RightEye", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"LeftHandThumb1", "LeftHandThumb2", "LeftHandThumb3", "LeftHandThumbEnd",
	"LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3", "LeftHandIndex4",
	"LeftHandIndexEnd", "LeftHandMiddle1", "LeftHandMiddle2", "LeftHandMiddle3",
	"LeftHandMiddle4", "LeftHandMiddleEnd", "LeftHandRing1", "LeftHandRing2",
	"LeftHandRing3", "LeftHandRing4", "LeftHandRingEnd", "LeftHandPinky1",
	"LeftHandPinky2", "LeftHandPinky3", "LeftHandPinky4", "LeftHandPinkyEnd",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightHandThumb1",
	"RightHandThumb2", "RightHandThumb3", "RightHandThumbEnd", "RightHandIndex1",
	"RightHandIndex2", "RightHandIndex3", "RightHandIndex4", "RightHandIndexEnd",
	"RightHandMiddle1", "RightHandMiddle2", "RightHandMiddle3", "RightHandMiddle4",
	"RightHandMiddleEnd", "RightHandRing1", "RightHandRing2", "RightHandRing3",
	"RightHandRing4", "RightHandRingEnd", "RightHandPinky1", "RightHandPinky2",
	"RightHandPinky3", "RightHandPinky4", "RightHandPinkyEnd", "LeftLeg", "LeftShin",
	"LeftFoot", "LeftToeBase", "LeftToeEnd", "RightLeg", "RightShin", "RightFoot",
	"RightToeBase", "RightToeEnd",
]

var _failures: Array[String] = []


func _init() -> void:
	_check(not Engine.is_editor_hint(), "native acceptance runs without editor plugins")
	_validate_dependency_closure(NATIVE_SCENE)

	var packed := ResourceLoader.load(
		NATIVE_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	_check(packed != null, "native scene loads")
	if packed == null:
		_finish()
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var skeleton := _find_first(instance, "Skeleton3D") as Skeleton3D
	var player := _find_first(instance, "AnimationPlayer") as AnimationPlayer
	_check(skeleton != null, "native scene contains Skeleton3D")
	_check(player != null, "native scene contains AnimationPlayer")
	if skeleton != null:
		var names: Array[String] = []
		for index in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(index))
		_check(names == EXPECTED_NAMES, "native scene retains canonical SOMA-77 bones")
	if skeleton != null and player != null:
		var animation := player.get_animation("motion")
		_check(animation != null, "stable native animation name resolves")
		_check(animation.get_track_count() == 69, "native animation retains expected tracks")
		_check(is_equal_approx(animation.length, 29.0 / 30.0), "native duration is unchanged")
		_validate_track_paths(animation, skeleton)
		player.play("motion")
		player.advance(animation.length * 0.5)
		var minimum_y := INF
		var maximum_y := -INF
		for index in skeleton.get_bone_count():
			var pose := skeleton.get_bone_global_pose(index)
			_check(pose.is_finite(), "sampled bone pose is finite")
			minimum_y = minf(minimum_y, pose.origin.y)
			maximum_y = maxf(maximum_y, pose.origin.y)
		_check(maximum_y - minimum_y > 1.0, "sampled skeleton has non-collapsed bone positions")

	instance.queue_free()
	_finish()


func _validate_dependency_closure(path: String) -> void:
	var pending: Array[String] = [path]
	var visited: Dictionary = {}
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		_check(not current.contains("addons/"), "native closure excludes addon code")
		_check(not current.ends_with(".gltf"), "native closure excludes source glTF")
		for dependency in ResourceLoader.get_dependencies(current):
			var dependency_path := String(dependency)
			# Typed dependency strings may be `type::path`; the path is last.
			if dependency_path.contains("::"):
				dependency_path = dependency_path.get_slice("::", 2)
			pending.append(dependency_path)
	_check(visited.size() == 2, "native closure contains only scene and AnimationLibrary")


func _validate_track_paths(animation: Animation, skeleton: Skeleton3D) -> void:
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		_check(path.get_name_count() == 1, "track targets one stable skeleton node")
		_check(path.get_name(0) == "Soma77Skeleton", "track uses stable skeleton node name")
		_check(path.get_subname_count() == 1, "track targets one bone")
		_check(
			skeleton.find_bone(path.get_subname(0)) >= 0,
			"track bone exists in native skeleton",
		)


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
		print("PASS: native runtime is self-contained and addon/glTF independent")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
