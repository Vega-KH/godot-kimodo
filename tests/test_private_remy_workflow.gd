extends SceneTree

const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const MotionResponse := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const PreviewPanel := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
const RigProfileStore := preload("res://addons/kimodo_motion/retargeting/rig_profile_store.gd")
const TakeArchive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const REMY_PATH := "res://tests/private_models/Remy-with-taunt-animation.fbx"
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const CAPABILITIES_FIXTURE := "res://tests/fixtures/soma77_capabilities.json"

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(REMY_PATH):
		print("SKIP: private Remy dock workflow (fixture is intentionally not distributed)")
		quit(0)
		return
	var remy := ResourceLoader.load(REMY_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var remy_hash := FileAccess.get_sha256(REMY_PATH)
	var baseline := remy.instantiate()
	var baseline_player := _find_first(baseline, "AnimationPlayer") as AnimationPlayer
	var bundled_names := baseline_player.get_animation_list()
	var bundled_current := baseline_player.current_animation
	baseline.free()

	var dock := Dock.new()
	root.add_child(dock)
	await process_frame
	(dock.find_child("NewSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	var session_path: String = dock._draft_path
	var session_id: String = dock._draft.session_id
	dock._on_character_target_changed(remy)
	_check(dock._character_target == remy, "unsupported character stays selected for Rig Setup")
	_check(dock._rig_profile == null, "generation is gated before profile certification")
	_check(dock._workspace_tabs.current_tab == dock._rig_setup_panel.get_index(), "selection routes directly to Rig Setup")
	var hand := dock._rig_setup_panel.find_child("RigRole_LeftHand", true, false) as OptionButton
	var suggested_hand := hand.selected
	hand.select(0)
	hand.emit_signal("item_selected", 0)
	_check(not dock._rig_setup_panel.current_mapping().has("LeftHand"), "artist override wins over suggestion")
	dock._rig_setup_panel.reset_button.emit_signal("pressed")
	_check((dock._rig_setup_panel.find_child("RigRole_LeftHand", true, false) as OptionButton).selected == suggested_hand, "Reset Suggestions restores the reviewed row")
	dock._rig_setup_panel.save_button.emit_signal("pressed")
	_check(dock._rig_profile != null, "reviewed Remy profile certifies and saves")
	var profile_path: String = dock._draft.rig_profile_path
	_check(FileAccess.file_exists(profile_path), "session references a project-owned profile")

	var parsed := MotionResponse.parse(FileAccess.get_file_as_bytes(MOTION_FIXTURE), 30, 30.0)
	var capabilities_json := FileAccess.get_file_as_string(CAPABILITIES_FIXTURE)
	var capabilities := Capabilities.parse_json_text(capabilities_json)
	var archive := TakeArchive.archive_generation(dock._draft, dock._draft_path, JSON.stringify({"options":{"num_samples":1}}), capabilities_json, FileAccess.get_file_as_bytes(MOTION_FIXTURE), capabilities["capabilities"], [parsed["motion"]])
	_check(archive["ok"], "Remy workflow retains an authoritative source take before preview")
	var accepted_source: bool = parsed["ok"] and dock._accept_source_motion(parsed["motion"])
	if not accepted_source:
		printerr("REMY PREVIEW DIAGNOSTIC: ", dock._character_status.text, " / ", dock._draft_status.text)
	_check(accepted_source, "Remy previews a deterministic Kimodo take")
	_check(dock._preview_panel.has_character(), "Remy character preview is available")
	var character_preview := dock._character_preview
	var follow_index: int = character_preview._follow_bone_index
	_check(
		follow_index >= 0
		and character_preview.skeleton().get_bone_name(follow_index) == "mixamorig_Hips",
		"Hips-is-root profile gives camera following to mapped Mixamo Hips",
	)
	character_preview.animation_player().seek(29.0 / 30.0, true)
	character_preview._update_follow_target()
	var followed_hips: Vector3 = character_preview._world_root.to_local(
		character_preview.skeleton().to_global(
			character_preview.skeleton().get_bone_global_pose(follow_index).origin
		)
	)
	_check(
		Vector2(character_preview.camera_target().x, character_preview.camera_target().z).distance_to(
			Vector2(followed_hips.x, followed_hips.z)
		) < 0.0001,
		"character camera tracks mapped Hips planar travel",
	)
	var preview_root: Node = dock._character_preview.motion_scene()
	var imported_player := _find_first_except(preview_root, "AnimationPlayer", "KimodoAnimationPlayer") as AnimationPlayer
	_check(imported_player != null and imported_player.get_animation_list() == bundled_names and imported_player.current_animation == bundled_current, "preview preserves and does not play bundled target animations")

	var output_dir := "res://tests/.goal18_remy_%d" % OS.get_process_id()
	var saved_path := output_dir.path_join("remy_motion.res")
	dock._preview_panel.submit_save_path(PreviewPanel.SaveKind.CHARACTER_ANIMATION, saved_path)
	_check(FileAccess.file_exists(saved_path), "Remy character animation saves as a lightweight library")
	var preview_path := output_dir.path_join("remy_preview.tscn")
	dock._preview_panel.submit_save_path(PreviewPanel.SaveKind.CHARACTER_PREVIEW, preview_path)
	_check(FileAccess.file_exists(preview_path), "Remy Character Preview saves")
	var saved_preview := ResourceLoader.load(
		preview_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var saved_preview_root := saved_preview.instantiate()
	var saved_players := saved_preview_root.find_children("*", "AnimationPlayer", true, false)
	_check(
		saved_players.size() == 1
		and saved_players[0].name == "KimodoAnimationPlayer"
		and (saved_players[0] as AnimationPlayer).has_animation("motion"),
		"saved Character Preview contains only its selected Kimodo animation player",
	)
	saved_preview_root.free()
	_check(
		imported_player.get_animation_list() == bundled_names
		and imported_player.current_animation == bundled_current
		and FileAccess.get_sha256(REMY_PATH) == remy_hash,
		"preview save leaves live and imported Remy animations untouched",
	)
	var accepted_path := output_dir.path_join("remy_production.res")
	dock._on_accept_requested(accepted_path, "remy_walk", false)
	if not FileAccess.file_exists(accepted_path):
		printerr("REMY ACCEPT DIAGNOSTIC: ", dock._preview_panel.accept_status.text)
	_check(FileAccess.file_exists(accepted_path), "Remy take accepts into a production library")
	var accepted := ResourceLoader.load(accepted_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	_check(accepted != null and accepted.has_animation("remy_walk"), "accepted Remy animation reloads")
	if dock._fallback_undo_redo != null:
		dock._fallback_undo_redo.undo()
		accepted = ResourceLoader.load(accepted_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
		_check(accepted != null and not accepted.has_animation("remy_walk"), "Remy Accept participates in Goal 17 Undo")
		dock._fallback_undo_redo.redo()

	# Re-select without clearing the session: exact signature loads the saved profile.
	dock._on_character_target_changed(remy)
	if dock._rig_profile == null:
		printerr("REMY REUSE DIAGNOSTIC: ", dock._character_status.text, " / profile=", dock._draft.rig_profile_path)
	_check(dock._rig_profile != null and dock._draft.rig_profile_path == profile_path, "exact signature reuses the saved profile")
	_check(
		dock._rig_setup_panel.find_child("RigRole_Hips", true, false) != null
		and dock._rig_setup_panel.find_child("RigRole_Chest", true, false) != null,
		"certified profile remains visible and editable in Rig Setup",
	)
	dock.queue_free()
	await process_frame
	var reopened_dock := Dock.new()
	root.add_child(reopened_dock)
	await process_frame
	reopened_dock._open_session_path(session_path)
	await process_frame
	_check(
		reopened_dock._rig_profile != null
		and reopened_dock._rig_setup_panel.find_child("RigRole_Hips", true, false) != null
		and reopened_dock._rig_setup_panel.find_child("RigRole_Chest", true, false) != null,
		"reopened mapped session reconstructs all Rig Setup selectors",
	)
	reopened_dock.queue_free()
	await process_frame
	_remove_directory(output_dir)
	_remove_tree(TakeArchive.DATA_ROOT.path_join(session_id))
	_remove_file(session_path)
	_remove_file(profile_path)
	_finish()

func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null

func _find_first_except(node: Node, type_name: StringName, excluded_name: String) -> Node:
	if node == null:
		return null
	if node.is_class(type_name) and node.name != excluded_name:
		return node
	for child in node.get_children():
		var found := _find_first_except(child, type_name, excluded_name)
		if found != null:
			return found
	return null

func _remove_file(path: String) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _remove_directory(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)

func _remove_tree(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := DirAccess.open(absolute)
	if directory == null:
		return
	for file_name in directory.get_files():
		DirAccess.remove_absolute(absolute.path_join(file_name))
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(absolute)

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("PASS: private Remy Rig Setup, profile reuse, preview, Save, and Accept")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
