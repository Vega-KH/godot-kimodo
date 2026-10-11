@tool
class_name KimodoPoseService
extends RefCounted

const Pose := preload("res://addons/kimodo_motion/poses/pose_asset.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const Paths := preload("res://addons/kimodo_motion/domain/project_paths.gd")
const KINDS := [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]


static func capture(skeleton: Skeleton3D, title: String, channels: Dictionary, provenance := {}) -> Dictionary:
	if skeleton == null or channels.is_empty():
		return _error("Select a skeleton and at least one bone channel.")
	var pose := Pose.new()
	pose.pose_id = Session.create_uuid()
	pose.title = title.strip_edges()
	pose.rig_signature = Pose.signature_for(skeleton)
	pose.provenance = provenance.duplicate(true)
	pose.sample = Animation.new()
	pose.sample.length = 1.0 / 30.0
	for index in skeleton.get_bone_count():
		pose.bone_names.append(skeleton.get_bone_name(index))
		var parent := skeleton.get_bone_parent(index)
		pose.parent_names.append(skeleton.get_bone_name(parent) if parent >= 0 else "")
		pose.local_rests.append(skeleton.get_bone_rest(index))
	for bone in channels:
		var index := skeleton.find_bone(bone)
		if index < 0:
			return _error("Unknown bone: %s." % bone)
		for kind in channels[bone]:
			if kind not in KINDS:
				return _error("Only bone position, rotation and scale can be captured.")
			var value: Variant
			if kind == Animation.TYPE_POSITION_3D:
				value = skeleton.get_bone_pose_position(index)
			elif kind == Animation.TYPE_ROTATION_3D:
				value = skeleton.get_bone_pose_rotation(index)
			else:
				value = skeleton.get_bone_pose_scale(index)
			_add_channel(pose.sample, bone, kind, value)
	var problem := pose.validation_error()
	return {"ok": true, "pose": pose} if problem.is_empty() else _error(problem)


static func capture_animation(skeleton: Skeleton3D, animation: Animation, skeleton_path: NodePath, time: float, title: String, channels: Dictionary) -> Dictionary:
	if animation == null or not is_finite(time) or time < 0.0 or time > animation.length:
		return _error("Select an animation and a time within its duration.")
	var result := capture(skeleton, title, channels, {"source_time": time})
	if not result["ok"]:
		return result
	var pose := result["pose"] as Pose
	for track in pose.sample.get_track_count():
		var bone: StringName = pose.sample.track_get_path(track).get_subname(0)
		var kind: int = pose.sample.track_get_type(track)
		var source_path := NodePath("%s:%s" % [skeleton_path, bone])
		var source_track := animation.find_track(source_path, kind)
		var value: Variant
		if source_track >= 0 and animation.track_is_enabled(source_track) and animation.track_get_key_count(source_track) > 0:
			if kind == Animation.TYPE_POSITION_3D:
				value = animation.position_track_interpolate(source_track, time)
			elif kind == Animation.TYPE_ROTATION_3D:
				value = animation.rotation_track_interpolate(source_track, time)
			else:
				value = animation.scale_track_interpolate(source_track, time)
		else:
			var rest := skeleton.get_bone_rest(skeleton.find_bone(bone))
			if kind == Animation.TYPE_POSITION_3D:
				value = rest.origin
			elif kind == Animation.TYPE_ROTATION_3D:
				value = rest.basis.get_rotation_quaternion()
			else:
				value = rest.basis.get_scale()
		pose.sample.track_set_key_value(track, 0, value)
	var problem: String = pose.validation_error()
	return result if problem.is_empty() else _error(problem)


static func apply(pose: Resource, skeleton: Skeleton3D) -> Dictionary:
	var problem: String = pose.compatibility_error(skeleton)
	if not problem.is_empty():
		return _error(problem)
	for track in pose.sample.get_track_count():
		var bone := skeleton.find_bone(pose.sample.track_get_path(track).get_subname(0))
		var value: Variant = pose.sample.track_get_key_value(track, 0)
		match pose.sample.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(bone, value)
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(bone, value)
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(bone, value)
	return {"ok": true}


static func keyed_copy(pose: Resource, skeleton: Skeleton3D, animation: Animation, skeleton_path: NodePath, time: float) -> Dictionary:
	var problem: String = pose.compatibility_error(skeleton)
	if not problem.is_empty():
		return _error(problem)
	if animation == null or not is_finite(time) or time < 0.0 or time > animation.length:
		return _error("Choose a key time within the destination animation.")
	var copy := animation.duplicate(true) as Animation
	var collisions := 0
	for track in pose.sample.get_track_count():
		var bone: StringName = pose.sample.track_get_path(track).get_subname(0)
		var kind: int = pose.sample.track_get_type(track)
		var path := NodePath("%s:%s" % [skeleton_path, bone])
		var destination := copy.find_track(path, kind)
		if destination < 0:
			destination = copy.add_track(kind)
			copy.track_set_path(destination, path)
		if not copy.track_is_enabled(destination):
			return _error("The destination channel is disabled: %s." % path)
		if copy.track_find_key(destination, time, Animation.FIND_MODE_APPROX) >= 0:
			collisions += 1
		var value: Variant = pose.sample.track_get_key_value(track, 0)
		_insert(copy, destination, kind, time, value)
	return {"ok": true, "animation": copy, "collisions": collisions}


static func save_new(pose: Resource, path: String) -> Dictionary:
	var problem: String = pose.validation_error()
	if not problem.is_empty():
		return _error(problem)
	var validation := Paths.validate_output_file(path, "tres")
	if not validation["ok"]:
		return validation
	path = validation["path"]
	if FileAccess.file_exists(path):
		return _error("A file already exists at this path. Choose a new pose file.")
	var directory := Paths.ensure_directory(path.get_base_dir())
	if not directory["ok"]:
		return directory
	var temporary := path.get_basename() + ".pending-" + Session.create_uuid() + ".tres"
	var error := ResourceSaver.save(pose, temporary)
	if error == OK:
		var reloaded := load_pose(temporary)
		if not reloaded["ok"]:
			error = ERR_FILE_CORRUPT
	if error == OK and not FileAccess.file_exists(path):
		error = DirAccess.rename_absolute(temporary, path)
	else:
		error = ERR_CANT_CREATE
	if error != OK:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(temporary)
		return _error("Godot could not save the pose. No existing asset was replaced.")
	return {"ok": true, "path": path}


static func load_pose(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _error("The pose file is missing.")
	var pose := ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_IGNORE)
	if not pose is Pose:
		return _error("This file is not a Kimodo pose asset.")
	var problem: String = pose.validation_error()
	return {"ok": true, "pose": pose} if problem.is_empty() else _error(problem)


static func _add_channel(animation: Animation, bone: String, kind: int, value: Variant) -> void:
	var track := animation.add_track(kind)
	animation.track_set_path(track, NodePath(".:%s" % bone))
	_insert(animation, track, kind, 0.0, value)


static func _insert(animation: Animation, track: int, kind: int, time: float, value: Variant) -> void:
	match kind:
		Animation.TYPE_POSITION_3D:
			animation.position_track_insert_key(track, time, value)
		Animation.TYPE_ROTATION_3D:
			animation.rotation_track_insert_key(track, time, value)
		Animation.TYPE_SCALE_3D:
			animation.scale_track_insert_key(track, time, value)


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
