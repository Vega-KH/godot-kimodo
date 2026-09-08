extends SceneTree

const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")
const OUTPUT := "res://tests/retargeting/fixtures/godot_humanoid_a_pose.tscn"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var fixture := Fixture.create_scene()
	var packed := PackedScene.new()
	if (
		packed.pack(fixture) != OK
		or ResourceSaver.save(packed, OUTPUT, ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES) != OK
	):
		printerr("FAIL: could not save humanoid fixture")
		fixture.free()
		quit(1)
		return
	fixture.free()
	if not _strip_scene_unique_ids(OUTPUT):
		printerr("FAIL: could not normalize humanoid fixture")
		quit(1)
		return
	print("PASS: wrote deterministic humanoid fixture to ", OUTPUT)
	quit(0)


func _strip_scene_unique_ids(path: String) -> bool:
	var expression := RegEx.create_from_string(" unique_id=[0-9]+")
	var text := FileAccess.get_file_as_string(path)
	var normalized := expression.sub(text, "", true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(normalized)
	return true
