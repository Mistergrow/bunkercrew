extends Node2D
## Hostile human anatomy uses the same articulated pixel limbs as the crew.
## Helmets, webbing, scarves and weapons are independent native pixel parts.
const RoleArt := preload("res://scripts/infantry_role_art.gd")
const Atlas := preload("res://scripts/infantry_art_atlas.gd")
const Rhythm := preload("res://scripts/rhythm_presentation.gd")
var soldier: Node2D
var pose: Dictionary = WorkerPoseArt.neutral()
var gun := Transform2D.IDENTITY
var troop_kind := "rifle_guard"
var squad_slot := 0
var corpse := false
var corpse_age := 0.0
var fall_start: Dictionary = {}
var fall_gun := Transform2D.IDENTITY
var reload_phase := 0.0
var treating := false
var cloth_sway := 0.0
var gore_mask:=0
var effects: Node
static var remains_material: ShaderMaterial
static var _soldier_palette: Dictionary = {}
const COLORS := {"olive":Color("59615e"),"cloth":Color("717873"),"light":Color("8a9088"),"shadow":Color("3a4140"),"deep":Color("292e2d"),"trouser":Color("414947"),"trouser_light":Color("68716a"),"leather":Color("493c31"),"leather_light":Color("746352")}

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if corpse:
		add_to_group("infantry_remains")
		if remains_material==null:
			remains_material=ShaderMaterial.new()
			remains_material.shader=preload("res://shaders/ground_infantry_remains.gdshader")
		material=remains_material

func _process(delta: float) -> void:
	if corpse:
		corpse_age+=delta
		if corpse_age>3.0:
			queue_free()
			return
		pose=WorkerPoseArt._blend(fall_start,WorkerPoseArt.sample("downed",1.0),clampf(corpse_age/.65,0,1))
		gun=fall_gun.interpolate_with(Transform2D(.12,Vector2(-7,-12)),smoothstep(0,.65,corpse_age))
		cloth_sway=0.0
		treating=false
		reload_phase=0.0
		modulate.a=1.0-smoothstep(2.2,3.0,corpse_age)
	else:
		if not is_instance_valid(soldier): return
		update_pose()
	queue_redraw()

