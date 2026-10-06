class_name FieldMedic
extends CharacterBody2D
const EquipmentArt := preload("res://scripts/support_equipment_art.gd")
const RhythmPresentation := preload("res://scripts/rhythm_presentation.gd")
const RhythmPose := preload("res://scripts/medic_rhythm_pose.gd")
const ExpressionCue := preload("res://scripts/medic_expression.gd")
## SAN-1 is a physical rescue assistant, not another controllable player. It
## carries the same finite medical charges and calls the shared treatment API.
var game: Node
var wetness: ActorWetness
var medical_supplies := MedicalCatalog.MAX_CHARGES
var status_label := "SAN-1 · Bereitschaft"
var target: Node2D
var treating := false
var treatment_progress := 0.0
var climbing := false
var facing := 1.0
const Logistics = preload("res://scripts/medic_logistics.gd")
var logistics: RefCounted
var logistics_cargo := ""
var logistics_phase := "idle"
var logistics_progress := 0.0
var rhythm_pose := RhythmPose.new()
var expression := ExpressionCue.new()
var _observed_target := 0
var _observed_logistics_phase := "idle"
var _observed_blocked := false
var navigation: MedicNavigation
var route: Array[Dictionary] = []
var elapsed := 0.0
var refill_progress := 0.0
var _rest_delay := 0.0
var _last_core_hp := -1.0
var _replan_clock := 0.0
var _last_destination := Vector2.INF
var _previous_position := Vector2.ZERO
var _stuck_time := 0.0
var _jump_elapsed := 0.0
var _emergency_mission := false
var _mission_complete := false
var _returning := false
var _motion_phase := 0.0
var _idle_time := 0.0
var _ladder := Rect2()
var treatments_completed := 0
var revives_completed := 0
const HOME_OFFSET := Vector2(55,0)

func _ready() -> void:
	add_to_group("medics")
	collision_layer=0
	collision_mask=1
	floor_snap_length=6.0
	z_index=14
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var shape:=CollisionShape2D.new()
	var box:=RectangleShape2D.new()
	box.size=MedicNavigation.BODY_SIZE
	shape.shape=box
	shape.position=Vector2(0,-MedicNavigation.BODY_SIZE.y*.5)
	add_child(shape)
	navigation=MedicNavigation.new(self,game)
	logistics=Logistics.new(self)
	_previous_position=global_position
	wetness=ActorWetness.new()
	wetness.name="Wetness"
	add_child(wetness)

func can_act() -> bool:
	return is_inside_tree() and not is_queued_for_deletion()

func dance_level() -> int:
	var research = game.get("upgrades") if is_instance_valid(game) else null
	return research.medic_dance_level() if is_instance_valid(research) else 0

func dance_allowed() -> bool:
	if not can_act() or not is_instance_valid(game) or not game.get("started") or get_tree().paused: return false
	if dance_level() <= 0 or _blocked_status() or global_position.distance_to(_home()) > 12: return false
	if is_instance_valid(target) or treating or climbing or refill_progress > 0 or _rest_delay > 0: return false
	if medical_supplies < MedicalCatalog.MAX_CHARGES or not logistics_cargo.is_empty() or logistics_phase != "idle": return false
	if not route.is_empty() or velocity.length() >= 4 or _idle_time < 0.32: return false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.get("game") == game and not enemy.is_queued_for_deletion() and global_position.distance_squared_to(enemy.global_position) < 370.0 * 370.0: return false
	for projectile in get_tree().get_nodes_in_group("air_projectiles"):
		if projectile.get("game") == game and not projectile.is_queued_for_deletion() and global_position.distance_squared_to(projectile.global_position) < 270.0 * 270.0: return false
	return true

func notice_task(_kind: String, destination: Node2D) -> void:
	# A brief reaction, never an added delay to rescue or transport.
	expression.notice("alert", to_local(destination.global_position) if is_instance_valid(destination) else Vector2(facing,0))
	_observed_logistics_phase = logistics_phase

