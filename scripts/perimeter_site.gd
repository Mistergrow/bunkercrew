class_name PerimeterSite
extends StaticBody2D
## Shared finite deposits, paid reconstruction and host-only automatic defense.
const C=preload("res://scripts/perimeter_catalog.gd")
const DRAWING=preload("res://scripts/perimeter_art.gd")
const Sound=preload("res://scripts/spatial_sound.gd")
var game: Node
var role: String=C.VALID_ROLES[0]
var side: int=1
var slot_index: int=0
var tier: int=0
var hp:=0.0
var max_hp:=0.0
var materials: Dictionary={}
var transfer: Dictionary={}
var work:=0.0
var cure:=0.0
var ruined:=false
var gate_open:=false
var gate_amount:=0.0
var ammo:=0
var aim_angle:=0.0
var cooldown:=0.0
var flash:=0.0
var recoil:=0.0
var shot_serial:=0
var burst_left:=0
var hit_flash:=0.0
var builder_player_id:=0
var collider: CollisionShape2D
var upper_collider: CollisionShape2D
var head_hurtbox: StaticBody2D
var barrel: Node2D
var tracking_target: Node2D
var _scan_clock:=0.0
var _gate_hold:=0.0
var _last_work_frame: int=-1000
var _last_action: String=""

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("walls")
	add_to_group("perimeter_sites")
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	material=DRAWING.pixel_material()
	collision_mask=0
	collider=CollisionShape2D.new()
	collider.name="Hull"
	var shape:=RectangleShape2D.new()
	shape.size=Vector2(34,32) if role=="fence" else Vector2(44,26)
	collider.position.y=-shape.size.y*.5
	collider.shape=shape
	add_child(collider)
	if role=="fence":
		upper_collider=CollisionShape2D.new()
		upper_collider.name="UpperPanel"
		upper_collider.shape=RectangleShape2D.new()
		upper_collider.shape.size=Vector2(34,20)
		upper_collider.position.y=-54
		add_child(upper_collider)
	else:
		# Hostile rounds also hit the receiver. It is a hurtbox (layer8), not
		# additional terrain that catches every allied round in the firing lane.
		head_hurtbox=preload("res://scripts/perimeter_hurtbox.gd").new()
		head_hurtbox.site=self
		add_child(head_hurtbox)
	barrel=Node2D.new()
	barrel.name="GunBarrel"
	barrel.use_parent_material=true
	barrel.draw.connect(_draw_barrel)
	add_child(barrel)
	aim_angle=0.0 if side>0 else PI
	sync_replica()

func authoritative() -> bool:
	if _departed_world(): return false
	var session=game.get("network") if is_instance_valid(game) else null
	return not is_instance_valid(session) or not session.active or session.is_host

func _departed_world() -> bool:
	var expedition=game.get("expedition") if is_instance_valid(game) else null
	return is_instance_valid(expedition) and expedition.get("road_open")==true

func _crew(player: Node) -> bool:
	return is_instance_valid(player) and not player.is_queued_for_deletion() and player.get("game")==game and player.get("player_id") is int and int(player.player_id)>=1 and int(player.player_id)<=PartyConfig.MAX_PLAYERS and "players" in game and player in game.players

func can_interact(player: Node) -> bool:
	return not _departed_world() and _crew(player)

func interaction_point() -> Vector2:
	return global_position-Vector2(0,28)

func interaction_title() -> String:
	return LocaleText.text(C.spec(role,maxi(1,tier)).label)

func next_spec() -> Dictionary:
	return C.spec(role,mini(C.max_tier(role),tier+1))

func _wave() -> int:
	var rounds=game.get("rounds") if is_instance_valid(game) else null
	return int(rounds.wave) if is_instance_valid(rounds) else 1

