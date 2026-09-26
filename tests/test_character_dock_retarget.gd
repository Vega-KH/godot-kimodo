extends SceneTree

const MotionResponse := preload(
	"res://addons/kimodo_motion/transport/mmcp_motion_response.gd"
)
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const PreviewPanel := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
const MOTION_FIXTURE := "res://tests/fixtures/soma77_mmcp_1_0.gltf"
const JENNY_SCENE := preload("res://tests/characters/fixtures/Jenny03.glb")
const JENNY_PATH := "res://tests/characters/fixtures/Jenny03.glb"
const SAMPLE_TIMES := [0.0, 0.25, 0.5, 29.0 / 30.0]

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture_hash := FileAccess.get_sha256(JENNY_PATH)
	var dock := Dock.new()
	root.add_child(dock)
	await process_frame
	(dock.find_child("NewSession", true, false) as Button).emit_signal("pressed")
	await process_frame
	var session_path: String = dock._draft_path
	var picker := dock.find_child("CharacterTarget", true, false) as Control
	var clear := dock.find_child("ClearCharacterTarget", true, false) as Button
	var save := dock.find_child("SaveSelectedTake", true, false) as Button
	var status := dock.find_child("CharacterStatus", true, false) as Label
	var selector := dock.find_child("PreviewSelection", true, false) as OptionButton
	var source: Control = dock.find_child("MotionPreview", true, false)
	var humanoid: Control = dock.find_child("HumanoidPreview", true, false)
	var character: Control = dock.find_child("CharacterPreview", true, false)
	_check(picker != null, "character target selector is present")
	_check(clear.disabled, "clear begins disabled")
	_check(dock.find_child("PreviewOnCharacter", true, false) == null, "obsolete preview button is absent")
	_check(save.disabled, "character save begins disabled")
	_check(selector.item_count == 3, "preview selector includes the skinned character")
	_check(selector.is_item_disabled(2), "character preview choice begins disabled")

	var invalid_root := Node3D.new()
	invalid_root.name = "InvalidCharacter"
	var invalid_skeleton := Skeleton3D.new()
	invalid_skeleton.name = "Skeleton3D"
	invalid_skeleton.add_bone("Hips")
	invalid_root.add_child(invalid_skeleton)
	invalid_skeleton.owner = invalid_root
	var invalid_scene := PackedScene.new()
	_check(invalid_scene.pack(invalid_root) == OK, "invalid target packs for validation coverage")
	invalid_root.free()
	dock._on_character_target_changed(invalid_scene)
	_check(status.text.contains("Root"), "incompatible target reports its missing Root")
	_check(not clear.disabled, "an incompatible selection can still be cleared")
	clear.emit_signal("pressed")
	_check(dock._character_target == null, "clear resets the target resource")

	dock._on_character_target_changed(JENNY_SCENE)
	_check(status.text.contains("61 bones"), "Jenny compatibility summary is shown")
	_check(status.text.contains("8 skinned meshes"), "Jenny skin summary is shown")
	_check(dock._accept_source_motion(_parse_motion()), "validated source enters the dock")
	_check(humanoid.has_motion(), "humanoid intermediate is ready")
	_check(character.has_motion(), "character preview owns a retargeted scene")
	_check(character.skeleton().get_bone_count() == 61, "character preview retains Jenny's rig")
	_check(_skinned_mesh_count(character.motion_scene()) == 8, "character preview retains all skins")
	_check(_animation(character).get_track_count() == 24, "character preview has editable body tracks")
	_check(selector.visible and selector.selected == 2, "character preview is selected")
	_check(not selector.is_item_disabled(2), "character preview choice enables with motion")
	_check(character.visible and not source.visible and not humanoid.visible, "only selected preview is visible")
	_check(not save.disabled, "character save enables after preview")
	_check(FileAccess.get_sha256(JENNY_PATH) == fixture_hash, "preview does not modify Jenny")

	dock._seek_previews(0.5)
	_check(absf(source.current_position() - 0.5) < 0.001, "source scrub stays synchronized")
	_check(absf(humanoid.current_position() - 0.5) < 0.001, "humanoid scrub stays synchronized")
	_check(absf(character.current_position() - 0.5) < 0.001, "character scrub stays synchronized")
	var loop_toggle := dock.find_child("LoopMotion", true, false) as CheckButton
	loop_toggle.button_pressed = false
	loop_toggle.emit_signal("toggled", false)
	_check(_animation(character).loop_mode == Animation.LOOP_NONE, "loop state reaches character")
	var play := dock.find_child("PlayPause", true, false) as Button
	play.emit_signal("pressed")
	_check(not character.is_playing(), "shared playback pauses the character")
	var source_view: Dictionary = source.camera_view()
	_check(character.camera_view() == source_view, "character camera inherits the shared view")

	var preview_scene: Node = character.motion_scene()
	var preview_animation := _animation(character)
	var relative_directory := "res://tests/.goal12_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()
	]
	var first_scene := relative_directory.path_join("jenny generated walk.tscn")
	dock._preview_panel.submit_save_path(PreviewPanel.SaveKind.CHARACTER, first_scene)
	var save_status := dock.find_child("TakeSaveStatus", true, false) as Label
	_check(FileAccess.file_exists(first_scene), "character scene is saved")
	_check(save_status.text.contains(first_scene), "character output path is reported")
	_check(character.motion_scene() == preview_scene, "save preserves live preview ownership")
	dock._preview_panel.submit_save_path(PreviewPanel.SaveKind.CHARACTER, first_scene)
	_check(save_status.text.contains("never overwrites"), "duplicate character save is rejected")
	_check(FileAccess.get_sha256(JENNY_PATH) == fixture_hash, "saving does not modify Jenny")

	var packed := ResourceLoader.load(
		first_scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var saved_scene := packed.instantiate()
	root.add_child(saved_scene)
	var saved_skeleton := _find_first(saved_scene, "Skeleton3D") as Skeleton3D
	var saved_player := saved_scene.get_node("KimodoAnimationPlayer") as AnimationPlayer
	_check(saved_skeleton.get_bone_count() == 61, "saved character reloads Jenny's skeleton")
	_check(_skinned_mesh_count(saved_scene) == 8, "saved character reloads all skins")
	_check(saved_player.has_animation("motion"), "saved character exposes editable motion")
	_compare_animations(preview_animation, saved_player.get_animation("motion"))
	_check(ResourceLoader.get_dependencies(first_scene).is_empty(), "saved character is self-contained")

	var old_character_scene: Node = character.motion_scene()
	clear.emit_signal("pressed")
	_check(not is_instance_valid(old_character_scene), "clearing target frees character preview")
	_check(not character.has_motion(), "clearing target removes character state")
	_check(humanoid.has_motion(), "clearing target preserves humanoid intermediate")
	_check(selector.selected == 1 and humanoid.visible, "clear returns to humanoid preview")
	_check(selector.is_item_disabled(2), "clear disables the character preview choice")
	_check(save.disabled, "clear disables character save")

	dock._on_character_target_changed(JENNY_SCENE)
	_check(character.has_motion(), "selecting a target rebuilds the character conversion")
	var replacement_character_scene: Node = character.motion_scene()
	_check(dock._accept_source_motion(_parse_motion()), "replacement source is accepted")
	_check(not is_instance_valid(replacement_character_scene), "replacement frees character preview")
	_check(humanoid.has_motion() and character.has_motion(), "replacement rebuilds derived previews")
	_check(dock._character_target == JENNY_SCENE, "replacement preserves target selection")

	saved_scene.queue_free()
	dock.queue_free()
	await process_frame
	if FileAccess.file_exists(session_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))
	_remove_test_directory(relative_directory)
	_check(root.get_child_count() == 0, "character dock workflow leaves no nodes behind")
	_finish()