func _blocked_status() -> bool:
	if logistics_phase == "holding": return true
	for key: String in ["SAN-1 · Rückweg blockiert", "SAN-1 · Transportweg blockiert"]:
		if status_label == LocaleText.text(key): return true
	if is_instance_valid(target):
		return status_label == LocaleText.format("SAN-1 · Zugang zu P%d blockiert", target.player_id) or status_label == LocaleText.format("SAN-1 · P%d: sicheren Stand suchen", target.player_id)
	return false

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.get("started"):
		rhythm_pose.clear()
		expression.clear()
		return
	var target_id := target.get_instance_id() if is_instance_valid(target) else 0
	if target_id != _observed_target:
		_observed_target = target_id
		if target_id != 0: notice_task("medical", target)
	# Replicas infer the same short reaction from existing authoritative fields.
	if logistics_phase == "collect" and _observed_logistics_phase != "collect":
		notice_task("transport", null)
	_observed_logistics_phase = logistics_phase
	var blocked := _blocked_status()
	if blocked and not _observed_blocked: expression.notice("search")
	_observed_blocked = blocked
	var redraw := expression.advance(delta)
	redraw = rhythm_pose.advance(delta, dance_allowed(), RhythmPresentation.frame_for(self), dance_level()) or redraw
	if redraw: queue_redraw()

func take_medical_supply() -> bool:
	if medical_supplies<=0: return false
	medical_supplies-=1
	return true

func _home() -> Vector2:
	return game.core.global_position+HOME_OFFSET if is_instance_valid(game) and is_instance_valid(game.get("core")) else Vector2(205,430)

func _humans() -> Array:
	return game.players.filter(func(player):return is_instance_valid(player) and "medical" in player and is_instance_valid(player.medical)) if is_instance_valid(game) and "players" in game else []

func _emergency_required(humans: Array) -> bool:
	return humans.size()>1 and humans.all(func(player):return player.is_downed())

func _patient_allowed(patient) -> bool:
	return is_instance_valid(patient) and "medical" in patient and is_instance_valid(patient.medical) and patient.medical.needs_medical_help()

func _select_patient(humans: Array):
	if humans.size()>1 and not _emergency_required(humans):
		if _emergency_mission and not _mission_complete and _patient_allowed(target) and target.is_downed(): return target
		return null
	var candidates:=humans.filter(func(player):return player.medical.needs_medical_help())
	if candidates.is_empty(): return null
	candidates.sort_custom(func(a,b):
		var priority_a: int=(0 if a.medical.state=="critical" else (1 if a.is_downed() else 2))
		var priority_b: int=(0 if b.medical.state=="critical" else (1 if b.is_downed() else 2))
		return priority_a<priority_b if priority_a!=priority_b else global_position.distance_squared_to(a.global_position)<global_position.distance_squared_to(b.global_position))
	return candidates[0]

func _physics_process(delta: float) -> void:
	if not is_instance_valid(game) or not game.get("started") or not logistics.authoritative():
		return
	if _travel_tick(delta): return
	elapsed+=delta
	_replan_clock=maxf(0.0,_replan_clock-delta)
	_rest_delay=maxf(0.0,_rest_delay-delta)
	_update_combat_delay()
	treating=false
	treatment_progress=0.0
	var humans:=_humans()
	var chosen=_select_patient(humans)
	if chosen!=target:
		target=chosen
		route.clear()
		_last_destination=Vector2.INF
		_replan_clock=0.0
		_mission_complete=false
		_emergency_mission=_emergency_required(humans) and is_instance_valid(target)
	if is_instance_valid(target) or medical_supplies<MedicalCatalog.MAX_CHARGES:
		logistics.suspend()
	if medical_supplies<=0:
		_return_home(delta,true)
	elif not is_instance_valid(target):
		if medical_supplies<MedicalCatalog.MAX_CHARGES or not logistics.tick(delta):
			_return_home(delta,medical_supplies<MedicalCatalog.MAX_CHARGES)
	elif target.medical.reachable_can_aid(self):
		_returning=false
		route.clear()
		_stand(delta)
		var down_before: bool=target.is_downed()
		if velocity.length()<=18:
			treating=true
			var label: String=LocaleText.text("Reanimation") if target.medical.state=="critical" else (LocaleText.text("Wiederbelebung") if down_before else (LocaleText.text("Schiene") if target.medical.fractured else LocaleText.text("Versorgung")))
			status_label=LocaleText.format("SAN-1 · P%d %s", [target.player_id,label])
			var completed: bool=target.medical.begin_or_continue_aid(self,delta)
			treatment_progress=target.medical.progress_for(self)
			if completed:
				treatments_completed+=1
				if down_before: revives_completed+=1
				_mission_complete=true
				if _emergency_mission:
					target=null
					_emergency_mission=false
					treating=false
					_replan_clock=0.0
	else:
		_returning=false
		refill_progress=0.0
		_seek_patient(delta)
	_motion_phase+=global_position.distance_to(_previous_position)*.22
	_previous_position=global_position
	_idle_time=_idle_time+delta if velocity.length()<4 and not climbing and not treating else 0.0
	queue_redraw()

