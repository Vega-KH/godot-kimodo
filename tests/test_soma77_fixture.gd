extends SceneTree

const FIXTURE_PATH := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const FIXTURE_SHA256 := "54a7a63a326149d4573005be29df49142345bec43240f4cc2451db6bd70461b0"
const GltfLoader := preload("res://addons/kimodo_motion/transport/mmcp_gltf_loader.gd")
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
	var data := FileAccess.get_file_as_bytes(FIXTURE_PATH)
	_check(not data.is_empty(), "fixture bytes can be read")
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	var digest: String = hashing.finish().hex_encode()
	_check(digest == FIXTURE_SHA256, "fixture SHA-256 matches provenance")

	var state: GLTFState = GltfLoader.parse_from_buffer(data)
	_check(state != null, "GLTFDocument parses fixture bytes")
	if state != null:
		_validate_source_channels(state.json)
	var imported: Node = GLTFDocument.new().generate_scene(state) if state != null else null
	_check(imported != null, "GLTFDocument imports fixture bytes")
	if imported == null:
		_finish()
		return

	root.add_child(imported)
	var skeleton := _find_first(imported, "Skeleton3D") as Skeleton3D
	var player := _find_first(imported, "AnimationPlayer") as AnimationPlayer
	_check(skeleton != null, "import creates Skeleton3D")
	_check(player != null, "import creates AnimationPlayer")
	if skeleton != null:
		_validate_skeleton(skeleton)
	if player != null:
		_validate_animation(player)

	imported.queue_free()
	_finish()


func _validate_skeleton(skeleton: Skeleton3D) -> void:
	_check(skeleton.get_bone_count() == 77, "skeleton contains 77 bones")
	var actual_names: Array[String] = []
	var root_count := 0
	for index in skeleton.get_bone_count():
		actual_names.append(skeleton.get_bone_name(index))
		var parent := skeleton.get_bone_parent(index)
		if parent < 0:
			root_count += 1
		else:
			_check(parent < index, "bone %s follows its parent" % skeleton.get_bone_name(index))
		_check(skeleton.get_bone_rest(index).is_finite(), "bone %s rest is finite" % index)
	_check(actual_names == EXPECTED_NAMES, "bone names retain canonical SOMA-77 order")
	_check(root_count == 1, "skeleton has exactly one root")


func _validate_source_channels(document: Dictionary) -> void:
	var channels: Array = document["animations"][0]["channels"]
	var rotation_channels := 0
	var translation_channels := 0
	for channel in channels:
		var path: String = channel["target"]["path"]
		if path == "rotation":
			rotation_channels += 1
		elif path == "translation":
			translation_channels += 1
	_check(channels.size() == 78, "source glTF has 78 animation channels")
	_check(rotation_channels == 77, "source glTF retains all 77 rotation channels")
	_check(translation_channels == 1, "source glTF has one root translation channel")


func _validate_animation(player: AnimationPlayer) -> void:
	var animation_names := player.get_animation_list()
	_check(animation_names.size() == 1, "import creates exactly one animation")
	if animation_names.is_empty():
		return
	var animation := player.get_animation(animation_names[0])
	_check(animation != null, "animation resource is accessible")
	if animation == null:
		return
	_check(is_equal_approx(animation.length, 29.0 / 30.0), "30 frames span 29/30 seconds")
	_check(animation.track_get_key_count(0) == 30, "animation retains 30 samples at 30 fps")
	_check(animation.get_track_count() == 69, "native animation has 68 varying rotations and one translation")

	var rotation_tracks := 0
	var position_tracks := 0
	for track in animation.get_track_count():
		var track_type := animation.track_get_type(track)
		if track_type == Animation.TYPE_ROTATION_3D:
			rotation_tracks += 1
		elif track_type == Animation.TYPE_POSITION_3D:
			position_tracks += 1
		for time in [0.0, animation.length * 0.5, animation.length]:
			var sample: Variant
			if track_type == Animation.TYPE_ROTATION_3D:
				sample = animation.rotation_track_interpolate(track, time)
			elif track_type == Animation.TYPE_POSITION_3D:
				sample = animation.position_track_interpolate(track, time)
			else:
				sample = null
			if sample is Quaternion:
				_check(sample.is_finite(), "rotation sample is finite")
			elif sample is Vector3:
				_check(sample.is_finite(), "position sample is finite")
			else:
				_check(false, "track interpolation returns a transform value")
	# Godot omits nine identity-only source rotation channels when generating
	# the native Animation. Their 77 Skeleton3D bones retain the rest rotation.
	_check(rotation_tracks == 68, "Godot removes only nine constant rotation tracks")
	_check(position_tracks == 1, "only the root has a translation track")


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
		print("PASS: SOMA-77 in-memory fixture import, hierarchy, tracks, and samples")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
