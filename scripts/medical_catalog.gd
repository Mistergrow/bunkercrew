class_name MedicalCatalog
extends RefCounted
## Shared medical tuning. Charges are separate from carried crafting material.
const MAX_CHARGES := 2
const REFILL_TIME := 6.0
const TREAT_TIME := 2.4
const REVIVE_TIME := 5.0
const CRITICAL_REVIVE_TIME := 8.0
const CRITICAL_DELAY := 45.0
const HEAL_AMOUNT := 35.0
const REVIVE_HEALTH_RATIO := 0.35
const AID_REACH := 48.0
const FLOOR_TOLERANCE := 30.0
const MOVEMENT_TOLERANCE := 6.0
const CHANNEL_GAP := 0.22
const RECOVERY_TIME := 1.1
const BLEED_DAMAGE_PER_LEVEL := 0.7
const FRACTURE_SPEED := 0.72
const FRACTURE_WORK := 0.78
const FRACTURE_JUMP := 0.82

static func charge_count(helper: Node) -> int:
	if not is_instance_valid(helper): return 0
	if "medical" in helper and is_instance_valid(helper.medical):
		return int(helper.medical.charges)
	return int(helper.medical_supplies) if "medical_supplies" in helper else 0

static func spend_charge(helper: Node) -> bool:
	if charge_count(helper)<=0: return false
	if "medical" in helper and is_instance_valid(helper.medical):
		helper.medical.charges -= 1
		helper.medical.changed.emit()
		return true
	return bool(helper.take_medical_supply()) if helper.has_method("take_medical_supply") else false
