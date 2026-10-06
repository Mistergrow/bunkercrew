class_name WorkerWeapon
extends Node2D

const NetInput := preload("res://scripts/network_input.gd")

const SHOT := preload("res://scripts/worker_projectile.gd")
const WEAPONS := {
	"rifle":{"title":"DIENSTGEWEHR","capacity":30,"damage":16.0,"interval":0.20,"reload":1.05,"pellets":1,"spread":0.012,"cost":1},
	"shotgun":{"title":"SCHROTFLINTE","capacity":6,"damage":9.0,"interval":0.82,"reload":1.25,"pellets":8,"spread":0.15,"cost":1},
	"arcgun":{"title":"IMPULSGEWEHR","capacity":12,"damage":34.0,"interval":0.52,"reload":1.15,"pellets":1,"spread":0.0,"cost":2},
	"veteran_rifle":{"title":"VETERANENGEWEHR", "family":"rifle", "capacity":20, "damage":24.0, "interval":0.28, "reload":1.20, "pellets":1, "spread":0.0035, "cost":1},
	"breacher_shotgun":{"title":"BRECHERSCHROTFLINTE", "family":"shotgun", "capacity":4, "damage":14.0, "interval":1.0, "reload":1.45, "pellets":6, "spread":0.10, "cost":1},
	"storm_arcgun":{"title":"STURMIMPULSGEWEHR", "family":"arcgun", "capacity":9, "damage":45.0, "interval":0.75, "reload":1.40, "pellets":1, "spread":0.0, "cost":3},
}
const EPIC_WEAPONS := ["veteran_rifle", "breacher_shotgun", "storm_arcgun"]
const GRIP_POINTS := [Vector2(-1,1), Vector2(15,-1)]
var worker
var game
var weapon_kind := "rifle"
var reserve := 90
var open_pack := 0
var loaded := {"rifle":30,"shotgun":0,"arcgun":0,"veteran_rifle":0,"breacher_shotgun":0,"storm_arcgun":0}
var aiming := false
var flash := 0.0
var recoil := 0.0
var aim_direction := Vector2.RIGHT
var aim_point := Vector2.ZERO
var reload_timer := 0.0
var cooldown := 0.0
var _aim_hold := 0.0
var _aim_pitch := 0.0
var _reload_kind := ""
var _shot_index := 0
var _empty_notice := 0.0
var _hands_notice := 0.0

func _ready() -> void:
	worker = get_parent()
	game = worker.game
	z_index = 2
	_update_origin()

func current_ammo() -> int:
	return int(loaded.get(weapon_kind,0))

func weapon_stats(kind: String = "") -> Dictionary:
	if kind.is_empty(): kind=weapon_kind
	return WeaponResearch.stats(game,kind,WEAPONS[kind])

func magazine_size() -> int:
	return int(weapon_stats().capacity)

func reserve_capacity() -> int:
	return int(weapon_stats().reserve_capacity)

func capture_ammunition() -> Dictionary:
	return {"loaded":loaded.duplicate(),"reserve":reserve,"open_pack":open_pack}

static func initial_ammunition() -> Dictionary:
	return {"loaded":{"rifle":30,"shotgun":0,"arcgun":0,"veteran_rifle":0,"breacher_shotgun":0,"storm_arcgun":0},"reserve":90,"open_pack":0}

