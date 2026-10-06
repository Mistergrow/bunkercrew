extends SceneTree
class GameStub extends Node:
	var player_count = 1
	var total_spawns = 0
	func sound(_s): pass
	func notify(_s): pass
	func spawn_enemy(_wave):
		var enemy = Node.new()
		add_child(enemy)
		enemy.add_to_group("enemies")
		total_spawns += 1
var checks = 0
func check(value,message):
	if not value:
		push_error("FAILED: "+message)
		quit(1)
		return false
	checks += 1
	print("PASS ",message)
	return true
func _initialize(): call_deferred("run")
func clear_enemies():
	for enemy in get_nodes_in_group("enemies"):
		enemy.remove_from_group("enemies")
		enemy.queue_free()
func run():
	var game = GameStub.new()
	root.add_child(game)
	var rounds = load("res://scripts/round_controller.gd").new()
	rounds.game = game
	game.add_child(rounds)
	rounds.set_process(false)
	if not check(Balance.TOTAL_WAVES == 20 and Balance.BUILD_TIMES.size() == Balance.TOTAL_WAVES and Balance.WAVE_COUNTS.size() == Balance.TOTAL_WAVES,"All twenty waves have explicit construction times and enemy counts"): return
	rounds.start_round()
	if not check(rounds.phase == "build" and rounds.time_left == Balance.BUILD_TIMES[0],"Round begins with full first build pause"): return
	rounds._process(Balance.BUILD_TIMES[0])
	if not check(rounds.phase == "warning" and rounds.time_left == Balance.WARNING_TIME,"Build transitions to warning signal"): return
	rounds._process(Balance.WARNING_TIME)
	rounds._process(0.01)
	if not check(rounds.phase == "attack" and rounds.spawned == 1,"Warning transitions to actual enemy wave"): return
	rounds._process(1000)
	if not check(rounds.phase == "attack" and not get_nodes_in_group("enemies").is_empty(),"Living enemies never disappear on a wave timeout"): return
	for wave_index in range(1,Balance.TOTAL_WAVES+1):
		while rounds.spawned < rounds.wave_total:
			rounds._process(Balance.SPAWN_INTERVAL)
		clear_enemies()
		rounds._process(0.01)
		if wave_index < Balance.TOTAL_WAVES:
			if not check(rounds.phase == "salvage","Wave %d ends in salvage pause" % wave_index): return
			rounds._process(Balance.SALVAGE_TIME)
			if not check(rounds.phase == "build" and rounds.wave == wave_index+1,"Salvage transitions to next build pause"): return
			rounds.begin_warning()
			rounds._process(Balance.WARNING_TIME)
	var expected_spawns: int = Balance.WAVE_COUNTS.reduce(func(total, count): return total + count, 0)
	if not check(rounds.phase == "victory" and not rounds.running and game.total_spawns == expected_spawns,"Final cleared wave %d wins after exactly %d solo enemies" % [Balance.TOTAL_WAVES,expected_spawns]): return
	rounds.start_round(1)
	game.player_count = 2
	rounds._process(0.01)
	rounds.begin_warning()
	rounds._process(Balance.WARNING_TIME)
	var coop_total := int(ceil(Balance.WAVE_COUNTS[0] * Balance.wave_multiplier(2)))
	if not check(rounds.wave_total == coop_total,"Drop-in cooperative player scales the next wave from %d to %d" % [Balance.WAVE_COUNTS[0],coop_total]): return
	rounds.defeat()
	if not check(rounds.phase == "defeat" and not rounds.running,"Core defeat stops round"): return
	rounds.start_round(2)
	if not check(rounds.wave == 1 and rounds.phase == "build" and rounds.running,"Round controller resets into playable fresh round"): return
	print("ROUND CHECKS PASSED: ",checks)
	game.queue_free()
	await process_frame
	quit(0)