func lock_reason() -> String:
	var spec:=next_spec()
	if _wave()<int(spec.wave): return LocaleText.format("Ausbau ab Welle %d",spec.wave)
	var upgrades=game.get("upgrades") if is_instance_valid(game) else null
	if not str(spec.tech).is_empty() and (not is_instance_valid(upgrades) or not upgrades.has_upgrade(spec.tech)):
		return LocaleText.format("Technik benötigt: %s",C.TECH_NAMES[spec.tech])
	return ""

func _paid() -> bool:
	for kind: String in next_spec().cost:
		if int(materials.get(kind,0))<int(next_spec().cost[kind]): return false
	return true

func action_for(player: Node) -> String:
	if not can_interact(player): return ""
	if tier>0 and hp>0:
		var selected: String=player.selected_material() if player.has_method("selected_material") else ""
		var repair_kind: String=C.spec(role,tier).repair
		if role!="fence" and ammo<int(C.GUNS[role].capacity) and AmmoTransfer.available(player) and (selected=="ammo" or hp>=max_hp): return "ammo"
		if hp<max_hp-.01 and cure<=0 and int(player.inventory.get(repair_kind,0))>0: return "repair"
		if role!="fence" and ammo<int(C.GUNS[role].capacity) and AmmoTransfer.available(player): return "ammo"
		if tier>=C.max_tier(role) or hp<max_hp-.01 or cure>0: return ""
	if not lock_reason().is_empty(): return ""
	return "build" if _paid() else "deposit"

func action_hint(player: Node) -> String:
	match action_for(player):
		"ammo": return LocaleText.text("Munitionskiste einlegen")
		"repair": return LocaleText.text("Verteidigung reparieren")
		"build": return LocaleText.text("Verteidigung montieren")
		"deposit": return LocaleText.text("Baumaterial liefern")
	return LocaleText.text("Vorräte prüfen")

func prompt(player: Node) -> String:
	var heading:=interaction_title()
	if tier>0:
		heading+=LocaleText.format(" · %d/%d LP",[ceili(hp),ceili(max_hp)])
		if role=="fence": heading+="\n"+LocaleText.text("Tor öffnet für die Besatzung; die Schießscharte lässt Schüsse beider Seiten passieren.")
		else: heading+=LocaleText.format("\n%d/%d Schuss · 1 Munitionskiste = 20 Schuss",[ammo,C.GUNS[role].capacity])
	if cure>0: return heading+LocaleText.format("\nBeton härtet: %.1f s",cure)
	var action:=action_for(player)
	if action=="ammo": return heading
	if action=="repair" or (tier>0 and hp<max_hp-.01):
		var spec:=C.spec(role,tier)
		return heading+LocaleText.format("\nReparatur: 1 %s → %d LP",[Balance.RESOURCE_NAMES[spec.repair],int(spec.repair_hp)])
	if tier>=C.max_tier(role): return heading+"\n"+LocaleText.text("Vollständig ausgebaut")
	var locked:=lock_reason()
	var portions:=PackedStringArray()
	for kind: String in next_spec().cost:
		portions.append(LocaleText.format("%s %d/%d",[Balance.RESOURCE_NAMES[kind],materials.get(kind,0),next_spec().cost[kind]]))
	if not locked.is_empty(): return heading+"\n"+" · ".join(portions)+"\n"+locked
	return heading+LocaleText.format("\n%s · %s",[next_spec().label," · ".join(portions)])

func interaction_progress(player: Node) -> float:
	var action:=action_for(player)
	if action=="build": return clampf(work/float(next_spec().time),0,1)
	if action in ["repair","ammo"]: return clampf(work/C.SERVICE_TIME,0,1)
	return clampf(float(transfer.get(str(player.player_id),0))/C.TRANSFER_TIME,0,1) if _crew(player) else 0.0