static func valid_ammunition(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=3 or not value.get("loaded") is Dictionary: return false
	if not CampaignState._integer(value.get("reserve"),0,WeaponResearch.MAX_RESERVE) or not CampaignState._integer(value.get("open_pack"),0,19): return false
	if value.loaded.size()!=WEAPONS.size(): return false
	for kind in WEAPONS:
		if not CampaignState._integer(value.loaded.get(kind),0,int(WeaponResearch.MAX_MAGAZINES[kind])): return false
	return true

func restore_ammunition(value: Dictionary) -> bool:
	if not valid_ammunition(value): return false
	cancel_actions()
	for kind in WEAPONS: loaded[kind]=int(value.loaded[kind])
	reserve=int(value.reserve)
	open_pack=int(value.open_pack)
	return true

func weapon_name() -> String:
	return LocaleText.text(WEAPONS[weapon_kind].title)

func total_ammunition() -> int:
	var total := reserve+open_pack
	for value in loaded.values():
		total += int(value)
	return total

func available_weapons() -> Array[String]:
	var available: Array[String] = ["rifle"]
	for kind: String in ["shotgun","arcgun"]:
		if is_instance_valid(game) and "upgrades" in game and is_instance_valid(game.upgrades) and game.upgrades.has_upgrade(kind):
			available.append(kind)
	var campaign = game.get("campaign") if is_instance_valid(game) else null
	if campaign is CampaignState and campaign.active:
		for kind: String in EPIC_WEAPONS:
			if campaign.expedition.epic_weapons.has(kind): available.append(kind)
	return available

static func family_for(kind: String) -> String:
	return str(WEAPONS.get(kind, {}).get("family", kind))

func is_epic() -> bool:
	return EPIC_WEAPONS.has(weapon_kind)

func worker_can_act() -> bool:
	return is_instance_valid(worker) and (not worker.has_method("can_act") or worker.can_act())

func cancel_actions() -> void:
	# A consumed ammo pack already belongs to reserve. Cancelling a reload never
	# discards those rounds and never transfers them to a second magazine.
	reload_timer = 0.0
	_reload_kind = ""
	_aim_hold = 0.0
	aiming = false
	flash = 0.0

func _authoritative() -> bool:
	var room = NetInput.for_game(game)
	return room == null or room.is_host

func _personal_mount() -> Node2D:
	if not is_instance_valid(worker): return null
	var seat = worker.mounted_turret
	if is_instance_valid(seat) and seat.has_method("allows_personal_weapon") and seat.allows_personal_weapon(): return seat
	return null

func cycle_weapon() -> void:
	if not _authoritative() or not worker_can_act():
		return
	var available := available_weapons()
	var previous_kind := weapon_kind
	weapon_kind = available[(available.find(weapon_kind)+1)%available.size()]
	reload_timer = 0
	_reload_kind = ""
	_aim_hold = 0.75
	if weapon_kind != previous_kind and is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"weapon_switch",global_position)
	if current_ammo() < int(WEAPONS[weapon_kind].cost):
		start_reload()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if not _authoritative(): return
	flash = maxf(0,flash-delta)
	recoil = WeaponEffectArt.recover_recoil(recoil,delta,21.0)
	cooldown = maxf(0,cooldown-delta)
	_empty_notice = maxf(0,_empty_notice-delta)
	_hands_notice = maxf(0,_hands_notice-delta)
	_aim_hold = maxf(0,_aim_hold-delta)
	if not is_instance_valid(worker) or not is_instance_valid(game) or not "started" in game or not game.started:
		aiming = false
		return
	_update_origin()
	if not worker_can_act():
		if worker.has_method("is_downed") and worker.is_downed():
			cancel_actions()
		aiming = false
		queue_redraw()
		return
	if reload_timer > 0:
		var previous_time := reload_timer
		reload_timer = maxf(0,reload_timer-delta)
		var load_time := reload_duration(_reload_kind)*0.52
		if previous_time > load_time and reload_timer <= load_time:
			_reload_sound("load")
		if reload_timer <= 0:
			var moved := mini(int(weapon_stats(_reload_kind).capacity)-int(loaded.get(_reload_kind, 0)),reserve)
			loaded[_reload_kind] = int(loaded.get(_reload_kind, 0)) + moved
			reserve -= moved
			if moved > 0:
				_reload_sound("close")
			_reload_kind = ""
	if is_instance_valid(worker.mounted_turret) and _personal_mount() == null:
		aiming = false
		queue_redraw()
		return
	if NetInput.just_pressed(worker,"cycle_weapon"):
		cycle_weapon()
	if NetInput.just_pressed(worker,"reload"):
		request_reload()
	var fire_held := NetInput.is_pressed(worker,"fire") or NetInput.just_pressed(worker,"fire")
	if fire_held and can_use():
		_aim_hold = 0.75
	_update_aim(delta,fire_held)
	aiming = can_use() and (_aim_hold > 0 or reload_timer > 0)
	if fire_held:
		fire()
	queue_redraw()

func _update_origin() -> void:
	var seat := _personal_mount()
	if seat != null:
		global_position = seat.personal_weapon_origin()
		return
	var visual = worker.get_node_or_null("PixelVisual")
	var crouched: bool = is_instance_valid(visual) and "crouched" in visual and visual.crouched
	position = Vector2(worker.facing*10,-21 if crouched else -38)

