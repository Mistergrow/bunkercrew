extends Node2D
## Shared presentation of gunfire and blasts: additive muzzle halos, smoke wisps,
## spent casings, a small pool of real lights and the camera impulses. Created on
## demand below the game by the first visible shot or burst, on host and guests
## alike, from state both already have (replicated flash timers and shot
## counters, the replicated "impact" event). It never reads or writes simulation
## state; every pool is fixed and everything is absent with reduced effects.
const FIRE_LIGHTING := preload("res://scripts/scenery_fire_lighting.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const META := &"combat_feel"
const MAX_HALOS := 12
const MAX_WISPS := 32
const MAX_CASINGS := 16
const SHOT_LIGHTS := 3
const BLAST_LIGHTS := 2
## No more than one abrupt light pulse per this interval for the whole view
## (below three per second). Faster fire accumulates into a steady glow.
const MIN_PULSE_INTERVAL := 0.36
const HALO_LIFE := 0.10
const WARM := Color(1.0,.72,.40)
const COLD := Color(.62,.86,1.0)
const BLAST := Color(1.0,.60,.30)
## Scorch marks left on the ground by blasts: a fixed pool, oldest replaced.
const MAX_SCORCH := 14
const SCORCH_LIFE := 11.0
## Flak shells followed for their presentation fuse (see track_flak).
const MAX_FLAK := 24
const FLAK_FUSED := &"flak_fused"
const NEAR_MISS := 34.0
## Hostile hitscan rounds drawn as flying streaks (see trace).
const MAX_TRACES := 16
const TRACE_SPEED := 2600.0
const HOSTILE_BODY := Color("e0482c")
const HOSTILE_HEAD := Color("ffd9a8")
## Gun smoke that builds up at a muzzle under sustained fire (see shot()).
const MAX_HAZE := 4
const HAZE_PUFFS := 5
const HAZE_DECAY := 1.4
## Gunfire lights the floor its muzzle stands over: its light voice moves
## down to that floor (the shared surface falloff is cut just below its
## centre, so a voice at the muzzle lit only what was above the barrel) and a
## pool of muzzle light falls on the ground and the floor around the shooter.
const MUZZLE_FLOOR_REACH := 90.0

var game: Node
var clock := 0.0
var pulses := 0
var shots_seen := 0
var blasts_seen := 0
var smoke_layer: Node2D
var glow_layer: Node2D
var shot_lamps: Array[PointLight2D] = []
var blast_lamps: Array[PointLight2D] = []
var _random := RandomNumberGenerator.new()
var _last_pulse := -10.0
var _geometry_clock := 1.0
var _halo_pos := PackedVector2Array()
var _halo_dir := PackedVector2Array()
var _halo_state := PackedVector2Array() # x: age (negative: free), y: strength
var _halo_cold := PackedByteArray()
var _halo_next := 0
var _halo_source := PackedInt64Array() # drawing node of the flash, 0: none
var _halo_tip := PackedVector2Array()
var _halo_shape := PackedVector3Array() # x: facing, y: shot counter, z: flash duration
var _halo_world: Array[Transform2D] = []
var _halo_via: Array[Transform2D] = []
var flash_layer: Node2D
var _wisp_pos := PackedVector2Array()
var _wisp_velocity := PackedVector2Array()
var _wisp_state := PackedVector2Array() # x: age (negative: free), y: life
var _wisp_next := 0
var _casing_pos := PackedVector2Array()
var _casing_velocity := PackedVector2Array()
var _casing_state := PackedVector2Array() # x: age (negative: free), y: floor height (NAN: unresolved)
var _casing_next := 0
var _shot_pos := PackedVector2Array()
var _shot_heat := PackedFloat32Array()
var _shot_glow := PackedFloat32Array()
var _shot_pulse := PackedFloat32Array()
var _shot_size := PackedFloat32Array()
var _shot_cold := PackedByteArray()
var _shot_floor := PackedFloat32Array() # floor below a gunfire voice (NAN: unknown, INF: none)
var _blast_pos := PackedVector2Array()
var _blast_state := PackedVector2Array() # x: age (negative: free), y: power
var _blast_peak := PackedFloat32Array()
var _floor_ray := PhysicsRayQueryParameters2D.new()
var scorch_layer: Node2D
var _scorch_pos := PackedVector2Array()
var _scorch_state := PackedVector3Array() # x: age (negative: free), y: width, z: seed
var _scorch_next := 0
var airbursts := 0
var _flak_id := PackedInt64Array() # 0: free
var _flak_pos := PackedVector2Array() # last presented position
var _flak_dir := PackedVector2Array()
var _flak_fuse := PackedFloat32Array() # distance travelled at which it bursts
var _air: Array[Node] = []
var _air_clock := 0.0
var _trace_from := PackedVector2Array()
var _trace_to := PackedVector2Array()
var _trace_state := PackedVector2Array() # x: age (negative: free), y: width
var _trace_next := 0
var _haze_pos := PackedVector2Array()
var _haze_dir := PackedVector2Array()
var _haze_build := PackedFloat32Array() # 0: free, 1: a dense cloud
var _blast_ground := PackedFloat32Array() # ground below a blast voice (NAN: unknown, INF: none)
var ground_glow_layer: Node2D

static func of(node: Node) -> Node2D:
	# The owning game is the nearest ancestor with the real camera rig. Stubs
	# and isolated galleries without one simply receive no shared layer.
	if not is_instance_valid(node) or not node.is_inside_tree(): return null
	var host: Node = node.get_parent()
	for step in 10:
		if host == null: return null
		if host.has_meta(META) or (host.has_method("impact") and host.get("player_camera") != null): break
		host = host.get_parent()
	if host == null or not (host is Node2D): return null
	if host.has_meta(META):
		var existing: Variant = host.get_meta(META)
		if is_instance_valid(existing) and not existing.is_queued_for_deletion() and existing.get_parent() == host: return existing
	if not host.has_method("impact") or host.get("player_camera") == null: return null
	var feel: Node2D = load("res://scripts/combat_feel.gd").new()
	feel.name = "CombatFeel"
	feel.set("game",host)
	host.set_meta(META,feel)
	host.add_child(feel)
	return feel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_random.seed = 90731
	_halo_pos.resize(MAX_HALOS)
	_halo_dir.resize(MAX_HALOS)
	_halo_state.resize(MAX_HALOS)
	_halo_cold.resize(MAX_HALOS)
	_halo_source.resize(MAX_HALOS)
	_halo_tip.resize(MAX_HALOS)
	_halo_shape.resize(MAX_HALOS)
	_halo_world.resize(MAX_HALOS)
	_halo_via.resize(MAX_HALOS)
	_wisp_pos.resize(MAX_WISPS)
	_wisp_velocity.resize(MAX_WISPS)
	_wisp_state.resize(MAX_WISPS)
	_casing_pos.resize(MAX_CASINGS)
	_casing_velocity.resize(MAX_CASINGS)
	_casing_state.resize(MAX_CASINGS)
	_halo_state.fill(Vector2(-1,0))
	_wisp_state.fill(Vector2(-1,0))
	_casing_state.fill(Vector2(-1,0))
	_shot_pos.resize(SHOT_LIGHTS)
	_shot_heat.resize(SHOT_LIGHTS)
	_shot_glow.resize(SHOT_LIGHTS)
	_shot_pulse.resize(SHOT_LIGHTS)
	_shot_size.resize(SHOT_LIGHTS)
	_shot_cold.resize(SHOT_LIGHTS)
	_shot_floor.resize(SHOT_LIGHTS)
	_shot_floor.fill(INF)
	_blast_pos.resize(BLAST_LIGHTS)
	_blast_state.resize(BLAST_LIGHTS)
	_blast_peak.resize(BLAST_LIGHTS)
	_blast_state.fill(Vector2(-1,0))
	_scorch_pos.resize(MAX_SCORCH)
	_scorch_state.resize(MAX_SCORCH)
	_scorch_state.fill(Vector3(-1,0,0))
	_flak_id.resize(MAX_FLAK)
	_flak_pos.resize(MAX_FLAK)
	_flak_dir.resize(MAX_FLAK)
	_flak_fuse.resize(MAX_FLAK)
	_trace_from.resize(MAX_TRACES)
	_trace_to.resize(MAX_TRACES)
	_trace_state.resize(MAX_TRACES)
	_trace_state.fill(Vector2(-1,0))
	_haze_pos.resize(MAX_HAZE)
	_haze_dir.resize(MAX_HAZE)
	_haze_build.resize(MAX_HAZE)
	_blast_ground.resize(BLAST_LIGHTS)
	_blast_ground.fill(INF)
	# Ground marks sit on the terrain and floors, below props, contact shadows
	# and every actor (all z 2 and above); never on the HUD's canvas layers.
	scorch_layer = Node2D.new()
	scorch_layer.name = "Scorch"
	scorch_layer.z_index = 1
	scorch_layer.material = PixelArt.grid_material(PixelArt.GRID_LIT)
	scorch_layer.draw.connect(_draw_scorch)
	add_child(scorch_layer)
	# A blast lights the ground it stands on (the terrain is unlit art, so the
	# blast lamps cannot reach it) and its scorch glows for a moment: additive,
	# on the ground marks' level below props and actors.
	ground_glow_layer = Node2D.new()
	ground_glow_layer.name = "GroundGlow"
	ground_glow_layer.z_index = 1
	ground_glow_layer.material = PixelArt.grid_material(PixelArt.GRID_ADD)
	ground_glow_layer.draw.connect(_draw_ground_glow)
	add_child(ground_glow_layer)
	# Gun smoke and casings are lit like the world around them: the night
	# ambient and the fire and muzzle lights reach them.
	PixelArt.atmosphere_from(game)
	smoke_layer = Node2D.new()
	smoke_layer.name = "Smoke"
	smoke_layer.z_index = 23
	smoke_layer.material = PixelArt.grid_material(PixelArt.GRID_LIT)
	smoke_layer.draw.connect(_draw_smoke)
	add_child(smoke_layer)
	flash_layer = Node2D.new()
	flash_layer.name = "Flash"
	flash_layer.z_index = 25
	# Grid material: the flash tongues step in world texels even on a turned
	# barrel; the flash's plain rects pass through unchanged.
	flash_layer.material = PixelArt.grid_material(PixelArt.GRID_UNLIT)
	flash_layer.draw.connect(_draw_flashes)
	add_child(flash_layer)
	glow_layer = Node2D.new()
	glow_layer.name = "Glow"
	glow_layer.z_index = 26
	glow_layer.material = PixelArt.grid_material(PixelArt.GRID_ADD)
	glow_layer.draw.connect(_draw_glow)
	add_child(glow_layer)
	_floor_ray.collision_mask = 1|2
	_floor_ray.hit_from_inside = false

func reduced() -> bool:
	if not is_instance_valid(game): return false
	var weather: Variant = game.get("weather")
	return is_instance_valid(weather) and weather.get("reduced_effects") == true

func _camera_rig() -> Node:
	if not is_instance_valid(game): return null
	var rig: Variant = game.get("player_camera")
	return rig if is_instance_valid(rig) and rig.has_method("add_trauma") else null

func _is_local_shooter(source: Node, rig: Node) -> bool:
	# A followed worker's own weapon, or the mount that worker is operating.
	for worker: Variant in rig.follow_players():
		if not is_instance_valid(worker): continue
		if worker == source or worker.is_ancestor_of(source): return true
		var seat: Variant = worker.get("mounted_turret")
		if is_instance_valid(seat) and (seat == source or seat.is_ancestor_of(source)): return true
	return false

func track(source: CanvasItem, tip: Vector2, via: Transform2D) -> bool:
	## Called from every muzzle draw while its flash lasts: keeps the flash on
	## the moving weapon mouth. False when this layer holds no flash for it.
	var id := source.get_instance_id()
	for index in MAX_HALOS:
		if _halo_source[index] != id or _halo_state[index].x < 0.0: continue
		_halo_tip[index] = tip
		_halo_via[index] = via
		return true
	return false

func shot(source: Node, at: Vector2, direction: Vector2, strength: float, cold: bool, duration: float = HALO_LIFE, tick: int = 0, facing: float = 1.0) -> void:
	## One visible discharge at a muzzle. Called from the shared muzzle drawing
	## when a replicated flash timer or shot counter starts a new flash.
	if reduced() or not at.is_finite() or not direction.is_finite(): return
	shots_seen += 1
	strength = clampf(strength,.3,2.0)
	_halo_pos[_halo_next] = at
	_halo_dir[_halo_next] = direction
	_halo_state[_halo_next] = Vector2(0,strength)
	_halo_cold[_halo_next] = 1 if cold else 0
	_halo_source[_halo_next] = 0
	if source is CanvasItem:
		# One flash per muzzle: a new discharge replaces the one still showing.
		var id := source.get_instance_id()
		for index in MAX_HALOS:
			if _halo_source[index] == id: _halo_source[index] = 0
		_halo_source[_halo_next] = id
		_halo_world[_halo_next] = source.get_global_transform()
		_halo_via[_halo_next] = Transform2D.IDENTITY
		_halo_tip[_halo_next] = source.get_global_transform().affine_inverse()*at
	_halo_shape[_halo_next] = Vector3(facing,tick,clampf(duration,.03,.4))
	_halo_next = (_halo_next+1)%MAX_HALOS
	if not cold:
		for index in (2 if strength >= 1.1 else 1):
			_wisp_pos[_wisp_next] = at+direction*(3.0+4.0*index)
			_wisp_velocity[_wisp_next] = direction*_random.randf_range(14,34)*strength+Vector2(_random.randf_range(-5,5),-_random.randf_range(9,20))
			_wisp_state[_wisp_next] = Vector2(0,_random.randf_range(.45,.85))
			_wisp_next = (_wisp_next+1)%MAX_WISPS
		_build_haze(at,direction,strength)
		if strength < 1.2:
			_casing_pos[_casing_next] = at-direction*(20.0+8.0*strength)
			_casing_velocity[_casing_next] = -direction*_random.randf_range(18,46)+Vector2(_random.randf_range(-8,8),-_random.randf_range(70,120))
			_casing_state[_casing_next] = Vector2(0,NAN)
			_casing_next = (_casing_next+1)%MAX_CASINGS
	_light_shot(at+direction*6.0,strength,cold)
	var rig := _camera_rig()
	if rig != null:
		if is_instance_valid(source) and _is_local_shooter(source,rig):
			rig.add_kick(-direction,1.9*pow(strength,1.4))
		elif strength >= 1.1:
			rig.add_trauma(.07*strength,at,620.0)
	set_process(true)

func _build_haze(at: Vector2, direction: Vector2, strength: float) -> void:
	# One cloud per muzzle: each round adds to it, a pause lets it thin out.
	var slot := -1
	var weakest := 0
	for index in MAX_HAZE:
		if _haze_build[index] > .02 and _haze_pos[index].distance_squared_to(at) < 40.0*40.0:
			slot = index
			break
		if _haze_build[index] < _haze_build[weakest]: weakest = index
	if slot < 0:
		slot = weakest
		_haze_build[slot] = 0.0
	_haze_pos[slot] = at
	_haze_dir[slot] = direction
	_haze_build[slot] = minf(1.0,_haze_build[slot]+.20*clampf(strength,.5,1.5))

func burst_started(burst: Node2D) -> void:
	## An impact burst appeared (local call or the replicated "impact" event).
	if reduced() or burst.get("reduced") == true: return
	var kind: String = str(burst.get("surface_material"))
	var power: float = clampf(float(burst.get("power")),.25,2.0)
	var rig := _camera_rig()
	if kind == "explosion":
		blasts_seen += 1
		# A blast inside the pulse interval keeps its fireball but swells in:
		# its lamp and its own additive flash both lose the abrupt peak.
		if not _light_blast(burst.global_position+Vector2(0,-8),power): burst.set("flash_scale",.4)
		if rig != null: rig.add_trauma(.46*sqrt(power),burst.global_position,1050.0)
		set_process(true)
	elif power >= 1.5 and kind in ["concrete","metal","glass"]:
		# Collapsing walls, panes and wrecks: weight without a flash.
		if rig != null: rig.add_trauma(.20,burst.global_position,700.0)

func _pulse_allowed() -> bool:
	if clock-_last_pulse < MIN_PULSE_INTERVAL: return false
	_last_pulse = clock
	pulses += 1
	return true

func _light_shot(at: Vector2, strength: float, cold: bool) -> void:
	var slot := -1
	var weakest := 0
	for index in SHOT_LIGHTS:
		var level: float = _shot_heat[index]+_shot_pulse[index]+_shot_glow[index]
		if level > .01 and _shot_pos[index].distance_squared_to(at) < 110.0*110.0:
			slot = index
			break
		if level < _shot_heat[weakest]+_shot_pulse[weakest]+_shot_glow[weakest]: weakest = index
	if slot < 0:
		slot = weakest
		# Taking over a still-warm voice keeps its level: no drop, no new flash.
	# A muzzle that moved finds the floor below it again (next physics step).
	if _shot_pos[slot].distance_squared_to(at) > 64.0: _shot_floor[slot] = NAN
	_shot_pos[slot] = at
	_shot_cold[slot] = 1 if cold else 0
	_shot_size[slot] = maxf(_shot_size[slot]*.6,strength)
	_shot_heat[slot] = minf(1.0,_shot_heat[slot]+.36)
	# The crisp pulse belongs to isolated shots. It shrinks as the steady glow
	# of sustained fire rises and is rate limited for the whole view.
	var room := 1.0-_shot_glow[slot]
	if room > .35 and _pulse_allowed(): _shot_pulse[slot] = room*room

func _light_blast(at: Vector2, power: float) -> bool:
	var slot := 0
	for index in BLAST_LIGHTS:
		if _blast_state[index].x < 0.0:
			slot = index
			break
		if _blast_state[index].x > _blast_state[slot].x: slot = index
	_blast_pos[slot] = at
	_blast_state[slot] = Vector2(0,power)
	_blast_ground[slot] = NAN
	# A blast closely following another abrupt pulse swells in instead of flashing.
	var abrupt := _pulse_allowed()
	_blast_peak[slot] = 1.0 if abrupt else .45
	return abrupt

func _lamp(pool: Array[PointLight2D], index: int, label: String) -> PointLight2D:
	while pool.size() <= index:
		# Gunfire voices are small and never cast shadows; blasts keep surface
		# shadows where the renderer affords them (2D shadow maps are most of a
		# software rasteriser's light cost, see tests/lighting_perf_probe.gd).
		# Both are cut just below their centre, so neither lights the rock or
		# the rooms beneath the surface.
		var lamp := FIRE_LIGHTING.make_lamp("%s%02d"%[label,pool.size()],label == "BlastLight" and FIRE_LIGHTING.WorldLighting.shadows_allowed())
		lamp.texture = FIRE_LIGHTING.surface_texture()
		add_child(lamp)
		pool.append(lamp)
	return pool[index]

func _process(delta: float) -> void:
	clock += delta
	var active := false
	for index in MAX_HALOS:
		if _halo_state[index].x < 0.0: continue
		_halo_state[index].x += delta
		if _halo_state[index].x >= maxf(HALO_LIFE,_halo_shape[index].z):
			_halo_state[index].x = -1.0
			_halo_source[index] = 0
		else: active = true
	for index in MAX_WISPS:
		if _wisp_state[index].x < 0.0: continue
		_wisp_state[index].x += delta
		if _wisp_state[index].x >= _wisp_state[index].y:
			_wisp_state[index].x = -1.0
			continue
		_wisp_velocity[index] *= exp(-delta*2.6)
		_wisp_velocity[index].y -= 16.0*delta
		_wisp_pos[index] += _wisp_velocity[index]*delta
		active = true
	for index in MAX_CASINGS:
		var state := _casing_state[index]
		if state.x < 0.0: continue
		state.x += delta
		if state.x >= .9:
			_casing_state[index].x = -1.0
			continue
		active = true
		if is_nan(state.y):
			# Normally resolved by the next physics step; never wait for long.
			if state.x > .12: state.y = _casing_pos[index].y+60.0
			_casing_state[index] = state
			continue
		var velocity := _casing_velocity[index]
		if velocity != Vector2.ZERO:
			velocity.y += 640.0*delta
			var next := _casing_pos[index]+velocity*delta
			if next.y >= state.y:
				next.y = state.y
				# One short hop, then it lies still until it fades.
				velocity = Vector2(velocity.x*.4,-velocity.y*.32) if velocity.y > 90.0 else Vector2.ZERO
			_casing_pos[index] = next
			_casing_velocity[index] = velocity
		_casing_state[index] = state
	for index in MAX_HAZE:
		if _haze_build[index] <= 0.0: continue
		_haze_build[index] *= exp(-delta/HAZE_DECAY)
		# Below the first visible density the cloud is gone (_draw_haze).
		if _haze_build[index] < .25: _haze_build[index] = 0.0
		else: active = true
	active = _update_flak(delta) or active
	for index in MAX_TRACES:
		if _trace_state[index].x < 0.0: continue
		_trace_state[index].x += delta
		if _trace_state[index].x >= _trace_from[index].distance_to(_trace_to[index])/TRACE_SPEED+.06: _trace_state[index].x = -1.0
		else: active = true
	for index in MAX_SCORCH:
		if _scorch_state[index].x < 0.0: continue
		_scorch_state[index].x += delta
		if _scorch_state[index].x >= SCORCH_LIFE: _scorch_state[index].x = -1.0
		else: active = true
	active = _update_lights(delta) or active
	scorch_layer.queue_redraw()
	ground_glow_layer.queue_redraw()
	smoke_layer.queue_redraw()
	flash_layer.queue_redraw()
	glow_layer.queue_redraw()
	if not active: set_process(false)

func _physics_process(_delta: float) -> void:
	# A new casing finds the floor below it once, inside the physics step.
	for index in MAX_CASINGS:
		var state := _casing_state[index]
		if state.x < 0.0 or not is_nan(state.y): continue
		_floor_ray.from = _casing_pos[index]
		_floor_ray.to = _casing_pos[index]+Vector2(0,150)
		var hit := get_world_2d().direct_space_state.intersect_ray(_floor_ray)
		_casing_state[index].y = float(hit.position.y)-1.0 if not hit.is_empty() else _casing_pos[index].y+150.0
	# A gunfire voice finds the floor its muzzle stands over once (INF: none
	# within reach, e.g. a gun high on a tower).
	for index in SHOT_LIGHTS:
		if not is_nan(_shot_floor[index]): continue
		_floor_ray.from = _shot_pos[index]
		_floor_ray.to = _shot_pos[index]+Vector2(0,MUZZLE_FLOOR_REACH)
		var hit := get_world_2d().direct_space_state.intersect_ray(_floor_ray)
		_shot_floor[index] = float(hit.position.y) if not hit.is_empty() and Vector2(hit.normal).y < -.5 else INF
	# A new blast voice finds the ground surface below it once (INF: open air).
	for index in BLAST_LIGHTS:
		if _blast_state[index].x < 0.0 or not is_nan(_blast_ground[index]): continue
		_floor_ray.from = _blast_pos[index]+Vector2(0,-12)
		_floor_ray.to = _blast_pos[index]+Vector2(0,60)
		var hit := get_world_2d().direct_space_state.intersect_ray(_floor_ray)
		_blast_ground[index] = float(hit.position.y) if not hit.is_empty() and Vector2(hit.normal).y < -.5 else INF

func _update_lights(delta: float) -> bool:
	var active := false
	var quiet := reduced()
	for index in SHOT_LIGHTS:
		_shot_heat[index] *= exp(-delta/.45)
		_shot_glow[index] += (_shot_heat[index]-_shot_glow[index])*(1.0-exp(-delta/.16))
		_shot_pulse[index] *= exp(-delta/.045)
		var level: float = _shot_glow[index]*.62+_shot_pulse[index]*.95
		if quiet or level < .012:
			if index < shot_lamps.size(): shot_lamps[index].enabled = false
			if quiet or _shot_heat[index] < .01:
				_shot_heat[index] = 0.0
				_shot_glow[index] = 0.0
				_shot_pulse[index] = 0.0
				_shot_size[index] = 0.0
			else: active = true
			continue
		active = true
		var lamp := _lamp(shot_lamps,index,"ShotLight")
		# By night a muzzle is the brightest thing around: it reaches further
		# and burns stronger, so the roof and the gunner visibly take each burst.
		var dark := PixelArt.night()
		var radius := (86.0+62.0*_shot_size[index])*(1.0+.45*dark)
		var floor_y := _shot_floor[index]
		if is_finite(floor_y):
			# From the floor up: the shooter, the floor, the mesh and the
			# bunker shell around the muzzle, never the rooms beneath.
			lamp.position = to_local(Vector2(_shot_pos[index].x,floor_y-2.0))
			radius += (floor_y-_shot_pos[index].y)*.8
		else:
			lamp.position = to_local(_shot_pos[index])
		lamp.color = COLD if _shot_cold[index] else WARM
		lamp.texture_scale = radius/64.0
		lamp.energy = level*(.55+.35*_shot_size[index])*(1.2 if is_finite(floor_y) else 1.0)*(1.0+.6*dark)
		lamp.enabled = true
	for index in BLAST_LIGHTS:
		var state := _blast_state[index]
		if state.x < 0.0:
			if index < blast_lamps.size(): blast_lamps[index].enabled = false
			continue
		state.x += delta
		_blast_state[index] = state
		# A short peak (the white-hot core), then the fireball's falling glow.
		var level: float = blast_level(_blast_peak[index],state.x)
		if quiet or state.x > 1.4 or (state.x > .2 and level < .012):
			_blast_state[index].x = -1.0
			if index < blast_lamps.size(): blast_lamps[index].enabled = false
			continue
		active = true
		var lamp := _lamp(blast_lamps,index,"BlastLight")
		lamp.position = to_local(_blast_pos[index])
		lamp.color = BLAST
		lamp.texture_scale = 380.0*sqrt(state.y)/64.0
		lamp.energy = level*1.55*sqrt(state.y)
		lamp.enabled = true
	# Occluders matter only to a shadow-casting blast voice.
	var shadowed := false
	for lamp in blast_lamps:
		if lamp.enabled and lamp.shadow_enabled: shadowed = true
	if shadowed:
		_geometry_clock += delta
		if _geometry_clock >= .5:
			_geometry_clock = 0.0
			var lighting := _fire_lighting()
			if lighting != null: lighting.ensure_occluders()
	return active

## Light level of a blast voice `age` seconds after the blast: a peak of
## `peak` for the white-hot core (a few frames), then the fireball's glow.
static func blast_level(peak: float, age: float) -> float:
	return peak*1.5*exp(-age/.06)+.70*smoothstep(.0,.07,age)*exp(-age/.34)

func _fire_lighting() -> Node:
	# Reached through the scene references, not a group: decoration must not
	# register groups (scenario_props_test keeps props purely cosmetic).
	if not is_instance_valid(game): return null
	var scenery: Variant = game.get("scenery")
	if not is_instance_valid(scenery): return null
	var props: Variant = scenery.get("props_layer")
	if not is_instance_valid(props): return null
	var debris: Variant = props.get("debris")
	if not is_instance_valid(debris): return null
	var lighting: Variant = debris.get("fire_lighting")
	return lighting if is_instance_valid(lighting) and lighting.has_method("ensure_occluders") else null

func _draw_smoke() -> void:
	for index in MAX_WISPS:
		var state := _wisp_state[index]
		if state.x < 0.0: continue
		var left := 1.0-state.x/state.y
		# A thin powder-smoke puff: translucent, it widens and tears into
		# dithered wisps as it drifts off.
		PixelArt.grid_smoke(smoke_layer,_wisp_pos[index],2.5+state.x*12.0,Color(PixelArt.smoke_tone(Color(.78,.76,.71)),.55*(.5+.5*left)),index,clampf(.25+smoothstep(.2,1.0,1.0-left)*.75,0.0,1.0))
	_draw_haze()
	for index in MAX_CASINGS:
		var state := _casing_state[index]
		if state.x < 0.0 or is_nan(state.y): continue
		var at := _casing_pos[index].round()
		var alpha := 1.0-smoothstep(.6,.9,state.x)
		# The tumbling brass alternates between its long and short side.
		var upright := _casing_velocity[index] != Vector2.ZERO and int(state.x*26.0)%2 == 0
		smoke_layer.draw_rect(Rect2(at,Vector2(2,4) if upright else Vector2(4,2)),Color(.80,.60,.26,alpha))
		smoke_layer.draw_rect(Rect2(at,Vector2(2,1) if upright else Vector2(1,2)),Color(1.0,.92,.64,alpha))

func _draw_haze() -> void:
	# Sustained fire fogs its own muzzle: a cloud of powder smoke that thickens
	# with every round (_build_haze), rolls forward off the barrel, climbs and
	# frays, and thins out over a second or two once the gun falls silent.
	for slot in MAX_HAZE:
		var build := _haze_build[slot]
		# Single shots never build a cloud; a few rounds a second for a second
		# or two do.
		var dense := smoothstep(.28,.85,build)
		if dense <= 0.0: continue
		var at := _haze_pos[slot]
		var forward := _haze_dir[slot]
		for puff in HAZE_PUFFS:
			var travel := clock*.62+float(puff)/float(HAZE_PUFFS)+float(slot)*.37
			var cycle := fposmod(travel,1.0)
			var lap := floori(travel)
			var rise := cycle*(18.0+16.0*dense)
			var drift := forward*(5.0+cycle*(8.0+6.0*dense))+Vector2(sin(float(lap*5+puff)*1.7)*cycle*5.0,-rise)
			var radius := (3.0+cycle*(5.0+7.0*dense))*(.55+.45*dense)
			var fade := clampf(.10+smoothstep(.15,1.0,cycle)*.85+(1.0-dense)*.30,0.0,1.0)
			PixelArt.grid_smoke(smoke_layer,at+drift,radius,Color(PixelArt.smoke_tone(Color(.80,.78,.74)),.45+.40*dense),puff+slot*7+lap*3,fade)

func trace(from: Vector2, to: Vector2, width: float = 1.0) -> void:
	## One hostile hitscan round (replicated muzzle flash and tracer end): a
	## red streak with a pale head that flies from the muzzle to the contact,
	## self-lit so a night battle still shows who fires at whom.
	if not from.is_finite() or not to.is_finite() or from.distance_squared_to(to) < 16.0: return
	_trace_from[_trace_next] = from
	_trace_to[_trace_next] = to
	_trace_state[_trace_next] = Vector2(0,clampf(width,1.0,3.0))
	_trace_next = (_trace_next+1)%MAX_TRACES
	set_process(true)

func _draw_traces(to_layer: Transform2D) -> void:
	for index in MAX_TRACES:
		var state := _trace_state[index]
		if state.x < 0.0: continue
		var from := to_layer*_trace_from[index]
		var to := to_layer*_trace_to[index]
		var span := to-from
		var length := span.length()
		var along := span/length
		var head := minf(length,state.x*TRACE_SPEED)
		# Once the round has arrived its tail runs into the contact point.
		var tail := maxf(0.0,head-34.0) if state.x*TRACE_SPEED <= length else minf(length,length-34.0+(state.x-length/TRACE_SPEED)*TRACE_SPEED*.6)
		tail = maxf(tail,0.0)
		if head-tail < 1.0: continue
		var width := state.y
		PixelArt.grid_line(flash_layer,from+along*tail,from+along*head,Color(.12,.04,.03,.55),width+2.0)
		PixelArt.grid_line(flash_layer,from+along*tail,from+along*head,HOSTILE_BODY,width)
		PixelArt.grid_line(flash_layer,from+along*maxf(tail,head-6.0),from+along*head,HOSTILE_HEAD,width+1.0)

func _draw_flashes() -> void:
	# The layered muzzle flashes themselves, unlit and animated every frame
	# from the age of the discharge, on the weapon's current transform.
	var to_layer := flash_layer.get_global_transform().affine_inverse()
	_draw_traces(to_layer)
	var drawn := false
	for index in MAX_HALOS:
		var state := _halo_state[index]
		if state.x < 0.0 or _halo_source[index] == 0 or state.x >= _halo_shape[index].z: continue
		var source := instance_from_id(_halo_source[index]) as CanvasItem
		if is_instance_valid(source) and source.is_inside_tree():
			if not source.is_visible_in_tree(): continue
			_halo_world[index] = source.get_global_transform()
		flash_layer.draw_set_transform_matrix(to_layer*_halo_world[index]*_halo_via[index])
		WeaponEffectArt.draw_flash(flash_layer,_halo_tip[index],1.0-state.x/_halo_shape[index].z,_halo_shape[index].x,state.y,int(_halo_shape[index].y),false,_halo_cold[index] == 1,true)
		drawn = true
	if drawn: flash_layer.draw_set_transform_matrix(Transform2D.IDENTITY)

func _draw_glow() -> void:
	for index in MAX_HALOS:
		var state := _halo_state[index]
		if state.x < 0.0 or state.x >= HALO_LIFE: continue
		var left := 1.0-state.x/HALO_LIFE
		var size := sqrt(state.y)
		var at := _halo_pos[index]+_halo_dir[index]*7.0*size
		var cold := _halo_cold[index] == 1
		var rim: Color = Color("8fb8ff") if cold else Color("f08a3a")
		PixelArt.grid_blob(glow_layer,at,34.0*size*(.72+.28*left),Color(rim,.09*left),index)
		PixelArt.grid_blob(glow_layer,at,22.0*size*(.72+.28*left),Color(rim,.13*left),index+1)
		PixelArt.grid_blob(glow_layer,at-_halo_dir[index]*2.0,12.0*size,Color(Color("d6f4ff") if cold else Color("ffd690"),.34*left*left),index+2)

func scorch(at: Vector2, width: float, variant: int = 0) -> void:
	## A blast's mark on the ground surface below it (impact_burst.gd). A blast
	## on a fresh mark renews it instead of stacking a second one.
	if not at.is_finite() or not is_finite(width) or width < 4.0: return
	width = minf(width,90.0)
	for index in MAX_SCORCH:
		var state := _scorch_state[index]
		if state.x >= 0.0 and absf(_scorch_pos[index].x-at.x) < (state.y+width)*.3 and absf(_scorch_pos[index].y-at.y) < 4.0:
			_scorch_state[index] = Vector3(minf(state.x,1.0),maxf(state.y,width),state.z)
			set_process(true)
			return
	_scorch_pos[_scorch_next] = at.round()
	_scorch_state[_scorch_next] = Vector3(0,width,posmod(variant,64))
	_scorch_next = (_scorch_next+1)%MAX_SCORCH
	set_process(true)

## Soot streaks thrown out along the ground by a blast: x: reach (share of
## the scorch width), y: rows below the surface.
const SCORCH_RAYS := [Vector2(.58,0),Vector2(.44,2),Vector2(.52,1),Vector2(.36,3),Vector2(.48,0),Vector2(.40,2)]

func _draw_scorch() -> void:
	# Burnt ground: a wide soot band, soot streaks thrown out to both sides and
	# a char core hugging the surface (mostly below it), dissolving texel by
	# texel over its last seconds.
	for index in MAX_SCORCH:
		var state := _scorch_state[index]
		if state.x < 0.0: continue
		var fade := smoothstep(SCORCH_LIFE*.35,SCORCH_LIFE,state.x)
		var at := _scorch_pos[index]
		var variant := int(state.z)
		var width := state.y
		PixelArt.grid_oval(scorch_layer,at+Vector2(0,2.0),Vector2(width*.5,4.0),Color(.11,.09,.075,.55),variant,fade)
		for ray in SCORCH_RAYS.size():
			var spoke: Vector2 = SCORCH_RAYS[(ray+variant)%SCORCH_RAYS.size()]
			var side := -1.0 if ray%2 == 0 else 1.0
			var start := at+Vector2(side*width*.14,spoke.y)
			PixelArt.grid_line(scorch_layer,start,start+Vector2(side*width*spoke.x*(.85+.15*float((variant+ray)%3)),0),Color(.07,.055,.045,.62),2.0 if ray < 2 else 1.0,clampf(fade*1.1,0.0,1.0))
		PixelArt.grid_oval(scorch_layer,at+Vector2(0,1.0),Vector2(width*.30,2.5),Color(.05,.04,.035,.80),variant+1,clampf(fade*1.15,0.0,1.0))

const EMBER_LIFE := 2.6

func _draw_ground_glow() -> void:
	# The blast light on the ground: a flat pool in dithered additive bands
	# under the fireball, rising and falling with the blast voice.
	var night := PixelArt.night()
	# Muzzle light on the floor under each gunfire voice (the terrain is unlit
	# art): a flat dithered pool that follows the voice's level, so sustained
	# fire keeps a steady warm patch and single shots blink it once.
	if not reduced():
		for index in SHOT_LIGHTS:
			var floor_y := _shot_floor[index]
			if not is_finite(floor_y): continue
			var level: float = _shot_glow[index]*.62+_shot_pulse[index]*.95
			if level < .02: continue
			var warm: Color = COLD if _shot_cold[index] else Color(1.0,.66,.34)
			var reach := (34.0+26.0*_shot_size[index])*(1.0+.5*night)
			PixelArt.grid_halo(ground_glow_layer,Vector2(_shot_pos[index].x,floor_y+2.0),reach,Color(warm,minf(.8,level*(.34+.56*night))),index*7+3,.16)
	for index in BLAST_LIGHTS:
		var state := _blast_state[index]
		if state.x < 0.0 or not is_finite(_blast_ground[index]): continue
		var level := blast_level(_blast_peak[index],state.x)
		var radius := 165.0*sqrt(state.y)
		PixelArt.grid_halo(ground_glow_layer,Vector2(_blast_pos[index].x,_blast_ground[index]+3.0),radius,Color(1.0,.60,.30,minf(.85,level*(.62+.30*night))),index*5,.12)
	# Embers in a fresh scorch: a few coals that glow and go out one by one,
	# each stepping slowly between two tones (never blinking on and off).
	if reduced(): return
	for index in MAX_SCORCH:
		var state := _scorch_state[index]
		if state.x < 0.0 or state.x >= EMBER_LIFE: continue
		var at := _scorch_pos[index]
		var variant := int(state.z)
		for coal in 7:
			var hash_value := posmod(variant*31+coal*17,23)
			if state.x > EMBER_LIFE*(.35+.65*float(hash_value)/22.0): continue
			var x := (float(hash_value)/22.0-.5)*state.y*.55
			var warm := posmod(floori(state.x*2.5)+coal,3) != 0
			ground_glow_layer.draw_rect(Rect2((at+Vector2(x,1.0+float(coal%2))).floor(),Vector2(2 if coal%3 == 0 else 1,1)),Color(1.0,.62,.26,.85) if warm else Color(.85,.30,.12,.70))

func track_flak(shell: Node2D) -> void:
	## A visible flak shell, registered by its own drawing on host and guests.
	## Its burst point is presentation only, derived from what both sides see:
	## the replicated shell (position, direction, distance travelled, source
	## gun and that gun's replicated tracking target) and the aircraft. It
	## bursts beside an aircraft it passes (near miss), at the range of the
	## aircraft it was aimed at (time fuse), on contact (it vanishes: a hit
	## or the ground), or after a deterministic default range.
	if not is_instance_valid(shell): return
	var id := shell.get_instance_id()
	var free := -1
	for index in MAX_FLAK:
		if _flak_id[index] == id: return
		if free < 0 and _flak_id[index] == 0: free = index
	if free < 0: return
	var direction := Vector2(shell.get("direction"))
	if not direction.is_finite() or direction.length_squared() < .01: return
	direction = direction.normalized()
	_flak_id[free] = id
	_flak_pos[free] = shell.global_position
	_flak_dir[free] = direction
	_flak_fuse[free] = _fuse_range(shell,direction)
	set_process(true)

func _fuse_range(shell: Node2D, direction: Vector2) -> float:
	var travelled := float(shell.get("distance_travelled"))
	var muzzle := shell.global_position-direction*travelled
	var source: Variant = shell.get("source")
	var tracked: Variant = source.get("tracking_target") if is_instance_valid(source) else null
	var nearest := INF
	_refresh_air(true)
	for enemy in _air:
		if not is_instance_valid(enemy) or not enemy is Node2D: continue
		var offset: Vector2 = (enemy as Node2D).global_position-muzzle
		var along := offset.dot(direction)
		var lateral := absf(offset.cross(direction))
		if along < 40.0 or (lateral > 40.0+along*.10 and enemy != tracked): continue
		nearest = minf(nearest,along)
	# The same small spread on every peer: from the replicated firing angle.
	var spread := float(posmod(int(roundf(direction.angle()*977.0)),9))/8.0
	return nearest+14.0+spread*34.0 if nearest < INF else 520.0+spread*260.0

func _refresh_air(now: bool = false) -> void:
	if not now and _air_clock > 0.0: return
	_air_clock = .1
	_air.clear()
	if not is_inside_tree(): return
	for enemy in get_tree().get_nodes_in_group("air_enemies"):
		if enemy.get("game") == game and enemy.get("dead") != true: _air.append(enemy)

func _update_flak(delta: float) -> bool:
	var any := false
	_air_clock -= delta
	for index in MAX_FLAK:
		var id := _flak_id[index]
		if id == 0: continue
		var shell := instance_from_id(id) as Node2D
		if not is_instance_valid(shell) or not shell.is_inside_tree() or shell.is_queued_for_deletion() or shell.get("retired") == true:
			# Gone before its fuse: it struck something (or expired) right here.
			if is_instance_valid(shell) and shell.is_inside_tree(): _flak_pos[index] = shell.global_position
			_flak_id[index] = 0
			_airburst(_flak_pos[index])
			continue
		any = true
		_refresh_air()
		var at := shell.global_position
		var direction := _flak_dir[index]
		var point := Vector2.INF
		if float(shell.get("distance_travelled")) >= _flak_fuse[index]: point = at
		else:
			for enemy in _air:
				if not is_instance_valid(enemy) or not enemy is Node2D: continue
				var offset: Vector2 = (enemy as Node2D).global_position-at
				var along := offset.dot(direction)
				# Only once it has passed the aircraft: a direct hit stops the
				# shell first and bursts on contact instead.
				if along > 0.0 or along < -90.0: continue
				if absf(offset.cross(direction)) < NEAR_MISS+_air_size(enemy):
					point = at+direction*along
					break
		_flak_pos[index] = at
		if point.is_finite():
			_flak_id[index] = 0
			shell.set_meta(FLAK_FUSED,true)
			shell.queue_redraw()
			_airburst(point)
	return any

func _air_size(enemy: Node) -> float:
	var profile: Variant = enemy.get("profile")
	if profile is Dictionary and profile.get("body_size") is Vector2:
		return minf(48.0,maxf(profile.body_size.x,profile.body_size.y)*.35)
	return 16.0

func _airburst(at: Vector2) -> void:
	if not at.is_finite() or not is_instance_valid(game): return
	airbursts += 1
	var burst := ImpactBurst.new()
	burst.position = at
	burst.surface_material = "flak"
	burst.direction = Vector2.UP
	burst.seed_value = 4099+airbursts*37
	burst.reduced = reduced()
	game.add_child(burst)

func diagnostics() -> Dictionary:
	var lit := 0
	for lamp in shot_lamps+blast_lamps:
		if lamp.enabled: lit += 1
	return {"shots":shots_seen,"blasts":blasts_seen,"pulses":pulses,"lit":lit,"lamps":shot_lamps.size()+blast_lamps.size(),"clock":clock}