func interact(player: Node,delta: float) -> void:
	if not authoritative() or get_tree().paused or not _crew(player) or not is_finite(delta) or delta<=0: return
	if player.has_method("can_act") and not player.can_act(): return
	if player.global_position.distance_to(global_position)>105: return
	var action:=action_for(player)
	if action.is_empty(): return
	var elapsed:=minf(delta,.25)
	if action=="deposit":
		var key:=str(player.player_id)
		transfer[key]=minf(C.TRANSFER_TIME,float(transfer.get(key,0))+elapsed)
		if transfer[key]>=C.TRANSFER_TIME:
			transfer[key]=0.0
			for kind: String in next_spec().cost:
				if int(materials.get(kind,0))<int(next_spec().cost[kind]) and int(player.inventory.get(kind,0))>0 and player.take_item(kind,1):
					materials[kind]=int(materials.get(kind,0))+1
					var events=game.get("combat_events") if is_instance_valid(game) else null
					if is_instance_valid(events) and events.has_method("record_activity"): events.record_activity(player)
					Sound.emit(game,"build",interaction_point())
					break
	else:
		if action!=_last_action or Engine.get_physics_frames()-_last_work_frame>20: work=0
		_last_action=action
		_last_work_frame=Engine.get_physics_frames()
		work+=elapsed
		var duration: float=float(next_spec().time) if action=="build" else C.SERVICE_TIME
		if work>=duration:
			work=0
			if action=="build": _complete_build(player)
			elif action=="ammo":
				var delivered:=AmmoTransfer.take(player,mini(C.AMMO_PER_CRATE,int(C.GUNS[role].capacity)-ammo))
				ammo+=int(delivered.rounds)
				_reward_role(player,"supply",float(delivered.rounds)*.1)
				Sound.emit(game,"reload_rifle_load",interaction_point())
			elif action=="repair" and player.take_item(C.spec(role,tier).repair,1):
				var repaired := minf(max_hp-hp,float(C.spec(role,tier).repair_hp))
				hp+=repaired
				_reward_role(player,"repair",repaired*.06)
				Sound.emit(game,"build",interaction_point())
	sync_replica()

func _complete_build(player: Node) -> void:
	if not _paid() or not lock_reason().is_empty() or tier>=C.max_tier(role): return
	tier+=1
	var spec:=C.spec(role,tier)
	max_hp=float(spec.hp)
	cure=float(spec.cure)
	hp=max_hp*.55 if cure>0 else max_hp
	materials.clear()
	transfer.clear()
	builder_player_id=int(player.player_id)
	_reward_role(player,"craft",4.0)
	ruined=false
	Sound.emit(game,"produce",global_position)
	sync_replica()

func is_blocking() -> bool:
	return not _departed_world() and tier>0 and hp>0 and (role!="fence" or gate_amount<.8)

func can_be_targeted() -> bool:
	return not _departed_world() and tier>0 and hp>0

func attack_point() -> Vector2:
	return global_position-Vector2(0,54 if role=="fence" else 19)

func impact_material() -> String:
	return "concrete" if role=="fence" and tier==2 else "metal"

func impact_sound() -> String:
	return "impact_stone" if impact_material()=="concrete" else "impact_metal"

func take_damage(amount: float) -> void:
	if not authoritative() or tier==0 or hp<=0 or not is_finite(amount) or amount<=0: return
	var surface:=impact_material()
	var impact_cue:=impact_sound()
	hp=maxf(0,hp-amount)
	hit_flash=.18
	if hp<=0:
		for kind: String in materials:
			if is_instance_valid(game) and game.has_method("spawn_pickup"): game.spawn_pickup(kind,int(materials[kind]),global_position-Vector2(0,12))
		materials.clear()
		transfer.clear()
		tier=0
		max_hp=0
		cure=0
		work=0
		ammo=0
		burst_left=0
		gate_open=false
		gate_amount=0
		ruined=true
		tracking_target=null
		Sound.emit(game,impact_cue,global_position)
		if is_instance_valid(game) and game.has_method("impact"): game.impact(global_position-Vector2(0,25),surface,Vector2.UP,1.0)
	sync_replica()

