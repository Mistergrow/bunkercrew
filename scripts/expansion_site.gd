class_name ExpansionSite
extends Node2D
## Fixed build slots accept materials into their own buffers, then complete once.
const SPECS := {
	"furnace":{"name":"ZUSATZOFEN", "cost":{"steel":2,"concrete":2}, "tech":"bunker_workshop", "benefit":"Zweiter Stahlofen im Tiefbau"},
	"ammo_press":{"name":"MUNITIONSPRESSE", "cost":{"steel":2,"concrete":2}, "tech":"bunker_workshop", "benefit":"2 Stahl → 2 Munitionskisten"},
	"depot":{"name":"VORRATSRAUM", "cost":{"steel":1,"concrete":2}, "tech":"", "benefit":"Versiegelte Vorräte: 12 Munitionskisten + 24 Sand"},
	"core_room":{"name":"KERNSCHUTZRAUM", "cost":{"steel":2,"concrete":3}, "tech":"bunker_armor", "benefit":"Bunkerkern dauerhaft +150 Haltbarkeit"},
	"alloy":{"name":"LEGIERUNGSWERK", "cost":{"steel":3,"concrete":2}, "tech":"bunker_workshop", "benefit":"2 Wolframerz + 1 Stahl → 2 Panzerstahl"},
	"armory":{"name":"WAFFENWERK", "cost":{"alloy":3,"steel":3}, "tech":"bunker_armor", "benefit":"Dachgeschütz: 50 % mehr Schaden"},
}
@export var kind := "furnace"
var game
var materials: Dictionary = {}
var transfer: Dictionary = {}
var construction := 0.0
var built := false
var excavation
var lining

func _ready() -> void:
	z_index = -6
	add_to_group("interactables")
	add_to_group("expansion_sites")
	lining = preload("res://scripts/room_lining.gd").new()
	lining.game = game
	lining.site = self
	lining.position = Vector2(-70,0)
	add_child(lining)
	var rear = preload("res://scripts/room_lining_visual.gd").new()
	rear.site = self
	rear.lining = lining
	add_child(rear)
	if is_instance_valid(excavation):
		excavation.cleared.connect(func():
			queue_redraw()
			game.notify(LocaleText.format("%s · Aushub fertig · Bauplan mit E benutzen", SPECS[kind].name)))

func interaction_point() -> Vector2:
	return global_position-Vector2(0,26)

func can_interact(_player) -> bool:
	return not built and excavated()

func excavated() -> bool:
	return not is_instance_valid(excavation) or excavation.is_cleared()

func tech_ready() -> bool:
	var tech: String = SPECS[kind].tech
	return tech.is_empty() or game.upgrades.has_upgrade(tech)

func complete_materials() -> bool:
	for resource in SPECS[kind].cost:
		if int(materials.get(resource,0)) < int(SPECS[kind].cost[resource]):
			return false
	return true

func prompt(_player) -> String:
	var spec: Dictionary = SPECS[kind]
	if not excavated():
		return LocaleText.format("%s · zuerst Erde ausheben · %d Felder verbleiben", [spec.name,excavation.remaining_count()])
	if not tech_ready():
		return LocaleText.format("%s · T: %s freischalten", [spec.name,game.upgrades.node_data(spec.tech).title])
	if complete_materials():
		return LocaleText.format("%s · halten: fertigbauen · %s", [spec.name,spec.benefit])
	var amounts: Array[String] = []
	for resource in spec.cost:
		amounts.append(LocaleText.format("%s %d/%d", [Balance.RESOURCE_NAMES[resource],materials.get(resource,0),spec.cost[resource]]))
	return LocaleText.format("%s · %s · halten: Material einbauen", [spec.name,", ".join(amounts)])

func interaction_progress(_player) -> float:
	return construction / 1.4

func interact(player, delta: float) -> void:
	if not is_instance_valid(player) or not is_finite(delta) or delta <= 0.0 or built or not excavated() or not tech_ready():
		return
	if complete_materials():
		construction += delta
		if construction >= 1.4:
			_finish()
	else:
		var id: int = player.get_instance_id()
		transfer[id] = float(transfer.get(id,0.0))+delta
		if transfer[id] < Balance.TRANSFER_TIME:
			return
		for resource in SPECS[kind].cost:
			if int(materials.get(resource,0)) < int(SPECS[kind].cost[resource]) and player.take_item(resource,1):
				materials[resource] = int(materials.get(resource,0))+1
				transfer[id] = 0.0
				preload("res://scripts/spatial_sound.gd").emit(game,"build",interaction_point())
				break
	queue_redraw()

