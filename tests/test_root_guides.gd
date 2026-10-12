extends SceneTree

const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const Service := preload("res://addons/kimodo_motion/guides/root_guide_service.gd")
const PoseService := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const Options := preload("res://addons/kimodo_motion/domain/generation_options.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Generation := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const JENNY := preload("res://tests/private_models/Jenny04.glb")
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
	var session := Session.create_new("Root guides")
	var directory := "res://tests/.root-guides-" + Session.create_uuid()
	var saved := Store.save_as(session, directory, "session")
	dock._session_controller.session = session
	dock._session_controller.path = saved["path"]
	dock._activate_session(session, saved["path"], {})
	dock._on_character_target_changed(JENNY)
	var character := JENNY.instantiate()
	root.add_child(character)
	character.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(4, 0, -3))
	var skeleton := _find(character, "Skeleton3D") as Skeleton3D
	var player := AnimationPlayer.new()
	character.add_child(player)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 2
	library.add_animation("author", animation)
	player.add_animation_library("", library)
	player.assigned_animation = "author"
	player.seek(0, false)
	var panel: Control = dock._guides_panel
	panel.set_target(skeleton, player, character)
	_check(panel.guide != null and not session.root_guides.is_empty(), "scene guide binds to matching session character")
	for sample in [[0.991, 30], [1.009, 30], [0.982, 29], [1.018, 31]]:
		player.seek(sample[0], false)
		_check(panel._frame() == sample[1], "guide rounds native cursor to nearest 30 FPS frame")
		_check(is_equal_approx(player.current_animation_position, sample[0]), "guide rounding does not seek native cursor")
	player.seek(0.001, false)
	panel.record_current()
	_check(session.root_guides["points"].size() == 1, "records native frame zero")
	var space: Dictionary = session.root_guides["space"]
	var model_origin := Space.unvector(space["model_hips_rest"])
	player.seek(0.5, false)
	panel.guide.global_position = Space.model_to_world(space, model_origin + Vector3(0.7, 0, 0.8))
	panel.heading_check.button_pressed = true
	panel.guide.global_basis = Basis(Vector3.UP, Space.model_heading_to_world(space, 0.4))
	panel.record_current()
	_check(session.root_guides["points"].size() == 2, "second native frame and facing recorded")
	var converted := Service.constraints(session.root_guides, [], 30)
	_check(converted["ok"] and converted["constraints"].size() == 2, "position-only and optional-heading frames stay distinct")
	var options := Options.new()
	options.root_constraints.assign(converted["constraints"])
	_check(options.validate(30)["ok"], "root path request validates")
	var request := options.to_mmcp_request(client.capabilities)
	_check(request["constraints"][1]["frames"] == [15], "native time converted to Kimodo frame")
	_check(absf(request["constraints"][1]["heading_radians"][0] - 0.4) < 0.0001, "world heading converted to model space")
	request["constraints"][1]["positions_xz"][0][0] = 99
	_check(options.root_constraints[1]["positions_xz"][0][0] != 99, "request snapshot is independent")
	var pose := {"frame": 15, "root_position": [5, 1, 5], "joint_rotations": {"Hips": [0, 0, 0, 1]}}
	_check(not Service.constraints(session.root_guides, [pose], 30)["ok"], "contradictory full-body root rejected")
	pose["root_position"] = [0.7, model_origin.y, 0.8]
	_check(not Service.constraints(session.root_guides, [pose], 30)["ok"], "contradictory pose facing rejected")
	var q := Quaternion(Vector3.UP, 0.4)
	pose["joint_rotations"]["Hips"] = [q.x, q.y, q.z, q.w]
	_check(Service.constraints(session.root_guides, [pose], 30)["ok"], "compatible full-body and path constraints combine")
	panel.record_current()
	_check(not panel._pending.is_empty(), "existing waypoint requires replacement review")
	player.seek(0.6, false)
	panel.replace_dialog.confirmed.emit()
	_check(panel._pending.is_empty() and session.root_guides["points"].size() == 2, "stale frame confirmation refused")
	_check(not panel.replace_dialog.visible, "stale replacement review closes")
	player.seek(0.5, false)
	panel.record_current()
	player.play("author")
	panel.replace_dialog.confirmed.emit()
	_check(panel._pending.is_empty() and session.root_guides["points"].size() == 2, "playback started during review refuses replacement")
	player.pause()
	session.prompt = "Keep newer prompt"
	dock._fallback_undo_redo.undo()
	_check(session.root_guides["points"].size() == 1 and session.prompt == "Keep newer prompt", "waypoint undo preserves unrelated intent")
	dock._fallback_undo_redo.redo()
	_check(session.root_guides["points"].size() == 2, "waypoint redo")
	var fixed_placement: Transform3D = character.transform
	var hips := skeleton.find_bone(dock._rig_profile.target_for("Hips"))
	for frame in [0, 15]:
		player.seek(frame / 30.0 + 0.001, false)
		if frame == 15:
			skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + Vector3(0.6, 0, 0.8))
			skeleton.set_bone_pose_rotation(hips, Quaternion(Vector3.UP, 0.4) * skeleton.get_bone_pose_rotation(hips))
		var channels := {}
		for index in skeleton.get_bone_count():
			channels[String(skeleton.get_bone_name(index))] = PoseService.KINDS
		var captured := PoseService.capture(skeleton, "Combined guide pose", channels)
		_check(captured["ok"], "complete edited pose captures")
		var prepared := dock.prepare_pose_keyframe(skeleton, captured["pose"], frame)
		_check(prepared["ok"], "Hips travel/turning converts with fixed character placement")
		if not prepared["ok"]:
			print(prepared["message"])
			continue
		_check(dock.queue_pose_keyframe(prepared["entry"])["ok"], "full-body pose queues")
		panel.match_queued_pose()
		panel.heading_check.button_pressed = true
		panel.record_current()
		panel.replace_dialog.confirmed.emit()
	_check(character.transform == fixed_placement and panel.check_current_binding()["ok"], "bone travel/turning preserves guide scene reference")
	_check(session.pose_keyframes.size() == 2 and Service.constraints(session.root_guides, session.pose_keyframes, 30)["ok"], "two edited full-body poses and matched guides combine")
	var roots: Array = session.pose_keyframes.map(func(entry: Dictionary) -> Array: return entry["constraint"]["root_position"])
	_check(Space.unvector(roots[0]).distance_to(Space.unvector(roots[1])) > 0.5, "second pose carries authored root travel")
	_check(dock._session_controller.flush()["ok"], "guide session autosaves")
	var reopened := Store.open(saved["path"])
	_check(reopened["ok"] and panel._equal(reopened["session"].root_guides, session.root_guides), "guide coordinates/frame/placement persist")
	session.root_guides = reopened["session"].root_guides.duplicate(true)
	client.capabilities = null
	_check(panel.check_current_binding()["ok"], "saved guide editing works offline")
	character.position.x += 1
	_check(not panel.check_current_binding()["ok"], "changed scene placement invalidates guides")
	character.position.x -= 1
	_check(not Service.constraints(session.root_guides, [], 10)["ok"], "shortened duration rejects out-of-range guides")
	var capture_args := OS.get_cmdline_user_args()
	if capture_args.size() == 1:
		DirAccess.make_dir_recursive_absolute(capture_args[0])
		dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dock._workspace_tabs.current_tab = dock._guides_panel.get_index()
		for width in [360, 680]:
			root.size = Vector2i(width, 1000)
			for frame in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture_args[0].path_join("root_guides_%d.png" % width))
	dock.free()
	character.free()
	client.free()
	generation.free()
	for filename in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: scene root guides, native frames, request conflicts, offline persistence and undo")
	quit(0 if failures.is_empty() else 1)


func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _find(child, type)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		print("ROOT_GUIDE_CHECK_FAILED ", message)
		failures.append(message)
