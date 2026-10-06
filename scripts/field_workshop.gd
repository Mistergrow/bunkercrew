class_name FieldWorkshop
extends Node2D

const NetInput := preload("res://scripts/network_input.gd")
const EquipmentArt := preload("res://scripts/support_equipment_art.gd")
## A paid, personal work order per recipe. Switching blueprints never discards
## deposits; another worker cannot collect or equip the first worker's order.

static var RECIPES: Array[Dictionary]:
	get: return CraftingCatalog.recipes()
const KITS := ["jaw_trap", "blast_trap", "sentry_kit"]
const MAX_DEFENSES := 12
var game: Node
var selection: Dictionary = {}
var orders: Dictionary = {}
var elapsed := 0.0

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("field_workshops")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 4

func recipe_index(player: Node) -> int:
	return maxi(0,CraftingCatalog.index(selection.get(player.player_id,0)))

func recipe_for(player: Node) -> Dictionary:
	return RECIPES[recipe_index(player)]

func order_for(player: Node, index: int = -1) -> Dictionary:
	if index < 0:
		index = recipe_index(player)
	var key := _stored_order_key(player.player_id,index)
	if not orders.has(key):
		orders[key] = {"materials":{}, "transfer":0.0, "remaining":0.0, "working":false, "ready":false, "recipe":index, "recipe_id":CraftingCatalog.id(index), "owner":player.player_id}
	return orders[key]

func _stored_order_key(owner_id: int,index: int) -> String:
	var key := CraftingCatalog.order_key(owner_id,index)
	var legacy := "%d:%d" % [owner_id,index]
	# Older snapshots with an explicit matching recipe ID can retain their
	# numeric key; read it instead of creating a second empty paid order.
	if not orders.has(key) and orders.has(legacy) and orders[legacy].get("recipe_id")==CraftingCatalog.id(index): return legacy
	return key

func cycle_recipe(player: Node) -> void:
	# Compatibility API for older integrations. The player UI selects explicitly.
	selection[player.player_id] = (recipe_index(player)+1)%RECIPES.size()
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"interact",global_position)
	queue_redraw()

func _process(delta: float) -> void:
	refresh_access()
	elapsed += delta
	for order: Dictionary in orders.values():
		if order.working:
			order.remaining = maxf(0.0,float(order.remaining)-delta)
			if order.remaining <= 0.0:
				order.working = false
				order.ready = true
				if is_instance_valid(game):
					preload("res://scripts/spatial_sound.gd").emit(game,"produce",global_position)
	queue_redraw()

func accessible() -> bool:
	if not is_instance_valid(game): return false
	var bunker: Node = game.get("scenario_bunker") if "scenario_bunker" in game else null
	if not is_instance_valid(bunker):
		var expansion: Node = game.get("expansion") if "expansion" in game else null
		if not is_instance_valid(expansion): return true
		for site in expansion.modules:
			if is_instance_valid(site) and site.kind == "ammo_press": return is_instance_valid(site.excavation) and site.excavation.is_cleared()
		return false
	return not bunker.fields.is_empty() and is_instance_valid(bunker.fields[0]) and bunker.fields[0].is_cleared()

func refresh_access() -> void:
	visible = accessible()

func can_interact(player: Node) -> bool:
	return accessible() and is_instance_valid(player) and (not player.has_method("can_act") or player.can_act())

func order_view(player: Node,index: int) -> Dictionary:
	return orders.get(_stored_order_key(player.player_id,index), {"materials":{},"remaining":0.0,"working":false,"ready":false})

