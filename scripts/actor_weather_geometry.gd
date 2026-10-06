class_name ActorWeatherGeometry
extends RefCounted

const IdentityArt := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const VehicleArt := preload("res://scripts/ground_vehicle_art.gd")
## Read-only silhouette sampling of the original atlases, plus the exact native
## medical pose and leg endpoints. Weather never uses an actor's hitbox as art.

static var _images: Dictionary = {}
static var _contours: Dictionary = {}
const WALK_FEET := [Vector2(10,-3),Vector2(5,-3),Vector2(-2,-3),Vector2(-10,-4),Vector2(-9,-8),Vector2(-3,-12),Vector2(6,-10),Vector2(12,-5)]
const CROUCH_FEET := [Vector2(-8,-3),Vector2(-4,-3),Vector2(1,-3),Vector2(7,-3),Vector2(9,-5),Vector2(5,-6),Vector2(0,-6),Vector2(-6,-5)]

static func machine_bounds(actor: Node2D) -> Rect2:
	# Bounds use the same authored destinations and live part transforms as
	# segments(). Large generic boxes otherwise reach several adjacent machines
	# and force their alpha silhouettes to be sampled for a single short drop.
	if actor.is_in_group("air_enemies"):
		var air_size: Vector2 = actor.profile.body_size
		var air_bounds: Rect2 = actor.body_part.global_transform * Rect2(-air_size*.5,air_size)
		var family: String = actor.profile.propulsion
		var span := clampf(air_size.x*.23,11,29) if family in ["rotor","tiltrotor","vtol"] else 3.0
		for engine: Vector2 in AircraftArtCatalog.engine_points(actor.kind,air_size.x):
			air_bounds = air_bounds.merge(actor.propulsion_part.global_transform * Rect2(engine+Vector2(-span,-1),Vector2(span*2,.1)))
		return air_bounds.merge(actor.weapon_part.global_transform * Rect2(-23+actor.weapon_recoil,-4,28-actor.weapon_recoil,.1)).abs()
	if actor.has_method("uses_rolling_contacts") and actor.uses_rolling_contacts():
		var vehicle_bounds: Rect2 = actor.body_part.global_transform * VehicleArt.RECTS[actor.kind]
		var muzzle: Vector2 = VehicleArt.muzzle(actor.kind)
		return vehicle_bounds.merge(actor.weapon_part.global_transform * Rect2(muzzle+Vector2(1,-4),Vector2(8-muzzle.x,.1)))
	var chassis: String = actor.chassis_kind()
	var region: Rect2 = SiegeMachine.BODY_REGIONS[chassis]
	var width: float = actor.profile.body_size.x
	if chassis=="colossus": width=74.0
	elif chassis=="siege": width=79.0
	elif chassis=="breaker": width=78.0
	var size := Vector2(width,width*region.size.y/region.size.x)
	var bounds: Rect2 = actor.body_part.global_transform * Rect2(Vector2(-width*.5,-19 if chassis=="runner" else -24),size)
	var tip: Vector2 = actor.weapon_muzzle()
	var weapon := Rect2(Vector2(-23,-17),Vector2(28,17)).merge(Rect2(tip-Vector2(1,17),Vector2(34,18)))
	bounds = bounds.merge(actor.weapon_part.global_transform * weapon)
	if is_instance_valid(actor.variant_visual) and is_instance_valid(actor.abilities):
		bounds = bounds.merge(actor.variant_visual.global_transform * Rect2(-50,-44,102,62))
	return bounds

static func _segment(result: Array[Dictionary], node: Node2D, a: Vector2, b: Vector2, material: String="metal") -> void:
	var start := node.to_global(a)
	var end := node.to_global(b)
	var normal := (end-start).orthogonal().normalized()
	if normal.y>0: normal=-normal
	result.append({"from":start,"to":end,"normal":normal,"material":material})