func _update_aim(delta: float, fire_held: bool) -> void:
	if NetInput.mouse_aim(worker):
		var offset := NetInput.aim_position(worker)-global_position
		if offset.length() > 15:
			if fire_held and can_use() and absf(offset.x) > 10:
				worker.facing = signf(offset.x)
			var pitch := clampf(atan2(offset.y,absf(offset.x)),-1.1,1.05)
			aim_direction = Vector2(worker.facing*cos(pitch),sin(pitch))
	else:
		if _personal_mount() != null:
			var facing_input := NetInput.axis(worker,"left","right")
			if absf(facing_input) > .1: worker.facing = signf(facing_input)
		_aim_pitch = clampf(_aim_pitch+NetInput.axis(worker,"aim_up","aim_down")*delta*1.6,-1.1,1.05)
		aim_direction = Vector2(worker.facing*cos(_aim_pitch),sin(_aim_pitch))
	_update_origin()
	var distance := 295.0 if family_for(weapon_kind) == "shotgun" else 640.0 if weapon_kind == "veteran_rifle" else 500.0
	if NetInput.mouse_aim(worker):
		distance = minf(distance,maxf(38,NetInput.aim_position(worker).distance_to(global_position)))
	aim_point = global_position+aim_direction*distance
	var sight := PhysicsRayQueryParameters2D.create(global_position,aim_point,1|2|4)
	sight.hit_from_inside = true
	var seat := _personal_mount()
	if seat != null: sight.exclude = seat.projectile_exclusions()
	var blocked := get_world_2d().direct_space_state.intersect_ray(sight)
	if not blocked.is_empty():
		aim_point = blocked.position

func can_use() -> bool:
	if not available_weapons().has(weapon_kind) or not worker_can_act(): return false
	if _personal_mount() != null: return true
	return not is_instance_valid(worker.mounted_turret) and not worker.climbing and not worker.mining and not worker._interacting and worker.carried_count() == 0

func _near_ammo_supply() -> Node:
	if not is_instance_valid(worker) or not "focus" in worker: return null
	var source=worker.focus
	return source if source is Supply and source.kind=="ammo" and source.can_interact(worker) else null

func refill_from_inventory(maximum: int=-1) -> int:
	if not _authoritative() or not worker_can_act(): return 0
	var room:=maxi(0,reserve_capacity()-reserve)
	if maximum>=0: room=mini(room,maximum)
	var moved:=int(AmmoTransfer.take(worker,room).rounds)
	reserve+=moved
	return moved

func refill_from_supply(supply: Node) -> int:
	if not _authoritative() or not worker_can_act(): return 0
	var moved:=int(AmmoTransfer.take(worker,maxi(0,reserve_capacity()-reserve),supply).rounds)
	reserve+=moved
	return moved

func request_reload() -> bool:
	if not _authoritative() or not worker_can_act() or (is_instance_valid(worker.mounted_turret) and _personal_mount()==null): return false
	var supply:=_near_ammo_supply()
	var refilled:=refill_from_supply(supply) if supply!=null else 0
	var started_reload:=start_reload()
	if refilled>0: _ammo_notice(LocaleText.format("Reserve aufgefüllt: +%d Schuss",refilled))
	elif not started_reload and reload_timer<=0:
		_ammo_notice(LocaleText.text("Magazin und Reserve voll") if current_ammo()>=magazine_size() and reserve>=reserve_capacity() else LocaleText.text("Keine Munition · Kiste mitnehmen oder am Munitionsvorrat nachladen"))
	return started_reload or refilled>0

func _ammo_notice(message: String) -> void:
	if is_instance_valid(game) and game.has_method("notify"): game.notify(message)

func start_reload() -> bool:
	if not _authoritative() or not available_weapons().has(weapon_kind) or reload_timer>0 or not worker_can_act() or (is_instance_valid(worker.mounted_turret) and _personal_mount()==null): return false
	if current_ammo()>=magazine_size():
		var stocked:=refill_from_inventory()
		if stocked>0: _ammo_notice(LocaleText.format("Reserve aufgefüllt: +%d Schuss",stocked))
		return stocked>0
	var need:=magazine_size()-current_ammo()
	if reserve<need: refill_from_inventory(need-reserve)
	if reserve<=0: return false
	reload_timer=reload_duration(weapon_kind)
	_reload_kind=weapon_kind
	_aim_hold=reload_timer+0.5
	_reload_sound("open")
	return true

func _reload_sound(phase: String) -> void:
	if is_instance_valid(game) and not _reload_kind.is_empty():
		var family := "arc" if family_for(_reload_kind) == "arcgun" else family_for(_reload_kind)
		preload("res://scripts/spatial_sound.gd").emit(game,"reload_%s_%s" % [family,phase],global_position)

