class_name ProductionStation
extends Node2D
const FurnaceSurfaceArt := preload("res://scripts/station_surface_art.gd")
const ShaderEffects := preload("res://scripts/station_shader_effects.gd")
const MixerAnimation := preload("res://scripts/mixer_animation.gd")

@export var kind: String = "mixer"
var game
var input_amount: int = 0
var input_scrap: int = 0
var working_scrap: int = 0
var output_amount: int = 0
var binder: int = Balance.BINDER_STOCK
var working: bool = false
var production_time: float = 0.0
var elapsed: float = 0.0
var transfer: Dictionary = {}
var batch_donors: Dictionary = {}

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("stations")
	if kind == "mixer":
		var animation := MixerAnimation.new()
		animation.name = "MixerAnimation"
		add_child(animation)
	if ShaderEffects.SETTINGS.has(kind):
		var effects := ShaderEffects.new()
		effects.name = "MaterialEffects"
		add_child(effects)

func _process(delta: float) -> void:
	elapsed += delta
	if working:
		production_time += delta
		if production_time >= duration():
			working = false
			working_scrap = 0
			production_time = 0.0
			output_amount += int(recipe().amount)
			_finish_batch_credit()
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"produce",global_position)
				game.fx(global_position + Vector2(35, -22), Balance.RESOURCE_COLORS[output_kind()], 8)
	var binder_cost: int = recipe().get("binder", 0)
	if not working and input_amount >= input_cost(input_kind()) and output_amount == 0 and binder >= binder_cost:
		working_scrap = mini(input_scrap,input_cost(input_kind()))
		input_scrap -= working_scrap
		input_amount -= input_cost(input_kind())
		binder -= binder_cost
		working = true
		production_time = 0.0
	queue_redraw()

func duration() -> float:
	var multiplier: float = game.upgrades.production_multiplier() if is_instance_valid(game) and "upgrades" in game and is_instance_valid(game.upgrades) else 1.0
	return float(recipe().time) * multiplier

func recipe() -> Dictionary:
	return Balance.RECIPES[kind]

func input_cost(resource: String) -> int:
	return int(recipe().inputs.get(resource, 0))

func input_kind() -> String:
	return str(recipe().inputs.keys()[0])

func input_kinds() -> Array[String]:
	var result: Array[String] = []
	for resource: String in recipe().inputs:
		result.append(resource)
	for alternate: String in recipe().get("alternates", {}):
		result.append(alternate)
	return result

func output_kind() -> String:
	return str(recipe().output)

func interaction_point() -> Vector2:
	return global_position + Vector2(0, -27)

func can_interact(_player) -> bool:
	return true

func interaction_title() -> String:
	return LocaleText.text(str(recipe().label))

func recipe_text() -> String:
	var parts := PackedStringArray()
	for resource: String in recipe().inputs:
		var ingredient := Balance.resource_quantity(resource, input_cost(resource))
		for alternate: String in recipe().get("alternates", {}):
			if recipe().alternates[alternate] == resource:
				ingredient = LocaleText.format("%s oder %s", [ingredient,Balance.RESOURCE_NAMES[alternate]])
		parts.append(ingredient)
	if int(recipe().get("binder", 0)) > 0:
		parts.append(LocaleText.text("Bindemittel"))
	return LocaleText.format("%s → %s", [" + ".join(parts), Balance.resource_quantity(output_kind(), int(recipe().amount))])

func input_status() -> String:
	var ingredient: String = LocaleText.text(Balance.RESOURCE_NAMES[input_kind()])
	for alternate: String in recipe().get("alternates", {}):
		ingredient += " / " + LocaleText.text(str(Balance.RESOURCE_NAMES[alternate]))
	var status := LocaleText.format("%s %d/%d", [ingredient, input_amount, input_cost(input_kind())])
	if int(recipe().get("binder", 0)) > 0:
		status += LocaleText.format(" · Bindemittel %d", binder)
	return status

func _has_usable_input(player) -> bool:
	for resource: String in input_kinds():
		if int(player.inventory.get(resource, 0)) > 0:
			return true
	return false

func action_hint(player) -> String:
	if output_amount > 0:
		return LocaleText.text("Inventar voll") if player.carried_count() >= Balance.capacity_for(player) else LocaleText.format("%s abholen", Balance.RESOURCE_NAMES[output_kind()])
	if working:
		return LocaleText.text("Herstellung läuft")
	if binder < int(recipe().get("binder", 0)):
		return LocaleText.text("Bindemittel aufgebraucht")
	return LocaleText.text("Material einfüllen") if _has_usable_input(player) else LocaleText.text("Material mitbringen")

