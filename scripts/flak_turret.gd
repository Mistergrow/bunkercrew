class_name FlakTurret
extends RoofTurret
## Dedicated air-defense gun. An occupied gun is manually aimed; unattended
## watch mode only spends stocked ammunition on visible airborne machines.
const FLAK_SPECS := {
	1:{"label":"FLAK I", "damage":46.0, "interval":0.42, "magazine":40, "hp":200.0},
	2:{"label":"FLAK II", "damage":64.0, "interval":0.34, "magazine":60, "hp":300.0},
	3:{"label":"FLAK III", "damage":86.0, "interval":0.27, "magazine":80, "hp":440.0},
}
class FlakHull extends StaticBody2D:
	var gun: Node2D
	func _ready():
		add_to_group("anti_air")
		collision_layer=2
		collision_mask=0
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size=Vector2(52,40)
		shape.shape=box
		add_child(shape)
	func attack_point() -> Vector2: return global_position
	func can_be_targeted() -> bool: return is_instance_valid(gun) and gun.hp>0.0
	func take_damage(amount: float) -> void:
		if is_instance_valid(gun): gun.take_damage(amount)
const MIN_ANGLE := -85.0
const MAX_ANGLE := 30.0
const RANGE := 1450.0
const AUTO_RATE_MULTIPLIER := 1.4
var tier := 1
var builder: Node2D
var autonomous := true
var tracking_target: Node2D
var scan_clock := 0.0
var hp := 200.0
var max_hp := 200.0
var hull: StaticBody2D

func _ready() -> void:
	ammo = 0
	reserve = 0
	aim_angle = deg_to_rad(-22)
	super._ready()
	add_to_group("flak_turrets")
	hull=FlakHull.new()
	hull.gun=self
	hull.position=Vector2(0,-22)
	add_child(hull)

func spec() -> Dictionary:
	return FLAK_SPECS[clampi(tier,1,3)]

func reload_duration() -> float:
	return 1.35

func ammo_capacity() -> int:
	return int(spec().magazine)

func reserve_capacity() -> int:
	return ammo_capacity()*3

func set_tier(value: int) -> void:
	# Upgrades change capacity and hardware, never ammunition already paid for.
	var missing := maxf(0.0,max_hp-hp)
	tier = clampi(value,1,3)
	max_hp=float(spec().hp)
	hp=maxf(0.0,max_hp-missing)
	queue_redraw()

func take_damage(amount: float) -> void:
	if amount<=0 or not is_finite(amount) or hp<=0:
		return
	hp=maxf(0.0,hp-amount)
	if hp<=0:
		exit()
		reload_timer=0.0
		if is_instance_valid(game):
			game.impact(global_position-Vector2(0,20),"explosion",Vector2.UP,1.1)
			game.notify(LocaleText.text("FLAK AUSGEFALLEN · am Pult mit Stahl reparieren."))
	queue_redraw()

func repair(player: Node) -> bool:
	if hp>=max_hp or not player.take_item("steel",1):
		return false
	var repaired := minf(max_hp-hp,80.0)
	hp+=repaired
	var events = game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(events) and events.has_method("record_role"): events.record_role(player,"repair",repaired*.06)
	if is_instance_valid(game): preload("res://scripts/spatial_sound.gd").emit(game,"build",global_position)
	queue_redraw()
	return true

func can_interact(_player: Node) -> bool:
	return hp>0

func enter(player: Node2D) -> void:
	if hp<=0: return
	super.enter(player)

func accept_ammo(player: Node, audible: bool=true) -> bool:
	var moved:=refill_from_worker(player,20)
	if moved<=0: return false
	if audible: _reload_sound("load")
	return true

func prompt(player: Node) -> String:
	var toggle := "G" if NetInput.mouse_aim(player) else LocaleText.text("Num* / L3")
	var mode := LocaleText.text("WACHE AN") if autonomous else LocaleText.text("WACHE AUS")
	if occupant==player:
		var controls := LocaleText.text("Maus / LMB · R laden · E verlassen") if NetInput.mouse_aim(player) else LocaleText.text("Pos1/Ende / Stick · ←/→ Seite · RStrg/RT · Entf/Y laden · Enter/X verlassen")
		return LocaleText.format("%s · %d/%d · Reserve %d · %s\n%s · %s: Wache", [spec().label,ammo,ammo_capacity(),reserve,mode,controls,toggle])
	if is_instance_valid(occupant):
		return LocaleText.format("%s besetzt · %d/%d Schuss", [spec().label,ammo,ammo_capacity()])
	return LocaleText.format("%s · %d/%d · Reserve %d · %s\nE / Enter: bedienen · %s: Wache · Munition am Pult unten abgeben", [spec().label,ammo,ammo_capacity(),reserve,mode,toggle])

