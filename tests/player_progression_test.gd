extends SceneTree
## Real workers, finite XP/skills, actual damage reduction and projectile ownership.
class GameProbe extends Node2D:
	var started := false
	var upgrades
	func sound(_kind): pass
	func fx(_pos,_color,_amount): pass
	func notify(_text): pass

var checks := 0
var failures := 0
var events: Array = []
func _initialize(): call_deferred("run")
func check(value: bool,label: String):
	checks += 1
	if value: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func make_worker(game: Node,id: int,character: String):
	var worker = load("res://scenes/player.tscn").instantiate()
	worker.game = game
	worker.player_id = id
	worker.character_id = character
	game.add_child(worker)
	worker.set_physics_process(false)
	worker.get_node("WorkerWeapon").set_physics_process(false)
	worker.progression.set_physics_process(false)
	return worker
func run():
	InputSetup.install()
	var game := GameProbe.new()
	root.add_child(game)
	var p1 = make_worker(game,1,"mara")
	var p2 = make_worker(game,2,"branko")
	var progress: PlayerProgression = p1.progression
	progress.event.connect(func(kind,data): events.append([kind,data]))
	check(CharacterCatalog.CHARACTERS.size()==8,"Eight individually selectable workers use a shared capability set")
	check(p1.hp==100 and p1.capacity()==6 and p1.work_multiplier()==1.0,"Default worker preserves existing health, carry and work balance")
	check(p2.hp==125 and p2.capacity()==7 and is_equal_approx(p2.movement_multiplier(),0.9),"Heavy worker has real health/cargo advantages and movement cost")
	check(p1.configure_character("ivo") and p1.hp==90 and p1.work_multiplier()>1.17 and p1.damage_multiplier()<1.0,"Fast worker's actual construction and weapon modifiers have a tradeoff")
	check(not p1.configure_character("invalid") and p1.character_id=="ivo","Invalid selection does not change a worker")
	p1.configure_character("mara")
	game.started = true
	check(not p1.configure_character("branko") and p1.hp==100,"Started rounds cannot reset health through character selection")
	var copy := CharacterCatalog.data("mara")
	copy.hp = 900
	check(CharacterCatalog.data("mara").hp==100,"Catalog callers cannot mutate the shared character definitions")
	check(not progress.purchase_skill("combat") and not progress.purchase_skill("unknown"),"No personal upgrade can be purchased without a valid skill point")
	progress.award_damage(-12)
	progress.award_damage(INF)
	progress.award_damage(NAN)
	check(progress.xp==0 and progress.level==1,"Negative and non-finite damage cannot grant XP")
	for i in 10: progress.award_damage(0.5)
	check(is_equal_approx(progress.xp,0.5),"Small pellet damage accumulates fractional XP without a per-hit minimum")
	progress.xp = 0
	p1.take_damage(20)
	progress.award_damage(500)
	check(progress.level==2 and progress.xp==0 and progress.skill_points==1,"Crossing the real XP threshold grants one level and exactly one skill point")
	check(p1.max_hp==110 and p1.hp==90,"Level health increases preserve the worker's existing 20-HP injury")
	check(p2.max_hp==125 and p2.progression.level==1 and p2.progression.xp==0,"Local partner health and progression remain independent")
	check(progress.purchase_skill("vitality") and p1.max_hp==125 and p1.hp==105 and progress.skill_points==0,"Paid vitality adds 15 max HP and preserves the injury deficit")
	check(not progress.purchase_skill("vitality") and p1.max_hp==125,"Repeated upgrade input cannot buy an unpaid rank")
	check(not progress.equip_armor(2) and not progress.equip_armor(-1),"Armor cannot skip its first tier or accept invalid tiers")
	check(progress.equip_armor(1) and not progress.equip_armor(1),"Crafted first-tier armor can be equipped only once")
	p1.hp = p1.max_hp
	p1.invulnerability = 0
	check(is_equal_approx(p1.take_damage(40),32) and p1.hp==93,"First-tier plates reduce actual enemy damage by twenty percent")
	check(progress.equip_armor(2) and not progress.equip_armor(3),"Second-tier armor is the final valid sequential upgrade")
	p1.invulnerability = 0
	check(is_equal_approx(p1.take_damage(40),26) and p1.hp==67,"Second-tier plates reduce actual damage by thirty-five percent")
	progress.award_kill()
	var first_xp: float = progress.xp
	check(progress.kills==1 and progress.combo==1 and progress.combo_time==5.0,"A credited kill starts the five-second personal combo window")
	progress.award_kill()
	check(progress.combo==2 and progress.xp>first_xp+14,"Chained kills produce a bounded real XP bonus")
	for i in 15: progress.award_kill()
	check(progress.combo==PlayerProgression.MAX_COMBO and progress.kills==17,"Long combos keep exact kill totals and cap the reward multiplier")
	progress._physics_process(5.1)
	check(progress.combo==0 and progress.combo_time==0,"Combo expires after five gameplay seconds without a kill")
	progress.award_kill()
	check(progress.combo==1,"A kill after expiry begins a new chain")
	var weapon = p1.get_node("WorkerWeapon")
	weapon.loaded.rifle = 5
	weapon.reserve = 17
	p1.inventory = {"ore":2,"ammo":1}
	var cargo: Dictionary = p1.inventory.duplicate(true)
	var rounds: int = weapon.total_ammunition()
	p1.invulnerability = 0
	p1.take_damage(9999)
	var recovery: float = p1.down_time
	progress.award_damage(progress.xp_required()*10)
	check(p1.is_downed() and p1.hp==0 and p1.down_time==recovery,"XP earned by an in-flight shot cannot revive a KO worker or shorten recovery")
	check(progress.combo==0 and p1.inventory==cargo and weapon.total_ammunition()==rounds,"KO breaks the combo and preserves all cargo and finite ammunition")
	check(p1.medical.begin_or_continue_aid(p2,MedicalCatalog.REVIVE_TIME) and is_equal_approx(p1.hp,p1.max_hp*MedicalCatalog.REVIVE_HEALTH_RATIO) and p2.medical.charges==1 and progress.armor_tier==2 and p1.inventory==cargo and weapon.total_ammunition()==rounds,"Paid partner revival scales restored HP to the upgraded maximum while preserving armor and inventory")
	p1._update_health(MedicalCatalog.RECOVERY_TIME+0.01)
	p1.inventory.clear()
	progress.award_damage(10000000)
	check(progress.level==PlayerProgression.MAX_LEVEL and progress.xp==0,"Maximum level is finite and discards excess XP without overflow")
	var points: int = progress.skill_points
	for i in 5: check(progress.purchase_skill("combat"),"Each paid combat rank is available up to rank five")
	check(not progress.purchase_skill("combat") and progress.skill_points==points-5,"Rank cap prevents further point spending")
	check(is_equal_approx(p1.damage_multiplier(),1.3),"Five combat ranks increase actual personal weapon damage by thirty percent")
	for i in 2: progress.purchase_skill("engineering")
	check(p1.capacity()==7 and is_equal_approx(p1.work_multiplier(),1.16) and is_equal_approx(p1.movement_multiplier(),1.04),"Engineering improves real work, movement and limited cargo capacity")
	weapon.cooldown = 0
	weapon.aim_direction = Vector2.RIGHT
	check(weapon.fire(),"Upgraded recovered worker can fire the real handheld weapon")
	var shot: WorkerShot
	for child in game.get_children():
		if child is WorkerShot: shot = child
	check(is_instance_valid(shot) and shot.credit_worker==p1 and is_equal_approx(shot.damage,20.8),"Handheld bullet snapshots its actual firing worker and upgraded damage")
	var turret = load("res://scenes/turret.tscn").instantiate()
	turret.game = game
	turret.position = Vector2(400,200)
	game.add_child(turret)
	turret.set_physics_process(false)
	turret.enter(p1)
	check(turret.fire(),"Upgraded worker can fire the real roof gun")
	var shell: BunkerProjectile
	for child in game.get_children():
		if child is BunkerProjectile: shell = child
	turret.exit()
	turret.enter(p2)
	check(is_instance_valid(shell) and shell.credit_worker==p1 and is_equal_approx(shell.damage,Balance.SHOT_DAMAGE*1.3),"Turret credit remains with the shooter after the local partner takes the controls")
	var has_level_event := false
	var has_hit_xp := false
	for item in events:
		if item[0]=="level_up" and item[1].player_id==1: has_level_event=true
		if item[0]=="hit" and is_equal_approx(item[1].xp,0.05): has_hit_xp=true
	check(has_level_event and has_hit_xp,"Presentation receives attributed level and exact earned-XP events")
	game.free()
	print("PERSONAL PROGRESSION: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
