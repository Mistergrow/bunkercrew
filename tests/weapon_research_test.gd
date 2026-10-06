extends SceneTree
## Paid research drives actual capacity, reloads, projectiles and finite stock.
class RoundState extends Node:
	var wave := 1
class SaveGate extends Node:
	var writable := true
	func commit_research() -> bool: return writable
class Lab extends Node2D:
	var started := false
	var upgrades: UpgradeSystem
	var rounds := RoundState.new()
	var expedition := SaveGate.new()
	var campaign: CampaignState
	func sound(_kind): pass
	func fx(_at,_color,_count): pass
	func notify(_text): pass
class Target extends StaticBody2D:
	var hp := 100.0
	var stagger := 0.0
	func _ready() -> void:
		collision_layer=4
		collision_mask=0
		add_to_group("enemies")
		var shape:=CollisionShape2D.new()
		var box:=RectangleShape2D.new()
		box.size=Vector2(12,36)
		shape.shape=box
		add_child(shape)
	func take_damage(amount: float) -> void: hp=maxf(0.0,hp-amount)
var checks:=0
var failures:=0
var game: Lab
var worker
var weapon
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("WEAPON RESEARCH %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)
func clear_shots() -> void:
	for child in game.get_children():
		if child is WorkerShot: child.free()
func shots() -> Array:
	return game.get_children().filter(func(child):return child is WorkerShot)
func load_weapon(kind: String) -> void:
	weapon.weapon_kind=kind
	weapon.cooldown=0
	weapon.reload_timer=0
	check(weapon.start_reload(),"Finite reserve starts real reload: "+kind)
	weapon._physics_process(3)
func run() -> void:
	InputSetup.install()
	game=Lab.new()
	root.add_child(game)
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.add_child(game.rounds)
	game.add_child(game.expedition)
	game.upgrades=UpgradeSystem.new()
	game.upgrades.game=game
	game.add_child(game.upgrades)
	worker=load("res://scenes/player.tscn").instantiate()
	worker.game=game
	worker.player_id=1
	game.add_child(worker)
	weapon=worker.get_node("WorkerWeapon")
	var original_ammo: int=weapon.total_ammunition()
	check(original_ammo==120 and weapon.magazine_size()==30,"Unresearched rifle retains30 loaded rounds and90 finite reserve")
	game.upgrades.points=100
	check(not game.upgrades.purchase("weapon_magazines"),"Magazine upgrade requires real weapon-handling parent")
	check(game.upgrades.purchase("weapon_handling"),"Existing shared20% damage research stays intact")
	check(not game.upgrades.purchase("weapon_magazines"),"Magazine upgrade respects wave2 gate")
	game.rounds.wave=2
	check(game.upgrades.purchase("weapon_magazines") and weapon.magazine_size()==36,"Paid research enlarges actual rifle magazine")
	check(weapon.current_ammo()==30 and weapon.total_ammunition()==original_ammo,"Buying capacity creates no loaded or reserve ammunition")
	check(not game.upgrades.purchase("weapon_bolt"),"Quick action respects its later wave4 gate")
	game.rounds.wave=10
	var points_before: int=game.upgrades.points
	game.expedition.writable=false
	check(not game.upgrades.purchase("weapon_bolt") and game.upgrades.points==points_before and not game.upgrades.has_upgrade("weapon_bolt"),"Save failure rolls back cost and executable reload benefit")
	check(is_equal_approx(weapon.reload_duration("rifle"),1.05),"Failed purchase leaves real reload timing unchanged")
	game.expedition.writable=true
	check(game.upgrades.purchase("weapon_bolt") and is_equal_approx(weapon.reload_duration("rifle"),1.05*.85),"Paid quick action shortens actual reload by15%")
	check(worker.configure_character("levin") and is_equal_approx(weapon.reload_duration("rifle"),1.05*.85*.85),"Character bonus and research multiply once each")
	worker.configure_character("mara")
	game.started=true
	load_weapon("rifle")
	check(weapon.current_ammo()==36 and weapon.reserve==84 and weapon.total_ammunition()==original_ammo,"Real extended-magazine reload moves exactly six existing rounds")
	check(game.upgrades.purchase("weapon_sights"),"Rifle sights purchase through their real prerequisite")
	weapon._shot_index=0
	weapon.cooldown=0
	weapon.aim_direction=Vector2.RIGHT
	var before_shot: int=weapon.total_ammunition()
	check(weapon.fire(),"Researched rifle fires actual projectile")
	var rifle: WorkerShot=shots()[0]
	check(is_equal_approx(rifle.direction.angle(),.012*.55*sin(2.31)),"Sights reduce actual launch spread by45%")
	check(is_equal_approx(rifle.damage,16*1.2) and weapon.total_ammunition()==before_shot-1,"Existing weapon damage still applies once and each shot remains finite")
	clear_shots()
	check(not game.upgrades.purchase("weapon_choke"),"Shotgun modification cannot bypass its weapon unlock")
	check(game.upgrades.purchase("shotgun") and game.upgrades.purchase("weapon_choke"),"Shotgun and its distinct cone upgrade purchase normally")
	load_weapon("shotgun")
	check(weapon.current_ammo()==8,"Extended shotgun capacity loads eight real rounds")
	before_shot=weapon.total_ammunition()
	weapon.aim_direction=Vector2.RIGHT
	weapon.cooldown=0
	check(weapon.fire() and shots().size()==8,"Real shotgun still produces eight pellets per finite shell")
	check(is_equal_approx(shots()[0].direction.angle(),-.15*.72) and is_equal_approx(shots()[-1].direction.angle(),.15*.72),"Choke changes the two physical cone edges rather than just its label")
	check(weapon.total_ammunition()==before_shot-1,"Pellet count never multiplies or creates ammunition")
	clear_shots()
	check(not game.upgrades.purchase("weapon_capacitor"),"Penetration upgrade requires arc weapon")
	check(game.upgrades.purchase("arcgun") and game.upgrades.purchase("weapon_capacitor"),"Arc weapon unlocks the paid penetration branch")
	load_weapon("arcgun")
	check(weapon.magazine_size()==16 and weapon.current_ammo()==16,"Arc capacity fits complete two-round discharges")
	weapon.cooldown=0
	weapon.aim_direction=Vector2.RIGHT
	check(weapon.fire() and shots()[0].remaining_hits==3,"Actual ordinary arc projectile can hit exactly three enemies")
	clear_shots()
	game.campaign=CampaignState.new("user://unused-weapon-research.json",false)
	game.campaign.active=true
	game.campaign.expedition.epic_weapons=["storm_arcgun","veteran_rifle","breacher_shotgun"]
	load_weapon("storm_arcgun")
	check(weapon.magazine_size()==12 and weapon.current_ammo()==12,"Rare arc capacity fits four complete three-round discharges")
	weapon.cooldown=0
	weapon.aim_direction=Vector2.RIGHT
	check(weapon.fire() and shots()[0].remaining_hits==4,"Actual rare arc projectile gains one bounded additional penetration")
	var bolt: WorkerShot=shots()[0]
	bolt.position=Vector2(500,300)
	bolt.direction=Vector2.RIGHT
	bolt.damage=10
	var targets: Array=[]
	for index in 5:
		var target:=Target.new()
		target.process_mode=Node.PROCESS_MODE_ALWAYS
		target.position=Vector2(520+index*22,300)
		game.add_child(target)
		targets.append(target)
	await physics_frame
	await physics_frame
	bolt._physics_process(.15)
	check(targets.slice(0,4).all(func(target):return target.hp==90) and targets[4].hp==100,"A real swept rare arc shot damages four enemies once and stops before the fifth: " +str(targets.map(func(target):return target.hp)))
	await process_frame
	clear_shots()
	for target in targets: target.free()
	check(weapon.reserve_capacity()==120,"Unresearched handheld reserve is bounded at120")
	before_shot=weapon.total_ammunition()
	check(game.upgrades.purchase("weapon_pouches") and weapon.reserve_capacity()==180,"Pouches increase actual capacity to180")
	check(weapon.total_ammunition()==before_shot,"Reserve expansion creates no ammunition or opened crate remainder")
	for kind: String in WorkerWeapon.WEAPONS:
		var modified:=WeaponResearch.stats(game,kind,WorkerWeapon.WEAPONS[kind])
		check(int(modified.capacity)==int(WeaponResearch.MAX_MAGAZINES[kind]) and int(modified.capacity)%int(modified.cost)==0,"Magazine holds whole shots for "+kind)
		check(WorkerWeapon.WEAPONS[kind].capacity==({"rifle":30,"shotgun":6,"arcgun":12,"veteran_rifle":20,"breacher_shotgun":4,"storm_arcgun":9}[kind]),"Derived research does not mutate shared weapon catalog: "+kind)
	for id: String in WeaponResearch.IDS:
		check(game.upgrades.persistent_owned().has(id) and CampaignCatalog.PERSISTENT_UPGRADES.has(id),"Purchased weapon research travels with campaign crew: "+id)
	check(game.upgrades.nodes_for_category(1).size()==9,"Weapon category contains original three nodes and six distinct upgrades")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Weapon research fixture closes without live projectiles")
	print("WEAPON RESEARCH: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
