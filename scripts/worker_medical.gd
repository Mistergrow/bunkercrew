class_name WorkerMedical
extends Node

const NetInput := preload("res://scripts/network_input.gd")
## Wounds and treatment belong to the patient. One uninterrupted helper owns a
## channel; charges move only on completion, so cancellation cannot waste supplies.
signal changed
signal aid_completed(helper: Node, was_downed: bool)

var worker
var bleeding := 0
var fractured := false
var bandaged := false
var splinted := false
var state := "healthy"
var charges := MedicalCatalog.MAX_CHARGES
var critical_remaining := 0.0
var down_elapsed := 0.0
var recovery_time := 0.0
var recovery_kind := ""
# Outgoing treatment fields read by the worker animation and HUD.
var aid_target: Node2D
var aid_kind := ""
var aid_progress := 0.0
var hit_serial := 0
var _refill_elapsed := 0.0
var _healer: Node2D
var _channel_elapsed := 0.0
var _channel_gap := 0.0
var _helper_origin := Vector2.ZERO
var _patient_origin := Vector2.ZERO
var _patient_hit := 0
var _helper_hit := 0

func _ready() -> void:
	worker = get_parent()

func incapacitated() -> bool:
	return state in ["downed","critical"]

func is_rising() -> bool:
	return recovery_time>0.0 and recovery_kind in ["revive","resuscitate"]

func needs_medical_help() -> bool:
	return incapacitated() or bleeding>0 or fractured or worker.hp<worker.max_hp-0.01

func movement_multiplier() -> float:
	return MedicalCatalog.FRACTURE_SPEED if fractured else 1.0

func work_multiplier() -> float:
	return MedicalCatalog.FRACTURE_WORK if fractured else 1.0

func on_damage(applied: float, trauma: String = "") -> void:
	if applied<=0.0: return
	hit_serial += 1
	interrupt()
	# Actual post-armor damage determines trauma: small hits remain ordinary HP
	# damage, while explosive/heavy blows can add an explicitly visible fracture.
	if applied>=18.0:
		bandaged = false
		bleeding = mini(3,maxi(bleeding,1 if applied<32.0 else (2 if applied<55.0 else 3)))
	if applied>=42.0 or (trauma in ["explosive","fall"] and applied>=28.0):
		fractured = true
		splinted = false
	_sync_state()
	changed.emit()

func incapacitate() -> void:
	if incapacitated(): return
	interrupt()
	state = "downed"
	critical_remaining = MedicalCatalog.CRITICAL_DELAY
	down_elapsed = 0.0
	worker.down_time = critical_remaining
	changed.emit()

func tick(delta: float) -> void:
	if not is_finite(delta) or delta<=0.0: return
	recovery_time = maxf(0.0,recovery_time-delta)
	if recovery_time<=0.0: recovery_kind = ""
	if is_instance_valid(_healer):
		_channel_gap += delta
		if _channel_gap>MedicalCatalog.CHANNEL_GAP or not _channel_valid(_healer):
			_clear_channel()
	if incapacitated():
		down_elapsed += delta
		critical_remaining = maxf(0.0,critical_remaining-delta)
		worker.down_time = maxf(0.001,critical_remaining)
		if critical_remaining<=0.0 and state!="critical":
			state = "critical"
			changed.emit()
		_refill_elapsed = 0.0
		return
	if bleeding>0:
		# Bleeding is not another enemy hit: no fresh knockback, invulnerability or
		# combat-delay reset. A wounded person can still restock near the core.
		worker.hp = maxf(0.0,worker.hp-float(bleeding)*MedicalCatalog.BLEED_DAMAGE_PER_LEVEL*delta)
		if worker.hp<=0.0:
			worker._begin_knockout()
			return
	if charges<MedicalCatalog.MAX_CHARGES and worker.since_hit>=Balance.WORKER_REGEN_DELAY and worker._near_core():
		_refill_elapsed += minf(delta,maxf(0.0,worker.since_hit-Balance.WORKER_REGEN_DELAY))
		while _refill_elapsed>=MedicalCatalog.REFILL_TIME and charges<MedicalCatalog.MAX_CHARGES:
			_refill_elapsed -= MedicalCatalog.REFILL_TIME
			charges += 1
			changed.emit()
	else:
		_refill_elapsed = 0.0
	_sync_state()