func _physics_process(delta: float) -> void:
	if not authoritative(): return
	hit_flash=maxf(0,hit_flash-delta)
	if tier==0: return
	if cure>0:
		var elapsed:=minf(cure,delta)
		cure=maxf(0,cure-delta)
		hp=minf(max_hp,hp+max_hp*.45*elapsed/float(C.spec(role,tier).cure))
	if role=="fence":
		_update_gate(delta)
	else:
		cooldown=maxf(0,cooldown-delta)
		flash=maxf(0,flash-delta)
		recoil=move_toward(recoil,0,delta*18)
		_watch(delta)
	sync_replica()

func navigation_passable() -> bool:
	return role=="fence"

func _update_gate(delta: float) -> void:
	var nearby:=false
	for player in get_tree().get_nodes_in_group("players")+get_tree().get_nodes_in_group("medics"):
		var own_medic: bool=is_instance_valid(player) and player.get("game")==game and player.is_in_group("medics")
		if (_crew(player) or own_medic) and player.is_visible_in_tree() and absf(player.global_position.x-global_position.x)<75 and absf(player.global_position.y-global_position.y)<85:
			nearby=true
			break
	_gate_hold=.55 if nearby else maxf(0,_gate_hold-delta)
	gate_open=_gate_hold>0
	gate_amount=move_toward(gate_amount,1.0 if gate_open else 0.0,delta*6.0)

func _target_point(enemy: Node2D) -> Vector2:
	var body: float=float(enemy.get("body_height")) if enemy.get("body_height")!=null else 34.0
	return enemy.global_position-Vector2(0,clampf(body,34,40))

func target_angle(enemy: Node2D) -> float:
	var difference:=_target_point(enemy)-(global_position+Vector2(C.GUNS.ground.pivot))
	return difference.angle()-asin(clampf(C.MUZZLE.y*side/maxf(1,difference.length()),-1,1))

func _bore_origin(angle: float) -> Vector2:
	return global_position+Vector2(C.GUNS.ground.pivot)+Vector2(-sin(angle),cos(angle))*C.MUZZLE.y*side

func muzzle_point() -> Vector2:
	return _bore_origin(aim_angle)+Vector2.from_angle(aim_angle)*(C.MUZZLE.x-recoil)

func target_visible(enemy: Node2D) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.get("game")!=game or enemy.get("dead")==true or not enemy.is_in_group("enemies"): return false
	if enemy.is_in_group("air_enemies"): return false
	var destination:=_target_point(enemy)
	var difference:=destination-(global_position+Vector2(C.GUNS.ground.pivot))
	if difference.x*side<18 or difference.length()>float(C.GUNS.ground.range): return false
	var angle:=Vector2(difference.x*side,difference.y).angle()
	if angle<deg_to_rad(-60) or angle>deg_to_rad(38): return false
	var query:=PhysicsRayQueryParameters2D.create(_bore_origin(target_angle(enemy)),destination,1|2)
	query.exclude=[get_rid()]
	query.hit_from_inside=true
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _watch(delta: float) -> void:
	_scan_clock-=delta
	if _scan_clock<=0:
		_scan_clock=.18
		tracking_target=null
		var nearest:=INF
		for enemy in get_tree().get_nodes_in_group("enemies"):
			if target_visible(enemy):
				var distance:=global_position.distance_squared_to(enemy.global_position)
				var body: float=float(enemy.get("body_height")) if enemy.get("body_height")!=null else 34.0
				# Small raiders and infantry take priority; armor remains a fallback.
				if body>48: distance+=1000000.0
				if distance<nearest:
					nearest=distance
					tracking_target=enemy
	if not is_instance_valid(tracking_target) or ammo<=0:
		if burst_left>0: cooldown=maxf(cooldown,float(C.GUNS.ground.interval))
		burst_left=0
		return
	var wanted_angle:=target_angle(tracking_target)
	aim_angle=rotate_toward(aim_angle,wanted_angle,delta*2.2)
	if absf(angle_difference(aim_angle,wanted_angle))<.03 and cooldown<=0: fire()