func request(player: Node,action_name: String,reference: Variant) -> bool:
	# Menu commands never trust a submitted owner, position or material count.
	var index := CraftingCatalog.index(reference)
	if index < 0 or action_name not in ["supply","collect"] or not can_interact(player): return false
	if "game" in player and player.game != game: return false
	if game.has_method("valid_focus") and not game.valid_focus(player,self): return false
	if not game.has_method("valid_focus") and (player.global_position-Vector2(0,20)).distance_to(interaction_point())>83.0: return false
	var network = NetInput.for_game(game)
	if network != null and not network.is_host: return false
	selection[player.player_id] = index
	var order := order_for(player)
	if order.working or not recipe_lock(player).is_empty(): return false
	if action_name == "collect":
		if not order.ready: return false
		interact(player,Balance.TRANSFER_TIME)
		return not order.ready
	if order.ready: return false
	var changed := false
	# One explicit confirmation supplies only the materials still owed by this
	# personal order. Partial payments survive changing plans and reopening.
	for kind: String in RECIPES[index].cost:
		var needed := maxi(0,int(RECIPES[index].cost[kind])-int(order.materials.get(kind,0)))
		var amount := mini(needed,int(player.inventory.get(kind,0)))
		if amount>0 and player.take_item(kind,amount):
			order.materials[kind] = int(order.materials.get(kind,0))+amount
			changed = true
	if not changed: return false
	var paid := true
	for kind: String in RECIPES[index].cost:
		paid = paid and int(order.materials.get(kind,0))>=int(RECIPES[index].cost[kind])
	order.transfer = 0.0
	if paid:
		order.working = true
		order.remaining = RECIPES[index].time
	preload("res://scripts/spatial_sound.gd").emit(game,"interact",global_position)
	queue_redraw()
	return true

func interaction_point() -> Vector2:
	return global_position-Vector2(0,26)

func opens_action_menu() -> bool:
	return true

func open_action_menu(player: Node) -> void:
	if is_instance_valid(game) and "hud" in game and is_instance_valid(game.hud) and game.hud.has_method("open_crafting"):
		game.hud.open_crafting(player,self)

func armor_tier(player: Node) -> int:
	return int(player.progression.armor_tier) if "progression" in player and is_instance_valid(player.progression) else 0

func recipe_lock(player: Node,index: int = -1) -> String:
	var recipe: Dictionary = RECIPES[index] if index >= 0 and index < RECIPES.size() else recipe_for(player)
	if not recipe.has("armor"):
		return ""
	if not "progression" in player or not is_instance_valid(player.progression):
		return LocaleText.text("Ausrüstung momentan nicht verfügbar")
	if armor_tier(player) >= int(recipe.armor):
		return LocaleText.text("Bereits ausgerüstet")
	if int(recipe.armor) > armor_tier(player)+1:
		return LocaleText.text("Zuerst Stahlweste I herstellen")
	return ""

func interaction_title() -> String:
	return LocaleText.text("Feldwerkbank")

func prompt(player: Node) -> String:
	var recipe := recipe_for(player)
	var order := order_for(player)
	var title := LocaleText.format("Feldwerkbank · P%d\nInteragieren: Baupläne und Fertigung öffnen",player.player_id)
	if order.ready:
		return LocaleText.format("%s\nAbholbereit · im Fertigungsmenü abholen",title)
	if order.working:
		return LocaleText.format("%s\nFertigung %.1f s · %s", [title,order.remaining,recipe.note])
	var locked := recipe_lock(player)
	if not locked.is_empty():
		return LocaleText.format("%s\n%s", [title,locked])
	var parts := PackedStringArray()
	for kind: String in recipe.cost:
		parts.append(LocaleText.format("%s %d/%d", [Balance.RESOURCE_NAMES.get(kind,kind),order.materials.get(kind,0),recipe.cost[kind]]))
	return LocaleText.format("%s\n%s · im Fertigungsmenü einbauen\n%s", [title," · ".join(parts),recipe.note])

func interaction_progress(player: Node) -> float:
	var order := order_for(player)
	if order.working:
		return 1.0-float(order.remaining)/float(recipe_for(player).time)
	if order.ready:
		return 1.0
	return float(order.transfer)/Balance.TRANSFER_TIME

