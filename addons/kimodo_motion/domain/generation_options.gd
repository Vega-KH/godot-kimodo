class_name KimodoGenerationOptions
extends RefCounted

var prompt := "A person walks forward."
var duration_frames := 30
var seed := 1234
var diffusion_steps := 100


func validate(fps: float) -> Dictionary:
	var clean_prompt := prompt.strip_edges()
	if clean_prompt.is_empty():
		return _error("Prompt cannot be empty.")
	if clean_prompt.length() > 1000:
		return _error("Prompt must be 1,000 characters or fewer.")
	if duration_frames < 1 or duration_frames > int(fps * 30.0):
		return _error("Duration must be between 1 frame and 30 seconds.")
	if diffusion_steps < 1 or diffusion_steps > 100:
		return _error("Diffusion steps must be between 1 and 100.")
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
		"constraints": [],
		"timing": {"fps": capabilities.fps},
		"options": {
			"diffusion_steps": diffusion_steps,
			"num_samples": 1,
			"seed": seed,
			"post_processing": false,
			"transition_frames": 5,
		},
	}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
