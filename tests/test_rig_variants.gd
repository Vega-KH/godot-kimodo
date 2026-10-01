extends SceneTree

const Factory := preload("res://tests/rig_variant_factory.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Matcher := preload("res://addons/kimodo_motion/retargeting/rig_candidate_matcher.gd")
const Compatibility := preload("res://addons/kimodo_motion/retargeting/rig_compatibility.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")
const Baker := preload("res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd")
const Map := preload("res://addons/kimodo_motion/retargeting/soma77_humanoid_map.gd")
const Store := preload("res://addons/kimodo_motion/retargeting/rig_profile_store.gd")
const SessionStore := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := Fixture.create_skeleton()
	root.add_child(source)
	var source_rests: Array[Transform3D] = []
	var posed: Array[Transform3D] = []
	# Pose every source joint, including the torso segments absent on some targets.
	for index in source.get_bone_count():
		source_rests.append(source.get_bone_global_rest(index))
		var rest := source.get_bone_rest(index)
		var axis := Vector3(0.2 + index % 3, 0.6, 0.3).normalized()
		source.set_bone_pose(index, Transform3D(rest.basis * Basis(axis, 0.13 + index * 0.002), rest.origin))
	var hips := source.find_bone("Hips")
	source.set_bone_pose_position(hips, source.get_bone_pose_position(hips) + Vector3(0.12, 0.04, -0.08))
	for index in source.get_bone_count():
		posed.append(source.get_bone_global_pose(index))
	var recipes := [
		{"names":"canonical", "torso":3, "digits":5},
		{"names":"mixamo", "torso":2, "digits":4, "hips_only":true, "scale":0.8, "bind_scale":1.0782628},
		{"names":"sided", "torso":1, "digits":4, "minimal":true, "axes":true},
		{"names":"opaque", "torso":2, "digits":5, "reverse":true, "axes":true, "scale":1.4, "proportions":true},
		{"names":"namespace", "torso":3, "digits":4, "short_digits":true, "hips_only":true},
		# Held-out combination: arbitrary names + one torso + short four-finger
		# hands + reversed indices + different axes/scale + optional body omissions.
		{"names":"opaque", "torso":1, "digits":4, "short_digits":true, "reverse":true, "axes":true, "scale":0.65, "minimal":true, "hips_only":true, "proportions":true},
	]
	for recipe in recipes:
		var built := Factory.create(recipe)
		var scene: Node3D = built["scene"]
		var target: Skeleton3D = built["skeleton"]
		root.add_child(scene)
		var mapping: Dictionary = built["mapping"]
		var policy := Profile.ROOT_HIPS_ONLY if recipe.get("hips_only", false) else Profile.ROOT_SEPARATE
		_check(Compatibility.inspect(scene)["ok"], "synthetic skin/rest agrees: " + str(recipe))
		var result := Profile.create(mapping, NodePath("Rig"), target, policy, "leg_height")
		_check(result["ok"], "partial profile certifies: " + str(result.get("message", recipe)))
		if result["ok"]:
			var profile: Resource = result["profile"]
			_check(Matcher.diagnose(target, mapping, policy).is_empty(), "partial certification keeps chain validation")
			var target_rests: Array[Transform3D] = []
			for index in target.get_bone_count():
				target_rests.append(target.get_bone_global_rest(index))
			var locals := Baker._target_local_poses(source, posed, source_rests, target, target_rests, profile)
			for index in target.get_bone_count():
				target.set_bone_pose(index, locals[index])
			# Oracle: transform rest anatomical axes by independently posed source
			# world deltas, then compare target's actual axes, not baked coefficients.
			var worst := 0.0
			for role in profile.rotation_targets():
				var child: StringName = profile.direction_child(role)
				if child.is_empty() or not profile.hand_frames.get(String(Map.orientation_frame_owner_for_target(role)), {}).is_empty():
					continue
				var si := source.find_bone(role)
				var sc := source.find_bone(child)
				var ti := target.find_bone(profile.target_for(role))
				var tc := target.find_bone(profile.target_for(child))
				var expected_axis := (posed[si].basis * source_rests[si].basis.inverse()) * source_rests[si].origin.direction_to(source_rests[sc].origin)
				var target_axis := target.get_bone_global_pose(ti).basis * target_rests[ti].basis.inverse() * target_rests[ti].origin.direction_to(target_rests[tc].origin)
				worst = maxf(worst, rad_to_deg(expected_axis.angle_to(target_axis)))
			_check(worst < 0.1, "independent body-axis oracle <0.1 degrees (%.6f)" % worst)
			var worst_palm := 0.0
			for role in profile.rotation_targets():
				var owner := String(Map.orientation_frame_owner_for_target(role))
				if owner.is_empty():
					continue
				var frame: Dictionary = profile.hand_frames[owner]
				var source_axes := _palm_axes(source, owner, frame, "source")
				var target_axes := _palm_axes(target, profile.target_for(owner), frame, "target")
				var si := source.find_bone(role)
				var ti := target.find_bone(profile.target_for(role))
				var source_delta := posed[si].basis * source_rests[si].basis.inverse()
				var target_delta := target.get_bone_global_pose(ti).basis * target_rests[ti].basis.inverse()
				for axis in 3:
					worst_palm = maxf(worst_palm, rad_to_deg((source_delta * source_axes[axis]).angle_to(target_delta * target_axes[axis])))
			_check(worst_palm < 0.1, "all wrist/digit axes agree <0.1 degrees (%.6f)" % worst_palm)
			var target_hips := target.find_bone(profile.target_for("Hips"))
			var expected_origin: Vector3 = target_rests[target_hips].origin + (posed[hips].origin - source_rests[hips].origin) * profile.translation_scale(source)
			_check(target.get_bone_global_pose(target_hips).origin.distance_to(expected_origin) < 0.0001, "root/pelvis displacement oracle")
			for extra in ["Accessory", "AccessoryTip", "ArmTwist"]:
				var index := target.find_bone(extra)
				_check(target.get_bone_pose(index).is_equal_approx(target.get_bone_rest(index)), "unmapped branch retains local rest")
				var parent := target.get_bone_parent(index)
				_check(target.get_bone_global_pose(index).is_equal_approx(target.get_bone_global_pose(parent) * target.get_bone_rest(index)), "unmapped branch inherits animated parent")
			_check(Baker.validate(source, _source_player(source), target, profile).is_empty(), "partial hands validate through transfer API")
			_round_trip(profile, target)
			_invariance(recipe, source, source_rests, posed, target, profile)
			_baked_round_trip(recipe, source, scene, target, profile)
			var missing := mapping.duplicate()
			missing.erase("LeftFoot")
			_check(not Profile.create(missing, NodePath("Rig"), target, policy)["ok"], "missing required foot is rejected")
			var bad := mapping.duplicate()
			bad["LeftHand"] = mapping["RightHand"]
			_check(not Profile.create(bad, NodePath("Rig"), target, policy)["ok"], "duplicate role assignment is rejected")
			var reversed_chain := mapping.duplicate()
			var swap: String = reversed_chain["LeftUpperArm"]
			reversed_chain["LeftUpperArm"] = reversed_chain["LeftLowerArm"]
			reversed_chain["LeftLowerArm"] = swap
			_check(not Profile.create(reversed_chain, NodePath("Rig"), target, policy)["ok"], "wrong chain order is rejected")
			var degenerate_frames: Dictionary = profile.hand_frames.duplicate(true)
			degenerate_frames["LeftHand"]["target_lateral_to"] = degenerate_frames["LeftHand"]["target_lateral_from"]
			_check(not Profile.create(mapping, NodePath("Rig"), target, policy, "none", degenerate_frames)["ok"], "degenerate palm geometry is rejected")
		if recipe["names"] in ["canonical", "mixamo", "sided", "namespace"]:
			var suggestions := Matcher.suggest(target)
			for role in mapping:
				_check(suggestions["rows"][role]["target"] == mapping[role], "convention suggestion: %s -> %s" % [role, mapping[role]])
		scene.free()
	var fingerless := Factory.create({"digits":0})
	var rejected := Profile.create(fingerless["mapping"], NodePath("Rig"), fingerless["skeleton"])
	_check(not rejected["ok"] and rejected["message"].contains("palm"), "fingerless rig explains insufficient palm landmarks")
	fingerless["scene"].free()
	_compatibility_diagnostics()
	source.free()
	if failures.is_empty():
		print("PASS: generic synthetic convention/anatomy matrix and independent pose oracle")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func _source_player(source: Skeleton3D) -> AnimationPlayer:
	var existing := source.get_node_or_null("SourcePlayer") as AnimationPlayer
	if existing != null:
		return existing
	var player := AnimationPlayer.new()
	player.name = "SourcePlayer"
	source.add_child(player)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 1.0
	for index in source.get_bone_count():
		var role := String(source.get_bone_name(index))
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath(".:" + role))
		animation.rotation_track_insert_key(track, 0.0, source.get_bone_pose_rotation(index))
		animation.rotation_track_insert_key(track, 1.0, source.get_bone_pose_rotation(index))
		if role in ["Root", "Hips"]:
			track = animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(track, NodePath(".:" + role))
			animation.position_track_insert_key(track, 0.0, source.get_bone_pose_position(index))
			animation.position_track_insert_key(track, 1.0, source.get_bone_pose_position(index))
	library.add_animation("motion", animation)
	player.add_animation_library("", library)
	return player

