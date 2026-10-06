extends Node2D
## Cosmetic fragments only: no damage, collision shapes or medical rule changes.
signal settings_changed(level: int)
const Settings=preload("res://scripts/violence_settings.gd")
const MAX_PARTICLES:=192
const MAX_PARTS:=12
const MAX_STAINS:=64
const HUMAN_COLORS={"olive":Color("59615e"),"cloth":Color("717873"),"light":Color("8a9088"),"shadow":Color("3a4140"),"deep":Color("292e2d"),"trouser":Color("414947"),"trouser_light":Color("68716a"),"leather":Color("493c31"),"leather_light":Color("746352")}
var game: Node
var settings:=Settings.new()
var level:=Settings.FULL
var particles: Array[Dictionary]=[]
var parts: Array[Dictionary]=[]
var stains: Array[Dictionary]=[]
var elapsed:=0.0
var collision_count:=0
var _rng:=RandomNumberGenerator.new()
var pending_masks: Dictionary={}
var pending_player_parts: Dictionary={}
var _observed_player_masks: Dictionary={}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	z_index=23
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	settings.load_settings()
	level=settings.level
	_rng.seed=193772

func set_level(value: int) -> void:
	if not settings.set_level(value): return
	level=settings.level
	if level<Settings.FULL: parts.clear()
	if level<Settings.FULL: pending_player_parts.clear()
	if level==Settings.OFF:
		particles=particles.filter(func(item):return item.material=="oil")
		stains=stains.filter(func(item):return item.material=="oil")
		for burst in get_tree().get_nodes_in_group(ImpactBurst.GROUP):
			if burst.get_parent()==game and burst.surface_material=="flesh": burst.retire()
	settings_changed.emit(level)
	queue_redraw()
	for actor in get_tree().get_nodes_in_group("players")+get_tree().get_nodes_in_group("human_enemies")+get_tree().get_nodes_in_group("infantry_remains"):
		if actor.get("game")!=game and actor.get("effects")!=self: continue
		if actor is CanvasItem: actor.queue_redraw()
		for child in actor.get_children():
			if child is CanvasItem: child.queue_redraw()

func clear() -> void:
	particles.clear()
	parts.clear()
	stains.clear()
	pending_masks.clear()
	pending_player_parts.clear()
	_observed_player_masks.clear()
	queue_redraw()

func _reduced() -> bool:
	var weather=game.get("weather") if is_instance_valid(game) else null
	return is_instance_valid(weather) and weather.get("reduced_effects")==true

static func visible_mask(actor: Node) -> int:
	if not is_instance_valid(actor) or not "gore_mask" in actor: return 0
	var world=actor.get("game")
	var effects=world.get("combat_gore") if is_instance_valid(world) else null
	if not is_instance_valid(effects) or effects.level!=Settings.FULL: return 0
	if actor.is_in_group("players"): return int(actor.gore_mask) if actor.is_downed() else 0
	return int(actor.gore_mask)|effects.mask_for_id(str(actor.get_meta("network_entity_id","")))

func mask_for_id(id: String) -> int:
	return int(pending_masks.get(id,{}).get("mask",0)) if not id.is_empty() else 0

func reset_actor(actor: Node) -> void:
	pending_masks.erase(str(actor.get_meta("network_entity_id","")))
	if actor.is_in_group("players"):
		parts=parts.filter(func(part):return int(part.player_id)!=int(actor.player_id))
		pending_player_parts.erase(int(actor.player_id))
		_observed_player_masks.erase(int(actor.player_id))
	queue_redraw()

func sync_actor(actor: Node) -> void:
	if not is_instance_valid(actor) or not actor.is_in_group("players"): return
	var id:=int(actor.player_id)
	var mask:=int(actor.gore_mask) if actor.is_downed() else 0
	if mask==0 and int(_observed_player_masks.get(id,0))>0: reset_actor(actor)
	_observed_player_masks[id]=mask
	if pending_player_parts.has(id) and mask>0:
		var pending: Dictionary=pending_player_parts[id]
		if int(pending.event.part)==mask and level==Settings.FULL:
			_spawn_part(pending.event)
			pending_player_parts.erase(id)

