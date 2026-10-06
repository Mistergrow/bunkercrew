class_name ActorWetness
extends Node2D
## Persistent cosmetic water and dirt. Saturation is sampled from actual sky
## cover, independently of the bounded visible raindrops and F3 particle count.
## Effects use animated art anchors. No health, movement or crafting modifiers.

const WET_RATE := 0.075
const DRY_RATE := 0.006
const MUD_FADE_RATE := 0.0009
const EXPOSURE_INTERVAL := 0.18
const LANDING_CONTACT_WINDOW := 0.15
const WetMaterials := preload("res://scripts/actor_wet_materials.gd")
var actor: Node2D
var amount := 0.0
var mud := 0.0
var exposure := 0.0
var age := 0.0
var drops_emitted := 0
var steps_emitted := 0
var _sample_clock := 0.0
var _drip_clock := 0.43
var _last_position := Vector2.ZERO
var _travel := 0.0
var _previous_contacts: Array[bool] = []
var _pending_contacts: Array[bool] = []
var _last_step_time := -10.0
var _was_airborne := false
var _landing_deadline := -1.0
var _stationary_time := 1.0
var _material_items: Array[CanvasItem] = []
var _last_shader_amount := -1.0
var _presentation_frame := -1
var _presentation_delta := 0.0
var _had_mud := false
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	actor=get_parent() as Node2D
	add_to_group("weather_actors")
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_last_position=actor.global_position
	_rng.seed=actor.get_instance_id()*739
	_sample_clock = _rng.randf_range(0.0,EXPOSURE_INTERVAL)
	_install_materials()

func _install_materials() -> void:
	var visual := actor.get_node_or_null("PixelVisual")
	if is_instance_valid(visual):
		_apply_material(visual,false)
		var weapon:=actor.get_node_or_null("WorkerWeapon")
		if is_instance_valid(weapon):
			_apply_material(weapon,true,-10000.0,true)
			# Aim markers are translucent drawing commands in the weapon canvas;
			# only the opaque steel receives water, not the player's crosshair.
	elif actor.is_in_group("enemies"):
		for part_name in ["body_part","legs_part","weapon_part","propulsion_part","variant_visual"]:
			var part = actor.get(part_name)
			if is_instance_valid(part):
				var cutoff := .5 if part_name=="body_part" and actor.has_method("uses_rolling_contacts") and actor.uses_rolling_contacts() else 0.0
				_apply_material(part,true,-10000.0,false,cutoff)
	elif actor.is_in_group("medics"):
		_apply_material(actor,true,-43.0)

func _apply_material(item: CanvasItem, metal: bool, art_top: float=-10000.0, opaque_only: bool=false, cutoff: float=0.0) -> void:
	var wet_material := WetMaterials.get_material(metal,art_top,opaque_only,cutoff)
	item.material=wet_material
	item.set_instance_shader_parameter("wetness",amount)
	_material_items.append(item)

func weather():
	var game = actor.get("game") if is_instance_valid(actor) else null
	return game.get("weather") if is_instance_valid(game) else null

func rain_segments() -> Array[Dictionary]:
	if not is_instance_valid(actor) or not actor.is_visible_in_tree(): return []
	return ActorWeatherGeometry.segments(actor)

func feet() -> Array[Vector2]:
	if not is_instance_valid(actor): return []
	return ActorWeatherGeometry.feet(actor)

func receive_rain(quantity: float, _point: Vector2, _normal: Vector2) -> void:
	if not is_finite(quantity) or quantity<=0.0: return
	# Visible hits add a tiny local deposit; exposure supplies the continuous rain.
	amount=clampf(amount+minf(quantity,0.045),0.0,1.0)

func _physics_process(delta: float) -> void:
	# A stalled render may cause several physics catch-up ticks with the same
	# painted pose. Accumulate time and sample cosmetic contacts once per frame.
	_presentation_delta += delta
	var frame := Engine.get_process_frames()
	if frame == _presentation_frame: return
	_presentation_frame = frame
	advance(_presentation_delta)
	_presentation_delta = 0.0

func advance(delta: float) -> void:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or delta<=0.0: return
	age+=delta
	var sky = weather()
	var strength: float = float(sky.get("rain_strength")) if is_instance_valid(sky) and sky.get("rain_strength")!=null else 1.0
	_sample_clock-=delta
	if _sample_clock<=0.0:
		_sample_clock=EXPOSURE_INTERVAL
		if strength>0.0: _sample_exposure(sky)
		else: exposure=0.0
	amount=clampf(amount+delta*(WET_RATE*exposure*strength-DRY_RATE*(1.0-exposure*strength)),0.0,1.0)
	mud=move_toward(mud,0.0,delta*MUD_FADE_RATE)
	var displacement := actor.global_position-_last_position
	var teleported := displacement.length()>70.0
	_stationary_time = 1.0 if teleported else (0.0 if absf(displacement.x)>.01 else _stationary_time+delta)
	_travel = 0.0 if teleported else _travel+absf(displacement.x)
	_last_position=actor.global_position
	if teleported:
		_previous_contacts.clear()
		_pending_contacts.clear()
		_was_airborne = actor.get("_airborne")==true
		_landing_deadline = -1.0
	else:
		_foot_contacts(sky,displacement)
	_drip_clock-=delta
	if _drip_clock<=0.0:
		_drip_clock=_rng.randf_range(0.55,1.0)/maxf(0.25,amount)
		if amount>0.22 and not _reduced(sky): _drip(sky)
	WetMaterials.update_clock(self,delta)
	if absf(amount-_last_shader_amount)>.001 or (is_zero_approx(amount) and _last_shader_amount!=0.0):
		for item in _material_items:
			item.set_instance_shader_parameter("wetness",amount)
		_last_shader_amount = amount
	if mud>.04 or _had_mud: queue_redraw()
	_had_mud = mud>.04

