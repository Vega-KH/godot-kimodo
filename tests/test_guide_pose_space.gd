extends SceneTree

const GuidePose := preload("res://addons/kimodo_motion/guides/guide_pose_service.gd")
const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Converter := preload("res://addons/kimodo_motion/poses/character_pose_converter.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/soma77_capabilities.json"))["models"][0]["canonical_skeleton"]
	var source := Converter.canonical_skeleton(payload)
	for scale in [0.65, 1.0, 1.7]:
		var target := Fixture.create_skeleton()
		root.add_child(target)
		var profile: Resource = Profile.exact_names(target, NodePath("."))["profile"]
		profile.translation_scale_policy = "leg_height"
		profile.reference_measurements["leg_height"] *= scale
		target.transform = Transform3D(Basis(Vector3.UP, 0.73).scaled(Vector3.ONE * 1.3), Vector3(4, 0.5, -3))
		var hips := target.find_bone("Hips")
		var ancestor := target.get_bone_parent(hips)
		if ancestor >= 0:
			target.set_bone_pose_rotation(ancestor, Quaternion(Vector3.UP, -0.3) * target.get_bone_pose_rotation(ancestor))
		target.set_bone_pose_rotation(hips, target.get_bone_pose_rotation(hips) * Quaternion(Vector3.RIGHT, 0.2))
		var captured := Space.capture(target, profile, Space.unvector(payload["joints"][0]["rest_translation"]))
		var reference := GuidePose.create_reference(target, profile, payload)
		_check(reference["ok"] and GuidePose.validation_error(reference["reference"]).is_empty(), "calibration reference validates")
		var malformed: Dictionary = reference["reference"].duplicate(true)
		malformed["hips_calibration"][0][0] = 9.0
		_check(not GuidePose.validation_error(malformed).is_empty(), "invalid calibration rejected on reopening")
		var current := GuidePose.current_guide(target, profile, captured["space"], reference["reference"])
		var desired: Transform3D = current["transform"]
		desired.origin += Vector3(1.1, 0, -0.8)
		desired.basis = Basis(Vector3.UP, 0.5) * desired.basis
		var before := Converter.global_transforms(target, false)
		var locals: Array[Transform3D] = []
		for index in target.get_bone_count():
			locals.append(target.get_bone_pose(index))
		_check(GuidePose.apply_guide(target, profile, captured["space"], reference["reference"], desired)["ok"], "visual guide application succeeds")
		var after := Converter.global_transforms(target, false)
		var world: Vector3 = target.global_transform * after[hips].origin
		_check(Vector2(world.x, world.z).distance_to(Vector2(desired.origin.x, desired.origin.z)) < 0.00001, "target placement with profile and scene scale applied once")
		_check(absf(after[hips].origin.y - before[hips].origin.y) < 0.00001, "Hips height preserved")
		_check(after[hips].basis.is_equal_approx(Basis(Vector3.UP, 0.5) * before[hips].basis), "yaw preserves authored tilt and rest orientation")
		for index in target.get_bone_count():
			if index != hips:
				_check(target.get_bone_pose(index).is_equal_approx(locals[index]), "other bone articulation unchanged")
		var converted := Converter.reconstruct(target, profile, source)
		_check(converted["ok"], "edited root converts to SOMA")
		var model_root := Space.world_to_model(captured["space"], Vector3(world.x, world.y, world.z))
		_check(model_root.distance_to(Space.unvector(converted["root_position"])) < 0.00001, "guide root agrees with complete inverse conversion")
		var restored := GuidePose.current_guide(target, profile, captured["space"], reference["reference"])
		_check(restored["transform"].is_equal_approx(desired), "pose-to-guide roundtrip")
		target.free()
	source.free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: calibrated guide Hips edits preserve height/articulation with parent yaw and profile/scene scale")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
