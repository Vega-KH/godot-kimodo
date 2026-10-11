class_name KimodoGenerationOptions
extends RefCounted

var prompt := "A person walks forward."
var duration_frames := 30
var seed := 1234
var diffusion_steps := 100
var num_samples := 1
var pose_constraints: Array[Dictionary] = []


func validate(fps: float) -> Dictionary:
	var clean_prompt := prompt.strip_edges()
	if clean_prompt.is_empty():
		return _error("Prompt cannot be empty.")
	if clean_prompt.length() > 1000:
		return _error("Prompt must be 1,000 characters or fewer.")
	if duration_frames < 1 or duration_frames > int(fps * 30.0):
		return _error("Duration must be between 1 frame and 30 seconds.")
	if diffusion_steps < 1 or diffusion_steps > 200:
		return _error("Diffusion steps must be between 1 and 200.")
	if num_samples < 1 or num_samples > 2:
		return _error("Take count must be 1 or 2 for the currently tested workflow.")
	var seen := {}
	for constraint in pose_constraints:
		var frame: Variant = constraint.get("frame")
		if not frame is int or frame < 0 or frame >= duration_frames or seen.has(frame):
			return _error("Pose constraint frames must be unique and within the generation duration.")
		seen[frame] = true
		if constraint.get("type") != "pose_keyframe" or constraint.get("fill_mode") != "rest":
			return _error("Only explicit full-body pose constraints are supported.")
		var rotations: Variant = constraint.get("joint_rotations")
		if not rotations is Dictionary or rotations.size() != 30:
			return _error("A full-body constraint must contain all SOMA-30 rotations.")
		for joint in preload("res://addons/kimodo_motion/poses/character_pose_converter.gd").JOINTS:
			var value: Variant = rotations.get(joint[0])
			if not value is Array or value.size() != 4:
				return _error("A SOMA-30 rotation is missing or invalid.")
			for component in value:
				if not (component is float or component is int) or not is_finite(float(component)):
					return _error("Pose constraint rotations must be finite.")
			var q := Quaternion(value[0], value[1], value[2], value[3])
			if absf(q.length_squared() - 1.0) > 0.0001:
				return _error("Pose constraint rotations must be normalized.")
		var position: Variant = constraint.get("root_position")
		if not position is Array or position.size() != 3:
			return _error("Pose constraint root position is required.")
		for component in position:
			if not (component is float or component is int) or not is_finite(float(component)):
				return _error("Pose constraint root position must be finite.")
	return {"ok": true}


func to_mmcp_request(capabilities: RefCounted) -> Dictionary:
	return {
		"protocol_version": capabilities.protocol_version,
		"model": capabilities.model_id,
		"skeleton": capabilities.skeleton_payload.duplicate(true),
		"segments": [{
			"type": "text",
			"prompt": prompt.strip_edges(),
			"duration_frames": duration_frames,
		}],
		"constraints": pose_constraints.duplicate(true),
		"timing": {"fps": capabilities.fps},
		"options": {
			"diffusion_steps": diffusion_steps,
			"num_samples": num_samples,
			"seed": seed,
			"post_processing": false,
			"transition_frames": 5,
		},
	}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