func _round_trip(profile: Resource, target: Skeleton3D) -> void:
	var signature := SessionStore.skeleton_signature(target)
	profile.certify(target, signature)
	var path := "res://tests/.variant_%d.tres" % OS.get_process_id()
	_check(Store.save(profile, path)["ok"], "partial profile saves")
	var loaded := Store.load_current(path, target, signature)
	_check(loaded["ok"] and loaded["profile"].hand_frames == profile.hand_frames and loaded["profile"].ignored_optional_roles == profile.ignored_optional_roles, "landmarks and intentional omissions round-trip")
	_check(not Store.load_current(path, target, "changed")["ok"], "stale partial profile is rejected")
	profile.schema_version = 1
	profile.hand_frames.clear()
	Store.save(profile, path)
	loaded = Store.load_current(path, target, signature)
	_check(loaded["ok"] and loaded["profile"].schema_version == 2, "Goal 18 profile upgrades in memory for exact signature")
	profile.schema_version = 2
	profile.hand_frames = Profile.suggest_hand_frames(profile.canonical_to_target)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _palm_axes(skeleton: Skeleton3D, owner: StringName, frame: Dictionary, layer: String) -> Array[Vector3]:
	var origin := skeleton.get_bone_global_rest(skeleton.find_bone(owner)).origin
	var forward := (skeleton.get_bone_global_rest(skeleton.find_bone(frame[layer + "_forward"])).origin - origin).normalized()
	var sideways := skeleton.get_bone_global_rest(skeleton.find_bone(frame[layer + "_lateral_to"])).origin - skeleton.get_bone_global_rest(skeleton.find_bone(frame[layer + "_lateral_from"])).origin
	var normal := forward.cross(sideways).normalized()
	return [normal.cross(forward).normalized(), normal, forward]

