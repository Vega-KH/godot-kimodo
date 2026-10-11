extends SceneTree

const PosePanel := preload("res://addons/kimodo_motion/ui/pose_library_panel.gd")
const Fixture := preload("res://addons/kimodo_motion/retargeting/humanoid_fixture.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Pass a unique capture directory.")
		quit(1)
		return
	var directory := arguments[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var character := Fixture.create_scene()
	var player := AnimationPlayer.new()
	character.add_child(player)
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	animation.length = 2
	library.add_animation("pose_authoring", animation)
	player.add_animation_library("", library)
	root.add_child(character)
	var panel := PosePanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)
	await process_frame
	panel.set_target(character.get_child(0), player)
	player.assigned_animation = "pose_authoring"
	player.seek(0.5, false)
	panel.pose_list.add_item("Open hand")
	panel.pose_list.add_item("Relaxed fingers")
	panel.pose_list.add_item("A very long saved pose title to check horizontal clipping")
	var tabs := panel.find_children("*", "TabContainer", true, false)[0] as TabContainer
	for width in [360, 680]:
		root.size = Vector2i(width, 950)
		for tab in 3:
			tabs.current_tab = tab
			for frame in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png(directory.path_join("pose_panel_%d_%d.png" % [width, tab]))
			if error != OK:
				push_error("Could not save pose panel screenshot.")
				quit(1)
				return
	panel.free()
	character.free()
	print("PASS: rendered separate pose panel at 360 and 680 pixels")
	quit()
