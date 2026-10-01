extends SceneTree

const Factory := preload("res://tests/rig_matching_factory.gd")
const Matcher := preload("res://addons/kimodo_motion/retargeting/rig_candidate_matcher.gd")
const Profile := preload("res://addons/kimodo_motion/retargeting/kimodo_rig_profile.gd")
const Names := preload("res://addons/kimodo_motion/retargeting/rig_name_hints.gd")
const SetupPanel := preload("res://addons/kimodo_motion/ui/rig_setup_panel.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	for convention in ["canonical", "export_ids", "neutral", "held_out"]:
		var built := Factory.create(convention)
		var result := Matcher.suggest(built["skeleton"])
		var correct := 0
		var wrong := 0
		for role in built["mapping"]:
			var row: Dictionary = result["rows"][role]
			if row["target"] == built["mapping"][role]:
				correct += 1
			elif not String(row["target"]).is_empty():
				wrong += 1
		print("MATCHING %s: %d/%d correct, %d incorrect" % [convention, correct, built["mapping"].size(), wrong])
		if not baseline:
			_check(correct == built["mapping"].size() and wrong == 0, "declared naming family: " + convention)
			_check(result == Matcher.suggest(built["skeleton"]), "deterministic suggestions")
		built["scene"].free()
	if not baseline:
		_adversarial_cases()
	for path in ["res://tests/private_models/Jenny04.glb", "res://tests/private_models/goal19_manual/remy-autorig-godot-universal.glb", "res://tests/private_models/goal19_manual/godette-restpose2.glb"]:
		if not ResourceLoader.exists(path):
			print("SKIP: matching baseline ", path)
			continue
		var instance := (load(path) as PackedScene).instantiate()
		var bones: Skeleton3D = instance.find_children("*", "Skeleton3D", true, false)[0]
		var result := Matcher.suggest(bones)
		var assigned := Matcher.mapping_from_rows(result["rows"])
		print("PRIVATE MATCHING %s: %d suggested; Root=%s, Hips=%s; diagnosis=%s" % [path.get_file(), assigned.size(), assigned.get("Root", ""), assigned.get("Hips", ""), str(Matcher.diagnose(bones, assigned, result["root_motion_policy"]))])
		if not baseline and path.contains("remy-autorig"):
			_check(assigned.get("Hips") == "root.x" and assigned.get("Root") == "c_traj", "universal pelvis and motion root are distinguished")
			_check(Matcher.diagnose(bones, assigned, result["root_motion_policy"]).is_empty(), "universal Remy suggestions certify without filename-specific matching")
		instance.free()
	if not baseline:
		await _capture_if_requested()
	if failures.is_empty():
		print("PASS: bounded naming/matching families")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _adversarial_cases() -> void:
	var built := Factory.create("export_ids")
	var skeleton: Skeleton3D = built["skeleton"]
	for pair in [["Spine", "spine_01"], ["Chest", "spine_02"], ["UpperChest", "spine_03"]]:
		skeleton.set_bone_name(skeleton.find_bone(built["mapping"][pair[0]]), pair[1])
	var result := Matcher.suggest(skeleton)
	for pair in [["Spine", "spine_01"], ["Chest", "spine_02"], ["UpperChest", "spine_03"]]:
		_check(result["rows"][pair[0]]["target"] == pair[1], "meaningful chain numbers survive mixed exporter IDs")
	built["scene"].free()
	built = Factory.create("canonical")
	skeleton = built["skeleton"]
	# Exact names remain authoritative over a normalized duplicate.
	_add_bone(skeleton, "Armature_LeftHand", skeleton.find_bone("LeftLowerArm"))
	_check(Matcher.suggest(skeleton)["rows"]["LeftHand"]["target"] == "LeftHand", "exact-name precedence")
	skeleton.set_bone_name(skeleton.find_bone("LeftHand"), "DEF-LeftHand")
	result = Matcher.suggest(skeleton)
	_check(result["rows"]["LeftHand"]["target"] == "" and result["rows"]["LeftHand"]["confidence"] == "ambiguous", "equal plausible aliases remain unresolved")
	_check(result["rows"]["LeftHand"]["candidates"].size() == 2, "ranked alternatives are retained for review")
	var panel := SetupPanel.new()
	panel.configure(skeleton, result)
	var selector := panel.find_child("RigRole_LeftHand", true, false) as OptionButton
	for index in selector.item_count:
		if selector.get_item_text(index) == "DEF-LeftHand":
			selector.select(index)
			selector.item_selected.emit(index)
	panel.suggest_button.pressed.emit()
	_check(panel.current_mapping()["LeftHand"] == "DEF-LeftHand", "Suggest Unmapped preserves manual resolution")
	selector.select(0)
	selector.item_selected.emit(0)
	panel.suggest_button.pressed.emit()
	_check(not panel.current_mapping().has("LeftHand"), "Suggest Unmapped preserves explicit manual omission")
	var reviewed_mapping := Matcher.mapping_from_rows(result["rows"])
	reviewed_mapping["LeftHand"] = "DEF-LeftHand"
	reviewed_mapping.erase("Jaw")
	var created := Profile.create(reviewed_mapping, NodePath("Rig"), skeleton)
	_check(created["ok"], "manual ambiguity resolution certifies")
	if created["ok"]:
		var profile: Resource = created["profile"]
		profile.hand_frames["LeftHand"]["target_forward"] = "LeftIndexProximal"
		panel.configure(skeleton, Matcher.reviewed(profile, result), result)
		var frame_before := panel.current_hand_frames()
		var chest := panel.find_child("RigRole_Chest", true, false) as OptionButton
		chest.select(0)
		chest.item_selected.emit(0)
		panel.suggest_button.pressed.emit()
		_check(not panel.current_mapping().has("Jaw"), "certified intentional omission survives suggestions")
		_check(panel.current_hand_frames() == frame_before, "certified palm choices survive an unrelated edit")
	panel.free()
	# Wrong-chain alternatives must not be presented as confident matches.
	skeleton.set_bone_name(skeleton.find_bone("LeftUpperArm"), "unknown_arm")
	_add_bone(skeleton, "Armature_LeftUpperArm", skeleton.find_bone("RightShoulder"))
	result = Matcher.suggest(skeleton)
	_check(result["rows"]["LeftUpperArm"]["target"] == "", "wrong-side parent chain rejects misleading name")
	_check(result["rows"]["LeftUpperArm"]["evidence"].contains("ancestor"), "wrong-chain evidence is actionable")
	# Control markers are not stripped to manufacture a confident deform match.
	for name in ["handIK.L", "Arm_Upper_Twist.L", "Spine_Control_201", "FingerControl_1.L"]:
		_check(Names._decoy(name), "control/IK/twist marker detected: " + name)
	built["scene"].free()
	# Renumbering the same skeleton must not affect ranked suggestions.
	built = Factory.create("held_out")
	skeleton = built["skeleton"]
	var reversed := Skeleton3D.new()
	var size := skeleton.get_bone_count()
	for index in size:
		var old := size - 1 - index
		reversed.add_bone(skeleton.get_bone_name(old))
		reversed.set_bone_rest(index, skeleton.get_bone_rest(old))
	for index in size:
		var parent := skeleton.get_bone_parent(size - 1 - index)
		if parent >= 0:
			reversed.set_bone_parent(index, size - 1 - parent)
	_check(Matcher.suggest(skeleton) == Matcher.suggest(reversed), "matching and ranked evidence are bone-index invariant")
	reversed.free()
	built["scene"].free()

func _add_bone(skeleton: Skeleton3D, name: String, parent: int) -> void:
	var index := skeleton.get_bone_count()
	skeleton.add_bone(name)
	skeleton.set_bone_parent(index, parent)
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, Vector3(0.04, 0.06, 0)))

func _capture_if_requested() -> void:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--capture-dir")
	if index < 0 or index + 1 >= args.size():
		return
	var path := args[index + 1]
	DirAccess.make_dir_recursive_absolute(path)
	root.size = Vector2i(480, 1100)
	var built := Factory.create("export_ids")
	var panel := SetupPanel.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.configure(built["skeleton"], Matcher.suggest(built["skeleton"]))
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join("rig_matching_export_ids.png"))
	var ambiguous := Factory.create("canonical")
	var skeleton: Skeleton3D = ambiguous["skeleton"]
	var old_root := skeleton.find_bone("Root")
	skeleton.set_bone_name(old_root, "Armature_Root")
	var wrapper := skeleton.get_bone_count()
	skeleton.add_bone("DEF-Root")
	skeleton.set_bone_rest(wrapper, Transform3D.IDENTITY)
	skeleton.set_bone_parent(old_root, wrapper)
	panel.configure(skeleton, Matcher.suggest(skeleton))
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join("rig_matching_ambiguous.png"))
	panel.free()
	built["scene"].free()
	ambiguous["scene"].free()
