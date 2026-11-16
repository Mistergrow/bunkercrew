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
	var tx := Transform2D(aim_direction.angle(),Vector2.ZERO).scaled_local(Vector2(1,1 if aim_direction.x>=0 else -1))
	var handling := _reload_handling(reload_progress())
	if handling>0.0:
		# Reloading tips the muzzle up and draws the gun in toward the chest.
		tx = tx*Transform2D(-0.45*handling,Vector2(-3.0,1.5)*handling)
	return tx

## 0..1 through a running personal reload, -1 otherwise. Driven only by the
## replicated reload timer and kind, so guests see the same handling.
func reload_progress() -> float:
	if reload_timer<=0.0 or _reload_kind.is_empty() or _personal_mount()!=null: return -1.0
	return clampf(1.0-reload_timer/maxf(0.01,reload_duration(_reload_kind)),0.0,1.0)

static func _reload_handling(progress: float) -> float:
	if progress<0.0: return 0.0
	return smoothstep(0.0,0.10,progress)*(1.0-smoothstep(0.86,1.0,progress))

## Support hand through the reload, in this node's space: off the fore-end to
## the magazine, pull it, to the belt pouch, a fresh magazine up into the
## well (seated as the load sound plays), rack the bolt, back to the fore-end.
## Shotguns feed three shells into the tube instead. INF when not reloading.
func reload_hand(tx: Transform2D) -> Vector2:
	var r := reload_progress()
	if r<0.0: return Vector2.INF
	var grip: Vector2 = tx*GRIP_POINTS[1]
	var visual = worker.get_node_or_null("PixelVisual") if is_instance_valid(worker) else null
	var crouched: bool = visual!=null and "crouched" in visual and bool(visual.crouched)
	var pouch := Vector2(-12.0*float(worker.facing),9.0) if crouched else Vector2(-10.0*float(worker.facing),14.0)
	if family_for(_reload_kind)=="shotgun":
		var port: Vector2 = tx*Vector2(6,5)
		if r<0.12 or r>=0.88: return grip.lerp(port,smoothstep(0.0,0.12,r) if r<0.12 else 1.0-smoothstep(0.88,1.0,r))
		var shell := fposmod((r-0.12)/0.76*3.0,1.0)
		return port.lerp(pouch,sin(shell*PI))
	var well: Vector2 = tx*Vector2(0,10)
	var below: Vector2 = tx*Vector2(0,16)
	var handle: Vector2 = tx*Vector2(3,-6)
	if r<0.10: return grip
	if r<0.20: return grip.lerp(well,smoothstep(0.10,0.20,r))
	if r<0.28: return well.lerp(tx*Vector2(0,17),smoothstep(0.20,0.28,r))
	if r<0.36: return (tx*Vector2(0,17)).lerp(pouch,smoothstep(0.28,0.36,r))
	if r<0.43: return pouch.lerp(below,smoothstep(0.36,0.43,r))
	if r<0.48: return below.lerp(well,smoothstep(0.43,0.48,r))
	if r<0.60: return well.lerp(handle,smoothstep(0.48,0.60,r))
	if r<0.70: return handle+tx.basis_xform(Vector2(-4,0))*sin(smoothstep(0.60,0.70,r)*PI)
	if r<0.86: return handle.lerp(grip,smoothstep(0.70,0.86,r))
	return grip

func grip_positions() -> PackedVector2Array:
	# The receiver and foregrip travel with the same aim, mirror and recoil as
	# the gun pixels. Body poses and foreground gloves share these contacts.
	var tx := drawing_transform()
	var support := reload_hand(tx)
	if support.is_finite(): return PackedVector2Array([tx*(GRIP_POINTS[0]-Vector2(recoil,0)),support])
	return PackedVector2Array([tx*(GRIP_POINTS[0]-Vector2(recoil,0)),tx*(GRIP_POINTS[1]-Vector2(recoil,0))])

func grip_positions_for(visual: Node2D) -> PackedVector2Array:
	var tx := ActorWeatherGeometry.worker_transform(visual).affine_inverse()*visual.global_transform.affine_inverse()*global_transform
	var grips := grip_positions()
	return PackedVector2Array([tx*grips[0],tx*grips[1]])

## The weapon is an authored sprite in 7.5 degree attitudes (local aim from
## straight up to steeply down, generate_tool_turns.py), drawn upright on a
## whole texel. Reload tilt and recoil step through those attitudes; a bare
## receiver shows while the magazine is out of the well.
const TOOLS := preload("res://assets/workers/tool_turns.png")
const TURN_STEPS := 48
const TURN_FIRST := -13
const TURN_LAST := 10
const TURN_CELL := 88
const TURN_CENTRE := Vector2(44, 44)
const TURN_TOP := 224
const TURN_ROWS := ["rifle", "shotgun", "arcgun", "veteran_rifle", "breacher_shotgun", "storm_arcgun"]
const BARE_ROWS := ["rifle", "veteran_rifle", "arcgun", "storm_arcgun"]

## The drawn attitude: mirror (1 or -1) applied after an upright cell whose
## rotation and texel origin in that mirrored frame are kept in `_drawn_turned`
## (members, so drawing allocates nothing per frame).
var _drawn_mirror := 1.0
var _drawn_turned := Transform2D.IDENTITY
var _drawn_step := 0

