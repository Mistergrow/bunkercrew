extends Node2D
const Quads := preload("res://scripts/canvas_quads.gd")
## Presentation child remains active when replicated gameplay parents are frozen.
## Reads replicated combat evidence; never controls damage, aim or cooldowns.
const Pose := preload("res://scripts/enemy_motion_pose.gd")
const Wreck := preload("res://scripts/enemy_motion_wreck.gd")
const PixelArt = preload("res://scripts/pixel_effect_art.gd")
var machine: Node2D
var airborne := false
var identity := "strider"
var state := "deploy"
var elapsed := 0.0
var pose: Dictionary = {}
var history: Array[String] = []
var _previous_hp := 0.0
var _previous_attacks := 0
var _previous_moving := false
var _previous_speed := 0.0
var _previous_target := 0
var _service_pending := false
var _purge_pending := false
var _scan_pending := false
var _scan_clock := 4.8
var _redraw_clock := 0.0
var _wreck_spawned := false
var automatic := true
var reduced_effects := false
var _entered_view := false
var _blend_from: Dictionary = {}

func _ready() -> void:
	machine = get_parent()
	airborne = machine.get_script().resource_path.get_file() == "air_machine.gd"
	identity = "boss" if machine.get_script().resource_path.get_file() == "boss_machine.gd" else str(machine.kind)
	_previous_hp = machine.hp
	_previous_attacks = machine.attack_count
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3
	pose = Pose.sample(state,0,identity,airborne)
	history.append(state)
	_scan_clock += float(Pose.PROFILES.keys().find(identity)%5)*0.6

func play(action: String, force: bool = false) -> bool:
	if not action in Pose.STATES or action == "destroy": return false
	if not force and state == "impact": return false
	_blend_from = pose.duplicate()
	state = action
	elapsed = 0
	pose = Pose.sample(state,0,identity,airborne)
	history.append(state)
	if history.size()>24: history.pop_front()
	return true

func _process(delta: float) -> void:
	if not is_instance_valid(machine) or machine.dead: return
	# Spawns begin outside the arena. Hold the initial deployment until the
	# hull enters the camera, so heavy walkers do not finish it off screen.
	if automatic and not _entered_view:
		if not get_viewport_rect().has_point(machine.get_global_transform_with_canvas().origin): return
		_entered_view = true
	advance(delta)
	reduced_effects = false
	if is_instance_valid(machine.game):
		var weather = machine.game.get("weather")
		if is_instance_valid(weather): reduced_effects = bool(weather.get("reduced_effects"))
	_redraw_clock += delta
	if _redraw_clock < (1.0/20.0 if reduced_effects else 1.0/60.0): return
	_redraw_clock = 0.0
	machine._pose_parts()
	var retained_weapon := machine.has_method("request_weapon_redraw")
	for child in machine.get_children():
		if retained_weapon and child == machine.weapon_part: continue
		if child is CanvasItem: child.queue_redraw()
	if retained_weapon: machine.request_weapon_redraw()
	machine.queue_redraw()

func advance(delta: float) -> void:
	if automatic: _observe(delta)
	elapsed += maxf(0,delta)
	if not state.is_empty() and elapsed >= Pose.duration(state,identity):
		state = ""
		elapsed = 0
	if state.is_empty() and automatic and machine.windup<=0 and machine.burst_remaining==0 and machine.muzzle_flash<=0:
		if _purge_pending:
			_purge_pending = false
			play("purge")
		elif _scan_pending:
			_scan_pending = false
			play("scan")
		elif _service_pending:
			_service_pending = false
			play("service")
	pose = Pose.sample(state,elapsed/Pose.duration(state,identity),identity,airborne)
	if not _blend_from.is_empty() and elapsed<0.09 and not state.is_empty():
		var blend := Pose.smooth(elapsed/0.09)
		for key in pose:
			pose[key] = lerp(_blend_from.get(key,pose[key]),pose[key],blend)

