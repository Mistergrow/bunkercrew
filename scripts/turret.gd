class_name RoofTurret
extends Node2D

const MountedPose := preload("res://scripts/mounted_worker_pose.gd")

const NetInput := preload("res://scripts/network_input.gd")

var damage_multiplier := 1.0

const PROJECTILE = preload("res://scenes/projectile.tscn")
const PIVOT := Vector2(0, -39)
var game: Node
var occupant: Node2D
var ammo := int(Balance.MAGAZINE)
var reserve := 0
var aim_angle := 0.32
var cooldown := 0.0
var recoil := 0.0
var flash := 0.0
var reload_timer := 0.0
var enter_frame := -10
var barrel: Node2D
var operator_controls: Node2D
var flash_tick := 0
var _ammo_notice_at := -4000

func _ready() -> void:
	var scenario := ScenarioCombat.for_game(game)
	if scenario != null and scenario.position_mode=="right": aim_angle=-PI-aim_angle
	add_to_group("interactables")
	add_to_group("turrets")
	barrel = Node2D.new()
	barrel.name = "ArticulatedWeapon"
	barrel.position = PIVOT
	barrel.draw.connect(_draw_weapon)
	add_child(barrel)
	operator_controls = Node2D.new()
	operator_controls.name = "OperatorControls"
	operator_controls.z_index = 1
	operator_controls.draw.connect(func(): MountedPose.draw_controls(operator_controls,self,operator_pose_anchors()))
	add_child(operator_controls)
	queue_redraw()

func interaction_point() -> Vector2:
	return global_position + Vector2(-18, -20)

func display_name(uppercase: bool=false) -> String:
	return LocaleText.text("DACHGESCHÜTZ" if uppercase else LocaleText.text("Dachgeschütz"))

func prompt(player: Node) -> String:
	if occupant == player:
		var controls := LocaleText.text("Maus zielen · LMB feuern · R laden · E verlassen")
		if not NetInput.mouse_aim(player):
			controls = LocaleText.text("Pos1/Ende zielen · ←/→ Seite · RStrg/RT feuern · Entf/Y laden · Enter/X verlassen") if panoramic_aim() else LocaleText.text("Pos1/Ende oder Stick zielen · RStrg/RT feuern · Entf/Y laden · Enter/X verlassen")
		if reload_timer > 0:
			return LocaleText.format("NACHLADEN …  %d / %d\n%s", [ammo, Balance.MAGAZINE, controls])
		return LocaleText.format("%s  %d / %d · Reserve %d\n%s", [display_name(true), ammo, Balance.MAGAZINE, reserve, controls])
	if is_instance_valid(occupant):
		return LocaleText.format("%s besetzt", display_name())
	return LocaleText.format("%s bedienen · %d / %d Schuss", [display_name(), ammo, Balance.MAGAZINE])

func interact(player: Node2D, _delta: float) -> void:
	if Engine.get_physics_frames() <= enter_frame + 1:
		return
	if NetInput.just_pressed(player,"interact"):
		if occupant == player:
			exit()
		elif not is_instance_valid(occupant):
			enter(player)

func enter(player: Node2D) -> void:
	if (player.has_method("can_act") and not player.can_act()) or is_instance_valid(occupant):
		return
	occupant = player
	occupant.mounted_turret = self
	if "facing" in occupant:
		occupant.facing = facing_direction()
	occupant.global_position = operator_position()
	enter_frame = Engine.get_physics_frames()
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"weapon_mount",handling_sound_position())
	queue_redraw()