func update_pose() -> void:
	if not is_instance_valid(soldier): return
	troop_kind=soldier.kind
	squad_slot=soldier.squad_slot
	scale=Vector2(soldier.attack_direction,1)*soldier.visual_scale
	var role := RoleArt.spec(troop_kind)
	var kneel: float=soldier.stance
	var phase: float=soldier.gait+float(squad_slot)*.7
	var stride: float=sin(phase)*float(role.stride) if soldier.moving else 0.0
	var bob: float=absf(sin(phase))*float(role.bob) if soldier.moving else sin(soldier.age*2.1+squad_slot)*.25
	cloth_sway=snappedf(sin(phase*.75+squad_slot)*1.3+(2.0 if soldier.moving else 0.0),1.0)
	treating=troop_kind=="combat_medic" and is_instance_valid(soldier.abilities) and soldier.abilities.repair_flash>0
	pose=WorkerPoseArt.neutral()
	pose.hip=Vector2(-1,float(role.hip_y)+bob).lerp(Vector2(-5,float(role.kneel_y)),kneel)
	pose.shoulder=Vector2(float(role.lean),float(role.hip_y)-17+bob).lerp(Vector2(float(role.kneel_lean),float(role.kneel_y)-17),kneel)
	pose.shoulder+=Vector2(-3,1)*sin(clampf(soldier.hit_flash/.2,0,1)*PI)
	pose.feet=[Vector2(-6+stride,-4-maxf(0,cos(phase))*float(role.lift) if soldier.moving else -4.0),Vector2(6-stride,-4-maxf(0,-cos(phase))*float(role.lift) if soldier.moving else -4.0)]
	pose.feet[0]=Vector2(pose.feet[0]).lerp(Vector2(-float(role.spread)-3,-4),kneel)
	pose.feet[1]=Vector2(pose.feet[1]).lerp(Vector2(float(role.spread),-4),kneel)
	var aim: Vector2=soldier.target_attack_point()
	if is_instance_valid(soldier.abilities) and soldier.abilities.aim_locked: aim=soldier.abilities.aim_point
	elif soldier.muzzle_flash>0: aim=soldier.to_global(soldier.tracer_end)
	var anchor: Vector2=Vector2(pose.shoulder)+Vector2(4-soldier.weapon_recoil*.5,float(role.gun_y))
	var origin: Vector2=soldier.to_global(Vector2(anchor.x*soldier.attack_direction,anchor.y)*soldier.visual_scale)
	var direction: Vector2=aim-origin
	if troop_kind=="grenadier" and is_instance_valid(soldier.abilities): direction=soldier.abilities.launch_velocity(origin,aim)
	var angle:=clampf(Vector2(direction.x*soldier.attack_direction,direction.y).angle(),-.9,.65)
	if soldier.moving: angle=lerpf(angle,float(role.carry),.65)
	if treating: angle=.85
	gun=Transform2D(angle,anchor)
	pose.hands=[gun*Vector2(13,4),gun*Vector2(-1,5)]
	pose.head_tilt=angle*.20
	# Audible kicks touch the upper body only; world-distance gait, gun aim,
	# planted soles, shot timing and treatment gestures retain their own phases.
	var rhythm_frame := Rhythm.frame_for(soldier)
	var rhythm_gain := Rhythm.gain(rhythm_frame)
	if rhythm_gain > 0.0 and soldier.hit_flash <= 0.0 and soldier.muzzle_flash <= 0.0 and not treating:
		var kick_time := float(rhythm_frame.get("last_kick_seconds", -1.0))
		var kick_age := float(rhythm_frame.get("audible_seconds", 0.0)) - kick_time
		var kick := exp(-kick_age / 0.18) * clampf(float(rhythm_frame.get("last_kick_strength", 0.0)), 0.0, 1.0) if kick_time >= 0.0 and kick_age >= 0.0 else 0.0
		var accent := kick * rhythm_gain
		pose.head_tilt -= accent * (0.028 if troop_kind == "heavy_gunner" else 0.040)
		pose.head_shift.y += accent * 0.45
	# Each role has a different service gesture. It stays inside the existing
	# cooldown and never invents a reload delay or consumes gameplay ammunition.
	reload_phase=0.0
	var cooldown: float=soldier.worker_attack_clock if soldier.worker_attack_count>0 and is_instance_valid(soldier.worker_target) else soldier.attack_clock
	var duration: float=float(soldier.profile.cooldown)
	if soldier.worker_attack_count>0 and is_instance_valid(soldier.worker_target): duration=float(soldier.profile.get("worker_interval",SiegeMachine.WORKER_ATTACK_INTERVAL))
	var window:=minf(float(role.reload_time),duration*.72)
	var shots:=maxi(soldier.attack_count,soldier.worker_attack_count)
	var since_shot:=duration-cooldown
	if shots>0 and shots%int(role.magazine)==0 and not soldier.moving and soldier.burst_remaining==0 and soldier.muzzle_flash<=0 and since_shot>.12 and since_shot<window+.12:
		reload_phase=clampf((since_shot-.12)/window,0,1)
		var reach:=sin(reload_phase*PI)
		match troop_kind:
			"marksman": pose.hands[1]=Vector2(pose.hands[1]).lerp(gun*Vector2(3,-5),reach)
			"heavy_gunner": pose.hands[0]=Vector2(pose.hands[0]).lerp(gun*Vector2(7,-8),reach)
			"scout": pose.hands[0]=Vector2(pose.hands[0]).lerp(gun*Vector2(3,12),reach)
			_: pose.hands[0]=Vector2(pose.hands[0]).lerp(Vector2(pose.hip)+Vector2(-7,-1),reach)
	if treating:
		var progress:=clampf(1.0-soldier.abilities.repair_flash,0,1)
		pose.hands[0]=(Vector2(pose.hip)+Vector2(-7,-2)).lerp(Vector2(pose.shoulder)+Vector2(14,7),smoothstep(0,.6,progress))
		var patient: Vector2=soldier.abilities.repair_endpoint-soldier.global_position
		pose.head_tilt=clampf(atan2(patient.y,absf(patient.x))*.18,-.25,.25)
	# The draw routine uses these exact endpoints; keep all reloading/treatment
	# gloves inside the two-segment arm reach used by weather and combat effects.
	for hand in 2:
		var root: Vector2=Vector2(pose.shoulder)+Vector2(-3,1) if hand==0 else Vector2(pose.shoulder)+Vector2(3,2)
		var reach: Vector2=Vector2(pose.hands[hand])-root
		if reach.length()>22.8: pose.hands[hand]=root+reach.normalized()*22.8