func _observe(delta: float) -> void:
	var current_hp: float = machine.hp
	if current_hp < _previous_hp-0.001: play("impact",true)
	_previous_hp = current_hp
	var count: int = machine.attack_count
	if count > _previous_attacks:
		_service_pending = true
		if int(floor(float(count)/3.0)) > int(floor(float(_previous_attacks)/3.0)): _purge_pending = true
	_previous_attacks = count
	var target_id: int = machine.target.get_instance_id() if is_instance_valid(machine.target) else 0
	if target_id != 0 and target_id != _previous_target: _scan_pending = true
	_previous_target = target_id
	_scan_clock -= delta
	if _scan_clock<=0:
		_scan_pending = true
		_scan_clock = 5.8+float(Pose.PROFILES.keys().find(identity)%5)*0.7
	var speed: float = machine.flight_velocity.length() if airborne else machine.locomotion_speed
	var moving_now: bool = speed>12.0 if airborne else machine.moving
	if ((_previous_moving and not moving_now) or (_previous_speed>18.0 and speed<8.0)) and state != "impact":
		play("stabilize")
	_previous_moving = moving_now
	_previous_speed = speed

func spawn_wreck() -> void:
	if _wreck_spawned or not is_instance_valid(machine) or not machine.is_inside_tree(): return
	_wreck_spawned = true
	Wreck.spawn(machine,identity,airborne)

func _draw() -> void:
	if not is_instance_valid(machine) or pose.is_empty() or airborne: return
	# Local sockets are transformed with the real hull; details cannot float away
	# from recoil, mirrored spawn sides or the heavier boss presentation.
	var hull: Node2D = machine.body_part
	draw_set_transform(hull.position,hull.rotation,hull.scale)
	var traits: Vector4 = Pose.PROFILES.get(identity,Pose.PROFILES.strider)
	var body_top := -float(machine.profile.body_size.y)*0.5 if airborne else -19.0
	var socket := Vector2(11,body_top+2)
	var mast: float = float(pose.mast)*traits.z
	var sensor := socket+Vector2(0,-5.0-mast)
	draw_line(socket,sensor,Color("19211f"),5)
	draw_line(socket+Vector2(-1,0),sensor+Vector2(-1,0),Color("888b77"),2)
	var look := Vector2.from_angle(PI+float(pose.sensor))
	var lens := sensor+look*5
	draw_line(sensor,lens,Color("303b38"),7)
	draw_line(sensor+Vector2(0,-2),lens+Vector2(0,-2),Color("a19b7c"),1)
	draw_circle(lens,2,Color("ea835b"))
	Quads.rect(self,Rect2(lens-Vector2(1,1),Vector2.ONE),Color("ffe0a5"))
	var hatch: float = pose.hatch
	var vent_origin := Vector2(20,body_top+7)
	for slat in 3:
		var at := vent_origin+Vector2(slat*4,0)
		draw_line(at,at+Vector2(1,-3.0-hatch*8.0),Color("171e1d"),4)
		draw_line(at+Vector2(-1,0),at+Vector2(0,-3.0-hatch*8.0),Color("9a9378"),1)
	var steam: float = pose.steam
	if steam>0.01:
		for puff in (3 if reduced_effects else 5):
			var cycle := fposmod(elapsed*1.7+float(puff)*0.2,1.0)
			var drift := sin(cycle*4.2+float(puff)*1.3)*cycle*2.0
			var point := vent_origin+Vector2(4.0+cycle*13.0+drift,-5.0-cycle*23.0)
			PixelArt.puff(self,point,1.0+cycle*4.0,Color(.58,.61,.55,steam*(1.0-cycle)*.45),puff,not reduced_effects)
	draw_set_transform(Vector2.ZERO)
	if float(pose.slide)>0.0 or state=="service":
		var gun: Node2D = machine.weapon_part
		draw_set_transform(gun.position,gun.rotation,gun.scale)
		var bolt := Vector2(-6.0+float(pose.slide),-7)
		draw_line(Vector2(-9,-7),Vector2(8,-7),Color("171e1d"),5)
		Quads.rect(self,Rect2(bolt-Vector2(3,2),Vector2(7,4)),Color("c0ac7c"))
		draw_line(bolt-Vector2(2,1),bolt+Vector2(3,-1),Color("e0d3a7"),1)
		draw_set_transform(Vector2.ZERO)