func exit() -> void:
	if is_instance_valid(occupant):
		occupant.mounted_turret = null
		occupant.global_position = global_position + Vector2(-46*facing_direction(),-2)
	occupant = null
	# The player's later physics callback sees the same key press; do not re-enter.
	enter_frame = Engine.get_physics_frames()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not authoritative(): return
	cooldown = maxf(0, cooldown - delta)
	recoil = WeaponEffectArt.recover_recoil(recoil,delta)
	flash = maxf(0, flash - delta)
	if reload_timer > 0:
		var previous_time := reload_timer
		reload_timer = maxf(0.0,reload_timer-delta)
		if previous_time > 1.05*0.52 and reload_timer <= 1.05*0.52:
			_reload_sound("load")
		if reload_timer <= 0:
			var transfer := mini(int(Balance.MAGAZINE) - ammo, reserve)
			ammo += transfer
			reserve -= transfer
			if transfer > 0:
				_reload_sound("close")
	if is_instance_valid(occupant) and occupant.has_method("is_downed") and occupant.is_downed():
		exit()
	if is_instance_valid(occupant) and (not occupant.has_method("can_act") or occupant.can_act()):
		occupant.global_position = operator_position()
		if NetInput.just_pressed(occupant,"interact") and Engine.get_physics_frames() > enter_frame + 1:
			exit()
		else:
			if NetInput.mouse_aim(occupant):
				var mouse_delta := NetInput.aim_position(occupant)-(global_position+PIVOT)
				aim_angle = clamped_aim(mouse_delta.angle()) if panoramic_aim() else clampf(atan2(mouse_delta.y,maxf(mouse_delta.x,12)),deg_to_rad(-10),deg_to_rad(65))
			else:
				aim_from_keys(delta,1.1,-10,65)
			if "facing" in occupant: occupant.facing=facing_direction()
			occupant.global_position = operator_position()
			if NetInput.just_pressed(occupant,"reload"):
				start_reload()
			if NetInput.is_pressed(occupant,"fire") or NetInput.just_pressed(occupant,"fire"):
				fire()
	pose_barrel()
	barrel.queue_redraw()
	queue_redraw()

func operator_position() -> Vector2:
	return global_position+Vector2(-29*facing_direction(),0)

func reload_duration() -> float:
	return 1.05

func operator_pose_anchors() -> Dictionary:
	return MountedPose.anchors(self,reload_duration())

func panoramic_aim() -> bool:
	return ScenarioCombat.for_game(game) != null

func facing_direction() -> float:
	return -1.0 if cos(aim_angle)<0 else 1.0

func clamped_aim(angle: float, downward_limit: float=65.0) -> float:
	# One continuous 310-degree arc across the sky. Only the ground immediately
	# below the mount is outside the joint stops; physical rays still block cover.
	return clampf(wrapf(angle,-PI*1.5,PI*0.5),-PI-deg_to_rad(downward_limit),deg_to_rad(downward_limit))

func aim_from_keys(delta: float, rate: float, legacy_up: float, legacy_down: float) -> void:
	if not panoramic_aim():
		aim_angle=clampf(aim_angle+NetInput.axis(occupant,"aim_up","aim_down")*delta*rate,deg_to_rad(legacy_up),deg_to_rad(legacy_down))
		return
	var side := NetInput.axis(occupant,"left","right")
	if absf(side)>0.5 and signf(side)!=facing_direction(): aim_angle=-PI-aim_angle
	var axis := NetInput.axis(occupant,"aim_up","aim_down")
	aim_angle=clamped_aim(aim_angle+axis*delta*rate*facing_direction(),legacy_down)

func pose_barrel() -> void:
	if is_instance_valid(operator_controls): operator_controls.queue_redraw()
	barrel.rotation=aim_angle
	barrel.scale.y=facing_direction() if panoramic_aim() else 1.0

func authoritative() -> bool:
	var session=NetInput.for_game(game)
	return session==null or session.is_host

func ammo_capacity() -> int:
	return int(Balance.MAGAZINE)

func reserve_capacity() -> int:
	return ammo_capacity()*3

func refill_from_worker(player: Node,maximum: int=-1) -> int:
	if not authoritative(): return 0
	var room:=maxi(0,reserve_capacity()-reserve)
	if maximum>=0: room=mini(room,maximum)
	var result:=AmmoTransfer.take(player,room)
	reserve+=int(result.rounds)
	AmmoTransfer.reward_delivery(game,player,int(result.rounds))
	return int(result.rounds)

func start_reload() -> bool:
	if not authoritative() or reload_timer>0 or not is_instance_valid(occupant): return false
	if occupant.has_method("can_act") and not occupant.can_act(): return false
	if ammo>=ammo_capacity(): return refill_from_worker(occupant)>0
	var need:=ammo_capacity()-ammo
	if reserve<need: refill_from_worker(occupant,need-reserve)
	if reserve<=0:
		_ammo_notice("Eine Munitionskiste mitnehmen: 1 Kiste = 20 Schuss.")
		return false
	reload_timer=reload_duration()
	_reload_sound("open")
	return true