func head_transform() -> Transform2D:
	var body:=WorkerPoseArt.torso_transform(pose)
	return Transform2D(body.get_rotation()*.55+float(pose.head_tilt),body*Vector2(1,-14)+Vector2(pose.head_shift))

func _draw() -> void:
	if pose.is_empty(): return
	var limb_mask:=preload("res://scripts/combat_gore.gd").visible_mask(soldier) if not corpse else 0
	if corpse and is_instance_valid(effects) and effects.level==2:
		limb_mask=gore_mask|effects.mask_for_id(str(get_meta("combat_actor_id","")))
	var previous: Dictionary=WorkerPoseArt.colors
	if _soldier_palette.is_empty():
		_soldier_palette=WorkerPoseArt.C.duplicate()
		_soldier_palette.merge(COLORS,true)
	WorkerPoseArt.colors=_soldier_palette
	var hip: Vector2=pose.hip
	var shoulder: Vector2=pose.shoulder
	var body:=WorkerPoseArt.torso_transform(pose)
	Atlas.draw_part(self,body,"rear",troop_kind,0,cloth_sway)
	if not limb_mask&4:
		WorkerPoseArt._leg(self,hip+Vector2(-3,0),pose.feet[0],false)
		RoleArt.limb_wear(self,hip+Vector2(-3,0),pose.feet[0],false,false)
	if not limb_mask&1:
		WorkerPoseArt._arm(self,shoulder+Vector2(-3,1),pose.hands[0],false)
		RoleArt.limb_wear(self,shoulder+Vector2(-3,1),pose.hands[0],true,false)
	if not limb_mask&8:
		WorkerPoseArt._leg(self,hip+Vector2(2,0),pose.feet[1],true)
		RoleArt.limb_wear(self,hip+Vector2(2,0),pose.feet[1],false,true)
	Atlas.draw_part(self,body,"torso",troop_kind)
	var head:=head_transform()
	Atlas.draw_part(self,head,"head",troop_kind,squad_slot,cloth_sway)
	_draw_gun(gun)
	if not limb_mask&2:
		WorkerPoseArt._arm(self,shoulder+Vector2(3,2),pose.hands[1],true)
		RoleArt.limb_wear(self,shoulder+Vector2(3,2),pose.hands[1],true,true)
	RoleArt.front_kit(self,pose,body,gun,troop_kind,treating,reload_phase,limb_mask)
	for wound in [[1,shoulder+Vector2(-3,1)],[2,shoulder+Vector2(3,2)],[4,hip+Vector2(-3,0)],[8,hip+Vector2(2,0)]]:
		if limb_mask&int(wound[0]): draw_rect(Rect2(Vector2(wound[1]).round()-Vector2(2,1),Vector2(5,3)),Color("702c29"))
	WorkerPoseArt.colors=previous

func _draw_gun(tx: Transform2D) -> void:
	var firing: bool=not corpse and is_instance_valid(soldier) and soldier.muzzle_flash>0
	Atlas.draw_part(self,tx,"gun",troop_kind)
	RoleArt.gun_details(self,tx,troop_kind,float(soldier.stance) if not corpse and is_instance_valid(soldier) else 0.0,firing,reload_phase)