func fire() -> bool:
	if not _authoritative() or not worker_can_act():
		return false
	if _personal_mount() == null and is_instance_valid(worker) and worker.carried_count() > 0 and _hands_notice <= 0 and is_instance_valid(game) and game.has_method("notify"):
		_hands_notice = 3.0
		game.notify(LocaleText.text("Zum Kämpfen Material mit Q / Rücktaste ablegen."))
	if not can_use() or cooldown > 0 or reload_timer > 0:
		return false
	var spec: Dictionary = weapon_stats()
	var cost := int(spec.cost)
	if current_ammo() < cost:
		if not start_reload() and _empty_notice <= 0:
			_empty_notice = 2.0
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"empty",global_position)
		return false
	loaded[weapon_kind] -= cost
	var events = game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(events) and events.has_method("record_activity"): events.record_activity(worker)
	cooldown = float(spec.interval)
	flash = 0.08 if family_for(weapon_kind) != "arcgun" else 0.13
	recoil = 3.5 if family_for(weapon_kind) == "rifle" else 6.0
	_aim_hold = 0.75
	aiming = true
	_shot_index += 1
	var multiplier := 1.0
	if is_instance_valid(game) and "upgrades" in game and is_instance_valid(game.upgrades) and game.upgrades.has_method("weapon_multiplier"):
		multiplier = game.upgrades.weapon_multiplier()
	if worker.has_method("damage_multiplier"):
		multiplier *= worker.damage_multiplier()
	for pellet in int(spec.pellets):
		var spread := float(spec.spread)*sin(_shot_index*2.31)
		if int(spec.pellets) > 1:
			spread = lerpf(-float(spec.spread),float(spec.spread),float(pellet)/(int(spec.pellets)-1))
		_launch_round(aim_direction.rotated(spread),float(spec.damage)*multiplier)
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,{"rifle":"shot","shotgun":"shotgun","arcgun":"arc"}.get(family_for(weapon_kind),"shot"),global_position)
	queue_redraw()
	return true

func _launch_round(direction: Vector2, damage: float) -> void:
	var shot := SHOT.new()
	shot.game = game
	shot.credit_worker = worker
	shot.direction = direction
	shot.damage = damage
	shot.flavor = family_for(weapon_kind)
	shot.z_index = 16
	var seat := _personal_mount()
	if seat != null: shot.excluded = seat.projectile_exclusions()
	if family_for(weapon_kind) == "shotgun":
		shot.life = 0.27
	elif family_for(weapon_kind) == "arcgun":
		shot.speed = 850
		shot.life = 0.8
		shot.remaining_hits = int(weapon_stats().pierce)
	if weapon_kind == "veteran_rifle":
		shot.speed = 1400.0
		shot.life = 0.9
	elif weapon_kind == "breacher_shotgun":
		shot.stagger_duration = 0.40
	# Starting at the shoulder checks the full barrel path on the first sweep.
	game.add_child(shot)
	shot.global_position = global_position

func drawing_transform() -> Transform2D:
	return Transform2D(aim_direction.angle(),Vector2.ZERO).scaled_local(Vector2(1,1 if aim_direction.x>=0 else -1))

func grip_positions() -> PackedVector2Array:
	# The receiver and foregrip travel with the same aim, mirror and recoil as
	# the gun pixels. Body poses and foreground gloves share these contacts.
	var tx := drawing_transform()
	return PackedVector2Array([tx*(GRIP_POINTS[0]-Vector2(recoil,0)),tx*(GRIP_POINTS[1]-Vector2(recoil,0))])

func grip_positions_for(visual: Node2D) -> PackedVector2Array:
	var tx := ActorWeatherGeometry.worker_transform(visual).affine_inverse()*visual.global_transform.affine_inverse()*global_transform
	var grips := grip_positions()
	return PackedVector2Array([tx*grips[0],tx*grips[1]])

