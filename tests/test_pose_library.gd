extends SceneTree

const Pose := preload("res://addons/kimodo_motion/poses/pose_asset.gd")
const Service := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var skeleton := _skeleton()
	root.add_child(skeleton)
	var channel_mask := {"Finger": [Animation.TYPE_ROTATION_3D]}
	var edited := Quaternion(Vector3.RIGHT, 0.7)
	skeleton.set_bone_pose_rotation(2, edited)
	var captured := Service.capture(skeleton, "Finger curl", channel_mask)
	_check(captured["ok"], "capture manually edited sparse pose")
	var pose: Resource = captured["pose"]
	_check(pose.sample.get_track_count() == 1, "mask stores only chosen channel")
	_check(pose.sample.track_get_key_value(0, 0).is_equal_approx(edited), "capture uses manual edits")
	var parent_before := Quaternion(Vector3.UP, 0.4)
	skeleton.set_bone_pose_rotation(1, parent_before)
	skeleton.set_bone_pose_rotation(2, Quaternion.IDENTITY)
	_check(Service.apply(pose, skeleton)["ok"], "apply sparse pose")
	_check(skeleton.get_bone_pose_rotation(1).is_equal_approx(parent_before), "absent parent channel unchanged")
	_check(skeleton.get_bone_pose_rotation(2).is_equal_approx(edited), "included finger channel changed")
	var animation := Animation.new()
	animation.length = 2.0
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath("Rig/Skeleton:Finger"))
	animation.rotation_track_insert_key(track, 0.0, Quaternion.IDENTITY)
	animation.rotation_track_insert_key(track, 2.0, Quaternion(Vector3.RIGHT, 1.0))
	var body_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(body_track, NodePath("Rig/Skeleton:Hand"))
	animation.position_track_insert_key(body_track, 0, Vector3(0.1, 1.0, 0))
	animation.position_track_insert_key(body_track, 2, Vector3(0.3, 1.2, -0.2))
	var source_hash := var_to_bytes(animation.track_get_key_value(track, 0))
	var sampled := Service.capture_animation(skeleton, animation, NodePath("Rig/Skeleton"), 1.0, "Half curl", channel_mask)
	_check(sampled["ok"], "sample non-Kimodo animation at interpolated time")
	_check(sampled["pose"].sample.track_get_key_value(0, 0).is_equal_approx(Quaternion(Vector3.RIGHT, 0.5)), "interpolated value correct")
	_check(source_hash == var_to_bytes(animation.track_get_key_value(track, 0)), "sampling source remains untouched")
	var keyed := Service.keyed_copy(pose, skeleton, animation, NodePath("Rig/Skeleton"), 1.0)
	_check(keyed["ok"] and keyed["collisions"] == 0, "key into native animation")
	_check(animation.track_get_key_count(track) == 2, "source is not modified by key preparation")
	_check(keyed["animation"].track_get_key_count(track) == 3, "new time inserted")
	_check(keyed["animation"].track_get_key_count(body_track) == 2 and keyed["animation"].track_get_key_value(body_track, 1) == Vector3(0.3, 1.2, -0.2), "sparse finger overlay preserves separate body track and keys")
	var replaced := Service.keyed_copy(sampled["pose"], skeleton, keyed["animation"], NodePath("Rig/Skeleton"), 1.0)
	_check(replaced["collisions"] == 1 and replaced["animation"].track_get_key_count(track) == 3, "collision reported and only existing time replaced")
	_check(replaced["animation"].track_get_key_value(track, 2).is_equal_approx(Quaternion(Vector3.RIGHT, 1.0)), "other key preserved")
	_check(not Service.keyed_copy(pose, skeleton, animation, NodePath("Rig/Skeleton"), 3.0)["ok"], "out of range key rejected")
	var reindexed := _skeleton(true)
	_check(pose.compatibility_error(reindexed).is_empty(), "equivalent reindexing accepted")
	reindexed.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)))
	_check(not pose.compatibility_error(reindexed).is_empty(), "changed rest rig rejected")
	reindexed.free()
	var corrupt: Resource = pose.duplicate(true)
	corrupt.schema_version = 99
	_check(not corrupt.validation_error().is_empty(), "unsupported version rejected")
	corrupt = pose.duplicate(true)
	corrupt.sample.track_set_key_value(0, 0, Quaternion(0, 0, 0, 0))
	_check(not corrupt.validation_error().is_empty(), "zero quaternion rejected")
	corrupt = pose.duplicate(true)
	corrupt.parent_names[1] = "Missing"
	_check(not corrupt.validation_error().is_empty(), "missing ancestor rejected before traversal")
	corrupt = pose.duplicate(true)
	corrupt.parent_names[1] = "Finger"
	_check(not corrupt.validation_error().is_empty(), "hierarchy cycle rejected")
	_check(not Service.save_new(pose, "user://forbidden_pose.tres")["ok"], "pose save outside project refused")
	_check(not Service.save_new(pose, "res://animations/kimodo/session_data/pose-test/bad.tres")["ok"], "pose save into managed source archive refused")
	_check(not Service.load_pose("res://tests/missing-pose-" + Session.create_uuid() + ".tres")["ok"], "missing pose diagnosed")
	var temporary := "res://tests/pose-" + Session.create_uuid() + ".tres"
	_check(Service.save_new(pose, temporary)["ok"], "independent pose saved")
	var disk_hash := FileAccess.get_sha256(temporary)
	_check(not Service.save_new(sampled["pose"], temporary)["ok"], "save collision refused")
	_check(FileAccess.get_sha256(temporary) == disk_hash, "existing file unchanged")
	var loaded := Service.load_pose(temporary)
	_check(loaded["ok"] and loaded["pose"].pose_id == pose.pose_id, "pose reload identity")
	_check(loaded["pose"].sample.track_get_key_value(0, 0).is_equal_approx(edited), "pose reload sample")
	DirAccess.remove_absolute(temporary)
	_full_channels()
	skeleton.free()
	if failures.is_empty():
		print("PASS: sparse character pose capture, disk roundtrip and native key application")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _full_channels() -> void:
	var skeleton := _skeleton()
	var mask := {"Root": Service.KINDS, "Hand": Service.KINDS, "Finger": Service.KINDS}
	var root_position := Vector3(1.25, 0.35, -2.0)
	var hand_scale := Vector3(0.8, 1.2, 1.05)
	var hand_rotation := Quaternion(Vector3(0.2, 0.6, 0.4).normalized(), 0.42)
	skeleton.set_bone_pose_position(0, root_position)
	skeleton.set_bone_pose_rotation(1, hand_rotation)
	skeleton.set_bone_pose_scale(1, hand_scale)
	var captured := Service.capture(skeleton, "Complete TRS", mask)
	_check(captured["ok"] and captured["pose"].sample.get_track_count() == 9, "complete pose captures all bone transform channels")
	var path := "res://tests/pose-full-" + Session.create_uuid() + ".tres"
	_check(Service.save_new(captured["pose"], path)["ok"], "complete pose persisted")
	var loaded := Service.load_pose(path)
	skeleton.reset_bone_poses()
	Service.apply(loaded["pose"], skeleton)
	_check(skeleton.get_bone_pose_position(0).distance_to(root_position) < 0.00001, "position disk/apply accuracy")
	_check(skeleton.get_bone_pose_scale(1).distance_to(hand_scale) < 0.00001, "scale disk/apply accuracy")
	_check(skeleton.get_bone_pose_rotation(1).angle_to(hand_rotation) < 0.0001, "rotation disk/apply accuracy")
	var clip := Animation.new()
	clip.length = 2
	for kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
		var track := clip.add_track(kind)
		clip.track_set_path(track, NodePath("Character/Rig:Hand"))
		if kind == Animation.TYPE_POSITION_3D:
			clip.position_track_insert_key(track, 0, Vector3(0, 1, 0))
			clip.position_track_insert_key(track, 2, Vector3(0, 3, 0))
		else:
			clip.scale_track_insert_key(track, 0, Vector3.ONE)
			clip.scale_track_insert_key(track, 2, Vector3(2, 1.4, 1.2))
	var sampled := Service.capture_animation(skeleton, clip, NodePath("Character/Rig"), 1.0, "Interpolated TRS", mask)
	Service.apply(sampled["pose"], skeleton)
	_check(skeleton.get_bone_pose_position(1).distance_to(Vector3(0, 2, 0)) < 0.00001, "position interpolation")
	_check(skeleton.get_bone_pose_scale(1).distance_to(Vector3(1.5, 1.2, 1.1)) < 0.00001, "scale interpolation")
	_check(skeleton.get_bone_pose_position(0) == Vector3.ZERO, "untracked sampled root uses rest, not prior manual value")
	var at_key := Service.capture_animation(skeleton, clip, NodePath("Character/Rig"), 0.0, "Keyed TRS", mask)
	Service.apply(at_key["pose"], skeleton)
	_check(skeleton.get_bone_pose_position(1) == Vector3(0, 1, 0) and skeleton.get_bone_pose_scale(1) == Vector3.ONE, "complete pose samples exact keyed transform values")
	var keyed := Service.keyed_copy(sampled["pose"], skeleton, Animation.new(), NodePath("Other/Rig"), 0.0)
	_check(keyed["ok"] and keyed["animation"].get_track_count() == 9, "all transform channels key with rebinding")
	_check(keyed["animation"].find_track(NodePath("Other/Rig:Hand"), Animation.TYPE_SCALE_3D) >= 0, "scale key uses destination skeleton path")
	DirAccess.remove_absolute(path)
	skeleton.free()


func _skeleton(reindexed := false) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	var names := ["Root", "Hand", "Finger"] if not reindexed else ["Root", "Finger", "Hand"]
	for name_value in names:
		skeleton.add_bone(name_value)
	for bone in ["Hand", "Finger"]:
		var index := skeleton.find_bone(bone)
		skeleton.set_bone_parent(index, skeleton.find_bone("Root" if bone == "Hand" else "Hand"))
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0 if bone == "Hand" else 0.2, 0.0)))
	skeleton.reset_bone_poses()
	return skeleton


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
