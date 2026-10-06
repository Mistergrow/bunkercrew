class_name RecipeStation
extends ProductionStation
## Stations with one dedicated buffer per required ingredient. A batch owns its
## inputs from start to finish; completed output blocks further deposits.

var ingredient_amounts: Dictionary = {}

func amount_for(resource: String) -> int:
	return input_amount if resource == input_kind() else int(ingredient_amounts.get(resource, 0))

func set_amount(resource: String, amount: int) -> void:
	if resource == input_kind():
		input_amount = amount
	else:
		ingredient_amounts[resource] = amount

func _process(delta: float) -> void:
	elapsed += delta
	if working:
		production_time += delta
		if production_time >= duration():
			working = false
			production_time = 0.0
			output_amount += int(recipe().amount)
			_finish_batch_credit()
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"produce",global_position)
				game.fx(global_position + Vector2(51, -21), Balance.RESOURCE_COLORS[output_kind()], 8)
	if not working and output_amount == 0 and _inputs_ready():
		for resource: String in recipe().inputs:
			set_amount(resource, amount_for(resource) - input_cost(resource))
		working = true
		production_time = 0.0
	queue_redraw()

func _inputs_ready() -> bool:
	for resource: String in recipe().inputs:
		if amount_for(resource) < input_cost(resource):
			return false
	return true

func _needed_material(player) -> String:
	var choices := input_kinds()
	if player.has_method("selected_material"):
		var selected: String = player.selected_material()
		if choices.has(selected):
			choices.erase(selected)
			choices.push_front(selected)
	for resource: String in choices:
		if amount_for(resource) < input_cost(resource) and int(player.inventory.get(resource, 0)) > 0:
			return resource
	return ""

func interact(player, delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or not is_instance_valid(player) or working:
		return
	var resource := _needed_material(player)
	if output_amount > 0:
		if player.carried_count() >= Balance.capacity_for(player):
			return
	elif resource.is_empty():
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
		set_amount(resource, amount_for(resource) + 1)
		_record_input(player)
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"pickup",global_position)
	queue_redraw()

func input_status() -> String:
	var parts := PackedStringArray()
	for resource: String in recipe().inputs:
		parts.append(LocaleText.format("%s %d/%d", [Balance.RESOURCE_NAMES[resource], amount_for(resource), input_cost(resource)]))
	return " · ".join(parts)

func _has_usable_input(player) -> bool:
	return not _needed_material(player).is_empty()

func world_status() -> String:
	if working or output_amount > 0:
		return super.world_status()
	var supplied := 0
	var required := 0
	for resource: String in recipe().inputs:
		supplied += amount_for(resource)
		required += input_cost(resource)
	return LocaleText.format("Material %d/%d", [supplied, required])