func _draw() -> void:
	if not aiming or not can_use():
		return
	draw_set_transform_matrix(drawing_transform())
	var kick := Vector2(-recoil,0)
	draw_rect(Rect2(Vector2(-18,-4)+kick,Vector2(13,8)),Art.INK)
	draw_rect(Rect2(Vector2(-16,-3)+kick,Vector2(10,5)),Color("887653"))
	draw_rect(Rect2(Vector2(-8,-6)+kick,Vector2(23,12)),Art.INK)
	draw_rect(Rect2(Vector2(-6,-4)+kick,Vector2(20,7)),Color("5d6b64"))
	draw_rect(Rect2(Vector2(-3,4)+kick,Vector2(5,9)),Color("242f34"))
	draw_rect(Rect2(Vector2(5,4)+kick,Vector2(7,7)),Color("89917b"))
	if family_for(weapon_kind) == "shotgun":
		for y in [-3,2]:
			draw_rect(Rect2(Vector2(12,y)+kick,Vector2(23,3)),Color("a6ab96"))
		draw_rect(Rect2(Vector2(12,-5)+kick,Vector2(12,10)),Color("85694b"))
	elif family_for(weapon_kind) == "arcgun":
		draw_rect(Rect2(Vector2(11,-8)+kick,Vector2(20,16)),Color("253340"))
		for x in [13,21,29]:
			draw_rect(Rect2(Vector2(x,-7)+kick,Vector2(3,14)),Color("8f8ade"))
		draw_rect(Rect2(Vector2(12,-2)+kick,Vector2(23,4)),Color("8bdff1"))
	else:
		draw_rect(Rect2(Vector2(13,-2)+kick,Vector2(21,4)),Color("a0a997"))
		draw_rect(Rect2(Vector2(29,-4)+kick,Vector2(7,8)),Color("253239"))
		draw_rect(Rect2(Vector2(-2,-8)+kick,Vector2(10,3)),Color("8b957f"))
	_draw_material_details(kick)
	if is_epic():
		# Bounded native details retain the common side-on industrial material.
		match weapon_kind:
			"veteran_rifle":
				draw_rect(Rect2(Vector2(-1,-12)+kick,Vector2(17,4)),Art.INK)
				draw_rect(Rect2(Vector2(1,-11)+kick,Vector2(12,2)),Color("baa274"))
				draw_rect(Rect2(Vector2(33,-3)+kick,Vector2(5,6)),Color("716d55"))
			"breacher_shotgun":
				draw_rect(Rect2(Vector2(29,-6)+kick,Vector2(8,13)),Art.INK)
				draw_rect(Rect2(Vector2(30,-5)+kick,Vector2(6,3)),Color("b19468"))
				for index in 3: draw_rect(Rect2(Vector2(-5+index*5,-5)+kick,Vector2(2,5)),Color("bd8857"))
			"storm_arcgun":
				for index in 3:
					draw_rect(Rect2(Vector2(12+index*7,-9)+kick,Vector2(4,3)),Color("aabe9e"))
					draw_rect(Rect2(Vector2(12+index*7,7)+kick,Vector2(4,3)),Color("85755a"))
	WeaponEffectArt.muzzle(self,Vector2(35-recoil,0),flash,0.13 if family_for(weapon_kind)=="arcgun" else 0.08,1,0.72 if family_for(weapon_kind)=="rifle" else 1.05,_shot_index,WeaponEffectArt.reduced(game),family_for(weapon_kind)=="arcgun")
	draw_set_transform(Vector2.ZERO)
	_draw_gripping_hands()
	if aim_point != Vector2.ZERO:
		var marker := to_local(aim_point)
		var tint := PartyConfig.player_color(worker.player_id)
		tint.a = .65
		for offset: Vector2 in [Vector2(-6,0),Vector2(6,0),Vector2(0,-6),Vector2(0,6)]:
			draw_line(marker+offset,marker+offset*0.6,tint,1)

func _draw_gripping_hands() -> void:
	var visual := worker.get_node_or_null("PixelVisual") as WorkerVisual
	if visual==null: return
	var grips := grip_positions()
	if _personal_mount()!=null:
		# A seated reload can deliberately move one hand to the ammunition feed.
		# Keep those actual operator contacts rather than pinning it to the gun.
		if visual.pose_skeleton.is_empty(): return
		var tx := ActorWeatherGeometry.worker_transform(visual)
		for index in 2: grips[index]=to_local(visual.to_global(tx*Vector2(visual.pose_skeleton.hands[index])))
	elif visual.weapon_pose().is_empty(): return
	var palette := WorkerIdentityArt.palette(str(worker.character_id), WorkerPoseArt.C)
	var limb_mask := preload("res://scripts/combat_gore.gd").visible_mask(worker)
	for index in 2:
		if limb_mask&(1 if index==0 else 2): continue
		var hand: Vector2 = grips[index]
		draw_rect(Rect2(hand+Vector2(-3,-2),Vector2(7,6)),palette.ink)
		draw_rect(Rect2(hand+Vector2(-2,-1),Vector2(5,4)),palette.leather_light if index==1 else palette.leather)
		draw_rect(Rect2(hand+Vector2(1,-1),Vector2(2,2)),palette.skin_light if index==1 else palette.skin)
		draw_rect(Rect2(hand+Vector2(-2,2),Vector2(4,1)),palette.leather)

