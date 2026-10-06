class_name PlayerProgression
extends Node
## Run-local personal XP. The combat dispatcher supplies only actual HP removed.
signal event(kind: String, data: Dictionary)
signal changed

const MAX_LEVEL := 30
const MAX_SKILL_RANK := 5
const XP_FIRST_LEVEL := 50.0
const XP_LEVEL_STEP := 25.0
const XP_PER_DAMAGE := 0.10
const XP_PER_KILL := 14.0
const COMBO_WINDOW := 5.0
const MAX_COMBO := 10
const COMBO_BONUS_STEP := 0.08
const HP_PER_LEVEL := 10.0
const HP_PER_VITALITY := 15.0
const DAMAGE_PER_COMBAT := 0.06
const WORK_PER_ENGINEERING := 0.08
const SPEED_PER_ENGINEERING := 0.02
const ARMOR_REDUCTION := [0.0, 0.20, 0.35]
const SKILL_SPECS := {
	"vitality":{"title":"VITALITÄT", "detail":"+15 maximale LP je Rang"},
	"combat":{"title":"WAFFENDRILL", "detail":"+6 % eigener Waffenschaden je Rang"},
	"engineering":{"title":"HANDWERK", "detail":"+8 % Arbeit, +2 % Tempo; +1 Last alle 2 Ränge"},
}

var worker
var level := 1
var xp := 0.0
var kills := 0
var combo := 0
var combo_time := 0.0
var skill_points := 0
var skills := {"vitality":0, "combat":0, "engineering":0}
var armor_tier := 0

func _ready() -> void:
	worker = get_parent()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(worker) or not is_instance_valid(worker.game) or not "started" in worker.game or not worker.game.started:
		return
	if worker.has_method("is_downed") and worker.is_downed():
		break_combo()
		return
	if combo_time > 0.0:
		combo_time = maxf(0.0, combo_time-delta)
		if combo_time <= 0.0:
			break_combo()

func break_combo() -> void:
	if combo == 0 and combo_time == 0.0:
		return
	combo = 0
	combo_time = 0.0
	changed.emit()

func xp_required() -> float:
	return XP_FIRST_LEVEL + XP_LEVEL_STEP*(level-1)

func _payload(extra: Dictionary = {}) -> Dictionary:
	var result := {"player_id":worker.player_id if is_instance_valid(worker) else 0, "level":level, "xp":xp, "current_xp":xp, "required":xp_required(), "kills":kills, "combo":combo}
	result.merge(extra,true)
	return result

func award_damage(applied: float, reward_multiplier: float = 1.0) -> void:
	if not is_finite(applied) or applied <= 0.0:
		return
	var earned := applied*XP_PER_DAMAGE*clampf(reward_multiplier,0.0,1.0)
	_add_xp(earned)
	event.emit("hit",_payload({"xp":earned,"earned":earned,"damage":applied}))

func award_kill(reward_multiplier: float = 1.0) -> void:
	kills += 1
	combo = mini(MAX_COMBO, combo+1) if combo_time > 0.0 else 1
	combo_time = COMBO_WINDOW
	var earned := XP_PER_KILL*(1.0+(combo-1)*COMBO_BONUS_STEP)*clampf(reward_multiplier,0.0,1.0)
	_add_xp(earned)
	event.emit("kill",_payload({"xp":earned,"earned":earned}))

func award_team(amount: float, action: String) -> void:
	if not is_finite(amount) or amount<=0: return
	_add_xp(amount)
	event.emit("support",_payload({"xp":amount,"earned":amount,"action":action}))

func _add_xp(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0:
		return
	if level >= MAX_LEVEL:
		xp = 0.0
		changed.emit()
		return
	xp += amount
	while level < MAX_LEVEL and xp >= xp_required():
		xp -= xp_required()
		level += 1
		skill_points += 1
		_refresh_hp()
		event.emit("level_up",_payload({"skill_points":skill_points}))
	if level >= MAX_LEVEL:
		xp = 0.0
	changed.emit()

func purchase_skill(id: String) -> bool:
	if not skills.has(id) or skill_points <= 0 or int(skills[id]) >= MAX_SKILL_RANK:
		return false
	skill_points -= 1
	skills[id] = int(skills[id])+1
	_refresh_hp()
	changed.emit()
	event.emit("skill",_payload({"skill":id,"rank":skills[id]}))
	return true

func equip_armor(tier: int) -> bool:
	if tier != armor_tier+1 or tier < 1 or tier >= ARMOR_REDUCTION.size():
		return false
	armor_tier = tier
	changed.emit()
	event.emit("armor",_payload({"tier":tier,"reduction":armor_reduction()}))
	return true

func _refresh_hp() -> void:
	if not is_instance_valid(worker):
		return
	var old_max: float = worker.max_hp
	var missing: float = maxf(0.0,old_max-worker.hp)
	var base: Dictionary = CharacterCatalog.data(worker.character_id)
	worker.max_hp = float(base.hp)+(level-1)*HP_PER_LEVEL+int(skills.vitality)*HP_PER_VITALITY
	# A level does not undo injury. A KO remains a KO until normal recovery.
	if worker.hp <= 0.0 or worker.is_downed():
		worker.hp = 0.0
	else:
		worker.hp = clampf(worker.max_hp-missing,0.0,worker.max_hp)
	worker.queue_redraw()

func damage_multiplier() -> float:
	return 1.0+int(skills.combat)*DAMAGE_PER_COMBAT

func work_multiplier() -> float:
	return 1.0+int(skills.engineering)*WORK_PER_ENGINEERING

func speed_multiplier() -> float:
	return 1.0+int(skills.engineering)*SPEED_PER_ENGINEERING

func capacity_bonus() -> int:
	return floori(int(skills.engineering)/2.0)

func armor_reduction() -> float:
	return ARMOR_REDUCTION[clampi(armor_tier,0,ARMOR_REDUCTION.size()-1)]