static func capture_contact(actor: Node,point: Vector2,incoming: Vector2,strength: float,flavor: String) -> void:
	var contact:={"frame":Engine.get_physics_frames(),"point":point,"direction":incoming.normalized(),"strength":strength,"flavor":flavor}
	if actor is Node2D and (actor.is_in_group("players") or actor.is_in_group("human_enemies")): contact.rig=_rig(actor)
	actor.set_meta("gore_contact",contact)

static func _rig(actor: Node2D) -> Dictionary:
	var visual=actor.get("infantry") if actor.is_in_group("human_enemies") else actor.get_node_or_null("PixelVisual")
	if not is_instance_valid(visual): return {}
	var pose: Dictionary={}
	var rig_transform: Transform2D=visual.global_transform
	if actor.is_in_group("human_enemies"):
		pose=visual.pose.duplicate(true)
	else:
		pose=visual.pose_skeleton.duplicate(true)
		if pose.is_empty():
			pose=WorkerPoseArt.neutral()
			var frame: Dictionary=preload("res://scripts/worker_personality.gd").frame(actor.character_id,visual.pose_name,visual.pose_frame)
			for key in ["hip","shoulder"]:
				if frame.has(key): pose[key]=Vector2(frame[key][0],frame[key][1])
			for key in ["feet","hands"]:
				if frame.has(key):
					for index in 2: pose[key][index]=Vector2(frame[key][index][0],frame[key][index][1])
		rig_transform=visual.global_transform*ActorWeatherGeometry.worker_transform(visual)
	var body:=WorkerPoseArt.torso_transform(pose)
	var roots: Array[Vector2]=[Vector2(pose.shoulder)+Vector2(-3,1),Vector2(pose.shoulder)+Vector2(3,2),Vector2(pose.hip)+Vector2(-3,0),Vector2(pose.hip)+Vector2(2,0)]
	if not actor.is_in_group("human_enemies"):
		var back: bool=bool(pose.get("back",false))
		var spread: float=5.0 if back else float(pose.get("hip_spread",4.0))
		roots=[body*Vector2(-8 if back else -6,0),body*Vector2(8 if back else 3,0),Vector2(pose.hip)+Vector2(-spread,0),Vector2(pose.hip)+Vector2(spread,0)]
	var tips: Array[Vector2]=[pose.hands[0],pose.hands[1],pose.feet[0],pose.feet[1]]
	var result:={}
	for index in 4:
		if index<2 and roots[index].distance_to(tips[index])>22.9: tips[index]=roots[index]+(tips[index]-roots[index]).normalized()*22.9
		result[1<<index]={"joint":rig_transform*roots[index],"tip":rig_transform*tips[index]}
	return result

