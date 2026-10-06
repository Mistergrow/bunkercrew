class_name RoomLining
extends Node2D
## Each excavated room owns a separate material buffer and two structural layers.
## Core durability is awarded once, only when a paid layer has finished curing.

signal changed

var game
var site: ExpansionSite
var tier := 0
var target_tier := 1
var materials: Dictionary = {}
var construction := 0.0
var curing_remaining := 0.0
var transfer: Dictionary = {}
var _curing_tier := 0
var _awarded_tiers: Dictionary = {}

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("room_linings")
	if is_instance_valid(site) and is_instance_valid(site.excavation):
		site.excavation.cleared.connect(_changed)
	queue_redraw()

func spec(for_tier: int = 0) -> Dictionary:
	return Balance.ROOM_LINING_SPECS[clampi(target_tier if for_tier == 0 else for_tier,1,2)]

func interaction_point() -> Vector2:
	return global_position - Vector2(0,26)

func can_interact(_player) -> bool:
	return is_instance_valid(site) and site.excavated() and tier < 2 and _curing_tier == 0

func complete_materials() -> bool:
	for kind: String in spec().cost:
		if int(materials.get(kind,0)) < int(spec().cost[kind]):
			return false
	return true

func prompt(_player) -> String:
	if not is_instance_valid(site) or not site.excavated():
		return LocaleText.text("RÜCKWAND · zuerst den Raum vollständig ausheben")
	if _curing_tier > 0:
		return LocaleText.format("%s · härtet %.1f s · danach Bunkerkern +%d HP", [spec(_curing_tier).label,curing_remaining,int(spec(_curing_tier).hp_bonus)])
	if tier >= 2:
		return LocaleText.text("TRAGWERK · fertig · Bunkerkern dauerhaft +75 HP")
	var recipe := spec()
	if complete_materials():
		return LocaleText.format("%s · halten: einbauen · danach %.0f s härten · Bunkerkern +%d HP", [recipe.label,recipe.cure_time,int(recipe.hp_bonus)])
	var amounts: Array[String] = []
	for kind: String in recipe.cost:
		amounts.append(LocaleText.format("%s %d/%d", [Balance.RESOURCE_NAMES[kind],int(materials.get(kind,0)),int(recipe.cost[kind])]))
	return LocaleText.format("%s · %s · halten: einfüllen · Bunkerkern +%d HP nach Härten", [recipe.label," + ".join(amounts),int(recipe.hp_bonus)])

func interaction_progress(player) -> float:
	if _curing_tier > 0:
		return clampf(1.0 - curing_remaining / float(spec(_curing_tier).cure_time),0,1)
	if tier >= 2:
		return 1.0
	if complete_materials():
		return clampf(construction / float(spec().build_time),0,1)
	return clampf(float(transfer.get(player.get_instance_id(),0.0)) / Balance.TRANSFER_TIME,0,1) if is_instance_valid(player) else 0.0

func interact(player, delta: float) -> void:
	if delta <= 0 or not can_interact(player):
		return
	if complete_materials():
		construction += delta
		if construction >= float(spec().build_time):
			_curing_tier = target_tier
			curing_remaining = float(spec().cure_time)
			construction = 0.0
			materials.clear()
			transfer.clear()
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"build",interaction_point())
		_changed()
		return
	var choices: Array = spec().cost.keys()
	if player.has_method("selected_material"):
		var selected: String = player.selected_material()
		if selected in choices:
			choices.erase(selected)
			choices.push_front(selected)
	var needed := ""
	for kind: String in choices:
		if int(materials.get(kind,0)) < int(spec().cost[kind]) and int(player.inventory.get(kind,0)) > 0:
			needed = kind
			break
	if needed.is_empty():
		return
	var id: int = player.get_instance_id()
	transfer[id] = float(transfer.get(id,0.0)) + delta
	if transfer[id] >= Balance.TRANSFER_TIME:
		# A synchronous one-unit transfer cannot interleave between two workers.
		# Inventory must accept the deduction before the room owns that material.
		if player.take_item(needed,1):
			materials[needed] = int(materials.get(needed,0)) + 1
			transfer[id] = 0.0
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"build",interaction_point())
	_changed()

func _process(delta: float) -> void:
	if _curing_tier == 0 or delta <= 0:
		return
	curing_remaining = maxf(0.0,curing_remaining-delta)
	if curing_remaining <= 0:
		var finished_tier := _curing_tier
		_curing_tier = 0
		tier = finished_tier
		target_tier = mini(2,tier+1)
		if not _awarded_tiers.has(finished_tier):
			_awarded_tiers[finished_tier] = true
			var bonus: float = spec(finished_tier).hp_bonus
			if is_instance_valid(game) and is_instance_valid(game.core):
				game.core.max_hp += bonus
				game.core.hp = minf(game.core.max_hp,game.core.hp+bonus)
				preload("res://scripts/spatial_sound.gd").emit(game,"produce",interaction_point())
	_changed()

func _changed() -> void:
	queue_redraw()
	changed.emit()

func _draw() -> void:
	if not is_instance_valid(site) or not site.excavated():
		return
	var color := Color("677462") if tier > 0 else Color("8e805e")
	if _curing_tier > 0:
		color = Color("7b8980")
	draw_rect(Rect2(-13,-43,26,37),Color("202c28"))
	draw_rect(Rect2(-11,-41,22,33),color)
	draw_rect(Rect2(-8,-34,16,19),Color("34443b"))
	for x in [-9,8]:
		for y in [-39,-11]:
			draw_rect(Rect2(x,y,2,2),Color("c0b792"))
	Art.text(self,Vector2(-6,-20),"II" if tier == 2 else "I" if tier == 1 else "+",10,Color("d0c5a3"))
	if _curing_tier > 0:
		Art.bar(self,Rect2(-13,-49,26,3),interaction_progress(null),Art.AMBER)
