extends SceneTree

# Run in a newly packaged project with models/character.glb; preserve outputs
# for the separate fresh-process offline gate. Never use an artist project.
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Generation := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Pose := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const Space := preload("res://addons/kimodo_motion/guides/root_guide_space.gd")
const Preview := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var client := Client.new()
	var generation := Generation.new()
	generation.timeout_seconds = 300
	root.add_child(client)
	root.add_child(generation)
	var dock := Dock.new()
	dock.configure(client, generation)
	root.add_child(dock)
	await process_frame
	var character: Node3D
	if OS.get_cmdline_user_args().has("--offline"):
		for entry in Store.list_sessions():
			if entry["title"] == "Goal 24 isolated visual poses":
				dock._open_session_path(entry["path"])
		_check(dock._draft != null, "offline session found")
		if dock._draft == null:
			_finish(dock, client, generation, null)
			return
		character = (load("res://authoring.tscn") as PackedScene).instantiate()
		root.add_child(character)
	else:
		dock._session_title_edit.text = "Goal 24 isolated visual poses"
		dock._on_new_session_pressed()
		var asset := load("res://models/character.glb") as PackedScene
		dock._on_character_target_changed(asset)
		dock._duration_edit.value = 60
		dock._url_edit.text = Client.DEFAULT_URL
		(dock.find_child("ConnectionAction", true, false) as Button).pressed.emit()
		await _wait(client, Client.ConnectionState.CONNECTING, 30)
		_check(client.state == Client.ConnectionState.READY, "live capabilities connected")
		if client.state != Client.ConnectionState.READY:
			_finish(dock, client, generation, null)
			return
		character = asset.instantiate()
		character.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(3, 0, -2))
		var player := AnimationPlayer.new()
		player.name = "AuthoringPlayer"
		character.add_child(player)
		player.owner = character
		var library := AnimationLibrary.new()
		var animation := Animation.new()
		animation.length = 2
		animation.step = 1.0 / 30.0
		library.add_animation("author", animation)
		player.add_animation_library("", library)
		var packed := PackedScene.new()
		_check(packed.pack(character) == OK and ResourceSaver.save(packed, "res://authoring.tscn") == OK, "native authoring scene saved")
		character.free()
		character = (load("res://authoring.tscn") as PackedScene).instantiate()
		root.add_child(character)
	var skeleton := _find(character, "Skeleton3D") as Skeleton3D
	var player := character.get_node("AuthoringPlayer") as AnimationPlayer
	player.assigned_animation = "author"
	player.seek(0, false)
	var panel: Control = dock._guides_panel
	panel.set_target(skeleton, player, character)
	_check(panel.guide != null, "guide binds to placed character")
	if panel.guide == null:
		print("LIVE_GUIDE_STATUS ", panel.status.text)
		_finish(dock, client, generation, character)
		return
	if not OS.get_cmdline_user_args().has("--offline"):
		panel.edit_character.button_pressed = true
		var space: Dictionary = dock._draft.root_guides["space"]
		var neutral := Space.unvector(space["model_hips_rest"])
		for waypoint in [[0, Vector3.ZERO, 0.0], [29, Vector3(0, 0, 0.7), 0.0], [59, Vector3(0.5, 0, 1.0), 0.7]]:
			player.seek(waypoint[0] / 30.0 + 0.001, false)
			panel._sync_character()
			panel.guide.global_position = Space.model_to_world(space, neutral + waypoint[1])
			panel.guide.global_basis = Basis(Vector3.UP, Space.model_heading_to_world(space, waypoint[2]))
			panel._sync_character()
			panel.heading_check.button_pressed = true
			if waypoint[0] == 29:
				panel.record_current()
			else:
				panel.record_pose_current()
			print("LIVE_VISUAL_POSE_RECORD frame=", waypoint[0], " status=", panel.status.text)
		_check(dock._draft.root_guides["points"].size() == 3 and dock._draft.pose_keyframes.size() == 2, "two combined poses and one route-only waypoint recorded")
		_check(panel.path_node.find_child("KimodoAuthoredPose_0", true, false) != null and panel.path_node.find_child("KimodoAuthoredPose_59", true, false) != null, "authored endpoint ghosts visible")
		dock._prompt_edit.text = "A person walks forward, then turns right while walking."
		dock._seed_edit.value = 1234
		dock._diffusion_steps_edit.value = 100
		dock._take_count_edit.value = 1
		var started := Time.get_ticks_msec()
		dock._on_generate_pressed()
		await _wait(generation, Generation.GenerationState.GENERATING, 310)
		_check(generation.state == Generation.GenerationState.READY, "combined root/pose CUDA generation")
		print("LIVE_ROOT_GUIDES elapsed_seconds=", (Time.get_ticks_msec() - started) / 1000.0, " state=", generation.state, " message=", generation.message, " draft=", dock._draft_status.text)
		if generation.state != Generation.GenerationState.READY:
			_finish(dock, client, generation, character)
			return
		_write("res://request.json", generation.last_request_json)
		var response := FileAccess.open("res://response.json", FileAccess.WRITE)
		response.store_buffer(generation.last_response_bytes)
		response.close()
		_write("res://capabilities.json", client.last_response_json)
		dock._preview_panel.submit_save_path(Preview.SaveKind.CHARACTER_ANIMATION, "res://exports/character.res")
		dock._on_accept_requested("res://exports/production.res", "guided", false)
		dock._fallback_undo_redo.undo()
		dock._fallback_undo_redo.redo()
		_check((load("res://exports/production.res") as AnimationLibrary).has_animation("guided"), "guided Save/Accept Undo/Redo")
		dock._flush_session()
	var record: Dictionary = dock._draft.active_generation_record()
	_check(record.get("authored_root_guides", {}).get("points", []).size() == 3, "exact guide provenance retained")
	if OS.get_cmdline_user_args().has("--offline"):
		dock._on_history_take_activated(0, record["takes"][0]["take_id"])
	_check(dock._character_preview.has_motion(), "guided take previews live/offline")
	panel.show_selected_take()
	_check(panel.scene_preview != null, "temporary scene preview at archived placement")
	if panel.scene_preview != null:
		var packed := PackedScene.new()
		_check(packed.pack(character) == OK, "scene with guide/preview packs")
		var saved_scene := packed.instantiate()
		_check(saved_scene.find_child("KimodoScenePreview", true, false) == null and saved_scene.find_child("KimodoRootGuide", true, false) == null, "temporary guide and scene preview excluded from saved scene")
		saved_scene.free()
		var ghost := _find(panel.scene_preview, "Skeleton3D") as Skeleton3D
		_check(ghost.global_transform.is_equal_approx(skeleton.global_transform), "preview skeleton matches authored scene transform")
		var model_scene: Node3D = dock._preview.motion_scene()
		var model_skeleton := _find(model_scene, "Skeleton3D") as Skeleton3D
		var model_player := _find(model_scene, "AnimationPlayer") as AnimationPlayer
		model_player.assigned_animation = model_player.get_animation_list()[0]
		for point in record["authored_root_guides"]["points"]:
			var time: float = point["frame"] / 30.0
			model_player.seek(time, true, true)
			panel.scene_preview_player.seek(time, true, true)
			var desired := Space.world_to_model(record["authored_root_guides"]["space"], Space.unvector(point["world_position"]))
			var actual := model_skeleton.get_bone_global_pose(model_skeleton.find_bone("Hips")).origin
			var error := Vector2(desired.x, desired.z).distance_to(Vector2(actual.x, actual.z))
			var desired_world := Space.unvector(point["world_position"])
			var actual_world := ghost.global_transform * ghost.get_bone_global_pose(ghost.find_bone(dock._rig_profile.target_for("Hips"))).origin
			var world_error := Vector2(desired_world.x, desired_world.z).distance_to(Vector2(actual_world.x, actual_world.z))
			print("ROOT_WAYPOINT frame=", point["frame"], " model_error_m=", error, " character_world_error_m=", world_error)
			_check(is_finite(error) and error < 0.25, "root waypoint smoke tolerance (measured, not general guarantee)")
		panel.hide_scene_preview()
		if OS.get_cmdline_user_args().has("--capture"):
			panel.show_selected_take()
			player.seek(29.0 / 30.0, false)
			var camera := Camera3D.new()
			root.add_child(camera)
			camera.position = Vector3(6, 3.5, 2.5)
			camera.look_at(character.position + Vector3(0.3, 0.9, 0.4))
			camera.current = true
			var light := DirectionalLight3D.new()
			root.add_child(light)
			light.rotation_degrees = Vector3(-45, -30, 0)
			var environment := WorldEnvironment.new()
			environment.environment = Environment.new()
			environment.environment.background_mode = Environment.BG_COLOR
			environment.environment.background_color = Color(0.15, 0.17, 0.2)
			environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.environment.ambient_light_color = Color.WHITE
			environment.environment.ambient_light_energy = 0.8
			root.add_child(environment)
			dock.hide()
			root.size = Vector2i(1100, 850)
			for frame in 10:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://scene_preview.png")
			camera.free()
			light.free()
			environment.free()
	_finish(dock, client, generation, character)


func _finish(dock: Node, client: Node, generation: Node, character: Node) -> void:
	dock.free()
	if is_instance_valid(character):
		character.free()
	client.free()
	generation.free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("PASS: isolated visual guide-pose live/offline workflow")
	quit(0 if failures.is_empty() else 1)


func _wait(client: Node, busy: int, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while client.state == busy and Time.get_ticks_msec() < deadline:
		await process_frame


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var result := _find(child, type)
		if result != null:
			return result
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		print("LIVE_GUIDE_CHECK_FAILED ", message)
		failures.append(message)
