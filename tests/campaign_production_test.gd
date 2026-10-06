extends "res://tests/round_playthrough.gd"
## Prepared fixture regression: full ingredient bags must reach the real processor,
## rather than being dropped/recollected forever by the campaign logistics helper.

var failures := 0

func check(value: bool, message: String) -> bool:
	checks += 1
	if value: print("PASS ",message)
	else:
		failures += 1
		push_error(message)
	return value

func run() -> void:
	Engine.time_scale = 10.0
	game = create_game()
	game.rounds.set_process(false)
	gunner = game.players[0]
	quartermaster = Worker.new()
	quartermaster.game = game
	game.add_child(quartermaster)
	quartermaster.set_physics_process(false)
	quartermaster.inventory = {"tungsten":6}
	production = preload("res://tests/campaign_production.gd").new()
	production.setup(self)
	var alloy = game._entity("alloy_furnace",Vector2(810,800))
	var delta := Engine.time_scale / float(Engine.physics_ticks_per_second)
	var finished := false
	for i in 300:
		await physics_frame
		if production.ensure("alloy",1,delta):
			finished = true
			break
	print("Prepared full-input fixture: cargo=",quartermaster.inventory," buffered=",alloy.input_amount," output=",alloy.output_amount," inputs_paid=",production.ingredient_used)
	check(finished,"A full bag of required tungsten reaches alloy production without a collect/drop deadlock")
	check(production.ingredient_used.get("tungsten",0)==2 and production.ingredient_used.get("steel",0)==1 and stock_taken.get("steel",0)==1,"The helper pays exactly two carried tungsten and one finite supply steel for its batch")
	var tungsten := int(quartermaster.inventory.get("tungsten",0))
	for pickup in get_nodes_in_group("pickups"):
		if pickup.kind=="tungsten": tungsten+=pickup.amount
	check(tungsten==4 and alloy.output_amount+int(quartermaster.inventory.get("alloy",0))==2,"All excess ore and both alloy outputs remain accounted for")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("Campaign production helper: ",checks," checks")
	quit(0 if failures==0 else 1)
