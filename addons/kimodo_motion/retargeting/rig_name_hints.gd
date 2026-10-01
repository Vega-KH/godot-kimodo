class_name KimodoRigNameHints
extends RefCounted

# Bounded exporter conventions, not edit-distance guessing. Original/numbered
# keys always remain available; exporter IDs are an additional weaker key.
static func inspect(skeleton: Skeleton3D) -> Dictionary:
	var suffix := RegEx.new()
	suffix.compile("_([0-9]+)$")
	var id_names := 0
	var ids := {}
	for index in skeleton.get_bone_count():
		var matched := suffix.search(String(skeleton.get_bone_name(index)))
		if matched != null and int(matched.get_string(1)) >= 10:
			id_names += 1
			ids[matched.get_string(1)] = true
	var exporter_ids := id_names >= 3 and ids.size() >= 3
	var result := {}
	for index in skeleton.get_bone_count():
		var original := String(skeleton.get_bone_name(index))
		var name := original
		var keys: Array[String] = [normalize(name)]
		var matched := suffix.search(name)
		if exporter_ids and matched != null:
			name = name.substr(0, matched.get_start())
			var key := normalize(name)
			if key not in keys:
				keys.append(key)
		var wrapped := name.to_lower()
		if wrapped.begins_with("gltf_created_") and wrapped.ends_with("_rootjoint"):
			keys.append("rootjoint")
		result[original] = {"keys": keys, "exporter_ids": exporter_ids and matched != null, "decoy": _decoy(name)}
	return result

static func normalize(name: String) -> String:
	var value := name.get_slice(":", name.get_slice_count(":") - 1).to_lower().replace("mixamorig", "")
	for prefix in ["armature_", "skeleton_", "rig_", "def-"]:
		value = value.trim_prefix(prefix)
	value = value.trim_suffix(".x")
	for side in [["l", "left"], ["r", "right"]]:
		for separator in [".", "_", "-"]:
			if value.ends_with(separator + side[0]):
				value = side[1] + value.trim_suffix(separator + side[0])
			elif value.begins_with(side[0] + separator):
				value = side[1] + value.trim_prefix(side[0] + separator)
	var result := ""
	for character in value:
		if character >= "a" and character <= "z" or character >= "0" and character <= "9":
			result += character
	return result

static func _decoy(name: String) -> bool:
	var camel := RegEx.new()
	camel.compile("([a-z])([A-Z])")
	var words := camel.sub(name, "$1_$2", true).to_lower().replace(".", "_").replace("-", "_").split("_")
	for word in words:
		if word in ["ik", "fk", "control", "ctrl", "pole", "twist", "end", "tip", "handle"]:
			return true
	return false
