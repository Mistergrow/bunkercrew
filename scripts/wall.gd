class_name DefenseWall
extends StaticBody2D

enum State { EMPTY, FORM, REBAR, FRESH, HARD }
@export var initial_state: int = State.EMPTY
@export_range(1, 4) var initial_tier: int = 1
const MAX_TIER := 4
const UPGRADE_TIME := 2.0
const UPGRADE_COSTS := {2: {"steel": 2, "concrete": 2}, 3: {"alloy": 2, "concrete": 3}, 4: {"alloy":3,"concrete":3}}
const UPGRADE_HP_BONUS := {1: 0.0, 2: 250.0, 3: 650.0, 4: 1150.0}
const UPGRADE_TECH := {2: "bunker_armor", 3: "bunker_armor", 4:"bunker_fortress"}
const UPGRADE_TECH_NAMES := {2: "Verbundwände", 3: "Verbundwände",4:"Festung"}
const UPGRADE_WAVES := {2:6,3:11,4:16}
const DamageArt := preload("res://scripts/structure_damage_art.gd")
var game
var state: int = State.EMPTY
var tier: int = 1
var hp: float = 0.0
var max_hp: float = 0.0
var reinforced: bool = false
var cure_time: float = 0.0
var work: float = 0.0
var work_action: String = ""
var last_work_frame: int = -1000
var hit_flash: float = 0.0
var pour_animation: float = 0.0
var assembly_animation: float = 0.0
var animation_time: float = 0.0
var collider: CollisionShape2D

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("walls")
	collision_layer = 2
	collision_mask = 0
	collider = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(30, 90)
	collider.position = Vector2(0, -45)
	collider.shape = shape
	add_child(collider)
	state = initial_state
	tier = clampi(initial_tier, 1, MAX_TIER) if state == State.HARD else 1
	reinforced = state == State.REBAR
	match state:
		State.FORM: max_hp = Balance.FORM_HP
		State.REBAR: max_hp = Balance.REBAR_FORM_HP
		State.FRESH: max_hp = Balance.FRESH_HP
		State.HARD: max_hp = completed_max_hp()
		_: max_hp = 0.0
	hp = max_hp
	collider.disabled = not is_blocking()
	queue_redraw()

func _process(delta: float) -> void:
	animation_time += delta
	hit_flash = maxf(0, hit_flash - delta)
	pour_animation = maxf(0, pour_animation - delta)
	assembly_animation = maxf(0, assembly_animation - delta)
	if state == State.FRESH:
		cure_time += delta
		var target_hp: float = Balance.REINFORCED_HP if reinforced else Balance.WALL_HP
		var start_hp: float = Balance.FRESH_HP * (Balance.FRESH_REBAR_MULTIPLIER if reinforced else 1.0)
		var new_max: float = lerpf(start_hp, target_hp, minf(1, cure_time / Balance.CURE_TIME))
		hp += maxf(0, new_max-max_hp)
		max_hp = new_max
		if cure_time >= Balance.CURE_TIME:
			state = State.HARD
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"produce",global_position)
	queue_redraw()

func interaction_point() -> Vector2:
	return global_position + Vector2(0, -34)

func is_blocking() -> bool:
	return state != State.EMPTY and hp > 0

func completed_max_hp() -> float:
	return (Balance.REINFORCED_HP if reinforced else Balance.WALL_HP) + float(UPGRADE_HP_BONUS[tier])

func tier_label() -> String:
	return ["I", "II", "III", "IV"][clampi(tier - 1, 0, MAX_TIER - 1)]

func upgrade_cost() -> Dictionary:
	return UPGRADE_COSTS[tier + 1].duplicate() if tier < MAX_TIER else {}

func upgrade_tech_unlocked() -> bool:
	if tier >= MAX_TIER or not is_instance_valid(game):
		return false
	var upgrades = game.get("upgrades")
	return is_instance_valid(upgrades) and upgrades.has_method("has_upgrade") and upgrades.has_upgrade(UPGRADE_TECH[tier + 1])

func upgrade_wave_unlocked() -> bool:
	if tier >= MAX_TIER or not is_instance_valid(game):
		return false
	var rounds = game.get("rounds")
	return is_instance_valid(rounds) and int(rounds.get("wave")) >= UPGRADE_WAVES[tier + 1]

func upgrade_unlocked() -> bool:
	return state == State.HARD and upgrade_tech_unlocked() and upgrade_wave_unlocked()