func builder() -> Node:
	for player in get_tree().get_nodes_in_group("players"):
		if _crew(player) and player.player_id==builder_player_id: return player
	return null

func fire() -> bool:
	if not authoritative() or get_tree().paused or tier==0 or hp<=0 or role=="fence" or ammo<=0 or cooldown>0 or not target_visible(tracking_target): return false
	var active:=get_tree().get_nodes_in_group("perimeter_rounds").filter(func(node):return not node.is_queued_for_deletion() and node.get("game")==game)
	if active.size()>=C.MAX_ACTIVE_SHOTS: return false
	var origin:=_bore_origin(aim_angle)
	var direction:=Vector2.from_angle(aim_angle)
	var muzzle:=muzzle_point()
	# Check the actual barrel axis as well as the ideal target ray: a tiny
	# tracking error must not spend ammunition against our narrow firing port.
	var clearance:=PhysicsRayQueryParameters2D.create(origin,origin+direction*origin.distance_to(_target_point(tracking_target)),1|2)
	clearance.exclude=[get_rid()]
	clearance.hit_from_inside=true
	if not get_world_2d().direct_space_state.intersect_ray(clearance).is_empty(): return false
	var query:=PhysicsRayQueryParameters2D.create(origin,muzzle,1|2|4)
	query.exclude=[get_rid()]
	query.hit_from_inside=true
	var hit:=get_world_2d().direct_space_state.intersect_ray(query)
	# Starting at the pivot means an enemy touching the barrel is never skipped.
	var projectile:=WorkerShot.new()
	projectile.game=game
	projectile.credit_worker=builder()
	projectile.direction=direction
	projectile.damage=float(C.GUNS[role].damage)
	projectile.position=game.to_local(origin if not hit.is_empty() else muzzle)
	projectile.life=.75
	projectile.add_to_group("perimeter_rounds")
	game.add_child(projectile)
	ammo-=1
	if burst_left<=0: burst_left=C.BURST_SIZE
	burst_left-=1
	cooldown=C.BURST_INTERVAL if burst_left>0 else float(C.GUNS.ground.interval)
	flash=.085
	recoil=4.0
	shot_serial+=1
	Sound.emit(game,"shot_rifle",muzzle)
	sync_replica()
	return true

func sync_replica() -> void:
	if not is_instance_valid(collider): return
	collision_layer=(3 if role=="fence" else 2) if is_blocking() else 0
	if role=="fence":
		# Follow the descending panel, clipping each solid section at ground level.
		var descent:=gate_amount*56.0
		for section in [[collider,-32.0,0.0],[upper_collider,-64.0,-44.0]]:
			var top: float=minf(0,float(section[1])+descent)
			var bottom: float=minf(0,float(section[2])+descent)
			section[0].shape.size=Vector2(34,maxf(.01,bottom-top))
			section[0].position.y=(top+bottom)*.5
	if is_instance_valid(head_hurtbox):
		head_hurtbox.collision_layer=8 if can_be_targeted() else 0
		head_hurtbox.position=C.GUNS.ground.pivot
		head_hurtbox.rotation=aim_angle
		head_hurtbox.scale=Vector2(1,float(side))
	set_meta("weather_material",impact_material())
	if is_instance_valid(barrel):
		barrel.visible=role!="fence" and tier>0
		if role!="fence":
			barrel.position=C.GUNS[role].pivot
			barrel.rotation=aim_angle
			barrel.scale=Vector2(1,float(side))
			barrel.queue_redraw()
	queue_redraw()

func _draw() -> void:
	DRAWING.draw_site(self)

func _draw_barrel() -> void:
	DRAWING.draw_barrel(self)

func _reward_role(player: Node, action: String, amount: float) -> void:
	var events=game.get("combat_events") if is_instance_valid(game) else null
	if is_instance_valid(events) and events.has_method("record_role"): events.record_role(player,action,amount)