func make_event(target: Node2D,applied: float,incapacitated: bool) -> Dictionary:
	if not is_instance_valid(target) or not is_finite(applied) or applied<=0: return {}
	var human:=target.is_in_group("players") or target.is_in_group("human_enemies")
	if not human and not target.is_in_group("enemies"): return {}
	var contact: Dictionary=target.get_meta("gore_contact",{})
	var precise: bool=contact.get("frame",-1)==Engine.get_physics_frames()
	var at: Vector2=contact.point if precise else target.global_position-Vector2(0,25)
	var direction: Vector2=contact.direction if precise else Vector2.LEFT
	var identity: String=str(target.character_id) if target.is_in_group("players") else "infantry"
	var event:={"material":"flesh" if human else "oil","point":at,"direction":direction,"strength":clampf(applied/22.0,.2,2.0),"part":0,"joint":at,"tip":at,"character":identity,"front":false,"facing":float(target.facing) if target.is_in_group("players") else float(target.get("attack_direction")),"player_id":int(target.player_id) if target.is_in_group("players") else 0}
	# Semantic mask is independent of this peer's option. Only a real terminal
	# impact may separate a limb; bleed-out and ordinary damage cannot do it.
	if human and incapacitated and precise and "gore_mask" in target and int(target.gore_mask)==0:
		var rig: Dictionary=contact.get("rig",_rig(target))
		var nearest:=INF
		for bit in rig:
			var segment: Dictionary=rig[bit]
			var distance:=at.distance_to(Geometry2D.get_closest_point_to_segment(at,segment.joint,segment.tip))
			if distance<nearest:
				nearest=distance
				event.part=bit
				event.joint=segment.joint
				event.tip=segment.tip
		if int(event.part)>0:
			event.front=int(event.part) in [2,8]
			target.gore_mask=int(event.part)
	return event

func present(event: Dictionary,target: Node=null,actor_id: String="") -> void:
	if event.is_empty(): return
	var material_kind: String=event.get("material","")
	if int(event.get("part",0))>0:
		# Baseline snapshots may remove a body before its impact event arrives.
		# Remember only bounded, short-lived cosmetic masks, never old bursts.
		if int(event.get("player_id",0))==0 and not actor_id.is_empty():
			if pending_masks.size()>=32: pending_masks.erase(pending_masks.keys()[0])
			pending_masks[actor_id]={"mask":int(event.part),"expires":elapsed+4.5}
		if is_instance_valid(target) and "gore_mask" in target and not target.is_in_group("players"): target.gore_mask|=int(event.part)
		for body in get_tree().get_nodes_in_group("infantry_remains"):
			if body.get("effects")==self and not actor_id.is_empty() and str(body.get_meta("combat_actor_id",""))==actor_id:
				body.gore_mask|=int(event.part)
				body.queue_redraw()
	if material_kind not in ["flesh","oil"] or (material_kind=="flesh" and level==Settings.OFF): return
	var point: Vector2=event.point
	if not get_viewport_rect().grow(100).has_point(get_global_transform_with_canvas()*to_local(point)): return
	var reduced:=_reduced()
	var cap:=64 if reduced else MAX_PARTICLES
	var strength: float=event.strength
	var direction: Vector2=event.direction
	var color:=Color("963d35") if material_kind=="flesh" else Color("302b20")
	for index in clampi(roundi(7.0+strength*8.0),6,23):
		if particles.size()>=cap: break
		var velocity:=direction.rotated(_rng.randf_range(-.8,.8))*_rng.randf_range(36,115)*sqrt(strength)
		velocity.y-=_rng.randf_range(12,60)
		particles.append({"point":point,"velocity":velocity,"age":0.0,"life":_rng.randf_range(.3,.85),"material":material_kind,"tint":color.lightened(_rng.randf_range(-.18,.1)),"size":1 if index%3 else 2})
		if reduced and index>=5: break
	if material_kind=="flesh" and level==Settings.FULL and int(event.get("part",0))>0:
		if int(event.player_id)>0:
			pending_player_parts[int(event.player_id)]={"event":event.duplicate(true),"expires":elapsed+.75}
			if is_instance_valid(target): sync_actor(target)
		else: _spawn_part(event)
	queue_redraw()

func _spawn_part(event: Dictionary) -> void:
	if parts.size()>= (4 if _reduced() else MAX_PARTS): parts.pop_front()
	var center: Vector2=Vector2(event.joint).lerp(event.tip,.5)
	parts.append({"point":center,"joint":Vector2(event.joint)-center,"tip":Vector2(event.tip)-center,"rotation":0.0,"spin":_rng.randf_range(-5,5),"velocity":Vector2(event.direction)*95+Vector2(0,-100),"age":0.0,"life":4.5,"stopped":false,"bounces":0,"character":event.character,"part":event.part,"front":event.front,"facing":event.facing,"player_id":event.player_id})

