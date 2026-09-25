class_name KimodoTransientTakeSet
extends RefCounted

var motions: Array[RefCounted] = []
var active_index := -1


func replace(next_motions: Array[RefCounted], preview: Control) -> void:
	clear(preview)
	motions = next_motions


func activate(index: int, preview: Control) -> bool:
	if index < 0 or index >= motions.size():
		return false
	var released: Node = preview.release_motion_scene()
	if active_index >= 0 and active_index < motions.size() and released != null:
		motions[active_index].scene = released
	if not preview.set_motion(motions[index]):
		if released != null and active_index >= 0 and active_index < motions.size():
			preview.set_motion(motions[active_index])
		return false
	active_index = index
	return true


func clear(preview: Control) -> void:
	if active_index >= 0 and active_index < motions.size() and preview != null:
		var released: Node = preview.release_motion_scene()
		if released != null:
			motions[active_index].scene = released
	for motion in motions:
		if motion != null and is_instance_valid(motion.scene):
			motion.scene.free()
	motions.clear()
	active_index = -1


func is_empty() -> bool:
	return motions.is_empty()


func size() -> int:
	return motions.size()


func at(index: int) -> RefCounted:
	return motions[index] if index >= 0 and index < motions.size() else null