func _travel_tick(delta: float) -> bool:
	# The loaded road has no working bunker. SAN rides with the real vehicle;
	# it never harvests its hidden stores or refills medical charges there.
	var trip = game.get("expedition")
	if not is_instance_valid(trip) or not trip.road_open or trip.stage not in ["travel","stop","failed"]: return false
	var truck = trip.vehicle
	if not is_instance_valid(truck) or not "journey_state" in truck: return false
	if not is_finite(delta) or delta<=0.0: return true
	elapsed+=delta
	logistics.suspend()
	target=null
	treating=false
	treatment_progress=0.0
	refill_progress=0.0
	route.clear()
	climbing=false
	var service: Dictionary = truck.journey_state
	var patient = _select_patient(_humans())
	if medical_supplies>0 and is_instance_valid(patient) and not is_instance_valid(patient.mounted_turret):
		target=patient
		visible=true
		collision_mask=1
		var patient_previous := global_position
		# Stand on the outside of a dismounted crew member. The nearer side
		# can lie inside the chassis, where the medical visibility ray is blocked.
		var destination: Vector2=patient.global_position+Vector2(-36 if patient.global_position.x<truck.global_position.x else 36,0)
		velocity.x=clampf((destination.x-global_position.x)/maxf(delta,.001),-MedicNavigation.SPEED,MedicNavigation.SPEED)
		velocity.y=minf(700.0,velocity.y+MedicNavigation.GRAVITY*delta)
		move_and_slide()
		if absf(patient.global_position.x-global_position.x)>.5: facing=signf(patient.global_position.x-global_position.x)
		_motion_phase+=global_position.distance_to(patient_previous)*.22
		_idle_time=0.0
		status_label=LocaleText.format("SAN-1 · unterwegs zu P%d",patient.player_id)
		if patient.medical.reachable_can_aid(self) and velocity.length()<=18:
			treating=true
			var down_before: bool=patient.is_downed()
			var label: String=LocaleText.text("Reanimation") if patient.medical.state=="critical" else LocaleText.text("Wiederbelebung") if down_before else LocaleText.text("Versorgung")
			status_label=LocaleText.format("SAN-1 · P%d %s",[patient.player_id,label])
			if patient.medical.begin_or_continue_aid(self,delta):
				treatments_completed+=1
				if down_before: revives_completed+=1
			treatment_progress=patient.medical.progress_for(self)
		queue_redraw()
		return true
	var helping: bool = service.get("phase","")=="repair" and bool(service.get("solo_assist",false)) and not truck.destroyed
	visible=helping
	if not helping:
		global_position=truck.global_position+Vector2(-40*float(truck.facing),-24)
		velocity=Vector2.ZERO
		_idle_time=0.0
		status_label=LocaleText.text("SAN-1 · im Konvoi")
		return true
	var point: Vector2 = truck.service_point()+Vector2(-25*float(truck.facing),20)
	var before := global_position
	collision_mask=1
	velocity.x=clampf((point.x-global_position.x)/maxf(delta,.001),-MedicNavigation.SPEED,MedicNavigation.SPEED)
	velocity.y=minf(700.0,velocity.y+MedicNavigation.GRAVITY*delta)
	move_and_slide()
	if absf(point.x-global_position.x)>.5: facing=signf(point.x-global_position.x)
	_motion_phase+=global_position.distance_to(before)*.22
	_idle_time=0.0
	status_label=LocaleText.text("SAN-1 · Reifenwechsel unterstützen")
	queue_redraw()
	return true

