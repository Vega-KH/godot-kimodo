extends SceneTree

# Run only in a new isolated project with the add-on and licensed Jenny fixture
# copied to res://models/character.glb. Retain outputs for fresh-process review.
const Client := preload("res://addons/kimodo_motion/transport/mmcp_capabilities_client.gd")
const Generation := preload("res://addons/kimodo_motion/transport/mmcp_generation_client.gd")
const Dock := preload("res://addons/kimodo_motion/ui/ai_motion_dock.gd")
const Store := preload("res://addons/kimodo_motion/domain/motion_session_store.gd")
const Service := preload("res://addons/kimodo_motion/poses/pose_service.gd")
const Converter := preload("res://addons/kimodo_motion/poses/character_pose_converter.gd")
const Preview := preload("res://addons/kimodo_motion/ui/preview_save_panel.gd")
const CHARACTER := "res://models/character.glb"
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
	if OS.get_cmdline_user_args().has("--offline"):
		var session_path := ""
		for entry in Store.list_sessions():
			if entry["title"] == "Goal 22 isolated pose smoke":
				session_path = entry["path"]
		_check(not session_path.is_empty(), "isolated session retained")
		dock._open_session_path(session_path)
		_check(dock._draft != null and dock._draft.pose_keyframes.size() == 2, "fresh-process authored constraints reload")
		if dock._draft != null and not dock._draft.generation_records.is_empty():
			var record: Dictionary = dock._draft.generation_records[0]
			_check(record["authored_pose_keyframes"].size() == 2, "immutable authored provenance reload")
			dock._on_history_take_activated(0, record["takes"][0]["take_id"])
			_check(dock._character_preview.has_motion(), "offline history reconstructs character motion")
		var opened := Service.load_pose("res://poses/edited_hand.tres")
		_check(opened["ok"], "pose reload without source animation instance")
		var scene := (load("res://authoring.tscn") as PackedScene).instantiate()
		var skeleton := _find(scene, "Skeleton3D") as Skeleton3D
		_check(Service.apply(opened["pose"], skeleton)["ok"], "fresh-process pose apply")
		var player := scene.get_node("PosePlayer") as AnimationPlayer
		_check(player.get_animation("work").track_get_key_count(0) == 3, "native authored keys reload")
		scene.free()
	else:
		dock._session_title_edit.text = "Goal 22 isolated pose smoke"
		dock._on_new_session_pressed()
		var character_scene := load(CHARACTER) as PackedScene
		dock._on_character_target_changed(character_scene)
		dock._duration_edit.value = 30
		dock._url_edit.text = Client.DEFAULT_URL
		(dock.find_child("ConnectionAction", true, false) as Button).pressed.emit()
		await _wait(client, Client.ConnectionState.CONNECTING, 30)
		_check(client.state == Client.ConnectionState.READY, "live capabilities connect")
		if client.state != Client.ConnectionState.READY:
			_finish(dock, client, generation)
			return
		var character := character_scene.instantiate()
		var skeleton := _find(character, "Skeleton3D") as Skeleton3D
		var mask := {}
		for index in skeleton.get_bone_count():
			mask[String(skeleton.get_bone_name(index))] = Service.KINDS
		var hand_name := String(dock._rig_profile.target_for("LeftHand"))
		var hand := skeleton.find_bone(hand_name)
		var animation := Animation.new()
		animation.length = 1
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		var player := AnimationPlayer.new()
		player.name = "PosePlayer"
		character.add_child(player)
		player.owner = character
		var binding := player.get_node(player.root_node).get_path_to(skeleton)
		animation.track_set_path(track, NodePath("%s:%s" % [binding, hand_name]))
		animation.rotation_track_insert_key(track, 0, skeleton.get_bone_pose_rotation(hand))
		animation.rotation_track_insert_key(track, 1, skeleton.get_bone_pose_rotation(hand) * Quaternion(Vector3.UP, 0.4))
		var sparse := Service.capture_animation(skeleton, animation, binding, 0.5, "Sampled hand", {hand_name: [Animation.TYPE_ROTATION_3D]})
		_check(Service.apply(sparse["pose"], skeleton)["ok"], "sample non-Kimodo clip")
		skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_pose_rotation(hand) * Quaternion(Vector3.RIGHT, 0.25))
		var forearm_name := String(dock._rig_profile.target_for("LeftLowerArm"))
		var forearm := skeleton.find_bone(forearm_name)
		skeleton.set_bone_pose_rotation(forearm, skeleton.get_bone_pose_rotation(forearm) * Quaternion(Vector3.FORWARD, 0.45))
		var edited := Service.capture(skeleton, "Edited arm and hand", {hand_name: [Animation.TYPE_ROTATION_3D], forearm_name: [Animation.TYPE_ROTATION_3D]})
		_check(Service.save_new(edited["pose"], "res://poses/edited_hand.tres")["ok"], "manually edited hand pose saved")
		for frame in [0, 15]:
			var keyed := Service.keyed_copy(edited["pose"], skeleton, animation, binding, frame / 30.0)
			_check(keyed["ok"], "pose keys prepared")
			animation = keyed["animation"]
			var authored := Service.capture(skeleton, "Authored full body", mask)
			var prepared := dock.prepare_pose_keyframe(skeleton, authored["pose"], frame)
			_check(prepared["ok"], "edited full body converts")
			if prepared["ok"]:
				_check(dock.queue_pose_keyframe(prepared["entry"])["ok"], "edited frame queued")
		var library := AnimationLibrary.new()
		library.add_animation("work", animation)
		player.add_animation_library("", library)
		var packed := PackedScene.new()
		_check(packed.pack(character) == OK and ResourceSaver.save(packed, "res://authoring.tscn") == OK, "native authoring scene saved")
		character.free()
		dock._prompt_edit.text = "A person stands and raises their left hand."
		dock._seed_edit.value = 1234
		dock._diffusion_steps_edit.value = 100
		dock._take_count_edit.value = 1
		var started := Time.get_ticks_msec()
		dock._on_generate_pressed()
		await _wait(generation, Generation.GenerationState.GENERATING, 310)
		_check(generation.state == Generation.GenerationState.READY, "pose-conditioned CUDA generation")
		print("LIVE_POSE elapsed_seconds=", (Time.get_ticks_msec() - started) / 1000.0, " state=", generation.state, " message=", generation.message)
		if generation.state == Generation.GenerationState.READY:
			_check(dock._take_set.size() == 1 and dock._character_preview.has_motion(), "generated take archived and character-previewed")
			var request: Dictionary = JSON.parse_string(generation.last_request_json)
			_check(request["constraints"].size() == 2, "two edited SOMA-30 frames submitted")
			var record: Dictionary = dock._draft.generation_records[0]
			_check(record["authored_pose_keyframes"] == dock._draft.pose_keyframes, "exact authored snapshot archived")
			_write("res://request.json", generation.last_request_json)
			_write("res://capabilities.json", client.last_response_json)
			var response := FileAccess.open("res://response.json", FileAccess.WRITE)
			response.store_buffer(generation.last_response_bytes)
			response.close()
			dock._preview_panel.submit_save_path(Preview.SaveKind.CHARACTER_ANIMATION, "res://exports/character.res")
			dock._preview_panel.submit_save_path(Preview.SaveKind.CHARACTER_PREVIEW, "res://exports/preview.tscn")
			_check(FileAccess.file_exists("res://exports/character.res"), "conditioned character Save")
			dock._on_accept_requested("res://exports/production.res", "conditioned", false)
			dock._fallback_undo_redo.undo()
			dock._fallback_undo_redo.redo()
			_check((load("res://exports/production.res") as AnimationLibrary).has_animation("conditioned"), "conditioned Accept Undo/Redo")
		dock._flush_session()
	_finish(dock, client, generation)


func _finish(dock: Node, client: Node, generation: Node) -> void:
	dock.free()
	client.free()
	generation.free()
	if failures.is_empty():
		print("PASS: isolated editable-pose live/offline workflow")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _wait(client: Node, busy: int, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while client.state == busy and Time.get_ticks_msec() < deadline:
		await process_frame


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _find(node: Node, kind: String) -> Node:
	if node.is_class(kind):
		return node
	for child in node.get_children():
		var found := _find(child, kind)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
