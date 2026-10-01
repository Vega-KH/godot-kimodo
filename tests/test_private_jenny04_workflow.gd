extends SceneTree

const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Generation := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Response := preload("res://addons/kimodo_motion/transport/mmcp_motion_response.gd")
const Capabilities := preload("res://addons/kimodo_motion/transport/mmcp_capabilities.gd")
const Archive := preload("res://addons/kimodo_motion/domain/take_archive_service.gd")
const PreviewPanel := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
const Baker := preload("res://addons/kimodo_motion/retargeting/humanoid_character_baker.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Geometry := preload("res://addons/kimodo_motion/retargeting/rig_geometry.gd")
const Compatibility := preload("res://addons/kimodo_motion/retargeting/rig_compatibility.gd")
const Acceptance := preload("res://addons/kimodo_motion/domain/acceptance_service.gd")
const Source := preload("res://tests/retargeting/generated/soma77_walk_humanoid.tscn")
const JENNY := "res://tests/private_models/Jenny04.glb"
const MANNEQUINY := "res://tests/private_models/mannequiny-0.3.0.glb"
const MOTION := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const CAPS := "res://tests/fixtures/soma77_capabilities.json"

var failures: Array[String] = []
var capture_directory := ""

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var capture_index := arguments.find("--capture-dir")
	if capture_index >= 0 and capture_index + 1 < arguments.size():
		capture_directory = arguments[capture_index + 1]
		DirAccess.make_dir_recursive_absolute(capture_directory)
		root.size = Vector2i(480, 1100)
	if not FileAccess.file_exists(JENNY):
		print("SKIP: private Jenny04 workflow (fixture is not distributed)")
		quit(0)
		return
	var hash_before := FileAccess.get_sha256(JENNY)
	var directory := "res://tests/.goal19_jenny_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var original := load(JENNY) as PackedScene
	var target := original.instantiate() as Node3D
	# Use a unique target path so saving a test profile never overwrites an artist's.
	# An authored clip tests preservation even though Jenny04 contains no clips.
	var authored := AnimationPlayer.new()
	authored.name = "AuthoredPlayer"
	target.add_child(authored)
	authored.owner = target
	var authored_library := AnimationLibrary.new()
	authored_library.add_animation("artist_clip", Animation.new())
	authored.add_animation_library("", authored_library)
	var packed := PackedScene.new()
	_check(packed.pack(target) == OK, "isolated target packs")
	var target_path := directory.path_join("target.tscn")
	_check(ResourceSaver.save(packed, target_path) == OK, "isolated target saves")
	target.free()
	packed = ResourceLoader.load(target_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var target_hash := FileAccess.get_sha256(target_path)
	var client := Client.new()
	var generation := Generation.new()
	root.add_child(client)
	root.add_child(generation)
	client.capabilities = Capabilities.parse_json_text(FileAccess.get_file_as_string(CAPS))["capabilities"]
	client.state = Client.ConnectionState.READY
	var dock := Dock.new()
	dock.configure(client, generation)
	root.add_child(dock)
	if not capture_directory.is_empty():
		dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	(dock.find_child("NewSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	var session_path: String = dock._draft_path
	var session_id: String = dock._draft.session_id
	dock._on_character_target_changed(packed)
	_check(dock._rig_profile != null, "regular Jenny04 body can configure without identity-based math")
	# Suggestions recognize Eye_L / Eye_R through the general sided convention.
	dock._rig_setup_panel.reset_button.emit_signal("pressed")
	_check(dock._rig_setup_panel.current_mapping().get("LeftEye", "") == "Eye_L", "generic sided names suggest the left eye")
	dock._rig_setup_panel.save_button.emit_signal("pressed")
	_check(dock._rig_profile != null and dock._rig_profile.target_for("RightEye") == "Eye_R", "reviewed optional eyes certify")
	var profile_path: String = dock._draft.rig_profile_path
	var frames: Dictionary = dock._rig_profile.hand_frames.duplicate(true)
	var omissions: Array = dock._rig_profile.ignored_optional_roles.duplicate()
	dock._workspace_tabs.current_tab = dock._rig_setup_panel.get_index()
	await _capture("rig_optional_roles.png")
	var scroll := dock._rig_setup_panel.rows.get_parent() as ScrollContainer
	scroll.scroll_vertical = 99999
	await _capture("rig_palm_landmarks.png")
	# Check the error is visible and generation is disabled after a valid target.
	if FileAccess.file_exists(MANNEQUINY):
		dock._on_character_target_changed(load(MANNEQUINY))
		_check(dock._character_status.text.contains("bind pose does not match") and dock._rig_setup_panel.status.text.contains("re-export"), "dock displays the actionable incompatibility")
		_check(dock._generate_button.disabled and dock._rig_profile == null and dock._rig_setup_panel.find_child("RigRole_Hips", true, false) == null, "incompatible selection clears stale maps and gates generation")
		await _capture("rig_incompatible.png")
		dock._on_character_target_changed(packed)
		_check(dock._rig_profile != null, "valid target restores reviewed mapping after rejection")
	var parsed := Response.parse(FileAccess.get_file_as_bytes(MOTION), 30, 30.0)
	var archive := Archive.archive_generation(dock._draft, session_path, JSON.stringify({"options":{"num_samples":1}}), FileAccess.get_file_as_string(CAPS), FileAccess.get_file_as_bytes(MOTION), client.capabilities, [parsed["motion"]])
	_check(archive["ok"] and dock._accept_source_motion(parsed["motion"]), "source archives and previews on Jenny04")
	var take_id: String = dock._draft.active_take_summaries()[0]["take_id"]
	var scene: Node3D = dock._character_preview.motion_scene()
	dock._workspace_tabs.current_tab = dock._preview_panel.get_index()
	await _capture("jenny04_preview.png")
	_check(dock._character_preview.skeleton().get_bone_name(dock._character_preview._follow_bone_index) == "Root", "Jenny04 camera follows effective Root")
	_check(scene.get_node("AuthoredPlayer").has_animation("artist_clip"), "live preview retains authored clip")
	var library_path := directory.path_join("character.res")
	dock._preview_panel.submit_save_path(PreviewPanel.SaveKind.CHARACTER_ANIMATION, library_path)
	var library := ResourceLoader.load(library_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	_check(library != null and FileAccess.get_file_as_bytes(library_path).size() < 200000, "saved library is lightweight and reloads")
	var fresh := packed.instantiate() as Node3D
	root.add_child(fresh)
	var player := AnimationPlayer.new()
	fresh.add_child(player)
	player.add_animation_library("", library)
	player.play("motion")
	player.seek(0.5, true)
	_check(Compatibility.inspect(fresh)["ok"], "saved tracks play on fresh target with unchanged rest/skin")
	fresh.free()
	var preview_path := directory.path_join("preview.tscn")
	dock._preview_panel.submit_save_path(PreviewPanel.SaveKind.CHARACTER_PREVIEW, preview_path)
	var preview_scene := (ResourceLoader.load(preview_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	_check(preview_scene.find_children("*", "AnimationPlayer", true, false).size() == 1, "saved preview removes authored players only in detached copy")
	preview_scene.free()
	var accepted_path := directory.path_join("production.res")
	dock._on_accept_requested(accepted_path, "jenny_walk", false)
	_check(FileAccess.file_exists(accepted_path), "optional-anatomy profile accepts into production library")
	var after := FileAccess.get_file_as_bytes(accepted_path)
	dock._fallback_undo_redo.undo()
	var undone := ResourceLoader.load(accepted_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	_check(not undone.has_animation("jenny_walk"), "Undo removes accepted entry")
	dock._fallback_undo_redo.redo()
	_check(FileAccess.get_file_as_bytes(accepted_path) == after, "Redo restores exact bytes")
	# Skin changes can invalidate an asset even when its skeleton signature matches.
	var incompatible := packed.instantiate() as Node3D
	var mesh := incompatible.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	mesh.skin = mesh.skin.duplicate() as Skin
	var bind := mesh.skin.get_bind_pose(0)
	bind.origin += Vector3(0.3, 0, 0)
	mesh.skin.set_bind_pose(0, bind)
	var changed := PackedScene.new()
	changed.pack(incompatible)
	var broken_path := directory.path_join("broken.tscn")
	changed.take_over_path(broken_path)
	var preflight := Acceptance._validate_clean_target(changed, broken_path, dock._draft.target_skeleton_signature, library.get_animation("motion"))
	_check(not preflight["ok"] and preflight["message"].contains("bind pose does not match"), "Accept rechecks skins, not just skeleton signature")
	incompatible.free()
	await _stress(original, directory)
	dock.queue_free()
	await process_frame
	dock = Dock.new()
	dock.configure(client, generation)
	root.add_child(dock)
	await process_frame
	dock._open_session_path(session_path)
	await process_frame
	if dock._rig_profile == null:
		printerr("JENNY04 REOPEN DIAGNOSTIC: ", dock._character_status.text, " / ", dock._draft_status.text)
	_check(dock._rig_profile != null and dock._rig_profile.hand_frames == frames and dock._rig_profile.ignored_optional_roles == omissions, "session reopen preserves frame pairs and omissions")
	_check(dock._rig_setup_panel.current_mapping().get("RightEye", "") == "Eye_R", "reopened Rig Setup retains optional eye mapping")
	dock._on_history_take_activated(0, take_id)
	_check(dock._character_preview.has_motion(), "History rebuilds preview offline")
	_check(FileAccess.get_sha256(JENNY) == hash_before and FileAccess.get_sha256(target_path) == target_hash, "source asset and authored target stay byte-identical")
	dock.queue_free()
	client.queue_free()
	generation.queue_free()
	await process_frame
	_remove_tree(directory)
	_remove_tree(Archive.DATA_ROOT.path_join(session_id))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path))
	if failures.is_empty():
		print("PASS: private Jenny04 skin/eyes/hair, optional profile, offline History, Save, Accept and Undo/Redo")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func _stress(original: PackedScene, directory: String) -> void:
	var source := Source.instantiate()
	root.add_child(source)
	var source_skeleton := source.find_child("HumanoidSkeleton") as Skeleton3D
	var source_player := source.find_child("AnimationPlayer") as AnimationPlayer
	var animation := source_player.get_animation("motion").duplicate(true) as Animation
	# Make Head, both eyes and all digits non-rest, independently of Kimodo's
	# training distribution. Existing walk tracks are replaced, not duplicated.
	var stress_bones: Array[String] = ["Head", "LeftEye", "RightEye", "LeftHand", "RightHand"]
	for side in ["Left", "Right"]:
		for digit in Profile.DIGIT_JOINTS:
			for joint in Profile.DIGIT_JOINTS[digit]:
				stress_bones.append(side + digit + joint)
	for bone in stress_bones:
		var track := -1
		for index in animation.get_track_count():
			if animation.track_get_type(index) == Animation.TYPE_ROTATION_3D and animation.track_get_path(index).get_subname(0) == bone:
				track = index
				break
		if track >= 0:
			animation.remove_track(track)
		track = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath("HumanoidSkeleton:" + bone))
		var rest := source_skeleton.get_bone_rest(source_skeleton.find_bone(bone)).basis.get_rotation_quaternion()
		animation.rotation_track_insert_key(track, 0.0, rest)
		animation.rotation_track_insert_key(track, 0.5, rest * Quaternion(Vector3(0.2, 0.7, 0.4).normalized(), 0.45 if bone != "RightEye" else -0.3))
		animation.rotation_track_insert_key(track, animation.length, rest)
	var stress_library := AnimationLibrary.new()
	stress_library.add_animation("motion", animation)
	source_player.remove_animation_library("")
	source_player.add_animation_library("", stress_library)
	var character := original.instantiate() as Node3D
	root.add_child(character)
	var target := character.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mapping: Dictionary = Profile.exact_names(target, character.get_path_to(target))["profile"].canonical_to_target.duplicate()
	mapping["LeftEye"] = "Eye_L"
	mapping["RightEye"] = "Eye_R"
	var profile: Resource = Profile.create(mapping, character.get_path_to(target), target)["profile"]
	var motion := Baker.create_motion(source, character, profile)
	_check(motion != null, "synthetic stress motion bakes on Jenny04")
	if motion == null:
		character.free()
		source.free()
		return
	var target_rests := Geometry.global_rests(target)
	var source_rests := Geometry.global_rests(source_skeleton)
	var hair := target.find_bone("Hair")
	var head := target.find_bone("Head")
	var worst := 0.0
	for time in [0.0, 0.25, 0.5, animation.length]:
		source_player.play("motion")
		source_player.seek(time, true)
		motion.player.seek(time, true)
		for eye in ["LeftEye", "RightEye"]:
			var si := source_skeleton.find_bone(eye)
			var ti := target.find_bone(profile.target_for(eye))
			var expected := source_skeleton.get_bone_global_pose(si).basis * source_rests[si].basis.inverse() * target_rests[ti].basis
			worst = maxf(worst, rad_to_deg(expected.get_rotation_quaternion().angle_to(target.get_bone_global_pose(ti).basis.get_rotation_quaternion())))
		_check(target.get_bone_pose(hair).is_equal_approx(target.get_bone_rest(hair)), "hair retains local rest under stress")
		_check(target.get_bone_global_pose(hair).is_equal_approx(target.get_bone_global_pose(head) * target.get_bone_rest(hair)), "hair follows animated Head under stress")
	_check(worst < 0.1, "independent optional-eye rotation oracle <0.1 degrees (%.6f)" % worst)
	motion.player.seek(0.5, true)
	for bone in ["Hair", "Eye_L", "Eye_R"]:
		_check(_weighted_displacement(character, target, bone) > 0.00001, bone + " has finite animated weighted vertex displacement")
	print("JENNY04 STRESS: optional-eye maximum angular error %.6f degrees; hair parent inheritance verified" % worst)
	Baker.save_library(character, directory, "jenny04_stress")
	if OS.get_cmdline_user_args().has("--keep-stress"):
		var manual_directory := "res://tests/private_models/goal19_manual"
		var library := Baker.save_library(character, manual_directory, "jenny04_stress")
		var preview := Baker.save_preview_scene(character, manual_directory, "jenny04_stress")
		var source_scene := PackedScene.new()
		_check(source_scene.pack(source) == OK, "manual stress source packs")
		var source_path := manual_directory.path_join("humanoid_stress.tscn")
		# The manual directory is test-owned, not a production destination.
		_check(ResourceSaver.save(source_scene, source_path) == OK, "manual stress source saves")
		print("MANUAL STRESS LIBRARY: ", library.get("library_path", ""))
		print("MANUAL STRESS PREVIEW: ", preview.get("scene_path", ""))
		print("MANUAL STRESS SOURCE: ", source_path)
	character.free()
	source.free()

func _capture(filename: String) -> void:
	if capture_directory.is_empty():
		return
	for frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_directory.path_join(filename))

func _weighted_displacement(character: Node3D, skeleton: Skeleton3D, bone: String) -> float:
	var maximum := 0.0
	for found in character.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		if mesh.skin == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var influences := bones.size() / vertices.size()
			for vertex in vertices.size():
				var used := false
				var posed := Vector3.ZERO
				var rest := Vector3.ZERO
				for influence in influences:
					var offset := vertex * influences + influence
					if weights[offset] <= 0.0:
						continue
					var bind := bones[offset]
					var name := mesh.skin.get_bind_name(bind)
					var index := skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(bind)
					used = used or skeleton.get_bone_name(index) == bone
					posed += (skeleton.get_bone_global_pose(index) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
					rest += (skeleton.get_bone_global_rest(index) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
				if used:
					_check(posed.is_finite(), "weighted skin vertex stays finite")
					maximum = maxf(maximum, posed.distance_to(rest))
	return maximum

func _remove_tree(path: String) -> void:
	# Only called with the exact per-process test directory / created session ID.
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file)))
	for child in directory.get_directories():
		_remove_tree(path.path_join(child))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