func _update_combat_delay() -> void:
	var core=game.get("core")
	if not is_instance_valid(core): return
	if "hp" in core:
		if _last_core_hp>=0 and float(core.hp)<_last_core_hp: _rest_delay=4.0
		_last_core_hp=float(core.hp)
	for player in _humans():
		if player.global_position.distance_to(core.global_position)<145 and float(player.since_hit)<4:
			_rest_delay=maxf(_rest_delay,4.0-float(player.since_hit))

func _return_home(delta: float,wants_refill: bool) -> void:
	var home:=_home()
	if not _returning:
		route.clear()
		_replan_clock=0.0
	_returning=true
	if global_position.distance_to(home)<10:
		_stand(delta)
		if wants_refill and medical_supplies<MedicalCatalog.MAX_CHARGES:
			if _rest_delay<=0 and velocity.length()<4:
				refill_progress+=delta
				if refill_progress>=refill_duration():
					medical_supplies+=1
					refill_progress=0.0
			else:
				refill_progress=0.0
			status_label=LocaleText.format("SAN-1 · Vorrat am Kern %.0f s", ceilf(refill_duration()-refill_progress)) if _rest_delay<=0 else LocaleText.text("SAN-1 · Kern unter Beschuss")
		else:
			refill_progress=0.0
			status_label=LocaleText.text("SAN-1 · Koop-Bereitschaft") if _humans().size()>1 else LocaleText.format("SAN-1 · bereit · %d Versorgungen", medical_supplies)
		return
	refill_progress=0.0
	status_label=LocaleText.text("SAN-1 · Rückweg zum Kern") if wants_refill else LocaleText.text("SAN-1 · zurück zur Station")
	if _replan_clock<=0 and (route.is_empty() or _stuck_time>.65):
		route=navigation.route(home)
		if route.is_empty(): route=navigation.route(home,true)
		_replan_clock=1.2
		_stuck_time=0.0
	if route.is_empty():
		status_label=LocaleText.text("SAN-1 · Rückweg blockiert")
		_stand(delta)
	else:
		_follow_route(delta)

func _seek_patient(delta: float) -> void:
	status_label=LocaleText.format("SAN-1 · unterwegs zu P%d", target.player_id)
	var moved: bool=_last_destination==Vector2.INF or _last_destination.distance_to(target.global_position)>20
	if _replan_clock<=0 and (route.is_empty() or moved or _stuck_time>.65):
		route=navigation.route_to(target)
		_last_destination=target.global_position
		_replan_clock=1.2
		_stuck_time=0.0
	if route.is_empty():
		status_label=LocaleText.format("SAN-1 · P%d: sicheren Stand suchen", target.player_id) if target.climbing else LocaleText.format("SAN-1 · Zugang zu P%d blockiert", target.player_id)
		_stand(delta)
	else:
		_follow_route(delta)

func _follow_route(delta: float, travel_speed: float = MedicNavigation.SPEED) -> void:
	if route.is_empty():
		_stand(delta)
		return
	var edge: Dictionary=route[0]
	var point: Vector2=edge.point
	var before:=global_position
	if edge.kind=="climb":
		climbing=true
		_ladder=edge.ladder
		collision_mask=0
		velocity=Vector2.ZERO
		global_position.x=move_toward(global_position.x,point.x,travel_speed*delta)
		var next_y:=move_toward(global_position.y,point.y,minf(MedicNavigation.CLIMB_SPEED,travel_speed)*delta)
		if not is_equal_approx(next_y,global_position.y) and not LadderPassage.allow_motion(self,next_y):
			return
		global_position.y=next_y
		if global_position.distance_to(point)<1.0:
			var continues_climbing: bool=route.size()>1 and route[1].kind=="climb"
			if not continues_climbing and not _land_at_passage(): return
			route.pop_front()
	elif edge.kind=="jump":
		if climbing and not _land_at_passage(): return
		climbing=false
		collision_mask=1
		if not bool(edge.get("launched",false)):
			edge.launched=true
			velocity=edge.launch
			_jump_elapsed=0.0
		_jump_elapsed+=delta
		velocity.y+=MedicNavigation.GRAVITY*delta
		move_and_slide()
		if is_on_floor() and _jump_elapsed>.15:
			if global_position.distance_to(point)<14:
				route.pop_front()
			else:
				route.clear()
				_replan_clock=0.0
		elif _jump_elapsed>float(edge.duration)+.55:
			route.clear()
			_replan_clock=0.0
	else:
		if climbing and not _land_at_passage(): return
		climbing=false
		collision_mask=1
		var dx:=point.x-global_position.x
		velocity.x=clampf(dx/maxf(delta,.001),-travel_speed,travel_speed)
		velocity.y+=MedicNavigation.GRAVITY*delta
		move_and_slide()
		if absf(point.x-global_position.x)<2 and absf(point.y-global_position.y)<4:
			route.pop_front()
	if absf(global_position.x-before.x)>.02: facing=signf(global_position.x-before.x)
	_stuck_time=_stuck_time+delta if global_position.distance_to(before)<.05 else 0.0