func _physics_process(delta: float) -> void:
	if not authoritative(): return
	if hp<=0:
		return
	cooldown = maxf(0.0,cooldown-delta)
	recoil = WeaponEffectArt.recover_recoil(recoil,delta,15.0)
	flash = maxf(0.0,flash-delta)
	if reload_timer>0:
		var previous_time := reload_timer
		reload_timer=maxf(0.0,reload_timer-delta)
		if previous_time > 1.35*0.52 and reload_timer <= 1.35*0.52:
			_reload_sound("load")
		if reload_timer<=0:
			var rounds := mini(ammo_capacity()-ammo,reserve)
			ammo += rounds
			reserve -= rounds
			if rounds > 0:
				_reload_sound("close")
	if is_instance_valid(occupant) and occupant.has_method("is_downed") and occupant.is_downed():
		exit()
	if is_instance_valid(game) and "players" in game:
		for player in game.players:
			if is_instance_valid(player) and player.focus==self and player.can_act() and NetInput.just_pressed(player,"craft_next"):
				autonomous=not autonomous
				if is_instance_valid(game): game.notify(LocaleText.text("FLAK-Wache aktiv · verbraucht eingelagerte Munition.") if autonomous else LocaleText.text("FLAK-Wache aus · nur manuell feuern."))
	if is_instance_valid(occupant) and occupant.can_act():
		occupant.global_position=operator_position()
		if NetInput.just_pressed(occupant,"interact") and Engine.get_physics_frames()>enter_frame+1:
			exit()
		else:
			if NetInput.mouse_aim(occupant):
				var mouse_delta := NetInput.aim_position(occupant)-(global_position+PIVOT)
				aim_angle=clamped_aim(mouse_delta.angle(),MAX_ANGLE) if panoramic_aim() else clampf(atan2(mouse_delta.y,maxf(mouse_delta.x,1)),deg_to_rad(MIN_ANGLE),deg_to_rad(MAX_ANGLE))
			else:
				aim_from_keys(delta,1.15,MIN_ANGLE,MAX_ANGLE)
			if "facing" in occupant: occupant.facing=facing_direction()
			occupant.global_position=operator_position()
			if NetInput.just_pressed(occupant,"reload"): start_reload()
			if NetInput.is_pressed(occupant,"fire"): fire()
	elif autonomous:
		_watch_sky(delta)
	pose_barrel()
	barrel.queue_redraw()
	queue_redraw()

func _target_point(enemy: Node2D) -> Vector2:
	var point := enemy.global_position
	var flight := Vector2.ZERO
	if "flight_velocity" in enemy:
		flight=enemy.flight_velocity
	elif "velocity" in enemy:
		flight=enemy.velocity
	var travel := minf(0.7,(point-(global_position+PIVOT)).length()/1450.0)
	return point+flight*travel

func target_visible(enemy) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.get("game")!=game or not enemy.is_in_group("air_enemies") or ("dead" in enemy and enemy.dead):
		return false
	var start := global_position+PIVOT
	var destination := _target_point(enemy)
	var difference := destination-start
	var angle := difference.angle()
	var permitted := absf(wrapf(clamped_aim(angle,MAX_ANGLE)-angle,-PI,PI))<0.01 if panoramic_aim() else difference.x>=15 and angle>=deg_to_rad(MIN_ANGLE) and angle<=deg_to_rad(MAX_ANGLE)
	if difference.length()>RANGE or not permitted:
		return false
	var query := PhysicsRayQueryParameters2D.create(start,destination,1|2)
	query.hit_from_inside=true
	query.exclude=[hull.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _watch_sky(delta: float) -> void:
	if ammo<=0 and reserve>0 and reload_timer<=0:
		start_reload()
	scan_clock-=delta
	if scan_clock<=0 or not target_visible(tracking_target):
		scan_clock=0.16
		tracking_target=null
		var distance := INF
		for enemy in get_tree().get_nodes_in_group("air_enemies"):
			if target_visible(enemy) and global_position.distance_squared_to(enemy.global_position)<distance:
				tracking_target=enemy
				distance=global_position.distance_squared_to(enemy.global_position)
	if not target_visible(tracking_target):
		return
	var target_angle := (_target_point(tracking_target)-(global_position+PIVOT)).angle()
	if panoramic_aim(): target_angle=clamped_aim(target_angle,MAX_ANGLE)
	aim_angle=move_toward(aim_angle,target_angle,delta*1.7)
	if absf(aim_angle-target_angle)<0.025:
		fire()

func start_reload() -> bool:
	if not authoritative() or hp<=0 or reload_timer>0: return false
	if is_instance_valid(occupant) and not occupant.can_act(): return false
	if ammo>=ammo_capacity(): return refill_from_worker(occupant)>0 if is_instance_valid(occupant) else false
	var need:=ammo_capacity()-ammo
	if reserve<need and is_instance_valid(occupant): refill_from_worker(occupant,need-reserve)
	if reserve<=0:
		if is_instance_valid(occupant): _ammo_notice("Eine Munitionskiste mitnehmen: 1 Kiste = 20 Schuss.")
		return false
	reload_timer=reload_duration()
	_reload_sound("open")
	return true

func _reload_sound(phase: String) -> void:
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"reload_flak_"+phase,handling_sound_position())