static func atlas_top(texture: Texture2D, region: Rect2, destination: Rect2) -> Array:
	var texture_id:=texture.get_rid().get_id()
	if not _contours.has(texture_id): _contours[texture_id]={}
	var regions: Dictionary=_contours[texture_id]
	if not regions.has(region): regions[region]={}
	var destinations: Dictionary=regions[region]
	if destinations.has(destination): return destinations[destination].pairs
	if not _images.has(texture_id): _images[texture_id]=texture.get_image()
	var source: Image = _images[texture_id]
	var result: Array = []
	var previous := Vector2.INF
	var steps := maxi(2,int(ceil(destination.size.x/2.0)))
	for step in steps+1:
		var x := int(region.position.x+minf(region.size.x-1,step*region.size.x/steps))
		var found := false
		for y in range(int(region.position.y),int(region.end.y)):
			if source.get_pixel(x,y).a<0.50: continue
			var point := destination.position+Vector2(float(step)*destination.size.x/steps,(y-region.position.y)*destination.size.y/region.size.y)
			if previous!=Vector2.INF and absf(point.y-previous.y)<destination.size.y*0.32:
				result.append([previous,point])
			previous=point
			found=true
			break
		if not found: previous=Vector2.INF
	var points := PackedVector2Array()
	for pair: Array in result:
		points.append(pair[0])
		points.append(pair[1])
	destinations[destination]={"pairs":result,"points":points}
	return result

static func _atlas_segments(result: Array[Dictionary], node: Node2D, transform: Transform2D, texture: Texture2D, region: Rect2, destination: Rect2, material: String="metal") -> void:
	# Alpha sampling is immutable. Transform its packed endpoints in native code
	# instead of crossing into Node2D.to_global twice for every small art edge.
	atlas_top(texture,region,destination)
	var local_points: PackedVector2Array=_contours[texture.get_rid().get_id()][region][destination].points
	var points: PackedVector2Array=node.global_transform*(transform*local_points)
	for index in range(0,points.size(),2):
		var a := points[index]
		var b := points[index+1]
		var normal := (b-a).orthogonal().normalized()
		if normal.y>0: normal=-normal
		result.append({"from":a,"to":b,"normal":normal,"material":material})

static func worker_transform(visual: Node2D) -> Transform2D:
	var worker = visual.worker
	var flinch: float = sin(clampf(worker.hurt_flash/0.22,0.0,1.0)*PI)*-0.13 if not worker.is_downed() and visual.special_pose!="mounted" and visual.mining_pose.is_empty() else 0.0
	var tx := Transform2D(worker.facing*flinch,Vector2(0,sin(absf(flinch)*8)*2))
	return tx.scaled_local(Vector2(visual.sprite_facing(),1))

static func worker_feet(visual: Node2D) -> Array[Vector2]:
	var pose: String = visual.pose_name
	var frame: int = visual.pose_frame
	if not visual.pose_skeleton.is_empty() and (visual.has_articulated_pose() or visual._limp_lower):
		return [visual.pose_skeleton.feet[0],visual.pose_skeleton.feet[1]]
	var authored := Personality.frame(str(visual.worker.character_id),pose,frame)
	if not authored.is_empty():
		return [Vector2(authored.feet[0][0],authored.feet[0][1]),Vector2(authored.feet[1][0],authored.feet[1][1])]
	match pose:
		"walk","carry_walk": return [WALK_FEET[(frame+4)%8],WALK_FEET[frame%8]]
		"crouch_walk": return [CROUCH_FEET[(frame+4)%8],CROUCH_FEET[frame%8]]
		"climb":
			var foot_points: Array = visual._frames.climb.feet[frame]
			return [Vector2(foot_points[0][0],foot_points[0][1]),Vector2(foot_points[1][0],foot_points[1][1])]
		"jump_up": return [Vector2(-10,-8-frame*2),Vector2(9,-12+frame)]
		"fall": return [Vector2(-7,-4),Vector2(8,-4-frame)]
		"land","mine": return [Vector2(-9,-3),Vector2(9 if pose=="mine" else 8,-3)]
		"work": return [Vector2(-7,-3),Vector2(7,-3)]
		"pickup","drop","crouch","crouch_mine": return [Vector2(-8,-3),Vector2(8,-3)]
		"turret": return [Vector2(-10,-3),Vector2(8,-3)]
		"weapon","weapon_up","weapon_down": return [Vector2(-8,-3),Vector2(7,-3)]
	return [Vector2(-6,-3),Vector2(5,-3)]

