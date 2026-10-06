extends SceneTree
## Real workers, station batches, repairs and ammunition with host-only rewards.
class Session extends Node:
	var active := false
	var is_host := true
	var connected := 4
	func connected_player_count() -> int: return connected
	func is_player_connected(id: int) -> bool: return id>=1 and id<=connected
class JourneyGate extends Node:
	var stage := "preparation"
	func outpost_pending() -> bool: return false
class Lab extends Node2D:
	var started := true
	var player_count := 4
	var players: Array = []
	var network := Session.new()
	var combat_events: CombatEvents
	var rounds: ShiftRoundController
	var upgrades: UpgradeSystem
	var core: BunkerCore
	var expedition: Node
	var spawns := 0
	func sound(_kind): pass
	func fx(_at,_color,_count): pass
	func notify(_message): pass
	func spawn_pickup(_kind,_count,_at): pass
	func on_core_destroyed(): pass
	func spawn_enemy(_wave): spawns+=1
var checks := 0
var failures := 0
var game: Lab
var crew: Array=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	print("TEAM %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func reset_rewards(count: int) -> void:
	game.players=crew.slice(0,count)
	game.player_count=count
	game.combat_events.team=TeamProgression.new()
	game.combat_events.team.game=game
	for worker in crew:
		worker.progression.level=1
		worker.progression.xp=0.0
		worker.progression.kills=0
		worker.progression.break_combo()
		if worker in game.players: game.combat_events.record_activity(worker)
func xp_total(worker: Node) -> float:
	var total: float=worker.progression.xp
	for level in range(1,worker.progression.level): total+=50+(level-1)*25
	return total
func run() -> void:
	InputSetup.install()
	game=Lab.new()
	root.add_child(game)
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.add_child(game.network)
	game.rounds=ShiftRoundController.new()
	game.rounds.game=game
	game.add_child(game.rounds)
	game.upgrades=UpgradeSystem.new()
	game.upgrades.game=game
	game.add_child(game.upgrades)
	game.combat_events=CombatEvents.new()
	game.combat_events.game=game
	game.add_child(game.combat_events)
	game.combat_events.persistence_enabled=false
	for index in 4:
		var worker=load("res://scenes/player.tscn").instantiate()
		worker.game=game
		worker.player_id=index+1
		worker.character_id="mara"
		game.add_child(worker)
		crew.append(worker)
		game.players.append(worker)
		game.combat_events.track_player(worker)
	var target:=Node2D.new()
	game.add_child(target)
	for count in range(1,5):
		reset_rewards(count)
		game.combat_events.credit_hit(target,100.0,crew[0],true,Vector2.ZERO)
		var total:=0.0
		for worker in game.players:
			total+=xp_total(worker)
			check(is_equal_approx(xp_total(worker),24.0*(1+.35*(count-1))/count),"%d crew: combat pool is equal for gunner and support P%d" % [count,worker.player_id])
		check(is_equal_approx(total,24.0*(1+.35*(count-1))),"%d crew: bounded total combat XP, no per-client multiplication" % count)
		check(crew[0].progression.kills==1 and crew[1].progression.kills==0,"%d crew: only actual killer owns kill counter" % count)
		game.rounds.start_round(count)
		game.rounds._begin_attack()
		check(game.rounds.wave_total==ceili(4*Balance.wave_multiplier(count)),"%d crew: actual round spawn budget scales" % count)
		for scene in ["enemy","ground_infantry","air_enemy"]:
			var path: String="res://scenes/%s.tscn" % scene
			var enemy=load(path).instantiate()
			enemy.game=game
			enemy.wave=1
			if scene=="ground_infantry": enemy.kind="rifle_guard"
			game.add_child(enemy)
			check(is_equal_approx(enemy.max_hp,float(enemy.profile.hp)*EnemyCatalog.hp_scale(1)*Balance.enemy_hp_multiplier(count)),"%d crew: real %s gets small spawn HP multiplier" % [count,scene])
			if scene!="air_enemy": check(is_equal_approx(enemy.attack_damage,float(enemy.profile.damage)*EnemyCatalog.damage_scale(1)*Balance.enemy_damage_multiplier(count)),"%d crew: real %s damage scales modestly" % [count,scene])
			var original_hp: float=enemy.hp
			game.player_count=1
			check(enemy.hp==original_hp,"Crew changes never heal or resize existing enemy HP")
			enemy.free()
		var wave_reward:=ceili(12*Balance.wave_multiplier(count))*(90*Balance.enemy_hp_multiplier(count)*.1+14)*(1+.35*(count-1))/count
		check(wave_reward>=12*23 and wave_reward<=12*23*1.4,"%d crew: wave20 shared XP/person stays between solo and +40%% before roles" % count)
	reset_rewards(4)
	game.network.active=true
	game.network.connected=2
	game.rounds.wave=2
	game.rounds.spawned=2
	game.rounds.phase="attack"
	game.rounds.running=true
	game.rounds.spawn_clock=999
	# Crew changes update active-player pacing/rewards. An attack's fixed roster
	# retains the final boss index; only the next attack gets a new budget.
	game.rounds.wave_total=12
	game.rounds._process(.01)
	check(game.rounds.player_count==2 and game.rounds.wave_total==12,"Dropout updates active crew while preserving the current attack roster")
	game.network.connected=4
	game.rounds._process(.01)
	check(game.rounds.player_count==4 and game.rounds.wave_total==12,"Reconnect preserves the current attack roster and final boss index")
	game.rounds.spawned=11
	game.network.connected=1
	game.rounds._process(.01)
	check(game.rounds.player_count==1 and game.rounds.wave_total==12 and game.rounds.spawned==11,"Dropout preserves already spawned enemies and the final remaining roster slot")
	game.rounds._begin_attack()
	check(game.rounds.player_count==1 and game.rounds.wave_total==Balance.WAVE_COUNTS[game.rounds.wave-1],"The next attack uses the newly connected crew count")
	game.combat_events.credit_hit(target,10,crew[0],false,Vector2.ZERO)
	check(crew[0].progression.xp==1 and crew[1].progression.xp==0,"Disconnected crew neither dilute nor receive XP")
	game.network.is_host=false
	var before:=xp_total(crew[0])
	game.combat_events.credit_hit(target,90,crew[0],true,Vector2.ZERO)
	game.combat_events.record_role(crew[0],"repair",9)
	check(xp_total(crew[0])==before and crew[0].progression.kills==0,"Guests cannot award combat or role XP")
	game.network.active=false
	game.network.is_host=true
	reset_rewards(4)
	game.combat_events.team.advance(91)
	game.combat_events.record_activity(crew[1])
	game.combat_events.record_activity(crew[0])
	game.combat_events.credit_hit(target,10,crew[0],false,Vector2.ZERO)
	check(is_equal_approx(crew[0].progression.xp,.675) and is_equal_approx(crew[1].progression.xp,.675) and crew[2].progression.xp==0,"Useful support keeps full share while expired AFK crew receive none")
	game.combat_events.team.advance(91)
	game.combat_events.record_activity(crew[1])
	var idle_before:=xp_total(crew[0])
	var active_before:=xp_total(crew[1])
	game.combat_events.credit_hit(target,10,crew[0],false,Vector2.ZERO)
	check(xp_total(crew[0])==idle_before and xp_total(crew[1])==active_before+1,"Automated defenses cannot keep an AFK builder eligible; working crew still share real damage")
	check(game.combat_events.team.elapsed-float(game.combat_events.team.activity.get(crew[0].get_instance_id(),-1000))>90,"Passive kill attribution never refreshes participation")
	var personal_weapon=crew[0].get_node("WorkerWeapon")
	personal_weapon.loaded.rifle=3
	personal_weapon.cooldown=0
	check(personal_weapon.fire(),"Actual finite handweapon can renew activity after a long work break")
	check(game.combat_events.team.elapsed==float(game.combat_events.team.activity.get(crew[0].get_instance_id(),-1000)),"Manual shot renews participation only after ammunition consumption")
	paused=true
	var prior_clock: float=game.combat_events.team.elapsed
	game.combat_events.team.advance(1000)
	check(game.combat_events.team.elapsed==prior_clock,"Menus and pause cannot expire participating crew")
	paused=false
	reset_rewards(4)
	game.core=BunkerCore.new()
	game.core.game=game
	game.add_child(game.core)
	game.core.hp-=65
	crew[1].inventory={"steel":2}
	game.core.interact(crew[1],Balance.CORE_REPAIR_TIME)
	check(is_equal_approx(crew[1].progression.xp,3.9) and crew[1].inventory.steel==1,"Paid actual core repair rewards exactly useful65HP")
	game.core.interact(crew[1],Balance.CORE_REPAIR_TIME*100)
	check(is_equal_approx(crew[1].progression.xp,3.9) and crew[1].inventory.steel==1,"Full-core interaction spam grants neither XP nor material loss")
	game.core.hp-=1
	game.core.interact(crew[1],Balance.CORE_REPAIR_TIME)
	check(is_equal_approx(crew[1].progression.xp,3.96),"Overrepair rewards only the single missing HP")
	var station:=ProductionStation.new()
	station.game=game
	game.add_child(station)
	crew[0].inventory={"sand":1}
	crew[2].inventory={"sand":1}
	station.interact(crew[0],Balance.TRANSFER_TIME)
	station.interact(crew[2],Balance.TRANSFER_TIME)
	check(crew[0].progression.xp==0 and crew[2].progression.xp==0,"Deposits alone cannot mint production XP")
	station._process(.01)
	station._process(station.duration())
	check(station.output_amount==2 and crew[0].progression.xp==2 and crew[2].progression.xp==2,"One completed batch shares four XP among actual input suppliers")
	for repeat in 5: station._process(50)
	check(crew[0].progression.xp==2 and crew[2].progression.xp==2,"Completed output cannot be rewarded again while uncollected")
	station.interact(crew[0],Balance.TRANSFER_TIME)
	check(crew[0].progression.xp==2,"Collecting or moving finished goods cannot duplicate batch XP")
	var turret=load("res://scenes/turret.tscn").instantiate()
	turret.game=game
	game.add_child(turret)
	turret.enter(crew[3])
	turret.ammo=0
	crew[3].inventory={"ammo":1}
	check(turret.start_reload() and int(crew[3].inventory.get("ammo",0))==0 and crew[3].progression.xp==2,"Finite ammunition crate consumed by the real MG grants supply XP")
	check(not turret.start_reload() and crew[3].progression.xp==2,"Held reload cannot repeat supply credit")
	turret.exit()
	crew[0].hp=50
	crew[1].global_position=crew[0].global_position
	var medic_before:=xp_total(crew[1])
	check(crew[0].medical.begin_or_continue_aid(crew[1],MedicalCatalog.TREAT_TIME),"Actual paid teammate treatment completes")
	check(xp_total(crew[1])>medic_before and crew[1].medical.charges==1,"Medical role earns XP after actual healing and charge consumption")
	var paid: float=game.combat_events.record_role(crew[1],"repair",100000)
	check(paid>0 and game.combat_events.record_role(crew[1],"repair",100000)==0,"Useful-role XP has a finite per-wave ceiling")
	check(game.combat_events.record_role(crew[1],"repair",NAN)==0 and game.combat_events.record_role(crew[1],"repair",-1)==0 and game.combat_events.record_role(crew[1],"fake",9)==0,"Invalid role requests cannot mint XP")
	game.rounds.wave+=1
	check(game.combat_events.record_role(crew[1],"repair",1)==1,"The next real wave opens its own finite role allowance")
	var truck:=Node2D.new()
	game.add_child(truck)
	var driver_before:=xp_total(crew[0])
	game.expedition=JourneyGate.new()
	game.add_child(game.expedition)
	truck.position.x=60
	game.combat_events.record_drive(crew[0],truck,60)
	check(xp_total(crew[0])==driver_before,"Driving around a garage cannot farm journey XP")
	game.expedition.stage="travel"
	game.combat_events.record_drive(crew[0],truck,60)
	check(xp_total(crew[0])==driver_before+1,"Real new forward distance earns one XP per60pixels")
	var other_driver_before:=xp_total(crew[1])
	truck.position.x=0
	game.combat_events.record_drive(crew[0],truck,60)
	truck.position.x=60
	game.combat_events.record_drive(crew[1],truck,60)
	check(xp_total(crew[0])==driver_before+1 and xp_total(crew[1])==other_driver_before,"Reversing and retracing with another driver cannot farm travel XP")
	truck.position.x=2400
	game.combat_events.record_drive(crew[0],truck,2340)
	check(xp_total(crew[0])==driver_before+40,"Whole journey driving reward caps at40XP")
	truck.position.x=10000
	game.combat_events.record_drive(crew[0],truck,7600)
	check(xp_total(crew[0])==driver_before+40,"Extra driving beyond route length cannot mint XP")
	for id: String in ["convoy_handling","convoy_transmission","convoy_reload","convoy_stabilizer","convoy_support","convoy_blast_lining"]:
		check(CampaignCatalog.PERSISTENT_UPGRADES.has(id) and not game.upgrades.node_data(id).is_empty(),"New research persists with canonical catalog: "+id)
	var stats:=CampaignCatalog.vehicle_stats(CampaignCatalog.VEHICLE_UPGRADES)
	check(stats.speed==140 and stats.acceleration==250 and stats.braking==460 and stats.reload_time==1.05 and stats.mg_damage==21 and stats.repair_multiplier==1.3 and stats.damage_multiplier==.85,"All six added research effects expose exact executable values")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Role test tears down all actual scene nodes")
	print("TEAM PROGRESSION: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