func fire() -> bool:
	if not authoritative(): return false
	if hp<=0 or cooldown>0 or reload_timer>0 or (is_instance_valid(occupant) and not occupant.can_act()):
		return false
	if ammo<=0:
		if not start_reload() and is_instance_valid(occupant):
			cooldown=0.4
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"empty",handling_sound_position())
		return false
	var firing_worker := occupant if is_instance_valid(occupant) else builder
	var shot_damage := float(spec().damage)*damage_multiplier*CampaignBonus.gun_multiplier(game)
	if is_instance_valid(firing_worker) and firing_worker.has_method("damage_multiplier"):
		shot_damage *= firing_worker.damage_multiplier()
	var direction := Vector2.from_angle(aim_angle)
	var start := global_position+PIVOT
	var muzzle := start+direction*64
	var ray := PhysicsRayQueryParameters2D.create(start,muzzle,1|2|4)
	ray.hit_from_inside=true
	ray.exclude=[hull.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	ammo-=1
	var events = game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(occupant) and is_instance_valid(events) and events.has_method("record_activity"): events.record_activity(occupant)
	cooldown=float(spec().interval)*(1.0 if is_instance_valid(occupant) else AUTO_RATE_MULTIPLIER)
	recoil=7
	flash=0.1
	flash_tick+=1
	var shell := preload("res://scripts/flak_projectile.gd").new()
	shell.game=game
	shell.damage=shot_damage
	shell.direction=direction
	shell.credit_worker=firing_worker
	shell.source=self
	get_parent().add_child(shell)
	shell.global_position=muzzle
	if not hit.is_empty():
		shell.global_position=hit.position
		shell.impact(hit.collider,hit.position,hit.normal)
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"cannon",handling_sound_position())
	return true

func _draw() -> void:
	draw_rect(Rect2(-44,-2,88,5),Color(0,0,0,0.35))
	MachineryArt.paint(self,"mount",Rect2(-33,-46,68,46))
	for side in [-1,1]:
		var x: float=side*31
		draw_rect(Rect2(x-7,-31,14,25),Color("232e2f"))
		draw_rect(Rect2(x-5,-30,10,3),Color("8e9786"))
		for i in tier:
			draw_rect(Rect2(x-3,-24+i*5,6,2),Color("c4ab72"))
	if reload_timer>0:
		UiArt.bar(self,Rect2(-30,-76,60,4),1-reload_timer/1.35,UiArt.AMBER)
	if is_instance_valid(occupant):
		var end := PIVOT+Vector2.from_angle(aim_angle)*142
		draw_arc(end,7,0,TAU,16,Color("d5bb7e"),1)
	if UiArt.world_label_visible(self):
		UiArt.centered(self,Vector2(0,-89),str(spec().label),10,UiArt.AMBER)
	if hp<max_hp:
		UiArt.bar(self,Rect2(-30,-81,60,3),hp/max_hp,UiArt.RED)

func _draw_weapon() -> void:
	# Existing industrial steel barrel art stays individually replaceable; two
	# articulated tubes alternate recoil while sharing the same physical muzzle.
	for index in 2:
		var kick := recoil if flash_tick%2==index else recoil*0.4
		MachineryArt.paint(barrel,"barrel",Rect2(-20-kick,-17+index*14,84,23))
	var y := -6.0 if flash_tick%2==0 else 8.0
	WeaponEffectArt.muzzle(barrel,Vector2(64-recoil,y),flash,0.1,1,1.3,flash_tick,WeaponEffectArt.reduced(game))