func _ammo_notice(message: String) -> void:
	if Time.get_ticks_msec()-_ammo_notice_at<3000: return
	_ammo_notice_at=Time.get_ticks_msec()
	if is_instance_valid(game) and game.has_method("notify"): game.notify(LocaleText.text(message))

func handling_sound_position() -> Vector2:
	# Operator-side edge of the feed housing: the hull cannot block its own controls.
	return to_global(PIVOT+Vector2(-34*facing_direction(),-5))

func _reload_sound(phase: String) -> void:
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"reload_cannon_"+phase,handling_sound_position())

func fire() -> bool:
	if not authoritative(): return false
	if is_instance_valid(occupant) and occupant.has_method("can_act") and not occupant.can_act():
		return false
	if cooldown > 0 or reload_timer > 0 or ammo <= 0:
		if ammo <= 0 and cooldown <= 0 and is_instance_valid(occupant):
			cooldown = 0.4
			if not start_reload() and is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"empty",global_position)
		return false
	var direction := Vector2.from_angle(aim_angle)
	var start := global_position + PIVOT
	var muzzle := start + direction * 70
	var shot_damage := Balance.SHOT_DAMAGE * damage_multiplier * CampaignBonus.gun_multiplier(game)
	var firing_worker := occupant
	if is_instance_valid(firing_worker) and firing_worker.has_method("damage_multiplier"):
		shot_damage *= firing_worker.damage_multiplier()
	# Sweep the complete barrel, including machines inside its visible length.
	# The first wall/terrain contact still blocks without damaging the bunker.
	var query := PhysicsRayQueryParameters2D.create(start, muzzle, 1 | 2 | 4)
	query.hit_from_inside = true
	var obstruction := get_world_2d().direct_space_state.intersect_ray(query)
	ammo -= 1
	var events = game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(occupant) and is_instance_valid(events) and events.has_method("record_activity"): events.record_activity(occupant)
	cooldown = Balance.SHOT_INTERVAL
	recoil = 6.0
	flash = 0.085
	flash_tick += 1
	if not obstruction.is_empty():
		var collider: Object = obstruction.collider
		ImpactBurst.contact(game,collider,obstruction.position,obstruction.normal,direction,clampf(shot_damage/32.0,0.5,1.5),"turret")
		if collider is Node and collider.is_in_group("enemies") and collider.has_method("take_damage"):
			if is_instance_valid(game) and game.has_method("combat_hit"):
				game.combat_hit(collider,shot_damage,firing_worker)
			else:
				collider.take_damage(shot_damage)
	else:
		var bullet := PROJECTILE.instantiate()
		bullet.game = game
		bullet.direction = direction
		bullet.damage = shot_damage
		bullet.credit_worker = firing_worker
		bullet.source = self
		get_parent().add_child(bullet)
		bullet.global_position = muzzle
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"cannon",handling_sound_position())
		game.fx(global_position + PIVOT + Vector2(-9, 8), Color("d2a454"), 1)
	return true

func _draw() -> void:
	draw_ellipse_shadow()
	MachineryArt.paint(self,"mount",Rect2(-32,-44,65,44))
	draw_rect(Rect2(-32,-19,18,15),Color("30392e"))
	for i in 5:
		draw_rect(Rect2(-30+i*3,-17,2,9),Color("b69b60"))
	if reload_timer > 0:
		Art.bar(self, Rect2(-31, -72, 62, 4), 1.0 - reload_timer / 1.05, Art.AMBER)
	if is_instance_valid(occupant):
		var aim_end := PIVOT + Vector2.from_angle(aim_angle) * 132
		draw_arc(aim_end, 7, 0, TAU, 12, Color(0.9, 0.83, 0.54, 0.65), 1)
		draw_line(aim_end - Vector2(10, 0), aim_end + Vector2(10, 0), Color(0.9, 0.83, 0.54, 0.45), 1)
		draw_line(aim_end - Vector2(0, 10), aim_end + Vector2(0, 10), Color(0.9, 0.83, 0.54, 0.45), 1)

func draw_ellipse_shadow() -> void:
	draw_rect(Rect2(-36, 0, 72, 4), Color(0, 0, 0, 0.3))

func _draw_weapon() -> void:
	MachineryArt.paint(barrel,"barrel",Rect2(-25-recoil,-16,95,34))
	WeaponEffectArt.muzzle(barrel,Vector2(70-recoil,0),flash,0.085,1,1.15,flash_tick,WeaponEffectArt.reduced(game))