func _baked_round_trip(recipe: Dictionary, source: Skeleton3D, scene: Node3D, target: Skeleton3D, profile: Resource) -> void:
	var expected: Array[Transform3D] = []
	for index in target.get_bone_count():
		expected.append(target.get_bone_global_pose(index))
	var motion := Baker.create_motion(source, scene, profile)
	_check(motion != null, "partial rig bakes a playable animation")
	if motion == null:
		return
	var directory := "res://tests/.variant_bake_%d" % OS.get_process_id()
	var saved := Baker.save_library(scene, directory, "variant")
	var library := ResourceLoader.load(saved["library_path"], "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	var animation := library.get_animation("motion")
	for track in animation.get_track_count():
		var bone := String(animation.track_get_path(track).get_subname(0))
		_check(bone in profile.canonical_to_target.values(), "baked library emits tracks only for mapped bones")
	var fresh := Factory.create(recipe)
	root.add_child(fresh["scene"])
	var player := AnimationPlayer.new()
	fresh["scene"].add_child(player)
	player.add_animation_library("", library)
	player.play("motion")
	player.seek(0.0, true)
	var skeleton: Skeleton3D = fresh["skeleton"]
	var original_skin := (scene.find_child("SkinMesh", true, false) as MeshInstance3D).skin
	var reloaded_skin := (fresh["scene"].find_child("SkinMesh", true, false) as MeshInstance3D).skin
	for index in skeleton.get_bone_count():
		var actual := skeleton.get_bone_global_pose(index)
		var angle := rad_to_deg(actual.basis.get_rotation_quaternion().angle_to(expected[index].basis.get_rotation_quaternion()))
		_check(angle < 0.1 and actual.origin.distance_to(expected[index].origin) < 0.0001 and actual.basis.get_scale().distance_to(expected[index].basis.get_scale()) < 0.0001, "saved partial-animation playback matches independent pose within declared angular/position tolerances: %s (%.6f degrees)" % [skeleton.get_bone_name(index), angle])
		var sample_vertex := Vector3(0.13, 0.27, -0.08)
		var original_vertex: Vector3 = expected[index] * original_skin.get_bind_pose(index) * sample_vertex
		var reloaded_vertex: Vector3 = actual * reloaded_skin.get_bind_pose(index) * sample_vertex
		# Propagate the existing 0.1-degree/0.0001-unit pose tolerances to
		# the skin-space point; distal bind coordinates amplify angular rounding.
		var bind_point: Vector3 = original_skin.get_bind_pose(index) * sample_vertex
		var vertex_tolerance := 0.0002 + deg_to_rad(0.1) * bind_point.length() * expected[index].basis.get_scale().length()
		_check(original_vertex.distance_to(reloaded_vertex) < vertex_tolerance, "saved playback preserves skin-space sample including common bind scale")
	fresh["scene"].free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved["library_path"]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))