func _stand(delta: float) -> void:
	velocity.x=0
	if climbing and not _land_at_passage():
		velocity=Vector2.ZERO
		collision_mask=0
		return
	if navigation.ladder_for(global_position).has_area() and not navigation.support_at(global_position):
		climbing=true
		collision_mask=0
		velocity=Vector2.ZERO
	else:
		climbing=false
		collision_mask=1
		velocity.y+=MedicNavigation.GRAVITY*delta
		move_and_slide()

func _land_at_passage() -> bool:
	# The rescue unit shares the worker's automatic hatch. It cannot switch
	# back to walking while another climber is still crossing the opening.
	if not navigation.ladder_for(global_position).has_area(): return true
	for floor_y: float in game.floor_levels:
		if absf(global_position.y-floor_y)>8.0: continue
		if not is_equal_approx(global_position.y,floor_y) and not LadderPassage.allow_motion(self,floor_y): return false
		global_position.y=floor_y
		return LadderPassage.landing_ready(self,floor_y)
	return true

func _draw() -> void:
	if rhythm_pose.draw(self, medical_supplies, facing):
		UiArt.centered(self,Vector2(0,-54),"SAN-1",9,Color("b7c4aa"))
		expression.draw(self)
		return
	var bob:=roundf(sin(elapsed*2.2)*.65) if not climbing else 0.0
	draw_rect(Rect2(-18,-1,36,4),Color(0,0,0,.32))
	if climbing:
		_draw_climbing_legs()
	else:
		EquipmentArt.tracks(self,_motion_phase)
	var look:=roundf(sin(elapsed*.7)*2) if _idle_time>2 else facing*3
	look = expression.head_look(look)
	EquipmentArt.medic_body(self,bob,look,medical_supplies,treating)
	if treating and is_instance_valid(target):
		_draw_treatment_arm(bob)
	elif _road_tool_active():
		_draw_road_tool(bob)
	elif _idle_time>3 and int(elapsed)%7<2:
		var inspection := _inspection_arm_pose(bob)
		EquipmentArt.linkage(self,inspection.shoulder,inspection.hand,3)
		EquipmentArt.casing(self,inspection.casing,Color("aaa98d"),2)
	else:
		EquipmentArt.linkage(self,Vector2(13*facing,-22+bob),Vector2(19*facing,-12+bob),3)
		EquipmentArt.casing(self,Rect2(16*facing-3,-14+bob,6,7),Color("929980"),1)
	if not logistics_cargo.is_empty():
		# The rear carrier stays secured while the medical arm remains free.
		var cargo_at := Vector2(-facing*15,-33+bob)
		EquipmentArt.casing(self,Rect2(cargo_at+Vector2(-9,-5),Vector2(18,13)),Color("4f5b48"),2)
		UiArt.material(self,logistics_cargo,cargo_at-Vector2(8,8),16)
		draw_line(cargo_at+Vector2(-9,7),cargo_at+Vector2(9,7),Color("a4ae91"),2)
	if treating:
		UiArt.bar(self,Rect2(-19,-48,38,3),treatment_progress,UiArt.GREEN)
	elif _returning and refill_progress>0:
		UiArt.bar(self,Rect2(-19,-48,38,3),refill_progress/refill_duration(),UiArt.AMBER)
	elif logistics_progress>0:
		UiArt.bar(self,Rect2(-19,-48,38,3),logistics_progress/logistics.handoff_time(),Art.CYAN)
	UiArt.centered(self,Vector2(0,-54),"SAN-1",9,Color("b7c4aa"))
	expression.draw(self)