func interact(player: Node, delta: float) -> void:
	if not is_instance_valid(player) or not is_finite(delta) or delta <= 0.0:
		return
	if player.has_method("can_act") and not player.can_act():
		return
	if not accessible(): return
	var recipe := recipe_for(player)
	var order := order_for(player)
	if order.working:
		return
	if not recipe_lock(player).is_empty():
		return
	if order.ready:
		if recipe.has("armor"):
			if not player.progression.equip_armor(int(recipe.armor)):
				return
		else:
			var amount := int(recipe.get("amount",1))
			if player.carried_count()+amount>Balance.capacity_for(player) or player.add_item(recipe.kind,amount) != amount:
				return
		order.ready = false
		order.materials.clear()
		order.transfer = 0.0
		if is_instance_valid(game):
			preload("res://scripts/spatial_sound.gd").emit(game,"produce",global_position)
			var message := "P%d: %s ausgerüstet" if recipe.has("armor") else "P%d: %s fertig · draußen mit B / Num. / Steuerkreuz rechts aufstellen" if KITS.has(recipe.kind) else "P%d: %s fertig"
			game.notify(LocaleText.format(message, [player.player_id,recipe.label]))
			if "combat_events" in game and is_instance_valid(game.combat_events):
				game.combat_events.record_craft(player,recipe.kind)
		return
	var needed := ""
	for kind: String in recipe.cost:
		if int(order.materials.get(kind,0)) < int(recipe.cost[kind]) and int(player.inventory.get(kind,0)) > 0:
			needed = kind
			break
	if needed.is_empty():
		return
	order.transfer = minf(Balance.TRANSFER_TIME,float(order.transfer)+maxf(delta,0.0))
	if float(order.transfer) < Balance.TRANSFER_TIME:
		return
	order.transfer = 0.0
	if not player.take_item(needed,1):
		return
	order.materials[needed] = int(order.materials.get(needed,0))+1
	var paid := true
	for kind: String in recipe.cost:
		paid = paid and int(order.materials.get(kind,0)) >= int(recipe.cost[kind])
	if paid:
		order.working = true
		order.remaining = recipe.time
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"interact",global_position)

func placement_point(player: Node2D, kind: String) -> Vector2:
	if not KITS.has(kind) or not is_instance_valid(game):
		return Vector2.INF
	var scenario := ScenarioCombat.for_game(game)
	var floor_y := scenario.ground_y if scenario != null else 430.0
	if absf(player.global_position.y-floor_y)>12.0 or (scenario == null and player.global_position.x<865.0):
		return Vector2.INF
	var width := 90.0 if kind == "sentry_kit" else 46.0
	var center_x := roundf(player.global_position.x+48.0*player.facing)
	var right_bound: float = game.world_right-100.0 if "world_right" in game else 1300.0
	if (scenario != null and not scenario.field_position_allowed(center_x,width*0.5)) or (scenario == null and (center_x<900.0 or center_x>right_bound)):
		return Vector2.INF
	var space := get_world_2d().direct_space_state
	for offset in [-width*0.5,0.0,width*0.5]:
		var ray := PhysicsRayQueryParameters2D.create(Vector2(center_x+offset,floor_y-20),Vector2(center_x+offset,floor_y+14),1)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y > -0.9 or absf(hit.position.y-floor_y)>2:
			return Vector2.INF
	var point := Vector2(center_x,floor_y)
	var box := RectangleShape2D.new()
	box.size = Vector2(width,62.0 if kind == "sentry_kit" else 24.0)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.transform = Transform2D(0,point-Vector2(0,box.size.y*0.5+1))
	query.collision_mask = 1|2|4
	if not space.intersect_shape(query,1).is_empty():
		return Vector2.INF
	var reach := PhysicsRayQueryParameters2D.create(player.global_position-Vector2(0,18),point-Vector2(0,18),1|2)
	if not space.intersect_ray(reach).is_empty():
		return Vector2.INF
	for defense in get_tree().get_nodes_in_group("field_defenses"):
		if not defense.is_queued_for_deletion() and defense.global_position.distance_to(point)<(width+defense.footprint_width())*0.5+18.0:
			return Vector2.INF
	if "ladders" in game:
		for ladder: Rect2 in game.ladders:
			if ladder.grow(18.0).has_point(point):
				return Vector2.INF
	return point