func _sample_exposure(sky) -> void:
	exposure=0.0
	if not is_instance_valid(sky): return
	var segments := rain_segments()
	if segments.is_empty(): return
	# Three separated true-art upper points avoid soaking from a sheltered pivot
	# or from a too-large character physics capsule.
	var upper: Array[Dictionary] = []
	for segment in segments:
		var height: float = minf(segment.from.y,segment.to.y)
		var slot := 0
		while slot<upper.size() and height>=minf(upper[slot].from.y,upper[slot].to.y): slot+=1
		if slot>=3: continue
		upper.insert(slot,segment)
		if upper.size()>3: upper.resize(3)
	var count := upper.size()
	for index in count:
		var segment: Dictionary = upper[index]
		var point: Vector2 = Vector2(segment.from).lerp(segment.to,0.5)+Vector2(0,-1)
		if sky.has_method("exposure_at"): exposure+=clampf(float(sky.exposure_at(point,actor)),0.0,1.0)
		elif sky.has_method("is_outdoors"): exposure+=1.0 if sky.is_outdoors(point) else 0.0
	exposure/=float(count)

func _surface_effects(sky):
	return sky.get("surface_effects") if is_instance_valid(sky) else null

func _reduced(sky) -> bool:
	return is_instance_valid(sky) and sky.get("reduced_effects")==true

func _foot_contacts(sky,displacement: Vector2 = Vector2.ZERO) -> void:
	# A stationary rig cannot spend travel on a walking contact. Keep the short
	# landing/presentation windows intact before avoiding idle leg reconstruction.
	if actor.is_in_group("air_enemies"): return
	if absf(displacement.x)<=.01 and _stationary_time>=.15 and _landing_deadline<age and not _was_airborne and actor.get("_airborne")!=true:
		_previous_contacts.clear()
		_pending_contacts.clear()
		_travel=0.0
		return
	var surfaces = _surface_effects(sky)
	if not is_instance_valid(surfaces): return
	var airborne: bool = actor.get("_airborne")==true
	# Physics may land before the next render tick replaces the raised fall
	# pose. Keep that one event briefly, until a real sole reaches real support.
	if _was_airborne and not airborne:
		_landing_deadline = age+LANDING_CONTACT_WINDOW
	_was_airborne = airborne
	var forbidden: bool = airborne or actor.get("climbing")==true or actor.get("dead")==true or is_instance_valid(actor.get("mounted_turret")) or (actor.has_method("is_downed") and actor.is_downed()) or ("medical" in actor and is_instance_valid(actor.medical) and actor.medical.is_rising())
	var on_screen := get_viewport_rect().grow(100).has_point(actor.get_global_transform_with_canvas().origin)
	if forbidden or not actor.is_visible_in_tree() or not on_screen:
		_previous_contacts.fill(false)
		_pending_contacts.fill(false)
		_travel = 0
		_landing_deadline = -1.0
		return
	# Invisible/offscreen or medically unavailable actors discard all contacts.
	# Reconstruct their animated soles only after these existing gates pass.
	var points := feet()
	if _previous_contacts.size()!=points.size() or _pending_contacts.size()!=points.size():
		_previous_contacts.resize(points.size())
		_previous_contacts.fill(false)
		_pending_contacts.resize(points.size())
		_pending_contacts.fill(false)
	if age>_landing_deadline:
		_landing_deadline = -1.0
	var landed := _landing_deadline>=age
	var stride_scale: float = float(actor.get("visual_scale")) if actor.get("visual_scale")!=null else 1.0
	# Render interpolation and physics may tick at different rates. Retain the
	# last actual motion briefly without allowing an idle pose to spend it.
	var velocity = actor.get("velocity")
	var striding: bool = actor.get("moving")==true or (velocity is Vector2 and absf(velocity.x)>8.0)
	var moving_now := absf(displacement.x)>.01 or (striding and _stationary_time<.15)
	var grounded_candidate := false
	for index in points.size():
		var foot: Vector2 = points[index]+Vector2(0,3.0*stride_scale)
		# Sample support only when the painted sole is landing, rather than
		# raycasting every raised or planted foot on every physics frame.
		var planted := absf(foot.y-actor.global_position.y)<=2.2
		var transition := planted and not _previous_contacts[index]
		if not planted: _pending_contacts[index] = false
		elif transition and moving_now: _pending_contacts[index] = true
		_previous_contacts[index] = planted
		grounded_candidate = grounded_candidate or planted
		if not planted or not (landed or (_pending_contacts[index] and moving_now and _travel>4.0)): continue
		if age-_last_step_time<.12: continue
		var state: Dictionary = surfaces.sample_contact(foot) if surfaces.has_method("sample_contact") else surfaces.surface_state_at(foot)
		if state.is_empty() or not bool(state.get("supported",true)) or absf(float(state.get("distance",INF)))>2.2: continue
		mud=clampf(mud+float(state.get("mud",0.0))*0.15,0.0,1.0)
		var weight := clampf(stride_scale,0.65,1.7)
		if actor.is_in_group("players"):
			weight = 1.25 if str(actor.get("character_id"))=="branko" else .88 if str(actor.get("character_id"))=="ivo" else 1.0
		if landed: weight *= 1.45
		_present_footstep(surfaces,sky,foot,weight,state)
		_landing_deadline = -1.0
		landed = false
		_pending_contacts.fill(false)
	# Tracks have no airborne swing phase; their real rolling movement displaces
	# water at the contact edge after a finite travelled distance.
	var vehicle: bool=actor.has_method("uses_rolling_contacts") and actor.uses_rolling_contacts()
	if (actor.is_in_group("medics") or vehicle) and moving_now and _travel>=13.0 and points.size()>0 and grounded_candidate and age-_last_step_time>=.12:
		var contact_index:=steps_emitted%points.size() if vehicle else (0 if actor.facing>0 else points.size()-1)
		var foot: Vector2 = points[contact_index]+Vector2(0,3.0*stride_scale if vehicle else 2.0)
		var state: Dictionary = surfaces.sample_contact(foot) if surfaces.has_method("sample_contact") else surfaces.surface_state_at(foot)
		if not state.is_empty() and bool(state.get("supported",true)) and absf(float(state.get("distance",INF)))<=2.2:
			mud=clampf(mud+float(state.get("mud",0.0))*0.10,0.0,1.0)
			_present_footstep(surfaces,sky,foot,.90 if vehicle else .55,state)
		_travel=0.0
	elif _stationary_time>=.15 or _travel>80.0:
		_travel = 0.0

