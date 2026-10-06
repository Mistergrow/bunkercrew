class_name MedicalAidTarget
extends Node2D
## A separate interaction target deliberately excludes the worker carrying it.
var medical: WorkerMedical

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("medical_targets")
	z_index = 2

func can_interact(helper: Node2D) -> bool:
	return is_instance_valid(medical) and medical.reachable_can_aid(helper)

func interaction_point() -> Vector2:
	return global_position-Vector2(0,20)

func interact(helper: Node2D, delta: float) -> void:
	medical.begin_or_continue_aid(helper,delta)

func interaction_progress(helper: Node2D) -> float:
	return medical.progress_for(helper)

func prompt(_helper: Node2D) -> String:
	var patient = medical.worker
	var title := LocaleText.text("WIEDERBELEBEN") if medical.incapacitated() else LocaleText.text("ERSTE HILFE")
	return LocaleText.format("P%d · %s\n%s · %.1fs halten · 1 Verband", [patient.player_id,medical.status_text(),title,medical.aid_duration()])