func update_attitude() -> void:
	_drawn_mirror = 1.0 if aim_direction.x >= 0 else -1.0
	var local := atan2(aim_direction.y, absf(aim_direction.x))
	var handling := _reload_handling(reload_progress())
	var origin := Vector2(-3.0, 1.5).rotated(local) * handling
	_drawn_step = clampi(roundi((local - 0.45 * handling) / TAU * TURN_STEPS), TURN_FIRST, TURN_LAST)
	var turned := float(_drawn_step) * TAU / TURN_STEPS
	_drawn_turned = Transform2D(turned, (origin + Vector2(-recoil, 0).rotated(turned)).round())

func _draw() -> void:
	if not aiming or not can_use():
		return
	update_attitude()
	var mirror := _drawn_mirror
	var turned := _drawn_turned
	var step := _drawn_step
	var progress := reload_progress()
	var magazine := _magazine_offset(progress)
	var bare := magazine != 0.0 and BARE_ROWS.has(weapon_kind)
	var row := TURN_ROWS.size() + BARE_ROWS.find(weapon_kind) if bare else maxi(0, TURN_ROWS.find(weapon_kind))
	var region := Rect2(Vector2((step - TURN_FIRST) * TURN_CELL, TURN_TOP + row * TURN_CELL), Vector2.ONE * TURN_CELL)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(mirror, 1))
	draw_texture_rect_region(TOOLS, Rect2(turned.origin - TURN_CENTRE, region.size), region)
	var parts := Transform2D(0.0, Vector2(mirror, 1), 0.0, Vector2.ZERO) * turned
	draw_set_transform_matrix(parts)
	# Moving parts of the reload in the same attitude: a magazine sliding in or
	# out of the well and the rifle bolt racked back.
	if bare and magazine > 0.0: draw_rect(Rect2(Vector2(-3, 4 + roundf(magazine)), Vector2(5, 9)), Color("242f34"))
	var bolt := _bolt_travel(progress)
	if bolt > 0.0 and family_for(weapon_kind) == "rifle": draw_rect(Rect2(Vector2(-2 - roundf(bolt), -8), Vector2(10, 3)), Color("8b957f"))
	WeaponEffectArt.muzzle(self,Vector2(35,0),flash,0.13 if family_for(weapon_kind)=="arcgun" else 0.08,1,0.72 if family_for(weapon_kind)=="rifle" else 1.05,_shot_index,WeaponEffectArt.reduced(game),family_for(weapon_kind)=="arcgun",parts)
	draw_set_transform(Vector2.ZERO)
	_draw_reload_items(progress)
	_draw_gripping_hands()
	if aim_point != Vector2.ZERO:
		var marker := to_local(aim_point)
		var tint := PartyConfig.player_color(worker.player_id)
		tint.a = .65
		for offset: Vector2 in [Vector2(-6,0),Vector2(6,0),Vector2(0,-6),Vector2(0,6)]:
			draw_line(marker+offset,marker+offset*0.6,tint,1)

## Magazine offset below its well during a reload (-1: out of the gun).
static func _magazine_offset(progress: float) -> float:
	if progress<0.20: return 0.0
	if progress<0.28: return 7.0*smoothstep(0.20,0.28,progress)
	if progress<0.43: return -1.0
	if progress<0.48: return 6.0*(1.0-smoothstep(0.43,0.48,progress))
	return 0.0

static func _bolt_travel(progress: float) -> float:
	return 4.0*sin(smoothstep(0.60,0.70,progress)*PI) if progress>=0.60 and progress<0.70 else 0.0

func _draw_reload_items(progress: float) -> void:
	if progress<0.0: return
	var family := family_for(_reload_kind)
	var hand := reload_hand(drawing_transform())
	if family=="shotgun":
		var shell := fposmod((progress-0.12)/0.76*3.0,1.0)
		if progress>0.12 and progress<0.88 and shell>0.35 and shell<0.95:
			draw_rect(Rect2(hand+Vector2(-2,-4),Vector2(4,7)),Art.INK)
			draw_rect(Rect2(hand+Vector2(-1,-3),Vector2(2,4)),Color("b6493a"))
			draw_rect(Rect2(hand+Vector2(-1,1),Vector2(2,1)),Color("c9a764"))
		return
	var body := Color("242f34") if family!="arcgun" else Color("3c4f6a")
	if progress>=0.28 and progress<0.50:
		# The spent magazine drops and tumbles in two authored attitudes.
		var since := progress-0.28
		var seconds := since*reload_duration(_reload_kind)
		var start: Vector2 = drawing_transform()*Vector2(-0.5,15)
		var at := start+Vector2(-8.0*float(worker.facing)*since*4.0,450.0*seconds*seconds)
		var upright := int(seconds*18.0)%2==0
		var size := Vector2(4,8) if upright else Vector2(8,4)
		if at.y<start.y+26.0:
			draw_rect(Rect2((at-size*0.5).round(),size),body)
	if progress>=0.28 and progress<0.43:
		# A fresh magazine in the glove on its way up to the well.
		var at: Vector2 = hand+Vector2(-2,-1) if progress>=0.36 else hand
		draw_rect(Rect2((at+Vector2(-3,-2)).round(),Vector2(5,9)),Art.INK)
		draw_rect(Rect2((at+Vector2(-2,-1)).round(),Vector2(3,7)),body.lightened(0.18))

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

func reload_duration(kind: String) -> float:
	var identity := str(worker.get("character_id")) if is_instance_valid(worker) and "character_id" in worker else "mara"
	return float(weapon_stats(kind).reload) * CharacterCatalog.reload_multiplier(identity)