func _invariance(recipe: Dictionary, source: Skeleton3D, rests: Array[Transform3D], posed: Array[Transform3D], expected: Skeleton3D, original: Resource) -> void:
	var renamed := recipe.duplicate()
	renamed["names"] = "opaque"
	renamed["reverse"] = not recipe.get("reverse", false)
	var variant := Factory.create(renamed)
	root.add_child(variant["scene"])
	var target: Skeleton3D = variant["skeleton"]
	var profile: Resource = Profile.create(variant["mapping"], NodePath("Rig"), target, original.root_motion_policy, "leg_height")["profile"]
	var target_rests: Array[Transform3D] = []
	for index in target.get_bone_count():
		target_rests.append(target.get_bone_global_rest(index))
	var locals := Baker._target_local_poses(source, posed, rests, target, target_rests, profile)
	for index in target.get_bone_count():
		target.set_bone_pose(index, locals[index])
	for role in profile.canonical_to_target:
		var actual := target.get_bone_global_pose(target.find_bone(profile.target_for(role)))
		var wanted := expected.get_bone_global_pose(expected.find_bone(original.target_for(role)))
		_check(actual.is_equal_approx(wanted), "renaming/reindexing invariance: " + role)
	variant["scene"].free()

func _compatibility_diagnostics() -> void:
	var built := Factory.create({})
	var scene: Node3D = built["scene"]
	var mesh := scene.find_child("SkinMesh", true, false) as MeshInstance3D
	var skeleton: Skeleton3D = built["skeleton"]
	# Nontrivial node transforms are accounted for, not mistaken for pose errors.
	skeleton.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(3, 2, 1))
	_check(Compatibility.inspect(scene)["ok"], "skeleton node transform is accounted for")
	var baseline := mesh.skin.get_bind_pose(0)
	var changed := baseline
	changed.origin += Vector3(0.2, 0, 0)
	mesh.skin.set_bind_pose(0, changed)
	var result := Compatibility.inspect(scene)
	_check(not result["ok"] and result["code"] == "bind_rest_mismatch" and result["message"].contains("SkinMesh") and result["message"].contains("Root") and result["message"].contains("re-export"), "bind/rest message identifies mesh/bone and remedy")
	mesh.skin.set_bind_pose(0, baseline)
	mesh.skin.set_bind_name(0, "AbsentBone")
	result = Compatibility.inspect(scene)
	_check(not result["ok"] and result["message"].contains("AbsentBone"), "missing binding names the bone")
	mesh.skin.set_bind_name(0, skeleton.get_bone_name(0))
	var rest := skeleton.get_bone_rest(0)
	var scaled := rest
	scaled.basis = scaled.basis.scaled(Vector3(1, 2, 1))
	skeleton.set_bone_rest(0, scaled)
	result = Compatibility.inspect(scene)
	_check(not result["ok"] and result["code"] == "unsupported_rest_basis" and result["message"].contains("non-uniform bone scale"), "unsafe bone scale explains rotation-only limitation")
	skeleton.set_bone_rest(0, rest)
	scene.free()
	_uniform_bind_scale_diagnostics()