func prompt(player) -> String:
	var heading := interaction_title() + "\n"
	if output_amount > 0:
		var collection_hint := LocaleText.text("Inventar voll · erst Material abgeben") if player.carried_count() >= Balance.capacity_for(player) else LocaleText.text("Halten: abholen")
		return heading + LocaleText.format("%s abholbereit\n%s", [Balance.resource_quantity(output_kind(), output_amount), collection_hint])
	if working:
		return heading + LocaleText.format("Herstellung · noch %.1f s\n%s", [maxf(0, duration() - production_time), recipe_text()])
	if binder < int(recipe().get("binder", 0)):
		return heading + LocaleText.format("Bindemittel aufgebraucht\nHerstellung nicht möglich · %s", input_status())
	var instruction := LocaleText.text("Halten: Material einfüllen") if _has_usable_input(player) else LocaleText.text("Benötigtes Material mitbringen")
	return heading + LocaleText.format("%s\n%s\n%s", [recipe_text(), input_status(), instruction])

func world_status() -> String:
	if working:
		return LocaleText.format("Herstellung · %.1f s", maxf(0, duration() - production_time))
	if output_amount > 0:
		return LocaleText.format("%s ×%d bereit", [Balance.RESOURCE_NAMES[output_kind()], output_amount])
	if binder < int(recipe().get("binder", 0)):
		return LocaleText.text("Bindemittel leer")
	return LocaleText.format("Material %d/%d", [input_amount, input_cost(input_kind())])

func world_status_color() -> Color:
	if output_amount > 0:
		return Art.CYAN
	return Art.AMBER if working else Art.MUTED

func interaction_progress(player) -> float:
	if working:
		return production_time / duration()
	return float(transfer.get(player.get_instance_id(), 0.0)) / Balance.TRANSFER_TIME

func interact(player, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or not is_instance_valid(player) or working:
		return
	# Finished goods remain collectible after the final binder is spent, but
	# accepting another input would strand it in a machine that cannot restart.
	if output_amount == 0 and binder < int(recipe().get("binder",0)):
		return
	var resource: String = input_kind()
	if int(player.inventory.get(resource, 0)) <= 0:
		for alternate: String in recipe().get("alternates", {}):
			if int(player.inventory.get(alternate, 0)) > 0:
				resource = alternate
				break
	if output_amount > 0 and player.carried_count() >= Balance.capacity_for(player):
		return
	if output_amount == 0 and (input_amount >= input_cost(input_kind()) or int(player.inventory.get(resource, 0)) <= 0):
		return
	var id: int = player.get_instance_id()
	transfer[id] = float(transfer.get(id, 0.0)) + delta
	if transfer[id] < Balance.TRANSFER_TIME:
		return
	transfer[id] = 0.0
	if output_amount > 0:
		var collected: int = player.add_item(output_kind(), 1)
		output_amount -= collected
		if collected>0: _activity(player)
	elif player.take_item(resource, 1):
		input_amount += 1
		if kind == "furnace" and resource == "scrap":
			input_scrap += 1
		_record_input(player)
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"pickup",global_position)

func _draw() -> void:
	if kind == "mixer":
		_draw_mixer()
	else:
		_draw_furnace()
	UiArt.world_label(self, Vector2(0, -126 if kind == "mixer" else -137), interaction_title(), world_status(), world_status_color())
	if working:
		Art.bar(self, Rect2(-43, -105, 86, 3), production_time / duration(), Art.AMBER)
	if output_amount > 0:
		_draw_ready_output()

func _draw_ready_output() -> void:
	# These are still the machine's finite output buffer, not extra pickups.
	# Share the actual item silhouette with carrying and Q-drops; the focused
	# quantity text remains authoritative when more than two units await pickup.
	var first_x := 64.0 if kind == "mixer" else 80.0
	for index in mini(output_amount,2):
		PickupArt.draw_world(self,output_kind(),0,Vector2(first_x+index*26.0,0))

func _draw_mixer() -> void:
	draw_rect(Rect2(-58,-4,115,6),Color(0,0,0,0.36))
	MachineryArt.paint(self,"mixer_frame",Rect2(-58,-72,110,73))

func _draw_furnace() -> void:
	draw_rect(Rect2(-59,-3,124,5),Color(0,0,0,0.38))
	FurnaceSurfaceArt.exhaust(self, PackedVector2Array([Vector2(-10,-113),Vector2(15,-113)]), elapsed, working)
	MachineryArt.paint(self,"furnace",Rect2(-58,-112,124,111))
	FurnaceSurfaceArt.firebox(self, Rect2(-19,-45,39,24), elapsed, working)
	draw_line(Vector2(-19,-21),Vector2(20,-21),Color("876945"),2)

func _activity(player: Node) -> void:
	var events = game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(events) and events.has_method("record_activity"): events.record_activity(player)

func _record_input(player: Node) -> void:
	_activity(player)
	batch_donors[player.get_instance_id()] = weakref(player)

func _finish_batch_credit() -> void:
	var events = game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(events) and events.has_method("record_role") and not batch_donors.is_empty():
		var share := 4.0 / batch_donors.size()
		for donor: WeakRef in batch_donors.values():
			var player = donor.get_ref()
			if is_instance_valid(player): events.record_role(player,"production",share)
	batch_donors.clear()