func _inspection_arm_pose(bob: float) -> Dictionary:
	# Reflect the whole grip casing, not just its left corner, so the idle
	# inspection stays attached to the same side as the robot's working arm.
	var direction := -1.0 if facing<0.0 else 1.0
	var arm := Transform2D(Vector2(direction,0),Vector2(0,1),Vector2(0,bob))
	return {"shoulder":arm*Vector2(14,-18),"hand":arm*Vector2(18,-25),"casing":arm*Rect2(15,-29,7,5)}

func _road_tool_active() -> bool:
	var trip=game.get("expedition") if is_instance_valid(game) else null
	if not is_instance_valid(trip) or not trip.road_open or not is_instance_valid(trip.vehicle): return false
	var truck=trip.vehicle
	return truck.journey_state.phase=="repair" and truck.journey_state.solo_assist and global_position.distance_to(truck.service_point())<72

func _draw_road_tool(bob: float) -> void:
	var truck=game.expedition.vehicle
	var wheel: Vector2=to_local(truck.service_point())
	var cycle:=sin(float(truck.journey_state.phase_time)*TAU*1.8)
	var shoulder:=Vector2(13*facing,-23+bob)
	var tool:=wheel+Vector2(-6*facing,cycle*2)
	var elbow:=shoulder.lerp(tool,.5)+Vector2(0,-7)
	EquipmentArt.linkage(self,shoulder,elbow,4)
	EquipmentArt.linkage(self,elbow,tool,3)
	EquipmentArt.joint(self,elbow)
	EquipmentArt.casing(self,Rect2(tool-Vector2(4,2),Vector2(8,5)),Color("c0bea2"),1)
	draw_line(tool,tool+Vector2(7*facing,-5),Color("bdc5ac"),2)

func _draw_climbing_legs() -> void:
	var phase:=global_position.y/14.0*PI
	for side in [-1.0,1.0]:
		var reach:=roundf(sin(phase+(0.0 if side<0 else PI))*5)
		var hip:=Vector2(side*11,-14)
		var elbow:=Vector2(side*18,-20+reach)
		var grip:=Vector2(side*12,-30+reach)
		EquipmentArt.linkage(self,hip,elbow,3)
		EquipmentArt.linkage(self,elbow,grip,3)
		EquipmentArt.joint(self,elbow)
		EquipmentArt.casing(self,Rect2(grip-Vector2(3,1),Vector2(7,3)),Color("949880"),1)
		EquipmentArt.linkage(self,Vector2(side*10,-9),Vector2(side*14,-3-reach),3)

func _draw_treatment_arm(bob: float) -> void:
	var downed: bool=target.is_downed()
	var treatment_y: float=-10 if downed else (-9 if target.medical.fractured else -24)
	var chest:=to_local(target.global_position)+Vector2(-target.facing*8,treatment_y)
	var shoulder:=Vector2(13*facing,-23+bob)
	var cycle:=sin(elapsed*(8.0 if downed else 4.5))
	var tool:=chest+Vector2(0,roundf(cycle*(2.5 if downed else 1.0)))
	var elbow:=shoulder.lerp(tool,.5)+Vector2(0,-10)
	EquipmentArt.linkage(self,shoulder,elbow,4)
	EquipmentArt.linkage(self,elbow,tool,3)
	EquipmentArt.joint(self,elbow)
	EquipmentArt.casing(self,Rect2(tool-Vector2(4,2),Vector2(8,5)),Color("c0bea2"),1)
	if target.medical.state=="critical":
		draw_line(Vector2(7,-15),tool+Vector2(1,2),Color("8b744e"),1)
		if cycle>.85: draw_rect(Rect2(tool-Vector2(1,2),Vector2(3,2)),Color("eed99c"))

func refill_duration() -> float:
	var research = game.get("upgrades") if is_instance_valid(game) else null
	return MedicalCatalog.REFILL_TIME * (research.medic_refill_multiplier() if is_instance_valid(research) and research.has_method("medic_refill_multiplier") else 1.0)