func _sync_state() -> void:
	if not incapacitated():
		state = "wounded" if bleeding>0 or fractured or worker.hp<worker.max_hp-0.01 else "healthy"

func aid_duration() -> float:
	if state=="critical": return MedicalCatalog.CRITICAL_REVIVE_TIME
	if state=="downed": return MedicalCatalog.REVIVE_TIME
	return MedicalCatalog.TREAT_TIME

func _kind() -> String:
	if state=="critical": return "resuscitate"
	if state=="downed": return "revive"
	return "splint" if fractured else "bandage"

func reachable_can_aid(helper: Node2D) -> bool:
	# A medical charge belongs to a live helper in this patient's physical world.
	# Retiring scene nodes can remain valid until the end of the frame, and their
	# old positions must never authorize treatment or consume another world's kit.
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(worker) or not worker is Node2D or not worker.is_inside_tree() or worker.is_queued_for_deletion(): return false
	if not is_instance_valid(helper) or not helper.is_inside_tree() or helper.is_queued_for_deletion() or helper==worker: return false
	var owner_game: Variant = worker.get("game")
	if not owner_game is Node or not is_instance_valid(owner_game) or not owner_game.is_inside_tree() or owner_game.is_queued_for_deletion() or helper.get("game")!=owner_game or helper.get_world_2d()!=worker.get_world_2d(): return false
	if "medical" in helper and is_instance_valid(helper.medical):
		if not helper.medical is WorkerMedical or not helper.medical.is_inside_tree() or helper.medical.is_queued_for_deletion() or helper.medical.get_parent()!=helper: return false
	if not needs_medical_help(): return false
	if not helper.has_method("can_act") or not helper.can_act() or MedicalCatalog.charge_count(helper)<=0: return false
	if helper.has_method("action"):
		for suffix in ["fire","reload","jump"]:
			var input_name: String = helper.action(suffix)
			if InputMap.has_action(input_name) and NetInput.is_pressed(helper,suffix): return false
	if "climbing" in helper and helper.climbing: return false
	if "mounted_turret" in helper and is_instance_valid(helper.mounted_turret): return false
	if absf(helper.global_position.y-worker.global_position.y)>MedicalCatalog.FLOOR_TOLERANCE: return false
	if helper.global_position.distance_to(worker.global_position)>MedicalCatalog.AID_REACH: return false
	var ray := PhysicsRayQueryParameters2D.create(helper.global_position-Vector2(0,18),worker.global_position-Vector2(0,18),1|2)
	ray.hit_from_inside = true
	return worker.get_world_2d().direct_space_state.intersect_ray(ray).is_empty()

func _helper_hit_serial(helper: Node) -> int:
	return int(helper.medical.hit_serial) if "medical" in helper and is_instance_valid(helper.medical) else 0

func _channel_valid(helper: Node2D) -> bool:
	if not reachable_can_aid(helper): return false
	if helper.global_position.distance_to(_helper_origin)>MedicalCatalog.MOVEMENT_TOLERANCE or worker.global_position.distance_to(_patient_origin)>MedicalCatalog.MOVEMENT_TOLERANCE: return false
	if _patient_hit!=hit_serial or _helper_hit!=_helper_hit_serial(helper): return false
	if "velocity" in helper and helper.velocity.length()>18.0: return false
	return true

