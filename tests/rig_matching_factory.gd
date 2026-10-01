extends RefCounted

const Variants := preload("res://tests/rig_variant_factory.gd")

static func create(convention: String) -> Dictionary:
	var built := Variants.create({"names":"canonical"})
	var skeleton: Skeleton3D = built["skeleton"]
	var mapping: Dictionary = built["mapping"]
	var skin := (built["scene"].find_child("SkinMesh", true, false) as MeshInstance3D).skin
	for index in skeleton.get_bone_count():
		var old := String(skeleton.get_bone_name(index))
		var renamed := old
		if convention == "export_ids":
			renamed = ("Hip" if old == "Hips" else old) + "_%d" % (100 + index)
		elif convention == "neutral":
			renamed = old + ".x" if not old.begins_with("Left") and not old.begins_with("Right") else old
		elif convention == "held_out":
			renamed = "Armature_" + ("pelvis" if old == "Hips" else old) + ".x_%d" % (700 + index)
		skeleton.set_bone_name(index, renamed)
		skin.set_bind_name(index, renamed)
		if mapping.has(old):
			mapping[old] = renamed
	return built