func _uniform_bind_scale_diagnostics() -> void:
	for scale_factor in [0.5, 1.0782628, 2.0]:
		var built := Factory.create({})
		var scene: Node3D = built["scene"]
		var skeleton: Skeleton3D = built["skeleton"]
		var mesh := scene.find_child("SkinMesh", true, false) as MeshInstance3D
		skeleton.transform = Transform3D(Basis(Vector3.UP, 0.5).scaled(Vector3.ONE * 0.927418), Vector3(3, 2, 1))
		mesh.transform = Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.2, 0.4, 0.1))
		var rests := Geometry.global_rests(skeleton)
		var common := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), Vector3.ZERO)
		var originals: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var pose: Transform3D = rests[bind].affine_inverse() * mesh.transform * common
			mesh.skin.set_bind_pose(bind, pose)
			originals.append(pose)
		var second := mesh.duplicate() as MeshInstance3D
		second.skin = mesh.skin.duplicate(true)
		skeleton.add_child(second)
		var result := Compatibility.inspect(scene)
		_check(result["ok"] and absf(result.get("bind_space_scale", 0.0) - scale_factor) < 0.00001, "common positive uniform bind scale across meshes: " + str(scale_factor))
		for bind in originals.size():
			_check(mesh.skin.get_bind_pose(bind) == originals[bind], "compatibility inspection preserves exact skin transforms")
		# One inconsistent mesh or bone must not receive independent normalization.
		second.skin.set_bind_pose(1, originals[1] * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 1.1), Vector3.ZERO))
		_check(not Compatibility.inspect(scene)["ok"], "different per-mesh/per-bone scales rejected")
		second.skin.set_bind_pose(1, originals[1])
		for invalid in [Transform3D(Basis(Vector3.UP, 0.08), Vector3.ZERO), Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1.1, 1)), Vector3.ZERO), Transform3D(Basis.IDENTITY.scaled(Vector3(-1, -1, -1)), Vector3.ZERO), Transform3D(Basis(Vector3(1, 0.1, 0), Vector3.UP, Vector3.BACK), Vector3.ZERO), Transform3D(Basis.IDENTITY, Vector3(0.1, 0, 0))]:
			for bind in originals.size():
				mesh.skin.set_bind_pose(bind, originals[bind] * invalid)
				second.skin.set_bind_pose(bind, originals[bind] * invalid)
			_check(not Compatibility.inspect(scene)["ok"], "common non-scalar transform is not a harmless scale")
		scene.free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