func _is_damaged() -> bool:
	return hp < max_hp - 0.001

func _has_cost(player, cost: Dictionary) -> bool:
	for kind: String in cost:
		if int(player.inventory.get(kind, 0)) < int(cost[kind]):
			return false
	return not cost.is_empty()

func _consume_cost(player, cost: Dictionary) -> bool:
	# Validate the complete recipe before any item leaves either player's inventory.
	# This is synchronous: no second worker can interleave a partial transaction.
	if not _has_cost(player, cost):
		return false
	var paid: Dictionary = {}
	for kind: String in cost:
		if not player.take_item(kind, int(cost[kind])):
			for previous: String in paid:
				player.add_item(previous, int(paid[previous]))
			return false
		paid[kind] = cost[kind]
	return true

func action_for(player) -> String:
	if state == State.EMPTY:
		return "form"
	if state == State.FORM:
		if int(player.inventory.get("steel",0)) >= Balance.WALL_STEEL_COST:
			return "reinforce"
		if int(player.inventory.get("concrete",0)) >= Balance.WALL_CONCRETE_COST:
			return "pour"
	if state == State.REBAR and int(player.inventory.get("concrete",0)) >= Balance.WALL_CONCRETE_COST:
		return "pour"
	if state in [State.FRESH, State.HARD] and _is_damaged():
		return "repair" if int(player.inventory.get("concrete", 0)) > 0 else ""
	if upgrade_unlocked() and _has_cost(player, upgrade_cost()):
		return "upgrade"
	return ""

func prompt(player) -> String:
	match state:
		State.EMPTY:
			return LocaleText.text("BAUPLATZ · Schalung stellen · halten (kostenlos)")
		State.FORM:
			if action_for(player) == "reinforce":
				return LocaleText.format("SCHALUNG · %d Stahl einbauen → stärkere Wand", Balance.WALL_STEEL_COST)
			return LocaleText.format("SCHALUNG · erst %d Stahl (optional), dann %d Beton gießen", [Balance.WALL_STEEL_COST, Balance.WALL_CONCRETE_COST])
		State.REBAR:
			return LocaleText.format("BEWEHRT · %d Beton gießen → %d Haltbarkeit", [Balance.WALL_CONCRETE_COST, Balance.REINFORCED_HP])
		State.FRESH:
			return LocaleText.format("FRISCHBETON · härtet %.0f s · %d/%d · Reparatur: 1 Beton", [maxf(0,Balance.CURE_TIME-cure_time),ceil(hp),ceil(max_hp)])
		State.HARD:
			var label := LocaleText.format("%s %s · %d/%d", [LocaleText.text("STAHLBETON") if reinforced else LocaleText.text("BETONWAND"), tier_label(), ceil(hp), ceil(max_hp)])
			if _is_damaged():
				return label + LocaleText.text(" · zuerst reparieren: 1 Beton")
			if tier >= MAX_TIER:
				return label + LocaleText.text(" · Vollausbau")
			var next_label: String = ["I", "II", "III", "IV"][tier]
			if not upgrade_tech_unlocked():
				return label + LocaleText.format(" · %s: Technik %s freischalten", [next_label, UPGRADE_TECH_NAMES[tier + 1]])
			if not upgrade_wave_unlocked():
				return label + LocaleText.format(" · Ausbau %s ab Welle %d", [next_label, UPGRADE_WAVES[tier+1]])
			var cost := upgrade_cost()
			var needs: Array[String] = []
			for kind in cost:
				needs.append(LocaleText.format("%s %d/%d", [Balance.RESOURCE_NAMES[kind],player.inventory.get(kind,0),cost[kind]]))
			return label + LocaleText.format(" · %s: %s · halten", [next_label," + ".join(needs)])
	return ""

func interaction_progress(_player) -> float:
	return work

