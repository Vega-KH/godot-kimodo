extends SceneTree

const Compatibility := preload("res://addons/kimodo_motion/retargeting/rig_compatibility.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for file in ["Jenny04.glb", "mannequiny-0.3.0.glb", "goal19_manual/godette-restpose2.glb", "goal19_manual/godette_rigged.glb"]:
		var path: String = "res://tests/private_models/" + file
		if not FileAccess.file_exists(path):
			print("SKIP: private variant import ", file)
			continue
		var hash_before := FileAccess.get_sha256(path)
		var scene := load(path) as PackedScene
		if scene == null:
			failures.append("Cannot import " + file)
			continue
		var instance := scene.instantiate()
		root.add_child(instance)
		var result := Compatibility.inspect(instance)
		if file == "Jenny04.glb":
			_check(result["ok"], "Jenny04 has matching imported bind/rest poses: " + str(result.get("message", "")))
			if result["ok"]:
				var skeleton: Skeleton3D = result["skeleton"]
				_check(skeleton.get_bone_count() == 64, "Jenny04 imports all 64 bones")
				for extra in ["Hair", "Eye_L", "Eye_R"]:
					_check(skeleton.find_bone(extra) >= 0, "Jenny04 imports " + extra)
				print("JENNY04: %d skinned meshes, maximum bind/rest errors position=%.8f axes=%.8f" % [result["meshes"], result["position_error"], result["basis_error"]])
		elif file.ends_with("godette-restpose2.glb"):
			_check(result["ok"], "Godette re-export accepts common uniform bind scale: " + str(result.get("message", "")))
			if result["ok"]:
				_check(absf(result["bind_space_scale"] - 1.078262) < 0.00001, "Godette detects ancestor-scale compensation")
				print("GODETTE: common bind scale %.8f, normalized axis error %.8f" % [result["bind_space_scale"], result["basis_error"]])
		else:
			_check(not result["ok"] and result["code"] == "bind_rest_mismatch", file + " is rejected for unsupported bind/rest mismatch, not its naming")
			var message: String = result.get("message", "")
			_check(message.contains("Mesh '") and message.contains("bone '") and message.contains("requires matching bind and rest poses") and message.contains("re-export") and message.contains("bone map will not fix"), "rejection explains the affected mesh/bone, limitation, and repair")
			print("EXPECTED INCOMPATIBILITY: ", message)
		instance.free()
		_check(FileAccess.get_sha256(path) == hash_before, "import audit preserves source " + file)
	if failures.is_empty():
		print("PASS: private import compatibility and actionable bind/rest rejection")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: ", failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