func begin_or_continue_aid(helper: Node2D, delta: float) -> bool:
	if not is_finite(delta) or delta<=0.0: return false
	if not reachable_can_aid(helper) or ("velocity" in helper and helper.velocity.length()>18.0):
		if helper==_healer: _clear_channel()
		return false
	if is_instance_valid(_healer) and helper!=_healer:
		return false
	if is_instance_valid(_healer) and not _channel_valid(helper):
		_clear_channel()
		return false
	if not is_instance_valid(_healer):
		if "medical" in helper and is_instance_valid(helper.medical) and is_instance_valid(helper.medical.aid_target) and helper.medical.aid_target!=worker:
			helper.medical.aid_target.medical._clear_channel()
		_healer = helper
		_helper_origin = helper.global_position
		_patient_origin = worker.global_position
		_patient_hit = hit_serial
		_helper_hit = _helper_hit_serial(helper)
		_channel_elapsed = 0.0
		if "facing" in helper and absf(worker.global_position.x-helper.global_position.x)>1.0:
			helper.facing = signf(worker.global_position.x-helper.global_position.x)
	_channel_gap = 0.0
	_channel_elapsed += delta * (CharacterCatalog.medical_speed(str(helper.character_id)) if "character_id" in helper else 1.0)
	_set_helper_pose(helper)
	if _channel_elapsed<aid_duration(): return false
	if not MedicalCatalog.spend_charge(helper):
		_clear_channel()
		return false
	var hp_before: float = worker.hp
	var was_downed := incapacitated()
	var completed_kind := _kind()
	_clear_channel()
	bandaged = true
	splinted = splinted or fractured
	bleeding = 0
	fractured = false
	critical_remaining = 0.0
	state = "wounded"
	if was_downed:
		worker._restore_from_aid(MedicalCatalog.REVIVE_HEALTH_RATIO)
	else:
		worker.hp = minf(worker.max_hp,worker.hp+MedicalCatalog.HEAL_AMOUNT)
	recovery_kind = completed_kind
	recovery_time = MedicalCatalog.RECOVERY_TIME
	_sync_state()
	if is_instance_valid(worker.game):
		preload("res://scripts/spatial_sound.gd").emit(worker.game,"medical_revive" if was_downed else "medical_heal",worker.global_position-Vector2(0,23))
		var events=worker.game.get("combat_events")
		if was_downed and is_instance_valid(helper) and helper.is_in_group("players") and is_instance_valid(events): events.unlock("field_medic")
		if is_instance_valid(events) and events.has_method("record_role"):
			events.record_role(helper,"aid",minf(6.0,maxf(0.0,worker.hp-hp_before)*0.05+(4.0 if was_downed else 0.0)))
	changed.emit()
	aid_completed.emit(helper,was_downed)
	return true

func _set_helper_pose(helper: Node) -> void:
	if "medical" in helper and is_instance_valid(helper.medical):
		helper.medical.aid_target = worker
		helper.medical.aid_kind = _kind()
		helper.medical.aid_progress = progress_for(helper)

func progress_for(helper: Node) -> float:
	return clampf(_channel_elapsed/aid_duration(),0.0,1.0) if is_instance_valid(_healer) and helper==_healer else 0.0

func _clear_channel() -> void:
	if is_instance_valid(_healer) and "medical" in _healer and is_instance_valid(_healer.medical) and _healer.medical.aid_target==worker:
		_healer.medical.aid_target = null
		_healer.medical.aid_kind = ""
		_healer.medical.aid_progress = 0.0
	_healer = null
	_channel_elapsed = 0.0
	_channel_gap = 0.0

func interrupt() -> void:
	_clear_channel()
	if is_instance_valid(aid_target) and "medical" in aid_target and is_instance_valid(aid_target.medical):
		aid_target.medical._clear_channel()
	aid_target = null
	aid_kind = ""
	aid_progress = 0.0

func status_text() -> String:
	if state=="critical": return LocaleText.text("KRITISCH · Wiederbeleben 8s")
	if state=="downed": return LocaleText.format("BEWUSSTLOS · %.0fs bis kritisch", critical_remaining)
	var parts := PackedStringArray()
	if bleeding>0: parts.append(LocaleText.format("BLUTUNG %s", ["","I","II","III"][bleeding]))
	if fractured: parts.append(LocaleText.text("BEINBRUCH"))
	if parts.is_empty(): return LocaleText.text("VERLETZT") if worker.hp<worker.max_hp-0.01 else LocaleText.text("STABIL")
	return " · ".join(parts)
