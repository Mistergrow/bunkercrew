extends CharacterBody2D
## Host-owned transport. CampaignState persists vehicle_data; snapshots carry
## the live chassis and crew state. Fuel is charged only for real displacement.
const Seat := preload("res://scripts/convoy_seat.gd")
const VehicleArt := preload("res://scripts/convoy_vehicle_art.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const NetInput := preload("res://scripts/network_input.gd")
const PROJECTILE := preload("res://scenes/projectile.tscn")
const BASE_HP := 600.0
const BASE_FUEL := 30.0
const BASE_CARGO := 18
const SPEED := 125.0
const FUEL_PER_PIXEL := 1.0/300.0
const MAGAZINE := 40
const SEAT_ROLES: Array[String]=["driver","gunner","passenger_left","passenger_right"]
static var ALLOWED_CARGO: Array[String]:
	get: return ItemCatalog.cargo_kinds()
const VEHICLE_UPGRADES := CampaignCatalog.VEHICLE_UPGRADES
var game: Node
var expedition: Node
var driver_seat: Node2D
var gunner_seat: Node2D
var passenger_left_seat: Node2D
var passenger_right_seat: Node2D
var seats: Array[Node2D]=[]
var hp := BASE_HP
var max_hp := BASE_HP
var fuel := 12.0
var max_fuel := BASE_FUEL
var cargo: Dictionary = {}
var cargo_capacity := BASE_CARGO
var fuel_multiplier := 1.0
var has_mg := false
var top_speed:=SPEED
var acceleration:=190.0
var braking:=350.0
var reload_duration:=1.4
var mg_damage:=18.0
var incoming_damage_multiplier:=1.0
var ammo := 0
var reserve := 0
var open_pack := 0
var vehicle_upgrades: Array = []
var aim_angle := -0.08
var recoil := 0.0
var flash := 0.0
var flash_tick := 0
var cooldown := 0.0
var reload_timer := 0.0
var hit_flash := 0.0
var facing := 1.0
var wheel_phase := 0.0
var suspension := 0.0
var animation_time := 0.0
var travel_distance := 0.0
var road_bounds := Vector2(-100000,100000)
var driving_enabled := true
var destroyed := false
var journey_state: Dictionary = Journey.new_state()
var defenders: Array[Node2D] = []
var _service_worker: Node2D
var _service_frame := -100
var _tool_frame := -100
var collider: CollisionShape2D
var cab_collider: CollisionShape2D
var visual: Node2D
var weapon_visual: Node2D
var wetness: Node2D

func _ready() -> void:
	add_to_group("convoy_vehicles")
	add_to_group("walls")
	add_to_group("interactables")
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	z_index=4
	collision_layer=2
	collision_mask=1
	collider=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=Vector2(182,44)
	collider.shape=shape
	collider.position=Vector2(0,-22)
	add_child(collider)
	cab_collider=CollisionShape2D.new()
	var cab_shape:=RectangleShape2D.new()
	cab_shape.size=Vector2(54,60)
	cab_collider.shape=cab_shape
	cab_collider.position=Vector2(62,-37)
	add_child(cab_collider)
	driver_seat=Seat.new()
	driver_seat.name="DriverSeat"
	driver_seat.vehicle=self
	driver_seat.game=game
	driver_seat.role="driver"
	add_child(driver_seat)
	gunner_seat=Seat.new()
	gunner_seat.name="GunnerSeat"
	gunner_seat.vehicle=self
	gunner_seat.game=game
	gunner_seat.role="gunner"
	add_child(gunner_seat)
	seats=[driver_seat,gunner_seat]
	for seat_role in ["passenger_left","passenger_right"]:
		var seat:=Seat.new()
		seat.name="PassengerLeftSeat" if seat_role=="passenger_left" else "PassengerRightSeat"
		seat.vehicle=self
		seat.game=game
		seat.role=seat_role
		add_child(seat)
		seats.append(seat)
	passenger_left_seat=seats[2]
	passenger_right_seat=seats[3]
	visual=Node2D.new()
	visual.name="PaintedChassis"
	visual.draw.connect(func(): VehicleArt.draw_hull(visual,self))
	add_child(visual)
	weapon_visual=Node2D.new()
	weapon_visual.name="ArticulatedMG"
	# Keep the mounted barrel and muzzle ahead of seated crew at world layer 15.
	weapon_visual.z_index=12
	weapon_visual.draw.connect(func(): VehicleArt.draw_weapon(weapon_visual,self))
	add_child(weapon_visual)
	wetness=preload("res://scripts/convoy_weather.gd").new()
	wetness.name="TireWeather"
	add_child(wetness)
	var engine_voice:=preload("res://scripts/convoy_audio.gd").new()
	engine_voice.name="DieselEngine"
	add_child(engine_voice)
	# Cosmetic transitions infer crew occupancy; they never own a gameplay timer.
	var presentation_script = load("res://scripts/convoy_presentation.gd") if ResourceLoader.exists("res://scripts/convoy_presentation.gd") else null
	if presentation_script != null:
		var presentation: Node = presentation_script.new()
		presentation.name="ConvoyPresentation"
		add_child(presentation)
	refresh_upgrades()

func setup(owner_game: Node, controller: Node=null) -> void:
	game=owner_game
	expedition=controller
	for seat in seats: seat.game=game
	refresh_upgrades()

func authoritative() -> bool:
	var network=NetInput.for_game(game)
	return network==null or bool(network.is_host)

func refresh_upgrades() -> void:
	var upgrades=game.get("upgrades") if is_instance_valid(game) else null
	if is_instance_valid(upgrades) and upgrades.has_method("has_upgrade"):
		vehicle_upgrades.clear()
		for id in VEHICLE_UPGRADES:
			if upgrades.has_upgrade(id): vehicle_upgrades.append(id)
	var old_max:=max_hp
	var stats:=preload("res://scripts/campaign_catalog.gd").vehicle_stats(vehicle_upgrades)
	max_hp=float(stats.max_hp)
	max_fuel=float(stats.fuel_capacity)
	cargo_capacity=int(stats.cargo_capacity)
	fuel_multiplier=float(stats.fuel_multiplier)
	has_mg=bool(stats.mounted_mg)
	_apply_driving_stats(stats)
	hp=clampf(hp+maxf(0,max_hp-old_max),0,max_hp)
	fuel=clampf(fuel,0,max_fuel)

func _apply_driving_stats(stats: Dictionary) -> void:
	top_speed=float(stats.get("speed",SPEED))
	acceleration=float(stats.get("acceleration",190.0))
	braking=float(stats.get("braking",350.0))
	reload_duration=float(stats.get("reload_time",1.4))
	mg_damage=float(stats.get("mg_damage",18.0))
	incoming_damage_multiplier=float(stats.get("damage_multiplier",1.0))

func configure_trip(start: Vector2, bounds: Vector2, data: Dictionary={}) -> void:
	global_position=start
	road_bounds=Vector2(minf(bounds.x,bounds.y),maxf(bounds.x,bounds.y))
	velocity=Vector2.ZERO
	travel_distance=0.0
	if data.get("upgrades",[]) is Array:
		vehicle_upgrades.clear()
		for id in data.get("upgrades",[]):
			if id in VEHICLE_UPGRADES and not vehicle_upgrades.has(id): vehicle_upgrades.append(id)
	refresh_upgrades()
	hp=clampf(float(data.get("hp",max_hp)),0,max_hp)
	fuel=clampf(float(data.get("fuel",12.0)),0,max_fuel)
	ammo=clampi(int(data.get("ammo",0)),0,MAGAZINE)
	reserve=clampi(int(data.get("reserve",0)),0,240)
	open_pack=clampi(int(data.get("open_pack",0)),0,39)
	cargo.clear()
	var incoming=data.get("cargo",{})
	if incoming is Dictionary:
		for kind in ALLOWED_CARGO:
			accept_material(kind,maxi(0,int(incoming.get(kind,0))))
	destroyed=hp<=0
	driving_enabled=not destroyed
	if is_instance_valid(collider): collider.set_deferred("disabled",destroyed)
	if is_instance_valid(cab_collider): cab_collider.set_deferred("disabled",destroyed)

func vehicle_data() -> Dictionary:
	return {"unlocked":true,"hp":hp,"fuel":fuel,"cargo":cargo.duplicate(true),"upgrades":vehicle_upgrades.duplicate(),"ammo":ammo,"reserve":reserve,"open_pack":open_pack}

func cargo_count() -> int:
	var result:=0
	for value in cargo.values(): result+=int(value)
	return result

func accept_material(kind: String, amount: int=1) -> int:
	if not authoritative() or not kind in ALLOWED_CARGO or amount<=0: return 0
	var accepted:=mini(amount,maxi(0,cargo_capacity-cargo_count()))
	if accepted>0: cargo[kind]=int(cargo.get(kind,0))+accepted
	if accepted>0 and cargo_count()>=cargo_capacity and is_instance_valid(game):
		var events=game.get("combat_events")
		if is_instance_valid(events): events.unlock("cargo_full")
	return accepted

func take_material(kind: String, amount: int=1) -> bool:
	if not authoritative() or amount<=0 or int(cargo.get(kind,0))<amount: return false
	cargo[kind]=int(cargo[kind])-amount
	if int(cargo[kind])==0: cargo.erase(kind)
	return true

func interaction_point() -> Vector2:
	if journey_state.phase=="repair": return service_point()
	return global_position+Vector2(0,-25)

func service_point() -> Vector2:
	return global_position+Vector2(float(VehicleArt.WHEELS[0])*facing,-20)

func work_uses_real_time() -> bool:
	# The timing window and tool work share the same real physics clock.
	return journey_state.phase=="repair"

func can_interact(worker) -> bool:
	if not is_instance_valid(worker) or not worker is Node2D or worker.is_queued_for_deletion() or worker.get("game")!=game or destroyed: return false
	if journey_state.phase=="repair": return can_service(worker)
	return free_seat()!=null

func can_service(worker) -> bool:
	if not is_instance_valid(worker) or not worker is Node2D or worker.is_queued_for_deletion() or not worker.is_inside_tree() or worker.get("game")!=game or destroyed or journey_state.phase!="repair": return false
	if not worker.has_method("can_act") or not worker.can_act() or is_instance_valid(worker.get("mounted_turret")): return false
	if is_instance_valid(game) and game.get("players") is Array and not worker in game.players: return false
	if bool(worker.get_meta("network_departed",false)): return false
	var network=NetInput.for_game(game)
	if is_instance_valid(network) and network.has_method("is_player_connected") and not network.is_player_connected(int(worker.get("player_id"))): return false
	var center: Vector2=worker.global_position-Vector2(0,20)
	return center.distance_to(service_point())<=78 and absf(center.y-service_point().y)<=60

func service_prompt() -> String:
	match str(journey_state.repair_step):
		"jack": return LocaleText.text("REIFENPANNE · Wagenheber ansetzen · E halten")
		"remove": return LocaleText.text("REIFENPANNE · Defektes Rad abnehmen · E halten")
		"fit": return LocaleText.text("REIFENPANNE · Ersatzrad einsetzen · E halten")
		"tighten": return LocaleText.format("RAD FESTZIEHEN · %d / 3 · E im markierten Bereich oder E halten",journey_state.repair_bolts)
		"lower": return LocaleText.text("REIFENPANNE · Wagenheber ablassen · E halten")
	return LocaleText.text("Reparatur beendet · Alle einsteigen")

func service_action(worker, delta: float, tapped: bool, held: bool) -> bool:
	if not authoritative() or not can_service(worker) or not is_finite(delta) or delta<=0 or delta>.1 or (not tapped and not held): return false
	var frame:=Engine.get_physics_frames()
	if _tool_frame==frame: return false
	if is_instance_valid(_service_worker) and _service_worker!=worker and can_service(_service_worker) and frame-_service_frame<=2: return false
	_service_worker=worker
	_service_frame=frame
	_tool_frame=frame
	journey_state.solo_assist=_solo_worker()!=null
	return Journey.service(journey_state,delta,tapped,held,int(worker.get("player_id")))

func _single_crew_member() -> Node2D:
	if not is_instance_valid(game) or not game.get("players") is Array: return null
	var candidate: Node2D = null
	var network=NetInput.for_game(game)
	for worker in game.players:
		if not is_instance_valid(worker) or not worker is Node2D or worker.is_queued_for_deletion() or not worker.is_inside_tree() or worker.get("game")!=game: continue
		if bool(worker.get_meta("network_departed",false)): continue
		if is_instance_valid(network) and network.has_method("is_player_connected") and not network.is_player_connected(int(worker.player_id)): continue
		# A downed second person is still a real crew slot, not a solo game.
		if candidate!=null: return null
		candidate=worker
	return candidate

func _solo_worker() -> Node2D:
	var worker:=_single_crew_member()
	return worker if is_instance_valid(worker) and (not worker.has_method("is_downed") or not worker.is_downed()) else null

func _sync_solo_defenders() -> void:
	var worker:=_single_crew_member()
	var road: bool=is_instance_valid(expedition) and expedition.get("road_open")==true and str(expedition.get("stage")) in ["travel","stop"]
	var enabled: bool=authoritative() and NetInput.for_game(game)==null and is_instance_valid(worker) and road and game.get("started")==true and not destroyed
	if enabled and defenders.is_empty() and journey_state.phase in ["starting","driving","repair"]:
		var escort_script: GDScript=load("res://scripts/convoy_defender.gd")
		var identities: Array[String]=["mara","branko","ivo"]
		identities.erase(str(worker.get("character_id")))
		for index in 2:
			var defender: Node2D=escort_script.new()
			defender.name="RearEscort" if index==0 else "FrontEscort"
			defender.game=game
			defender.vehicle=self
			defender.character_id=identities[index]
			defender.post_side=-1.0 if index==0 else 1.0
			add_child(defender)
			defenders.append(defender)
	for defender in defenders:
		if not is_instance_valid(defender) or defender.is_queued_for_deletion(): continue
		if enabled and journey_state.phase=="repair": defender.deploy()
		else: defender.stow()

func active_defenders() -> int:
	var count:=0
	for defender in defenders:
		if is_instance_valid(defender) and not defender.is_queued_for_deletion() and defender.get("game")==game and defender.can_be_targeted(): count+=1
	return count

func repair_roles_text() -> String:
	var operator:=int(journey_state.repair_operator)
	var escorts:=active_defenders()
	if operator>0:
		return LocaleText.format("Reifenwechsel: P%d · Begleiter geben Deckung" if escorts>0 else "Reifenwechsel: P%d · Übrige Crew gibt Deckung",operator)
	if journey_state.solo_assist and is_instance_valid(_solo_service_medic()):
		return LocaleText.text("SAN-1 wechselt · Du und Begleiter geben Deckung" if escorts>0 else "SAN-1 wechselt · Du verteidigst den Transporter")
	return LocaleText.text("E am Hinterrad · Begleiter verteidigen" if escorts>0 else "Am Hinterrad E halten · Andere sichern")

func _solo_service_medic() -> Node2D:
	var worker:=_solo_worker()
	if not is_instance_valid(worker): return null
	var medic=game.get("medic")
	if not is_instance_valid(medic) or medic.is_queued_for_deletion() or medic.get("game")!=game or not medic is Node2D: return null
	if medic.get("treating")==true or is_instance_valid(medic.get("target")): return null
	if (medic.global_position-Vector2(0,20)).distance_to(service_point())>64 or worker.global_position.distance_to(global_position)>350: return null
	return medic

func _advance_solo_assist(delta: float) -> void:
	if not is_finite(delta) or delta<=0 or not journey_state.solo_assist or journey_state.phase!="repair" or Engine.get_physics_frames()-_service_frame<=2: return
	if not authoritative() or _tool_frame==Engine.get_physics_frames(): return
	var worker:=_solo_worker()
	if not is_instance_valid(worker):
		journey_state.solo_assist=false
		return
	# Medical treatment and tool work are separate physical jobs. SAN may
	# prioritize an injured player beside the wheel without repairing in parallel.
	if not is_instance_valid(_solo_service_medic()): return
	_tool_frame=Engine.get_physics_frames()
	Journey.service(journey_state,minf(delta,.1)*.55,false,true,int(worker.player_id))
	journey_state.repair_operator=0

func begin_breakdown() -> bool:
	if not authoritative() or destroyed or not Journey.begin_breakdown(journey_state): return false
	driving_enabled=false
	velocity.x=0.0
	if is_instance_valid(driver_seat.occupant):
		var driver: Node2D=driver_seat.occupant
		driver_seat.exit()
		# Place the repairer outside the rear chassis collider, beside the flat.
		driver.global_position=service_point()+Vector2(-50*facing,20)
	_sync_solo_defenders()
	return true

func display_name(_uppercase: bool=false) -> String:
	return LocaleText.text("Konvoi-Transporter")

func prompt(worker: Node) -> String:
	if journey_state.phase=="repair": return service_prompt()
	var available:=free_seat()
	return available.prompt(worker) if available!=null else LocaleText.text("Alle vier Plätze sind besetzt")

func interact(worker: Node2D, delta: float) -> void:
	if journey_state.phase=="repair":
		service_action(worker,delta,NetInput.just_pressed(worker,"interact"),NetInput.is_pressed(worker,"interact"))
		return
	var available:=free_seat()
	if available!=null: available.interact(worker,delta)

func free_seat() -> Node2D:
	for seat in seats:
		if not is_instance_valid(seat.occupant): return seat
	return null

func board_any(worker: Node2D) -> bool:
	var available:=free_seat()
	return board(worker,available.role) if available!=null else false

func switch_seat(worker: Node2D) -> bool:
	if not authoritative() or destroyed: return false
	var current:=seat_for(worker)
	if current==null: return false
	var at:=seats.find(current)
	for offset in range(1,seats.size()):
		var next:=seats[(at+offset)%seats.size()]
		if is_instance_valid(next.occupant): continue
		current.exit(false)
		return next.enter(worker)
	return false

func board(worker: Node2D, preferred_seat: String="driver") -> bool:
	if not authoritative() or destroyed or not is_instance_valid(worker): return false
	if preferred_seat not in SEAT_ROLES or not "game" in worker or worker.game!=game: return false
	if worker.global_position.distance_to(global_position)>190.0: return false
	var seat=seats[SEAT_ROLES.find(preferred_seat)]
	if seat.enter(worker):
		_sound("weapon_mount")
		return true
	return false

func dismount(worker: Node2D) -> bool:
	if not authoritative(): return false
	for seat in seats:
		if is_instance_valid(seat) and seat.occupant==worker:
			seat.exit()
			return true
	return false

func seat_for(worker: Node) -> Node2D:
	for seat in seats:
		if is_instance_valid(seat) and seat.occupant==worker: return seat
	return null

func is_blocking() -> bool:
	return hp>0 and not destroyed

func attack_point() -> Vector2:
	return global_position+Vector2(0,-30)

func impact_material() -> String:
	return "metal"

func impact_sound() -> String:
	return "impact_metal"

func uses_rolling_contacts() -> bool:
	return true

func weather_segments() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for pair in ActorWeatherGeometry.atlas_top(VehicleArt.HULL,VehicleArt.REGION,VehicleArt.BODY):
		var start:=to_global(Vector2(pair[0])*Vector2(facing,1)+Vector2(0,suspension))
		var end:=to_global(Vector2(pair[1])*Vector2(facing,1)+Vector2(0,suspension))
		var normal: Vector2=(end-start).orthogonal().normalized()
		if normal.y>0: normal=-normal
		result.append({"from":start,"to":end,"normal":normal,"material":"metal"})
	return result

func take_damage(amount: float) -> void:
	if not authoritative() or destroyed or not is_finite(amount) or amount<=0: return
	hp=maxf(0,hp-amount*incoming_damage_multiplier)
	hit_flash=0.16
	if hp>0: return
	destroyed=true
	Journey.change_phase(journey_state,"failed","failed")
	driving_enabled=false
	velocity=Vector2.ZERO
	for seat in seats: seat.exit()
	collider.set_deferred("disabled",true)
	cab_collider.set_deferred("disabled",true)
	if is_instance_valid(game): ImpactBurst.emit(game,attack_point(),"explosion",Vector2.UP,1.1)
	if is_instance_valid(expedition) and expedition.has_method("vehicle_destroyed"): expedition.vehicle_destroyed()

func _physics_process(delta: float) -> void:
	if not authoritative() or not is_finite(delta) or delta<=0: return
	Journey.advance(journey_state,delta)
	_sync_solo_defenders()
	if not is_instance_valid(_service_worker) or not can_service(_service_worker) or Engine.get_physics_frames()-_service_frame>2:
		_service_worker=null
		journey_state.repair_operator=0
	_advance_solo_assist(delta)
	cooldown=maxf(0,cooldown-delta)
	if reload_timer>0:
		reload_timer=maxf(0,reload_timer-delta)
		if reload_timer<=0:
			var transfer:=mini(MAGAZINE-ammo,reserve)
			ammo+=transfer
			reserve-=transfer
			_sound("reload_cannon_close")
	var switched: Array[Node2D]=[]
	for seat in seats:
		if not is_instance_valid(seat.occupant): continue
		if seat.occupant.has_method("can_act") and not seat.occupant.can_act():
			seat.exit()
		elif NetInput.just_pressed(seat.occupant,"interact") and Engine.get_physics_frames()>seat.enter_frame+1:
			seat.exit()
		elif not seat.occupant in switched and NetInput.just_pressed(seat.occupant,"cycle_target") and Engine.get_physics_frames()>seat.enter_frame+1:
			switched.append(seat.occupant)
			switch_seat(seat.occupant)
	var driver=driver_seat.occupant
	var throttle:=NetInput.axis(driver,"left","right") if is_instance_valid(driver) else 0.0
	advance_motion(delta,throttle)
	var gunner=gunner_seat.occupant
	var controller=gunner if is_instance_valid(gunner) else driver
	if has_mg and not destroyed and is_instance_valid(controller):
		if NetInput.mouse_aim(controller): aim_angle=(NetInput.aim_position(controller)-gun_origin()).angle()
		else:
			aim_angle+=NetInput.axis(controller,"aim_up","aim_down")*delta*1.2
			if NetInput.axis(controller,"left","right")<0: aim_angle=-PI+0.1
			elif NetInput.axis(controller,"left","right")>0: aim_angle=-0.1
		aim_angle=clampf(wrapf(aim_angle,-PI*1.5,PI*0.5),-PI-0.7,0.7)
		if NetInput.just_pressed(controller,"reload"): start_reload()
		if NetInput.is_pressed(controller,"fire") or NetInput.just_pressed(controller,"fire"): fire(controller)
	for seat in seats: seat.sync_operator()

func advance_motion(delta: float, throttle: float) -> void:
	if not authoritative() or not is_finite(delta) or delta<=0 or not is_finite(throttle) or destroyed: return
	var input_axis:=clampf(throttle,-1,1) if driving_enabled and fuel>0 else 0.0
	velocity.x=move_toward(velocity.x,input_axis*top_speed,delta*(acceleration if absf(input_axis)>0.1 else braking))
	# Coasting stops at the last fraction of a litre; no movement is free.
	if fuel<=0: velocity.x=0
	elif absf(velocity.x)*delta*FUEL_PER_PIXEL*fuel_multiplier>fuel:
		velocity.x=signf(velocity.x)*fuel/(delta*FUEL_PER_PIXEL*fuel_multiplier)
	velocity.y=minf(700,velocity.y+900*delta)
	var before:=global_position
	move_and_slide()
	global_position.x=clampf(global_position.x,road_bounds.x,road_bounds.y)
	var distance:=absf(global_position.x-before.x)
	fuel=maxf(0,fuel-distance*FUEL_PER_PIXEL*fuel_multiplier)
	travel_distance+=distance
	var events=game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(driver_seat.occupant) and is_instance_valid(events) and events.has_method("record_drive"):
		events.record_drive(driver_seat.occupant,self,maxf(0,global_position.x-before.x))
	wheel_phase+=(global_position.x-before.x)/12.0
	if absf(velocity.x)>3: facing=signf(velocity.x)
	cab_collider.position.x=62*facing

func gun_origin() -> Vector2:
	return global_position+Vector2(-7*facing,-77+suspension)

func refill_ammo(maximum: int=-1) -> int:
	if not authoritative() or not has_mg or destroyed: return 0
	var room:=maxi(0,240-reserve)
	if maximum>=0: room=mini(room,maximum)
	var moved:=0
	while moved<room:
		if open_pack==0:
			if not take_material("ammo",1): break
			open_pack=20
		var amount:=mini(open_pack,room-moved)
		open_pack-=amount
		moved+=amount
	reserve+=moved
	return moved

func start_reload() -> bool:
	if not authoritative() or not has_mg or destroyed or reload_timer>0: return false
	if ammo>=MAGAZINE: return refill_ammo()>0
	var need:=MAGAZINE-ammo
	if reserve<need: refill_ammo(need-reserve)
	if reserve<=0: return false
	reload_timer=reload_duration
	_sound("reload_cannon_open")
	return true

func fire(worker: Node=null) -> bool:
	if not authoritative() or not has_mg or destroyed or cooldown>0 or reload_timer>0: return false
	if ammo<=0:
		start_reload()
		return false
	var direction:=Vector2.from_angle(aim_angle)
	var origin:=gun_origin()
	var muzzle:=origin+direction*47
	var ray:=PhysicsRayQueryParameters2D.create(origin,muzzle,1|2|4)
	ray.exclude=[get_rid()]
	ray.hit_from_inside=true
	var hit:=get_world_2d().direct_space_state.intersect_ray(ray)
	ammo-=1
	var events=game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(worker) and is_instance_valid(events) and events.has_method("record_activity"): events.record_activity(worker)
	cooldown=0.12
	flash=0.075
	recoil=3.0
	flash_tick+=1
	if not hit.is_empty():
		ImpactBurst.contact(game,hit.collider,hit.position,hit.normal,direction,0.65,"turret")
		if hit.collider is Node and hit.collider.is_in_group("enemies") and hit.collider.has_method("take_damage"):
			if is_instance_valid(game) and game.has_method("combat_hit"): game.combat_hit(hit.collider,mg_damage,worker)
			else: hit.collider.take_damage(mg_damage)
	else:
		var projectile=PROJECTILE.instantiate()
		projectile.game=game
		projectile.damage=mg_damage
		projectile.direction=direction
		projectile.credit_worker=worker
		projectile.source=self
		projectile.life=0.8
		get_parent().add_child(projectile)
		projectile.global_position=muzzle
	_sound("shot_rifle")
	return true

func _sound(sound_name: String) -> void:
	if is_instance_valid(game): preload("res://scripts/spatial_sound.gd").emit(game,sound_name,gun_origin())

func _process(delta: float) -> void:
	animation_time+=delta
	recoil=move_toward(recoil,0,delta*22)
	flash=maxf(0,flash-delta)
	hit_flash=maxf(0,hit_flash-delta)
	suspension=sin(wheel_phase*1.7)*minf(absf(velocity.x)/SPEED,1)*0.85
	for seat in seats: seat.sync_operator()
	if is_instance_valid(visual): visual.queue_redraw()
	if is_instance_valid(weapon_visual): weapon_visual.queue_redraw()
	queue_redraw()

func _draw() -> void:
	VehicleArt.draw_running_gear(self,self)

func sync_replica() -> void:
	# NetworkWorld freezes gameplay callbacks and invokes this presentation hook.
	suspension=sin(wheel_phase*1.7)*minf(absf(velocity.x)/SPEED,1)*0.85
	_apply_driving_stats(CampaignCatalog.vehicle_stats(vehicle_upgrades))
	for seat in seats: seat.sync_operator()
	if is_instance_valid(collider): collider.set_deferred("disabled",destroyed)
	if is_instance_valid(cab_collider):
		cab_collider.set_deferred("disabled",destroyed)
		cab_collider.position.x=62*facing
	visual.queue_redraw()
	weapon_visual.queue_redraw()
	queue_redraw()

func _exit_tree() -> void:
	for seat in seats:
		if is_instance_valid(seat): seat.exit()
