extends "res://tests/visual_review_capture.gd"
## Dense motion captures for the character animation pass. It reuses the
## visual-review instrument unchanged (same main scene, stretch path, seeds and
## input staging) and only adds its own stage, tests/anim_pass3_stage.gd, so a
## sequence can be sampled every frame, for any crew identity or infantry role.
## Start it like tools/visual_review.py starts its capture script:
##   godot --audio-driver Dummy --fixed-fps 60 --path . --script tests/anim_pass3_capture.gd \
##     -- --no-profile-save --no-upnp --out=<abs dir> --shots=<json> --results=<name>.jsonl
const PassStage := preload("res://tests/anim_pass3_stage.gd")

func _run_shot() -> void:
	var stage: Variant = PassStage
	if str(spec.stage) == "anim" and stage.has_method(str(spec.method)):
		await stage.call(str(spec.method), self, spec)
		_shot_done = true
		return
	super._run_shot()