func deploy(player: Node2D) -> bool:
	if player.has_method("can_act") and not player.can_act():
		return false
	if is_instance_valid(player.mounted_turret):
		return false
	var kind: String = player.selected_material()
	if not KITS.has(kind) or int(player.inventory.get(kind,0)) <= 0:
		if is_instance_valid(game):
			game.notify(LocaleText.text("Bausatz mit Tab / Einfg / LB wählen · Werkbank im Bunker: Fallen und Feldgeschütz."))
		return false
	var point := placement_point(player,kind)
	if point == Vector2.INF or get_tree().get_nodes_in_group("field_defenses").size() >= MAX_DEFENSES:
		game.notify(LocaleText.text("Freien Boden vor dem Bunker wählen · Platz und Abstand zu Maschinen nötig · höchstens 12 Anlagen."))
		return false
	if not player.take_item(kind,1):
		return false
	var defense := preload("res://scripts/field_defense.gd").new()
	defense.game = game
	defense.kind = kind
	defense.builder = player
	defense.position = point
	game.add_child(defense)
	if "combat_events" in game and is_instance_valid(game.combat_events):
		game.combat_events.record_deploy(player,kind)
	preload("res://scripts/spatial_sound.gd").emit(game,"build",global_position)
	game.notify(LocaleText.text("Feldgeschütz bereit · E: bedienen · Munitionskiste mitnehmen und R: laden.") if kind=="sentry_kit" else LocaleText.text("Falle gesetzt · nach einer Sekunde scharf · trifft nur Maschinen."))
	return true

func _draw() -> void:
	var working := false
	for order: Dictionary in orders.values():
		working = working or bool(order.working)
	EquipmentArt.workshop(self,elapsed,working)
	# The focused action hint names the bench. A second floating title would
	# cross the service ladder and the neighboring core in the compact room.
	_draw_placement_previews()

func _draw_placement_previews() -> void:
	if not is_instance_valid(game) or not "players" in game:
		return
	for player in game.players:
		if not is_instance_valid(player) or not player.can_act() or is_instance_valid(player.mounted_turret):
			continue
		var kind: String = player.selected_material()
		var scenario := ScenarioCombat.for_game(game)
		var floor_y := scenario.ground_y if scenario != null else 430.0
		if not KITS.has(kind) or int(player.inventory.get(kind,0))<=0 or absf(player.global_position.y-floor_y)>32 or (scenario == null and player.global_position.x<835):
			continue
		var valid_point := placement_point(player,kind)
		var okay := valid_point!=Vector2.INF and get_tree().get_nodes_in_group("field_defenses").size()<MAX_DEFENSES
		var point := to_local(valid_point if okay else Vector2(roundf(player.global_position.x+48*player.facing),floor_y))
		var tint := Color("a8b976") if okay else Color("c65b47")
		var width := 90.0 if kind=="sentry_kit" else 46.0
		var height := 62.0 if kind=="sentry_kit" else 24.0
		draw_rect(Rect2(point-Vector2(width/2,height),Vector2(width,height)),Color(tint,0.075))
		for side in [-1.0,1.0]:
			var edge := point+Vector2(side*width/2,-2)
			draw_line(edge,edge+Vector2(-side*11,0),tint,2)
			draw_line(edge,edge-Vector2(0,9),tint,2)
		if kind=="sentry_kit":
			draw_line(point-Vector2(20,1),point-Vector2(0,39),Color(tint,0.7),2)
			draw_line(point+Vector2(20,-1),point-Vector2(0,39),Color(tint,0.7),2)
			draw_line(point-Vector2(15,39),point+Vector2(40,-42),Color(tint,0.7),4)
		elif kind=="jaw_trap":
			draw_line(point+Vector2(-19,-4),point+Vector2(-19,-18),Color(tint,0.7),3)
			draw_line(point+Vector2(19,-4),point+Vector2(19,-18),Color(tint,0.7),3)
		else:
			draw_rect(Rect2(point-Vector2(17,13),Vector2(34,10)),Color(tint,0.6),false,2)
		var label := LocaleText.text("B: SETZEN") if NetInput.mouse_aim(player) else LocaleText.text("Num. / →: SETZEN")
		# Place the hint above worker helmets; a ground-height caption would be
		# hidden by the carrying animation immediately beside the blueprint.
		UiArt.centered(self,point-Vector2(0,maxf(height,97.0)+10),label if okay else LocaleText.text("HIER KEIN PLATZ"),10,tint)