func _physics_process(delta: float) -> void:
	if delta<=0: return
	elapsed+=delta
	if _reduced():
		while particles.size()>64: particles.pop_front()
		while parts.size()>4: parts.pop_front()
		while stains.size()>20: stains.pop_front()
	for id in pending_masks.keys():
		if float(pending_masks[id].expires)<=elapsed: pending_masks.erase(id)
	for id in pending_player_parts.keys():
		if float(pending_player_parts[id].expires)<=elapsed: pending_player_parts.erase(id)
	if is_instance_valid(game) and "players" in game:
		for actor in game.players: sync_actor(actor)
	for index in range(particles.size()-1,-1,-1):
		var bit:=particles[index]
		bit.age+=delta
		if bit.age>=bit.life:
			particles.remove_at(index)
			continue
		bit.velocity.y+=360.0*delta
		var destination: Vector2=bit.point+bit.velocity*delta
		var hit:=_trace(bit.point,destination)
		if not hit.is_empty():
			collision_count+=1
			_add_stain(hit,bit)
			particles.remove_at(index)
		else: bit.point=destination
	for index in range(parts.size()-1,-1,-1):
		var part:=parts[index]
		part.age+=delta
		if part.age>=part.life or _recovered(int(part.player_id)):
			parts.remove_at(index)
			continue
		if part.stopped and not _support_valid(part):
			part.stopped=false
			part.velocity=Vector2(0,12)
			part.spin=0.0
		if not part.stopped: _advance_part(part,delta)
	for index in range(stains.size()-1,-1,-1):
		var stain:=stains[index]
		stain.age+=delta
		if stain.age>=stain.life or not _support_valid(stain): stains.remove_at(index)
	queue_redraw()

func _recovered(id: int) -> bool:
	if id==0 or not is_instance_valid(game) or not "players" in game: return false
	for player in game.players:
		if is_instance_valid(player) and player.player_id==id: return not player.is_downed() and int(player.gore_mask)==0
	return false

func _trace(start: Vector2,end: Vector2) -> Dictionary:
	var query:=PhysicsRayQueryParameters2D.create(start,end,1|2)
	query.hit_from_inside=true
	return get_world_2d().direct_space_state.intersect_ray(query)

func _advance_part(part: Dictionary,delta: float) -> void:
	part.velocity.y+=420*delta
	var next: Vector2=part.point+Vector2(part.velocity)*delta
	var next_rotation: float=part.rotation+part.spin*delta
	var earliest: Dictionary={}
	var fraction:=1.0
	# Sweep both limb ends and its centre, including the four-pixel silhouette.
	for anchor in [Vector2(part.joint),Vector2.ZERO,Vector2(part.tip)]:
		for edge in [Vector2.LEFT*3.5,Vector2.RIGHT*3.5,Vector2.UP*3.5,Vector2.DOWN*3.5]:
			var start: Vector2=part.point+(anchor+edge).rotated(part.rotation)
			var end: Vector2=next+(anchor+edge).rotated(next_rotation)
			var hit:=_trace(start,end)
			if hit.is_empty(): continue
			if Vector2(hit.normal).length_squared()<0.1 and start.distance_to(hit.position)<0.01:
				# A planted sole can start slightly inside support because of the
				# fragment's thickness. Permit a genuine outward launch, while
				# retaining collisions when the endpoint is still embedded.
				var reverse:=_trace(end,start)
				if not reverse.is_empty() and Vector2(reverse.normal).dot(end-start)>0.0:
					continue
			var portion:=start.distance_to(hit.position)/maxf(.001,start.distance_to(end))
			if portion<=fraction:
				fraction=portion
				earliest=hit
	part.point=Vector2(part.point).lerp(next,fraction)
	part.rotation=lerpf(part.rotation,next_rotation,fraction)
	if not earliest.is_empty():
		collision_count+=1
		part.point+=Vector2(earliest.normal)*.7
		if part.bounces==0 and Vector2(part.velocity).length()>45 and Vector2(earliest.normal).length_squared()>.1:
			part.velocity=Vector2(part.velocity).bounce(earliest.normal)*.23
			part.spin*=.25
			part.bounces=1
		else:
			part.stopped=true
			part.velocity=Vector2.ZERO
			part.merge(_support_state(earliest.collider),true)

