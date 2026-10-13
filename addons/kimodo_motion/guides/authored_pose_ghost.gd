@tool
class_name KimodoAuthoredPoseGhost
extends RefCounted

const Pose := preload("res://addons/kimodo_motion/guides/guide_pose_service.gd")


static func create(source: PackedScene, entry: Dictionary, parent: Node3D, placement: Transform3D) -> Dictionary:
	var character := source.instantiate() as Node3D
	if character == null:
		return {"ok": false, "message": "The pose ghost needs a 3D character scene."}
	var skeletons: Array[Skeleton3D] = []
	var nodes: Array[Node] = [character]
	var players: Array[Node] = []
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.67, 0.2, 0.38)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		node.set_script(null)
		node.owner = null
		if node is Skeleton3D:
			skeletons.append(node)
		if node is AnimationPlayer or node is AnimationTree:
			players.append(node)
		if node is MeshInstance3D:
			node.material_override = material
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for child in node.get_children():
			nodes.append(child)
	if skeletons.size() != 1:
		character.free()
		return {"ok": false, "message": "The pose ghost needs exactly one character skeleton."}
	for player in players:
		if is_instance_valid(player):
			player.free()
	var checked := Pose.restore_channels(skeletons[0], entry["authored_channels"])
	if not checked["ok"]:
		character.free()
		return checked
	character.name = "KimodoAuthoredPose_%d" % entry["frame"]
	character.set_meta("kimodo_authored_frame", entry["frame"])
	character.set_meta("kimodo_session_id", entry["session_id"])
	character.set_meta("kimodo_pose_id", entry["guide_pose_id"])
	parent.add_child(character)
	var alignment := placement * skeletons[0].global_transform.affine_inverse()
	character.global_transform = alignment * character.global_transform
	return {"ok": true, "character": character, "skeleton": skeletons[0]}
