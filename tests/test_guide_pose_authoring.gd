extends SceneTree

const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const PoseGuide := preload("res://addons/kimodo_motion/guides/guide_pose_service.gd")
const Converter := preload("res://addons/kimodo_motion/poses/character_pose_converter.gd")
const GuideService := preload("res://addons/kimodo_motion/guides/root_guide_service.gd")
const PosePanel := preload("res://addons/kimodo_motion/ui/pose_library_panel.gd")
const Session := preload("res://addons/kimodo_motion/domain/motion_session.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Generation := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
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
	var session := Session.create_new("Guide pose authoring")
	var directory := "res://tests/.guide-poses-" + Session.create_uuid()
	var saved := Store.save_as(session, directory, "session")
	dock._session_controller.session = session
	dock._session_controller.path = saved["path"]
	dock._activate_session(session, saved["path"], {})
	dock._on_character_target_changed(JENNY)
	var character := JENNY.instantiate() as Node3D
	root.add_child(character)
	character.transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 1.3), Vector3(4, 0.2, -3))
	var fixed_placement := character.transform
	var skeleton := _find(character, "Skeleton3D") as Skeleton3D
	var player := AnimationPlayer.new()
	character.add_child(player)
	var library := AnimationLibrary.new()
	var clip := Animation.new()
	clip.length = 2
	library.add_animation("author", clip)
	player.add_animation_library("", library)
	player.assigned_animation = "author"
	player.seek(0, false)
	var panel: Control = dock._guides_panel
	panel.set_target(skeleton, player, character)
	_check(not panel._pose_reference.is_empty(), "validated calibrated reference persists")
	panel.edit_character.button_pressed = true
	var hips := skeleton.find_bone(dock._rig_profile.target_for("Hips"))
	var before := Converter.global_transforms(skeleton, false)
	var original_hips: Transform3D = before[hips]
	var old_world := skeleton.global_transform * original_hips.origin
	var desired: Transform3D = panel.guide.global_transform
	desired.origin += Vector3(0.8, 0, -0.4)
	desired.basis = Basis(Vector3.UP, 0.45) * desired.basis
	panel.guide.global_transform = desired
	panel._sync_character()
	var edited := Converter.global_transforms(skeleton, false)
	var edited_world := skeleton.global_transform * edited[hips].origin
	_check(Vector2(edited_world.x, edited_world.z).distance_to(Vector2(desired.origin.x, desired.origin.z)) < 0.00001, "guide edits Hips XZ with scene scale/yaw")
	_check(absf(edited_world.y - old_world.y) < 0.00001, "guide preserves Hips height")
	_check(character.transform == fixed_placement, "guide leaves scene-node reference fixed")
	_check(panel.guide.global_transform.is_equal_approx(desired), "guide and Hips settle without drift")
	for tick in 5:
		panel._sync_character()
	_check(Converter.global_transforms(skeleton, false)[hips].is_equal_approx(edited[hips]), "repeated synchronization has no feedback drift")
	var canonical := Converter.canonical_skeleton(client.capabilities.skeleton_payload)
	var reconstructed := Converter.reconstruct(skeleton, dock._rig_profile, canonical)
	canonical.free()
	var lateral := Quaternion(reconstructed["joint_rotations"]["Hips"][0], reconstructed["joint_rotations"]["Hips"][1], reconstructed["joint_rotations"]["Hips"][2], reconstructed["joint_rotations"]["Hips"][3]) * Vector3.LEFT
	var model_heading := Space.world_heading_to_model(session.root_guides["space"], atan2((desired.basis * Vector3.BACK).x, (desired.basis * Vector3.BACK).z))
	_check(absf(wrapf(atan2(lateral.z, -lateral.x) - model_heading, -PI, PI)) < 0.0001, "guide yaw agrees with complete SOMA conversion")
	# Applying a reusable pose must win over an old handle, and keep finger edits.
	var pose_panel := PosePanel.new()
	root.add_child(pose_panel)
	pose_panel.set_target(skeleton, player)
	pose_panel.position_check.button_pressed = true
	pose_panel.root_check.button_pressed = true
	pose_panel.character_pose_applied.connect(panel.pose_applied)
	pose_panel.bone_list.select(hips)
	var thumb := skeleton.find_bone(dock._rig_profile.target_for("LeftThumbProximal"))
	if thumb < 0:
		for index in skeleton.get_bone_count():
			if String(skeleton.get_bone_name(index)).to_lower().contains("thumb"):
				thumb = index
				break
	_check(thumb >= 0, "private fixture supplies an actual finger bone")
	pose_panel.bone_list.select(thumb, false)
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) + Vector3(0.15, 0, 0.2))
	skeleton.set_bone_pose_rotation(thumb, skeleton.get_bone_pose_rotation(thumb) * Quaternion(Vector3.RIGHT, 0.3))
	pose_panel.title_edit.text = "Moved pose"
	pose_panel.capture_current()
	var authored: Array = panel._complete_channels()
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_rest(hips).origin)
	pose_panel.apply_pose()
	_check(panel._complete_channels() == authored, "pose library application remains authoritative")
	var aligned := PoseGuide.current_guide(skeleton, dock._rig_profile, session.root_guides["space"], panel._pose_reference)
	_check(panel.guide.global_transform.is_equal_approx(aligned["transform"]), "library application synchronizes guide immediately")
	panel.heading_check.button_pressed = true
	panel.record_pose_current()
	_check(session.pose_keyframes.size() == 1 and session.root_guides["points"].size() == 1, "one button records waypoint and complete pose")
	_check(GuideService.constraints(session.root_guides, session.pose_keyframes, 60)["ok"], "combined record submits compatible constraints")
	var entry: Dictionary = session.pose_keyframes[0].duplicate(true)
	var ghost: Node = panel.path_node.find_child("KimodoAuthoredPose_0", true, false)
	_check(ghost != null, "combined record shows authored ghost")
	var ghost_skeleton := _find(ghost, "Skeleton3D") as Skeleton3D
	_check(ghost_skeleton.get_bone_pose_rotation(thumb).is_equal_approx(skeleton.get_bone_pose_rotation(thumb)), "ghost preserves authored finger/detail pose")
	_check(_find(ghost, "AnimationPlayer") == null, "authored ghost has no animation driver")
	session.prompt = "Keep unrelated newer prompt"
	dock._fallback_undo_redo.undo()
	_check(session.pose_keyframes.is_empty() and session.root_guides["points"].is_empty() and session.prompt == "Keep unrelated newer prompt", "single undo removes both fields and preserves unrelated intent")
	dock._fallback_undo_redo.redo()
	_check(session.pose_keyframes.size() == 1 and session.root_guides["points"].size() == 1, "single redo restores pair")
	panel.record_pose_current()
	_check(not panel._pending.is_empty(), "combined replacement requires review")
	panel.replace_dialog.canceled.emit()
	_check(session.pose_keyframes[0] == entry, "replacement cancellation leaves pair intact")
	_check(not panel.replace_dialog.visible, "cancel closes combined replacement review")
	panel.record_pose_current()
	skeleton.set_bone_pose_rotation(thumb, skeleton.get_bone_pose_rotation(thumb) * Quaternion(Vector3.UP, 0.1))
	panel.replace_dialog.confirmed.emit()
	_check(session.pose_keyframes[0] == entry and panel._pending.is_empty(), "stale edited bones refuse combined replacement")
	panel.record_pose_current()
	panel.replace_dialog.confirmed.emit()
	_check(session.pose_keyframes[0] != entry and session.pose_keyframes.size() == 1, "reviewed replacement updates complete snapshot")
	var points_before_failure: Array = session.root_guides["points"].duplicate(true)
	var poses_before_failure: Array = session.pose_keyframes.duplicate(true)
	var spine := skeleton.find_bone(dock._rig_profile.target_for("Spine"))
	var spine_before := skeleton.get_bone_pose_position(spine)
	skeleton.set_bone_pose_position(spine, spine_before + Vector3(0.1, 0, 0))
	panel.record_pose_current()
	_check(session.pose_keyframes == poses_before_failure and session.root_guides["points"] == points_before_failure and panel._pending.is_empty(), "conversion failure cannot leave a half-recorded pair")
	skeleton.set_bone_pose_position(spine, spine_before)
	panel.show_ghosts.button_pressed = false
	_check(panel.path_node.find_child("KimodoAuthoredPose_0", true, false) == null, "hide removes authored ghosts")
	panel.show_ghosts.button_pressed = true
	_check(panel.path_node.find_child("KimodoAuthoredPose_0", true, false) != null, "show reconstructs authored ghosts")
	player.seek(0.501, false)
	panel._sync_character()
	panel.guide.global_position += Vector3(0.2, 0, 0.3)
	panel._sync_character()
	panel.record_current()
	_check(session.root_guides["points"].size() == 2 and session.pose_keyframes.size() == 1, "waypoint-only record does not queue a pose")
	_check(panel.path_node.find_child("KimodoAuthoredPose_15", true, false) == null, "waypoint-only has marker instead of ghost")
	panel._select_point(panel._frames.find(0))
	_check(is_equal_approx(player.current_animation_position, 0.501) and panel._complete_channels() == session.pose_keyframes[0]["authored_channels"], "select restores actual pose at current native frame without seeking")
	var hips_before_waypoint := skeleton.get_bone_pose(hips)
	panel._select_point(panel._frames.find(15))
	_check(not skeleton.get_bone_pose(hips).is_equal_approx(hips_before_waypoint), "waypoint selection restores root visually")
	skeleton.set_bone_pose_rotation(thumb, skeleton.get_bone_pose_rotation(thumb) * Quaternion(Vector3.UP, 0.12))
	var newer_finger := skeleton.get_bone_pose_rotation(thumb)
	panel._bone_undo.undo()
	_check(skeleton.get_bone_pose(hips).is_equal_approx(hips_before_waypoint) and skeleton.get_bone_pose_rotation(thumb).is_equal_approx(newer_finger), "waypoint restore Undo changes only Hips")
	panel._bone_undo.redo()
	_check(skeleton.get_bone_pose_rotation(thumb).is_equal_approx(newer_finger), "waypoint restore Redo preserves unrelated bone edits")
	panel._select_point(panel._frames.find(0))
	var packed := PackedScene.new()
	_check(packed.pack(character) == OK, "scene packs while ghosts present")
	var clean := packed.instantiate()
	_check(clean.find_child("KimodoRootPath", true, false) == null and clean.find_child("KimodoAuthoredPose_0", true, false) == null, "temporary guide/ghosts excluded from saved scene")
	clean.free()
	_check(dock._session_controller.flush()["ok"], "combined records autosave")
	var reopened := Store.open(saved["path"])
	_check(reopened["ok"], "combined records reopen")
	client.capabilities = null
	dock._activate_session(reopened["session"], saved["path"], {})
	panel.set_target(skeleton, player, character)
	_check(not panel._pose_reference.is_empty() and panel.path_node.find_child("KimodoAuthoredPose_0", true, false) != null, "offline binding reconstructs authored ghost/reference")
	_check(panel.guide.global_transform.is_equal_approx(PoseGuide.current_guide(skeleton, dock._rig_profile, dock._draft.root_guides["space"], panel._pose_reference)["transform"]), "rebound editing guide follows current character pose")
	player.seek(0, false)
	panel.record_pose_current()
	_check(not panel._pending.is_empty(), "offline combined editing prepares replacement")
	panel.replace_dialog.confirmed.emit()
	_check(panel._pending.is_empty() and dock._draft.pose_keyframes.size() == 1, "offline replacement commits with serialized profile precision")
	panel.clear_guides()
	_check(not panel._pending.is_empty(), "clearing paired records explains linked pose removal")
	panel.replace_dialog.canceled.emit()
	_check(dock._draft.pose_keyframes.size() == 1, "clear cancellation preserves paired pose")
	panel.record_current()
	panel.replace_dialog.confirmed.emit()
	_check(dock._draft.pose_keyframes.is_empty() and not dock._draft.root_guides["points"][1].has("pose_id"), "waypoint-only replacement removes previous linked pose")
	dock._fallback_undo_redo.undo()
	_check(dock._draft.pose_keyframes.size() == 1, "undo waypoint-only replacement restores combined pair")
	var independent: Dictionary = dock.prepare_pose_keyframe(skeleton, panel._capture_complete()["pose"], 20)
	_check(independent["ok"] and dock.queue_pose_keyframe(independent["entry"])["ok"], "independent Pose Library-style constraint remains supported offline")
	panel.points_list.select(panel._frames.find(0))
	panel.remove_selected()
	_check(dock._draft.pose_keyframes.size() == 1 and dock._draft.pose_keyframes[0] == independent["entry"] and dock._draft.root_guides["points"].size() == 1, "combined removal preserves independent pose constraint")
	dock._fallback_undo_redo.undo()
	_check(dock._draft.pose_keyframes.size() == 2, "removal undo restores pair and keeps independent pose")
	var before_clear_guides: Dictionary = dock._draft.root_guides.duplicate(true)
	var before_clear_poses: Array = dock._draft.pose_keyframes.duplicate(true)
	dock._draft.prompt = "Preserve unrelated intent during clear"
	panel.clear_guides()
	panel.replace_dialog.confirmed.emit()
	_check(dock._draft.root_guides.is_empty() and dock._draft.pose_keyframes.size() == 1 and dock._draft.pose_keyframes[0] == independent["entry"], "committed clear drops linked records and preserves independent pose")
	dock._fallback_undo_redo.undo()
	_check(dock._draft.root_guides == before_clear_guides and dock._draft.pose_keyframes == before_clear_poses and dock._draft.prompt == "Preserve unrelated intent during clear", "clear Undo restores both fields without reverting unrelated intent")
	panel.set_target(skeleton, player, character)
	_check(panel.path_node.find_child("KimodoAuthoredPose_0", true, false) != null, "rebind after clear Undo reconstructs ghost offline")
	var capture_args := OS.get_cmdline_user_args()
	if capture_args.size() == 1:
		DirAccess.make_dir_recursive_absolute(capture_args[0])
		pose_panel.hide()
		dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dock._workspace_tabs.current_tab = panel.get_index()
		for width in [360, 680]:
			root.size = Vector2i(width, 1250)
			for tick in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture_args[0].path_join("guide_poses_%d.png" % width))
	pose_panel.free()
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
		print("PASS: visual Hips authoring, combined atomic records, authored ghosts and offline editing")
	quit(0 if failures.is_empty() else 1)


func _find(node: Node, type: String) -> Node:
	if node == null:
		return null
	if node.is_class(type):
		return node
	for child in node.get_children():
		var found := _find(child, type)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		print("GUIDE_POSE_CHECK_FAILED ", message)
		failures.append(message)