func interact(player, delta: float) -> void:
	if not is_instance_valid(player) or not is_finite(delta) or delta <= 0.0:
		return
	var action: String = action_for(player)
	if action.is_empty():
		return
	if action != work_action:
		# Two workers with different cargo cannot cancel each other every frame.
		if work > 0 and Engine.get_physics_frames()-last_work_frame < 4:
			return
		work = 0.0
		work_action = action
	last_work_frame = Engine.get_physics_frames()
	var duration: float = Balance.FORM_TIME if action == "form" else Balance.WALL_WORK_TIME
	if action == "upgrade":
		duration = UPGRADE_TIME
	if action == "repair" and is_instance_valid(game) and is_instance_valid(game.get("upgrades")) and game.upgrades.has_method("repair_multiplier"):
		duration /= game.upgrades.repair_multiplier()
	work += delta / duration
	if work < 1.0:
		return
	work = 0.0
	match action:
		"form":
			state = State.FORM
			tier = 1
			reinforced = false
			max_hp = Balance.FORM_HP
			hp = max_hp
		"reinforce":
			if not player.take_item("steel",Balance.WALL_STEEL_COST):
				return
			state = State.REBAR
			reinforced = true
			max_hp = Balance.REBAR_FORM_HP
			hp = max_hp
		"pour":
			if not player.take_item("concrete",Balance.WALL_CONCRETE_COST):
				return
			state = State.FRESH
			pour_animation = 1.2
			cure_time = 0.0
			max_hp = Balance.FRESH_HP * (Balance.FRESH_REBAR_MULTIPLIER if reinforced else 1.0)
			hp = max_hp
		"repair":
			if not player.take_item("concrete",1):
				return
			var repaired := minf(max_hp-hp,Balance.WALL_REPAIR)
			hp += repaired
			var events = game.get("combat_events") if is_instance_valid(game) else null
			if is_instance_valid(events) and events.has_method("record_role"): events.record_role(player,"repair",repaired*0.06)
		"upgrade":
			if not upgrade_unlocked() or _is_damaged() or not _consume_cost(player, upgrade_cost()):
				return
			var previous_max := max_hp
			tier += 1
			max_hp = completed_max_hp()
			hp += max_hp - previous_max
			assembly_animation = 0.8
	if action in ["reinforce","pour","upgrade"]:
		var events = game.get("combat_events") if is_instance_valid(game) else null
		if is_instance_valid(events) and events.has_method("record_role"): events.record_role(player,"craft",2.0)
	collider.set_deferred("disabled",not is_blocking())
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"build",global_position)
		game.fx(global_position+Vector2(0,-45),Art.AMBER,8)
	queue_redraw()