func _finish() -> void:
	if built or not excavated():
		return
	built = true
	remove_from_group("interactables")
	var lamp = preload("res://scenes/level_prop.tscn").instantiate()
	lamp.kind_index = 5
	lamp.anchor = 1
	lamp.display_size = Vector2(21,32)
	lamp.position = Vector2(-64,-145)
	add_child(lamp)
	match kind:
		"furnace":
			game._entity("station",global_position,{"kind":"furnace"})
		"ammo_press":
			game._entity("ammo_press",global_position)
		"alloy":
			game._entity("alloy_furnace",global_position)
		"armory":
			game.turret.damage_multiplier = 1.5
			var prop = preload("res://scenes/level_prop.tscn").instantiate()
			prop.kind_index = 1
			prop.display_size = Vector2(126,83)
			add_child(prop)
		"depot":
			game._entity("supply",global_position+Vector2(-30,0),{"kind":"ammo","amount":12})
			game._entity("supply",global_position+Vector2(45,0),{"kind":"sand","amount":24})
		"core_room":
			game.core.max_hp += 150.0
			game.core.hp += 150.0
	preload("res://scripts/spatial_sound.gd").emit(game,"produce",interaction_point())
	game.notify(LocaleText.format("%s fertig · %s", [SPECS[kind].name,SPECS[kind].benefit]))
	game.fx(global_position-Vector2(0,40),Art.AMBER,15)
	queue_redraw()

func _draw() -> void:
	if not excavated():
		# Survey paint on the rock face; a finished room never appears before its
		# own excavation. The actual solid terrain is drawn by independent cells.
		Art.text(self,Vector2(-93,-156),SPECS[kind].name,10,Color("b6a07a"))
		Art.text(self,Vector2(-93,-143),LocaleText.text("AUSHUB / ERDE FREILEGEN"),9,Color("948a6e"))
		return
	_draw_chamber()
	if built and is_instance_valid(lining) and lining.tier>0:
		Art.text(self,Vector2(-82,-159),SPECS[kind].name,11,Color("979985"))
	if not built:
		for x in range(-87,88,18):
			draw_line(Vector2(x,-8),Vector2(x+9,-2),Color("a3955e"),4)
		# A carpenter's plan stand, unpacked reinforcement and material stacks.
		# It is a world object; only the selected site's HUD explains the controls.
		for x in [-24,24]:
			draw_line(Vector2(x,-55),Vector2(x*1.5,-4),Color("342e25"),6)
			draw_line(Vector2(x,-55),Vector2(x*1.5,-4),Color("8b7552"),2)
		draw_rect(Rect2(-40,-76,80,35),Color("302c24"))
		draw_rect(Rect2(-37,-73,74,29),Color("b9aa7e"))
		for x in range(-28,30,12):
			draw_line(Vector2(x,-70),Vector2(x,-48),Color("827f61"),1)
		for y in [-67,-59,-51]:
			draw_line(Vector2(-32,y),Vector2(30,y),Color("827f61"),1)
		draw_rect(Rect2(-17,-66,30,16),Color("4c5b4f"),false,2)
		draw_line(Vector2(-15,-64),Vector2(12,-52),Color("657364"),1)
		for i in 3:
			draw_rect(Rect2(-80+i*4,-17-i*7,29,9),Color("777d68"))
			draw_line(Vector2(-80+i*4,-17-i*7),Vector2(-53+i*4,-17-i*7),Color("b3b59a"),1)
		for i in 4:
			draw_line(Vector2(56+i*6,-4),Vector2(48+i*6,-51-i*4),Color("181f20"),4)
			draw_line(Vector2(55+i*6,-4),Vector2(47+i*6,-51-i*4),Color("8b7759"),1)
	elif kind == "core_room":
		draw_rect(Rect2(-57,-88,114,85),Art.INK)
		draw_rect(Rect2(-53,-84,106,78),Color("62746c"))
		for x in [-40,-15,10,35]:
			draw_rect(Rect2(x,-73,15,54),Color("26322e"))
			for y in range(-67,-22,9):
				draw_rect(Rect2(x+3,y,8,3),Color("969d7b"))
		Art.text(self,Vector2(-37,-3),LocaleText.text("KERN +150"),11,Color("c2c29c"))

func _draw_chamber() -> void:
	# Excavated bays stay part of one continuous floor. Concrete lining is a
	# separate paid structure, using exactly the upstairs architectural renderer.
	if not is_instance_valid(lining) or (lining.tier==0 and lining.curing_remaining<=0):
		for x in range(-103,106,19):
			draw_colored_polygon(PackedVector2Array([Vector2(x,-188),Vector2(x+17,-188),Vector2(x+11,-177-posmod(x,9)),Vector2(x+2,-182)]),Color("343e31"))
	draw_rect(Rect2(-98,-8,197,8),Color(0.01,0.02,0.01,0.32))
