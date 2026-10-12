extends SceneTree

const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const Service := preload("res://addons/kimodo_motion/guides/root_guide_service.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var skeleton := Fixture.create_skeleton()
	root.add_child(skeleton)
	var profile: Resource = Profile.exact_names(skeleton, NodePath("."))["profile"]
	profile.translation_scale_policy = "leg_height"
	profile.reference_measurements["leg_height"] *= 1.7
	skeleton.transform = Transform3D(Basis(Vector3.UP, 0.73).scaled(Vector3.ONE * 1.3), Vector3(4, 0.5, -3))
	var captured := Space.capture(skeleton, profile, Vector3(0, 1.005, 0))
	_check(captured["ok"], "translated rotated uniformly scaled placement supported")
	var space: Dictionary = captured["space"]
	for point in [Vector3(0, 1.005, 0), Vector3(2, 1.3, -4), Vector3(-0.3, 0.8, 1)]:
		var world := Space.model_to_world(space, point)
		_check(Space.world_to_model(space, world).distance_to(point) < 0.00001, "coordinate roundtrip")
	var start := Space.model_to_world(space, Vector3(0, 1.005, 0))
	var end := Space.model_to_world(space, Vector3(1, 1.005, 0))
	_check(absf(start.distance_to(end) - 1.7 * 1.3) < 0.00001, "scene and profile scale applied once")
	for heading in [-2.8, -0.5, 0.0, 2.7]:
		var restored := Space.world_heading_to_model(space, Space.model_heading_to_world(space, heading))
		_check(absf(wrapf(restored - heading, -PI, PI)) < 0.0001, "heading roundtrip")
	skeleton.scale = Vector3(1, 2, 1)
	_check(not Space.capture(skeleton, profile, Vector3.ZERO)["ok"], "nonuniform placement rejected")
	skeleton.transform = Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3.ZERO)
	_check(not Space.capture(skeleton, profile, Vector3.ZERO)["ok"], "tilted ground plane rejected")
	var shear := Transform3D(Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.6, 0, 0.8)), Vector3.ZERO)
	skeleton.transform = shear
	_check(not Space.capture(skeleton, profile, Vector3.ZERO)["ok"], "equal-axis-length shear rejected")
	var invalid_space := space.duplicate(true)
	invalid_space["placement"] = Space.encode_transform(shear)
	var intent := {"version": 1, "space": invalid_space, "points": [], "target_signature": "a".repeat(64), "profile_configuration": {}, "scene_path": "res://scene.tscn", "skeleton_path": ".", "player_path": "player"}
	_check(not Service.validation_error(intent).is_empty(), "persisted sheared placement rejected")
	skeleton.free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: root guide scene/model coordinates, scale and heading")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