func _present_footstep(surfaces,sky,point: Vector2,weight: float,state: Dictionary) -> void:
	_last_step_time = age
	steps_emitted += 1
	if surfaces.has_method("contact_event"):
		surfaces.contact_event(point,weight,actor,state)
	elif not _reduced(sky):
		surfaces.footstep(point,weight,actor)
	# Tires and tracks still displace the surface, but are not walking boots.
	if actor.has_method("uses_rolling_contacts") and actor.uses_rolling_contacts(): return
	var game = actor.get("game")
	var sound = game.get("audio") if is_instance_valid(game) else null
	if is_instance_valid(sound) and sound.has_method("play_footstep"):
		var heavy: bool = actor.is_in_group("enemies") and stride_weight()>1.1
		var enemy_kind := str(actor.get("kind")) if actor.is_in_group("enemies") else ""
		if not enemy_kind.is_empty():
			sound.play_footstep(str(state.get("kind","water")),state.get("point",point),weight,heavy,false,enemy_kind)
		else:
			sound.play_footstep(str(state.get("kind","dry")),state.get("point",point),weight,heavy,actor.is_in_group("players"),"",str(actor.get("character_id")) if actor.is_in_group("players") else "")

func stride_weight() -> float:
	return float(actor.get("visual_scale")) if actor.get("visual_scale")!=null else 1.0

func _drip(sky) -> void:
	var surfaces = _surface_effects(sky)
	if not is_instance_valid(surfaces) or not surfaces.has_method("emit_drip"): return
	var segments := rain_segments()
	if segments.is_empty(): return
	var segment: Dictionary = segments[_rng.randi_range(0,segments.size()-1)]
	var point: Vector2 = segment.to
	var movement: Vector2 = actor.get("velocity") if actor.get("velocity") is Vector2 else Vector2.ZERO
	surfaces.emit_drip(point+Vector2(0,2),Vector2(clampf(movement.x*0.12,-12,12),18),amount,actor)
	drops_emitted+=1

func _draw() -> void:
	if mud<=0.04 or not is_instance_valid(actor): return
	# Dirt stays on the actual moving sole, including raised ladder feet and a
	# lying patient's boots. It is never drawn at the actor origin by assumption.
	var draw_scale: float = float(actor.get("visual_scale")) if actor.get("visual_scale")!=null else 1.0
	for foot in feet():
		var at := to_local(foot).round()
		var color := Color(0.31,0.25,0.18,minf(0.82,mud))
		draw_rect(Rect2(at+Vector2(-4,-1)*draw_scale,Vector2(5,2)*draw_scale),color)
		draw_rect(Rect2(at+Vector2(3,0)*draw_scale,Vector2(2,2)*draw_scale),color.lightened(0.10))