func _parse_motion() -> RefCounted:
	var parsed := MotionResponse.parse(
		FileAccess.get_file_as_bytes(MOTION_FIXTURE), 30, 30.0
	)
	_check(parsed["ok"], "motion fixture parses")
	return parsed["motion"] if parsed["ok"] else null


func _animation(preview: Control) -> Animation:
	var player: AnimationPlayer = preview.animation_player()
	return player.get_animation("motion")


func _skinned_mesh_count(node: Node) -> int:
	var count := 0
	for found in node.find_children("*", "MeshInstance3D", true, false):
		if (found as MeshInstance3D).skin != null:
			count += 1
	return count


func _compare_animations(source: Animation, saved: Animation) -> void:
	var saved_by_key := {}
	for track in saved.get_track_count():
		saved_by_key[_track_key(saved, track)] = track
	for source_track in source.get_track_count():
		var key := _track_key(source, source_track)
		_check(saved_by_key.has(key), "saved character retains %s" % key)
		if not saved_by_key.has(key):
			continue
		for time in SAMPLE_TIMES:
			var before: Variant = _sample(source, source_track, time)
			var after: Variant = _sample(saved, saved_by_key[key], time)
			if before is Quaternion:
				_check(
					before.normalized().angle_to(after.normalized()) <= 0.001,
					"%s rotation reloads" % key,
				)
			else:
				_check(before.distance_to(after) <= 0.000001, "%s position reloads" % key)


func _track_key(animation: Animation, track: int) -> String:
	return "%d:%s" % [animation.track_get_type(track), animation.track_get_path(track)]


func _sample(animation: Animation, track: int, time: float) -> Variant:
	if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
		return animation.rotation_track_interpolate(track, time)
	return animation.position_track_interpolate(track, time)


func _find_first(node: Node, type_name: StringName) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_first(child, type_name)
		if found != null:
			return found
	return null


func _remove_test_directory(directory: String) -> void:
	var absolute := ProjectSettings.globalize_path(directory)
	var access := DirAccess.open(absolute)
	if access == null:
		return
	for file_name in access.get_files():
		DirAccess.remove_absolute(absolute.path_join(file_name))
	DirAccess.remove_absolute(absolute)


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: dock character selection, preview, save, reload, and lifecycle")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)