func _draw_material_details(kick: Vector2) -> void:
	# Single-pixel worn edges, receiver cutouts and fasteners share the actors'
	# native texel scale. They stay attached through aim, mirror and recoil.
	var edge := Color("a7ad95")
	var recess := Color("34413e")
	var steel := Color("78877b")
	draw_line(Vector2(-6,-4)+kick, Vector2(12,-4)+kick, edge, 1)
	draw_line(Vector2(-6,2)+kick, Vector2(11,2)+kick, recess, 1)
	draw_rect(Rect2(Vector2(-4,-2)+kick,Vector2(9,3)), Color("384944"))
	draw_rect(Rect2(Vector2(-2,-2)+kick,Vector2(5,1)), Color("8a9682"))
	draw_rect(Rect2(Vector2(8,-2)+kick,Vector2(5,2)), Color("b3b7a0"))
	draw_rect(Rect2(Vector2(9,-1)+kick,Vector2(3,1)), Color("566358"))
	for point in [Vector2(-5,0), Vector2(6,-3)]:
		draw_rect(Rect2(point+kick,Vector2.ONE), Color("c0b58e"))
	for index in 3:
		draw_line(Vector2(-15+index*3,-2)+kick, Vector2(-16+index*3,1)+kick, Color("63553d"),1)
	draw_line(Vector2(-15,-3)+kick, Vector2(-9,-3)+kick, Color("b0a17c"),1)
	draw_line(Vector2(5,5)+kick, Vector2(10,5)+kick, Color("b0b49a"),1)
	for index in 3:
		draw_line(Vector2(6,6+index)+kick, Vector2(9,6+index)+kick, Color("5d6c5c"),1)
	match family_for(weapon_kind):
		"rifle":
			draw_line(Vector2(14,-2)+kick,Vector2(29,-2)+kick,Color("c0c4aa"),1)
			draw_line(Vector2(14,1)+kick,Vector2(29,1)+kick,recess,1)
			for x in [17,24]: draw_rect(Rect2(Vector2(x,-3)+kick,Vector2(2,6)),steel)
			draw_rect(Rect2(Vector2(30,-3)+kick,Vector2(4,1)),Color("8c9480"))
			draw_rect(Rect2(Vector2(33,-1)+kick,Vector2(2,2)),Color("101f23"))
		"shotgun":
			for y in [-3,2]:
				draw_line(Vector2(25,y)+kick,Vector2(34,y)+kick,Color("c1bfa7"),1)
				draw_line(Vector2(25,y+2)+kick,Vector2(34,y+2)+kick,recess,1)
			for x in [14,17,20]:
				draw_line(Vector2(x,-3)+kick,Vector2(x,2)+kick,Color("504733"),1)
				draw_line(Vector2(x+1,-3)+kick,Vector2(x+1,2)+kick,Color("b69d70"),1)
			draw_rect(Rect2(Vector2(24,-4)+kick,Vector2(2,9)),steel)
		"arcgun":
			draw_line(Vector2(12,-8)+kick,Vector2(29,-8)+kick,steel,1)
			for x in [13,21,29]:
				draw_rect(Rect2(Vector2(x,-6)+kick,Vector2(1,12)),Color("b5b4cf"))
				draw_rect(Rect2(Vector2(x+2,-6)+kick,Vector2(1,12)),Color("585e86"))
				draw_rect(Rect2(Vector2(x,-3)+kick,Vector2(3,1)),Color("7c8b89"))
				draw_rect(Rect2(Vector2(x,3)+kick,Vector2(3,1)),Color("455557"))
			draw_line(Vector2(13,-1)+kick,Vector2(33,-1)+kick,Color("d3ede0"),1)
			draw_line(Vector2(13,1)+kick,Vector2(33,1)+kick,Color("438e99"),1)

func reload_duration(kind: String) -> float:
	var identity := str(worker.get("character_id")) if is_instance_valid(worker) and "character_id" in worker else "mara"
	return float(weapon_stats(kind).reload) * CharacterCatalog.reload_multiplier(identity)