static func segments(actor: Node2D) -> Array[Dictionary]:
	if actor.has_method("weather_segments"): return actor.weather_segments()
	if actor.has_method("uses_rolling_contacts") and actor.uses_rolling_contacts(): return VehicleArt.weather_segments(actor)
	var result: Array[Dictionary] = []
	var visual := actor.get_node_or_null("PixelVisual")
	if is_instance_valid(visual):
		var tx := worker_transform(visual)
		if visual.has_articulated_pose():
			var pose: Dictionary = visual.pose_skeleton
			var body := WorkerPoseArt.torso_transform(pose)
			var head := WorkerPoseArt.head_transform(pose)
			# Sample the same clean head/torso pieces as the articulated renderer.
			# This follows Ivo's low cap and Branko's broad coat as well as Mara's hat.
			_atlas_segments(result,visual,tx*head,IdentityArt.head(actor.character_id,bool(pose.get("back",false))),Rect2(0,0,112,112),Rect2(-49,-33,112,112))
			_atlas_segments(result,visual,tx*body,IdentityArt.torso(actor.character_id,bool(pose.get("back",false))),Rect2(0,0,112,112),Rect2(-48,-48,112,112),"cloth")
			if visual.special_pose in ["downed","rise"]:
				_segment(result,visual,tx*(Vector2(pose.shoulder)+Vector2(0,-5)),tx*(Vector2(pose.hip)+Vector2(0,-5)),"cloth")
			for hand: Vector2 in pose.hands:
				_segment(result,visual,tx*(hand+Vector2(-3,-2)),tx*(hand+Vector2(3,-2)),"cloth")
			if not visual.mining_pose.is_empty():
				_segment(result,visual,tx*Vector2(pose.tool_butt),tx*Vector2(pose.tool_head),"wood")
				_segment(result,visual,tx*(Vector2(pose.tool_head)+Vector2(pose.tool_axis).orthogonal()*12.0),tx*Vector2(pose.tool_tip))
		else:
			var region := Rect2(Vector2(visual.pose_frame*112,int(visual._frames[visual.pose_name].row)*112),Vector2(112,112))
			for texture in [IdentityArt.body(actor.character_id),IdentityArt.arms(actor.character_id)]:
				_atlas_segments(result,visual,tx,texture,region,Rect2(-WorkerVisual.FEET_ANCHOR,Vector2(112,112)),"cloth")
		var weapon:=actor.get_node_or_null("WorkerWeapon")
		if is_instance_valid(weapon) and weapon.aiming and weapon.can_use():
			var gun_tx:=Transform2D(weapon.aim_direction.angle(),Vector2.ZERO).scaled_local(Vector2(1,1 if weapon.aim_direction.x>=0 else -1))
			var kick:=Vector2(-weapon.recoil,0)
			for pair in [[Vector2(-18,-4),Vector2(-8,-4)],[Vector2(-8,-6),Vector2(15,-6)],[Vector2(15,-2),Vector2(35,-2)]]:
				_segment(result,weapon,gun_tx*(Vector2(pair[0])+kick),gun_tx*(Vector2(pair[1])+kick))
	elif actor.is_in_group("air_enemies"):
		var size: Vector2 = actor.profile.body_size
		_atlas_segments(result,actor.body_part,Transform2D.IDENTITY,actor.chassis_atlas,AirMachine.BODY_REGIONS[actor.profile.atlas],Rect2(-size*0.5,size))
		var family: String = actor.profile.propulsion
		for engine: Vector2 in AircraftArtCatalog.engine_points(actor.kind,size.x):
			var span := clampf(size.x*.23,11,29) if family in ["rotor","tiltrotor","vtol"] else 3.0
			_segment(result,actor.propulsion_part,engine+Vector2(-span,-1),engine+Vector2(span,-1))
		_segment(result,actor.weapon_part,Vector2(-23+actor.weapon_recoil,-4),Vector2(5,-4))
	elif actor.is_in_group("enemies"):
		var chassis: String = actor.chassis_kind()
		var region: Rect2 = SiegeMachine.BODY_REGIONS[chassis]
		var width: float = actor.profile.body_size.x
		if chassis=="colossus": width=74.0
		elif chassis=="siege": width=79.0
		elif chassis=="breaker": width=78.0
		var size := Vector2(width,width*region.size.y/region.size.x)
		_atlas_segments(result,actor.body_part,Transform2D.IDENTITY,actor.chassis_atlas,region,Rect2(Vector2(-width*0.5,-19 if chassis=="runner" else -24),size))
		_ground_equipment(result,actor)
	elif actor.is_in_group("medics"):
		var bob := roundf(sin(actor.elapsed*2.2)*0.65) if not actor.climbing else 0.0
		var look: float = roundf(sin(actor.elapsed*0.7)*2) if actor._idle_time>2 else actor.facing*3
		_segment(result,actor,Vector2(look-7,-39+bob),Vector2(look+7,-39+bob))
		_segment(result,actor,Vector2(-17,-28+bob),Vector2(17,-28+bob))
	return result

