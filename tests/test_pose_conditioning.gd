extends SceneTree

const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Generation := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Options := preload("res://addons/kimodo_motion/domain/generation_options.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Service := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const JENNY := preload("res://tests/characters/fixtures/Jenny03.glb")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var client := Client.new()
	var generation := Generation.new()
	root.add_child(client)
	root.add_child(generation)
	client.capabilities = Capabilities.parse_json_text(FileAccess.get_file_as_string("res://tests/fixtures/soma77_capabilities.json"))["capabilities"]
	var dock := Dock.new()
	dock.configure(client, generation)
	root.add_child(dock)
	await process_frame
	var session := Session.create_new("Pose constraints")
	var directory := "res://tests/.pose-conditioning-" + Session.create_uuid()
	var saved := Store.save_as(session, directory, "session")
	dock._session_controller.session = session
	dock._session_controller.path = saved["path"]
	dock._activate_session(session, saved["path"], {})
	dock._on_character_target_changed(JENNY)
	var character := JENNY.instantiate()
	var skeleton := _find(character) as Skeleton3D
	var mask := {}
	for index in skeleton.get_bone_count():
		mask[String(skeleton.get_bone_name(index))] = Service.KINDS
	var authored := Service.capture(skeleton, "Complete pose", mask)
	var prepared := dock.prepare_pose_keyframe(skeleton, authored["pose"], 5)
	_check(prepared["ok"], "prepare full-body constraint from character pose")
	if prepared["ok"]:
		var queued := dock.queue_pose_keyframe(prepared["entry"])
		_check(queued["ok"] and session.pose_keyframes.size() == 1, "constraint queued in current session")
		var options := Options.new()
		options.pose_constraints.append(session.pose_keyframes[0]["constraint"])
		_check(options.validate(30)["ok"], "full SOMA-30 pose validates")
		var request := options.to_mmcp_request(client.capabilities)
		_check(request["constraints"][0]["joint_rotations"].size() == 30, "request sends SOMA-30 constraints")
		request["constraints"][0]["frame"] = 8
		_check(options.pose_constraints[0]["frame"] == 5, "request is an independent snapshot")
		session.prompt = "Newer intent"
		dock._fallback_undo_redo.undo()
		_check(session.pose_keyframes.is_empty() and session.prompt == "Newer intent", "constraint undo preserves newer intent")
		dock._fallback_undo_redo.redo()
		dock._flush_session()
		var reopened := Store.open(saved["path"])
		_check(reopened["ok"] and reopened["session"].pose_keyframes.size() == 1, "pose constraints persist in schema-2 session")
		options.duration_frames = 5
		_check(not options.validate(30)["ok"], "shortened duration rejects out-of-bounds frame")
		dock.remove_pose_keyframe(5)
		_check(session.pose_keyframes.is_empty(), "constraint removal")
		dock._fallback_undo_redo.undo()
		_check(session.pose_keyframes.size() == 1, "constraint removal undo")
		generation._set_state(Generation.GenerationState.GENERATING, "Waiting")
		_check(not dock.queue_pose_keyframe(prepared["entry"])["ok"], "generation locks constraint changes")
		generation.cancel_generation()
		var original_scale: String = dock._rig_profile.translation_scale_policy
		dock._rig_profile.translation_scale_policy = "none" if original_scale != "none" else "leg_height"
		_check(not dock.queue_pose_keyframe(prepared["entry"])["ok"], "profile policy change invalidates reviewed constraint")
		dock._rig_profile.translation_scale_policy = original_scale
	dock._session_controller.dirty = false
	dock.free()
	client.free()
	generation.free()
	character.free()
	DirAccess.remove_absolute(saved["path"])
	DirAccess.remove_absolute(directory)
	if failures.is_empty():
		print("PASS: full-body pose queue, request, persistence and field-only undo")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _find(node: Node) -> Node:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find(child)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