func take_damage(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0 or not is_blocking():
		return
	hp = maxf(0, hp - amount)
	hit_flash = 0.12
	if get_meta("impact_contact_frame", -1) != Engine.get_physics_frames():
		ImpactBurst.emit(game, global_position + Vector2(17,-35), "concrete", Vector2.RIGHT, 0.8)
	if hp <= 0:
		state = State.EMPTY
		tier = 1
		reinforced = false
		max_hp = 0
		cure_time = 0
		work = 0
		work_action = ""
		assembly_animation = 0.0
		collider.set_deferred("disabled",true)
		if is_instance_valid(game):
			ImpactBurst.emit(game, global_position + Vector2(0,-40), "concrete", Vector2.UP, 2.0)
			preload("res://scripts/spatial_sound.gd").emit(game,"explosion",global_position)
	queue_redraw()

func _draw() -> void:
	if state == State.EMPTY:
		for i in range(6):
			draw_line(Vector2(-15,-i*15),Vector2(-15,-i*15-7),Color("667773"),2)
			draw_line(Vector2(15,-i*15),Vector2(15,-i*15-7),Color("667773"),2)
		draw_rect(Rect2(-20,-5,40,5),Color("595b50"))
		Art.text(self,Vector2(-9,-40),"+",20,Color("8c9b87"))
		return
	if state in [State.FORM, State.REBAR]:
		draw_rect(Rect2(-18,-89,36,88),Art.INK)
		draw_rect(Rect2(-15,-85,30,81),Color("715b40"))
		for y in range(-79,-3,17):
			draw_line(Vector2(-14,y),Vector2(14,y),Color("b0915e"),2)
		for x in [-13,10]:
			draw_rect(Rect2(x,-91,4,92),Color("b3a276"))
		if state == State.REBAR:
			for x in [-9,1,11]:
				draw_line(Vector2(x,-105),Vector2(x,-5),Color("55585a"),4)
				draw_line(Vector2(x-1,-105),Vector2(x-1,-5),Color("b7a088"),1)
			for y in range(-99,-5,13):
				draw_line(Vector2(-14,y),Vector2(17,y),Color("a48262"),2)
	else:
		var tint: Color = Color("919485") if state == State.HARD else Color("616c65")
		if hit_flash > 0:
			tint = Color("d3c2a7")
		draw_rect(Rect2(-18,-93,36,93),Art.INK)
		draw_rect(Rect2(-15,-90,30,90),tint)
		draw_rect(Rect2(-15,-90,4,90),tint.lightened(0.2))
		draw_rect(Rect2(11,-90,4,90),tint.darkened(0.3))
		for i in range(22):
			var x: int = -10 + (i*11)%21
			var y: int = -86 + (i*17)%82
			draw_rect(Rect2(x,y,2+i%3,2),tint.darkened(0.16))
		if reinforced:
			draw_rect(Rect2(-18,-89,36,5),Color("8f8270"))
			draw_rect(Rect2(-18,-12,36,5),Color("8f8270"))
		if state == State.HARD:
			_draw_upgrade_panels()
		DamageArt.wall(self, hp, max_hp, tier, reinforced)
		if state == State.FRESH:
			var fill: float = 1.0-cure_time/Balance.CURE_TIME
			draw_rect(Rect2(-10,-85,20,3+fill*4),Color("a6ac97"))
			if pour_animation > 0:
				draw_line(Vector2(-7,-111),Vector2(-4,-87),Color("babca4"),4)
				for i in range(4):
					var fall: float = fmod(pour_animation*60+i*13,29)
					draw_rect(Rect2(-12+i*7,-95+fall,3,3),Color("a7ab96"))
			Art.bar(self,Rect2(-20,-102,40,4),cure_time/Balance.CURE_TIME,Art.CYAN)
	if hp < max_hp - 1:
		Art.bar(self,Rect2(-20,-112,40,4),hp/max_hp,Art.RED if hp<max_hp*0.4 else Art.AMBER)

func _draw_upgrade_panels() -> void:
	# The original 30×90 collider remains inside these visible structural rails.
	# Concrete, crossed steel braces and riveted outer armor are distinct tiers.
	if tier >= 2:
		for x in [-21, 17]:
			draw_rect(Rect2(x, -91, 4, 90), Color("252e2c"))
			draw_rect(Rect2(x, -89, 2, 87), Color("b0aa8c"))
		for y in [-83, -17]:
			draw_rect(Rect2(-21, y - 1, 42, 7), Color("303a36"))
			draw_rect(Rect2(-20, y, 40, 4), Color("829185"))
			draw_line(Vector2(-18, y), Vector2(18, y), Color("b1b59b"), 1)
		for points in [[Vector2(-13, -74), Vector2(13, -27)], [Vector2(-13, -27), Vector2(13, -74)]]:
			draw_line(points[0], points[1], Color("34443e"), 6)
			draw_line(points[0], points[1], Color("879589"), 3)
	if tier >= 3:
		var plate := Color("5c7069").lightened(assembly_animation * 0.12)
		for y in [-79, -45]:
			draw_rect(Rect2(-18, y, 36, 29), Color("25312e"))
			draw_rect(Rect2(-16, y + 2, 32, 25), plate)
			draw_line(Vector2(-15, y + 2), Vector2(15, y + 2), Color("a6b29c"), 2)
			draw_rect(Rect2(12, y + 4, 3, 20), Color("46564f"))
			for x in [-13, 11]:
				for dy in [5, 23]:
					draw_rect(Rect2(x, y + dy, 2, 2), Color("c2b999"))
		var blink := 0.8 + sin(animation_time * 2.8) * 0.2
		for x in [-5, 2]:
			draw_rect(Rect2(x, -49, 4, 2), Color(0.61, 0.79, 0.63, blink))
	if tier >= 4:
		for x in [-24,18]:
			draw_rect(Rect2(x,-88,6,86),Color("222a28"))
			draw_rect(Rect2(x+1,-85,4,80),Color("a0a08c"))
			for y in range(-80,-7,13):
				draw_rect(Rect2(x+1,y,4,3),Color("5e675c"))
		for y in [-79,-45]:
			draw_line(Vector2(-12,y+7),Vector2(12,y+22),Color("8c856b"),5)
			draw_line(Vector2(-12,y+5),Vector2(12,y+20),Color("c1b596"),2)
	if work_action == "upgrade" and work > 0:
		var offset := (1.0 - minf(work, 1.0)) * 12.0
		draw_rect(Rect2(-16 + offset, -76, 32, 61), Color(0.72, 0.76, 0.64, 0.25))
		Art.bar(self, Rect2(-20, -101, 40, 3), work, Art.AMBER)
	# A compact plate stays readable without a permanent health bar.
	draw_rect(Rect2(-10, -13, 20, 11), Color("242e2a"))
	Art.text(self, Vector2(-3 * tier, -4), tier_label(), 9, Color("d7c894"))
