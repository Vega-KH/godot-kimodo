extends SceneTree

const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")
const Baker := preload("res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Matcher := preload("res://addons/kimodo_motion/retargeting/rig_candidate_matcher.gd")
const TARGET := "res://tests/private_models/goal19_manual/godette-restpose2.glb"
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists(TARGET):
		print("SKIP: private common-parent feasibility fixture")
		quit(0)
		return
	var hash_before := FileAccess.get_sha256(TARGET)
	var scene := (load(TARGET) as PackedScene).instantiate()
	root.add_child(scene)
	var skeleton: Skeleton3D = scene.find_children("*", "Skeleton3D", true, false)[0]
	# Explicit test-only artist choices; never special cases in production.
	# The first spine helper is colocated with Body. Omit that optional role;
	# preserve it at local rest rather than weakening the zero-length check.
	var mapping := {"Root":"Root_225", "Hips":"Body_220", "Chest":"Spine_2_198", "UpperChest":"Ribcage_197", "Neck":"Neck_1_132", "Head":"Head_129"}
	for side in ["Left", "Right"]:
		var left: bool = side == "Left"
		mapping[side + "Shoulder"] = "Clavic.L_162" if left else "Clavic.R_192"
		mapping[side + "UpperArm"] = "Arm_Upper_1.L_157" if left else "Arm_Upper_1.R_187"
		mapping[side + "LowerArm"] = "Arm_Lower_1.L_155" if left else "Arm_Lower_1.R_185"
		mapping[side + "Hand"] = "Hand.L_154" if left else "Hand.R_184"
		mapping[side + "UpperLeg"] = "Leg_Upper.L_205" if left else "Leg_Upper.R_211"
		mapping[side + "LowerLeg"] = "Leg_Lower.L_202" if left else "Leg_Lower.R_208"
		mapping[side + "Foot"] = "Foot.L_201" if left else "Foot.R_207"
	var frames := {}
	for side in ["Left", "Right"]:
		# Enough independent palm geometry for this body-motion experiment.
		# Anonymous finger numbering is NOT claimed to establish digit semantics.
		frames[side + "Hand"] = {
			"source_forward":side + "MiddleProximal", "source_lateral_from":side + "IndexProximal", "source_lateral_to":side + "LittleProximal",
			"target_forward":"Finger_2.L_139" if side == "Left" else "Finger_2.R_169",
			"target_lateral_from":"Finger_1.L_136" if side == "Left" else "Finger_1.R_166",
			"target_lateral_to":"Finger_4.L_145" if side == "Left" else "Finger_4.R_175",
		}
	var created := Profile.create(mapping, scene.get_path_to(skeleton), skeleton, Profile.ROOT_SEPARATE, "leg_height", frames)
	_check(created["ok"], "explicit common-parent map certifies: " + str(created.get("message", "")))
	if not created["ok"]:
		scene.free()
		_finish()
		return
	var invalid := mapping.duplicate()
	invalid["Hips"] = "Hip_218"
	var issues := Matcher.diagnose(skeleton, invalid, Profile.ROOT_SEPARATE, frames)
	_check(not issues.is_empty() and issues[0].contains("descend"), "sibling Hip mapping remains rejected")
	var source := _stress_source()
	root.add_child(source)
	var source_player := source.get_node("SourcePlayer") as AnimationPlayer
	var profile: Resource = created["profile"]
	var target_rests := Geometry.global_rests(skeleton)
	var source_rests := Geometry.global_rests(source)
	var hip := skeleton.find_bone("Hip_218")
	var body := skeleton.find_bone("Body_220")
	var hip_rest := skeleton.get_bone_rest(hip)
	var motion := Baker.create_motion(source, scene, profile)
	_check(motion != null, "common-parent body motion bakes")
	if motion == null:
		source.free()
		scene.free()
		_finish()
		return
	var animation: Animation = motion.player.get_animation("motion")
	for track in animation.get_track_count():
		_check(not String(animation.track_get_path(track)).ends_with(":Hip_218"), "unmapped weighted hip receives no invented track")
	var directory := "res://tests/.goal20_common_%d" % OS.get_process_id()
	var saved := Baker.save_library(scene, directory, "common_parent")
	_check(saved.has("library_path"), "common-parent animation library saves")
	var fresh := (load(TARGET) as PackedScene).instantiate()
	root.add_child(fresh)
	var fresh_skeleton: Skeleton3D = fresh.find_children("*", "Skeleton3D", true, false)[0]
	var player := AnimationPlayer.new()
	fresh.add_child(player)
	player.add_animation_library("", ResourceLoader.load(saved["library_path"], "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE))
	player.play("motion")
	var mesh := scene.find_child("Object_7", true, false) as MeshInstance3D
	var bind := -1
	for index in mesh.skin.get_bind_count():
		if mesh.skin.get_bind_name(index) == "Hip_218":
			bind = index
	_check(bind >= 0, "weighted hip has a skin binding")
	var worst_axis := 0.0
	var first_point := Vector3.ZERO
	var moved := 0.0
	for time in [0.0, 0.25, 0.5, 0.75]:
		source_player.seek(time, true)
		motion.player.seek(time, true)
		player.seek(time, true)
		_check(skeleton.get_bone_global_pose(hip).is_equal_approx(skeleton.get_bone_global_pose(body) * hip_rest), "weighted hip inherits common-parent motion without extra articulation")
		var source_hips := source.find_bone("Hips")
		var source_axis: Vector3 = source_rests[source_hips].origin.direction_to(source_rests[source.find_bone("Spine")].origin)
		var expected_axis := source.get_bone_global_pose(source_hips).basis * source_rests[source_hips].basis.inverse() * source_axis
		var target_axis: Vector3 = target_rests[body].origin.direction_to(target_rests[skeleton.find_bone(mapping["Chest"])].origin)
		var actual_axis := skeleton.get_bone_global_pose(body).basis * target_rests[body].basis.inverse() * target_axis
		worst_axis = maxf(worst_axis, rad_to_deg(expected_axis.angle_to(actual_axis)))
		for role in profile.rotation_targets():
			var child: StringName = profile.direction_child(role)
			if child.is_empty() or String(role).ends_with("Hand"):
				continue
			var si := source.find_bone(role)
			var ti := skeleton.find_bone(profile.target_for(role))
			var source_direction: Vector3 = source_rests[si].origin.direction_to(source_rests[source.find_bone(child)].origin)
			var target_direction: Vector3 = target_rests[ti].origin.direction_to(target_rests[skeleton.find_bone(profile.target_for(child))].origin)
			var wanted := source.get_bone_global_pose(si).basis * source_rests[si].basis.inverse() * source_direction
			var actual := skeleton.get_bone_global_pose(ti).basis * target_rests[ti].basis.inverse() * target_direction
			worst_axis = maxf(worst_axis, rad_to_deg(wanted.angle_to(actual)))
		for index in skeleton.get_bone_count():
			_check(skeleton.get_bone_global_pose(index).is_equal_approx(fresh_skeleton.get_bone_global_pose(index)), "fresh saved playback preserves branch: " + String(skeleton.get_bone_name(index)))
		if bind >= 0:
			var point := _weighted_hip_vertex(mesh, skeleton, bind)
			if time == 0.0:
				first_point = point
			moved = maxf(moved, point.distance_to(first_point))
	_check(worst_axis < 0.1, "independent common-parent pelvis-axis oracle: %.6f degrees" % worst_axis)
	_check(moved > 0.01, "skin-bound hip sample genuinely moves")
	if "--keep-preview" in OS.get_cmdline_user_args():
		var keep := Baker.save_preview_scene(scene, "res://tests/private_models/goal20_manual", "godette_common_parent_%d" % OS.get_process_id())
		print("COMMON-PARENT MANUAL PREVIEW: ", keep)
	print("COMMON PELVIS: worst body axis error %.6f degrees; hip skin-space sample displacement %.6f" % [worst_axis, moved])
	fresh.free()
	source.free()
	scene.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved["library_path"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
	_check(FileAccess.get_sha256(TARGET) == hash_before, "feasibility test preserves source asset")
	_finish()

func _stress_source() -> Skeleton3D:
	var skeleton := Fixture.create_skeleton()
	var player := AnimationPlayer.new()
	player.name = "SourcePlayer"
	skeleton.add_child(player)
	var animation := Animation.new()
	animation.length = 1.0
	for index in skeleton.get_bone_count():
		var role := String(skeleton.get_bone_name(index))
		var rest := skeleton.get_bone_rest(index)
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath(".:" + role))
		for time in [0.0, 0.5, 1.0]:
			var angle := 0.23 * sin(time * PI)
			var axis := Vector3(0.3, 0.7, 0.2).normalized()
			animation.rotation_track_insert_key(track, time, (rest.basis * Basis(axis, angle)).get_rotation_quaternion())
		if role in ["Root", "Hips"]:
			track = animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(track, NodePath(".:" + role))
			for time in [0.0, 0.5, 1.0]:
				var offset := Vector3(time * 0.2, 0, time * 0.1) if role == "Root" else Vector3(0, 0.1 * sin(time * PI), 0)
				animation.position_track_insert_key(track, time, rest.origin + offset)
	var library := AnimationLibrary.new()
	library.add_animation("motion", animation)
	player.add_animation_library("", library)
	player.play("motion")
	return skeleton

func _weighted_hip_vertex(mesh: MeshInstance3D, skeleton: Skeleton3D, hip_bind: int) -> Vector3:
	var arrays := mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var influences := bones.size() / vertices.size()
	for vertex in vertices.size():
		var weighted := false
		for slot in influences:
			var offset: int = vertex * influences + slot
			if bones[offset] == hip_bind and weights[offset] > 0.00001:
				weighted = true
		if not weighted:
			continue
		var result := Vector3.ZERO
		for slot in influences:
			var offset: int = vertex * influences + slot
			var bind := bones[offset]
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
			result += (skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
		return result
	_check(false, "mesh includes an actual vertex weighted to the hip branch")
	return Vector3.ZERO

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("PASS: bounded common-parent feasibility, skin inheritance and saved playback")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)