func _support_state(collider: Object) -> Dictionary:
	var result:={"support":weakref(collider)}
	if collider is Node2D: result.support_transform=collider.global_transform
	if "gate_amount" in collider: result.support_gate=float(collider.gate_amount)
	return result

func _support_valid(entry: Dictionary) -> bool:
	var support: Object=entry.support.get_ref() if entry.has("support") else null
	if not is_instance_valid(support) or (support is Node and support.is_queued_for_deletion()): return false
	if support.has_method("is_blocking") and not support.is_blocking(): return false
	if support is CollisionObject2D and (support.collision_layer&3)==0: return false
	if entry.has("support_transform") and support.global_transform!=entry.support_transform: return false
	if entry.has("support_gate") and not is_equal_approx(float(support.gate_amount),float(entry.support_gate)): return false
	return true

func _add_stain(hit: Dictionary,bit: Dictionary) -> void:
	if not is_instance_valid(hit.get("collider")) or Vector2(hit.normal).length_squared()<.1: return
	if stains.size()>= (20 if _reduced() else MAX_STAINS): stains.pop_front()
	var stain:={"point":Vector2(hit.position)+Vector2(hit.normal)*.65,"normal":hit.normal,"age":0.0,"life":5.5,"material":bit.material,"tint":Color(bit.tint).darkened(.22),"size":float(bit.size)+_rng.randf_range(.5,2.0)}
	stain.merge(_support_state(hit.collider))
	if _support_valid(stain): stains.append(stain)

func _draw() -> void:
	for stain in stains:
		var point:=to_local(stain.point).round()
		var tangent:=Vector2(stain.normal).orthogonal()*float(stain.size)
		var tint: Color=stain.tint
		tint.a=1.0-smoothstep(stain.life-1.0,stain.life,stain.age)
		draw_line((point-tangent).round(),(point+tangent*.7).round(),tint,2)
	for bit in particles:
		var tint: Color=bit.tint
		tint.a=1.0-smoothstep(float(bit.life)*.7,bit.life,bit.age)
		var point:=to_local(bit.point).round()
		draw_rect(Rect2(point,Vector2(bit.size,bit.size+1)),tint)
	for part in parts:
		var previous: Dictionary=WorkerPoseArt.colors
		WorkerPoseArt.colors=WorkerIdentityArt.palette(part.character,WorkerPoseArt.C)
		if part.character=="infantry": WorkerPoseArt.colors.merge(HUMAN_COLORS,true)
		var fade:=1.0-smoothstep(3.7,part.life,part.age)
		for key in WorkerPoseArt.colors:
			var tint: Color=WorkerPoseArt.colors[key]
			tint.a*=fade
			WorkerPoseArt.colors[key]=tint
		draw_set_transform(to_local(part.point).round(),part.rotation,Vector2(part.facing,1))
		var joint:=Vector2(part.joint)*Vector2(part.facing,1)
		var tip:=Vector2(part.tip)*Vector2(part.facing,1)
		if int(part.part) in [1,2]: WorkerPoseArt._arm(self,joint,tip,part.front)
		else: WorkerPoseArt._leg(self,joint,tip,part.front)
		draw_rect(Rect2(joint.round()-Vector2(2,2),Vector2(4,3)),Color(.42,.12,.1,fade))
		WorkerPoseArt.colors=previous
	draw_set_transform(Vector2.ZERO)