static func _ground_equipment(result: Array[Dictionary],actor: Node2D) -> void:
	var tip: Vector2=actor.weapon_muzzle()
	var top := -6.0
	match actor.chassis_kind():
		"assault": top=-10.0
		"colossus": top=-8.0
		"siege": top=-11.0
	match actor.kind:
		"sniper":
			_segment(result,actor.weapon_part,Vector2(-23,-17),Vector2(-2,-17))
			top=-9.0
		"demolisher":
			_segment(result,actor.weapon_part,tip+Vector2(9,-16),tip+Vector2(32,-16))
			top=-9.0
		"lancer":
			_segment(result,actor.weapon_part,tip,tip+Vector2(20,-9))
			top=-8.0
		"bastion": top=-14.0
	_segment(result,actor.weapon_part,tip+Vector2(1,-3),Vector2(-17,-3))
	_segment(result,actor.weapon_part,Vector2(-17,top),Vector2(5,top))
	if not is_instance_valid(actor.variant_visual) or not is_instance_valid(actor.abilities): return
	var node: Node2D=actor.variant_visual
	var ability=actor.abilities
	match actor.kind:
		"shield_guard":
			var open := snappedf(ability.shield_open,0.2)
			var recoil := sin(clampf(ability.shield_flash/0.18,0,1)*PI)*3
			_segment(result,node,Vector2(-46-recoil,-25-open*11),Vector2(-29-recoil,-25-open*11))
			_segment(result,node,Vector2(-46-recoil,2+open*12),Vector2(-29-recoil,2+open*12))
		"lancer": _segment(result,node,Vector2(15,-24),Vector2(32,-24))
		"sniper": _segment(result,node,Vector2(18,-43),Vector2(30,-43))
		"demolisher": _segment(result,node,Vector2(13,-28),Vector2(35,-28))
		"repair_crawler":
			_segment(result,node,Vector2(-8,-37),Vector2(7,-37))
			_segment(result,node,Vector2(-29,-22),Vector2(-18,-22))
			_segment(result,node,Vector2(-12,-31),Vector2(13,-31))
			var elbow := Vector2(29,-28+sin(actor.age*2.0)*3.0)
			_segment(result,node,Vector2(10,-17),elbow+Vector2(0,-3))
			_segment(result,node,elbow+Vector2(0,-3),Vector2(46,-10+sin(actor.age*2.0)*3.0))
		"bastion":
			_segment(result,node,Vector2(-44,-4),Vector2(-28,-9))
			_segment(result,node,Vector2(28,-9),Vector2(44,-4))
			var vent := 9.0 if ability.vent_time>0 else 0.0
			_segment(result,node,Vector2(-39,-30-vent),Vector2(-11,-30-vent))
			_segment(result,node,Vector2(8,-27-vent),Vector2(37,-27-vent))

static func feet(actor: Node2D) -> Array[Vector2]:
	if actor.has_method("weather_feet"): return actor.weather_feet()
	if actor.has_method("uses_rolling_contacts") and actor.uses_rolling_contacts(): return VehicleArt.weather_feet(actor)
	var result: Array[Vector2] = []
	var visual := actor.get_node_or_null("PixelVisual")
	if is_instance_valid(visual):
		var tx := worker_transform(visual)
		for foot in worker_feet(visual): result.append(visual.to_global(tx*foot))
	elif actor.is_in_group("enemies") and not actor.is_in_group("air_enemies"):
		for index in int(actor.profile.legs):
			result.append(actor.legs_part.to_global(actor.leg_foot(index)))
	elif actor.is_in_group("medics") and not actor.climbing:
		result=[actor.to_global(Vector2(-13,-2)),actor.to_global(Vector2(13,-2))]
	return result
