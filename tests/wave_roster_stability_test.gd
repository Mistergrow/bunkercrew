extends SceneTree
class World extends Node:
	var player_count := 1
	var bosses := 0
	var spawned_totals: Array[int] = []
	func sound(_kind): pass
	func notify(_text): pass
	func unlock_depth(): pass
	func spawn_enemy(wave, index, total):
		spawned_totals.append(total)
		if wave == 20 and index == total-1: bosses += 1
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run():
	for transition in [[1,2,11],[1,2,12],[2,1,14],[2,4,5],[4,1,12]]:
		var world := World.new()
		root.add_child(world)
		world.player_count = transition[0]
		var controller := ShiftRoundController.new()
		controller.game = world
		world.add_child(controller)
		controller.set_process(false)
		var living := Node.new()
		world.add_child(living)
		living.add_to_group("enemies")
		controller.start_round(world.player_count)
		controller.wave = 20
		controller._begin_attack()
		var total := controller.wave_total
		for i in transition[2]: controller._process(10)
		world.player_count = transition[1]
		while controller.spawned<total: controller._process(10)
		controller._process(10)
		check(controller.wave_total==total and world.spawned_totals.size()==total,"Crew changes keep the attack roster fixed")
		check(world.bosses==1,"Exactly one final boss spawns before or after a crew change")
		check(controller.running and controller.phase=="attack","Living enemies prevent premature final victory")
		check(world.spawned_totals.all(func(value): return value==total),"Every spawn uses the same roster signature")
		living.free()
		controller._process(0)
		check(controller.phase=="victory","Clearing the fixed final roster permits victory")
		controller.start_round(world.player_count)
		controller._begin_attack()
		check(controller.wave_total==ceili(Balance.WAVE_COUNTS[0]*Balance.wave_multiplier(world.player_count)),"Next attack scales to the current crew")
		world.free()
	print("WAVE ROSTER STABILITY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
