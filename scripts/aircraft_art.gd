extends RefCounted
## Immutable painted hulls with native propulsion, moving bays and weapons.
const Quads := preload("res://scripts/canvas_quads.gd")
const PixelArt := preload("res://scripts/pixel_effect_art.gd")
const Surface := preload("res://scripts/station_surface_art.gd")
const STEEL := Color("737564")
const DARK := Color("182523")
const RUST := Color("ae8359")
## Weapon pods and the bomb bay are hand-pixelled at world size
## (tools/generate_aircraft_pods_v2.py). A pod holds the nearest of 48 baked
## aim keys, drawn upright on whole texels through a counter-transform instead
## of turning a striped sprite rigidly; the node keeps the exact aim for the
## launch point, flash and charge.
const PODS := preload("res://assets/enemies/aircraft_pods_v2.png")
const POD_CELL := 48.0
const POD_KEYS := 48
const POD_ROWS := {"dart":0,"tracer":1,"rocket":2,"arc":3}
const POD_HEAVY_ROW := 4
const POD_BAY_ROW := 5
## Aircraft size the pod and bay texels are authored for (AirEnemyCatalog).
const POD_SCALE := 0.85
const SCORCHED := Color(.78,.72,.66)

static func reduced(machine: Node2D) -> bool:
	if not is_instance_valid(machine.game): return false
	var weather = machine.game.get("weather")
	return is_instance_valid(weather) and bool(weather.get("reduced_effects"))

## A fixed wing's return pass narrows the hull edge-on in these baked widths
## (share of its span; 1 is level flight) instead of squashing the sprite.
const BANK_KEYS: Array[float] = [.35,.6,.85,1.0]

static func bank_key(width: float) -> float:
	var nearest := 1.0
	for key in BANK_KEYS:
		if absf(key-width) < absf(nearest-width): nearest = key
	return nearest

## World size of a hull at `unit` world units per hull unit (the aircraft's
## drawn scale) and a bank key: its bake key, one texel per world unit.
static func hull_size(body_size: Vector2, unit: float, bank: float = 1.0) -> Vector2i:
	return Vector2i(roundi(body_size.x*unit*bank),roundi(body_size.y*unit))

## The drawn size of this machine's hull. A machine may carry `hull_unit`
## (distant flybys are drawn unscaled) and `hull_bank`; else its profile scale.
static func hull_texels(machine: Node2D) -> Vector2i:
	var unit: float = float(machine.get("hull_unit")) if machine.get("hull_unit") != null else float(machine.profile.get("scale",1.0))
	var bank: float = float(machine.get("hull_bank")) if machine.get("hull_bank") != null else 1.0
	return hull_size(machine.profile.body_size,unit,bank)

static func local_socket(machine: Node2D, source: Vector2) -> Vector2:
	var region: Rect2 = AircraftArtCatalog.REGIONS[machine.kind]
	return (source-region.get_center())*float(machine.profile.body_size.x)/region.size.x

static func body(machine: Node2D, node: Node2D) -> void:
	var size: Vector2 = machine.profile.body_size
	var clock: float = machine.visual_age()
	if machine.hp<machine.max_hp*.45 and not reduced(machine):
		_damage_trail(machine,node,size,clock)
	if machine.chassis_atlas != null:
		var region: Rect2 = AircraftArtCatalog.REGIONS[machine.kind]
		# The hull's bake at its drawn size and attitude, upright on world
		# texels; the plate itself only for a size that was never baked.
		if not WorldTexels.draw_stance(node,AircraftArtCatalog.TEXTURE_PATH,region,Rect2(-size*0.5,size),hull_texels(machine)):
			node.draw_texture_rect_region(WorldTexels.fallback_source(AircraftArtCatalog.TEXTURE_PATH),Rect2(-size*0.5,size),region)
	else:
		# Missing optional art remains a readable aircraft, never a ground chassis.
		node.draw_colored_polygon(PackedVector2Array([Vector2(-size.x*.5,0),Vector2(-size.x*.28,-size.y*.27),Vector2(size.x*.4,-size.y*.27),Vector2(size.x*.5,-size.y*.5),Vector2(size.x*.48,size.y*.24),Vector2(-size.x*.26,size.y*.28)]),STEEL)
	# Lamp, bay, coils and marks sit on the hull's world texels: drawn in its
	# upright frame at their (turned) anchors, in whole texels.
	node.draw_set_transform_matrix(WorldTexels.upright(node))
	var lamp := WorldTexels.upright_point(node,Vector2(-size.x*.30,-size.y*.05)).round()
	Quads.rect(node,Rect2(lamp,Vector2(2,1)),Color("f6bd76") if fposmod(clock+machine.formation_phase,1.6)<.18 else Color("7d4e34"))
	if machine.kind in ["bomber","dive_bomber"]:
		var opening := clampf(machine.windup/float(machine.profile.windup),0,1) if machine.windup>0 else (1.0 if machine.burst_remaining>0 else 0.0)
		var bay := WorldTexels.upright_point(node,Vector2(-size.x*.08,size.y*.34)).round()
		# Recessed bay with ribs and riveted doors, authored on world texels.
		node.draw_texture_rect_region(PODS,Rect2(bay-Vector2.ONE*POD_CELL*.5,Vector2.ONE*POD_CELL),Rect2(0.0,POD_BAY_ROW*POD_CELL,POD_CELL,POD_CELL))
		var grid := PixelArt.supports_grid(node)
		for side in [-1.0,1.0]:
			var hinge := bay+Vector2(side*9,0)
			var leaf := hinge+Vector2(-side*8*(1-opening),opening*7)
			if grid: PixelArt.grid_line(node,hinge,leaf,STEEL,2.0)
			else: node.draw_line(hinge,leaf,STEEL,2)
		if opening>.15:
			Quads.rect(node,Rect2(bay+Vector2(-2,-1),Vector2(4,6)),RUST)
	if machine.kind=="pulse_fighter":
		var charge := clampf(machine.windup/float(machine.profile.windup),0,1)
		for coil in 4:
			Quads.rect(node,Rect2(WorldTexels.upright_point(node,Vector2(size.x*.22+coil*3,-4)).round(),Vector2(2,5)),RUST.lightened(charge*.35) if charge>.1 else RUST.darkened(.45))
	if machine.elite:
		for stripe in 3: Quads.rect(node,Rect2(WorldTexels.upright_point(node,Vector2(stripe*4-6,-size.y*.20)).round(),Vector2(2,4)),Art.AMBER)
	node.draw_set_transform_matrix(Transform2D.IDENTITY)

## A damaged aircraft trails smoke. The puffs are laid out in world axes
## behind its flight (whatever the hull's turn or mirror), spaced so they keep
## pace with the air they were left in; they swell, rise a little and tear
## into wisps. Worse damage makes the trail longer, denser and darker, with a
## warm glow where it leaves the engine. Drawn under the hull.
const TRAIL_PUFFS := 8

static func _damage_trail(machine: Node2D, node: Node2D, size: Vector2, clock: float) -> void:
	var damage := 1.0-clampf(float(machine.hp)/maxf(1.0,float(machine.max_hp)*.45),0.0,1.0)
	var velocity: Vector2 = machine.flight_velocity
	var speed := velocity.length()
	var back := -velocity/speed if speed > 6.0 else Vector2(-float(machine.attack_direction),0.0)
	var socket := node.to_global(Vector2(size.x*.23,-size.y*.08))
	node.draw_set_transform_matrix(node.get_global_transform().affine_inverse()*Transform2D(0.0,socket))
	var reach := clampf(speed*.8,34.0,120.0)*(.75+.5*damage)
	for index in TRAIL_PUFFS:
		var cycle := clock*1.1+float(index)/float(TRAIL_PUFFS)
		var age := fposmod(cycle,1.0)
		# Behind the flight and rising: a hovering machine sends a column up.
		var at := back*age*reach+Vector2(sin(cycle*2.3)*age*4.0,-age*(12.0+14.0*(1.0-clampf(speed/60.0,0.0,1.0))))
		var tone := Color(.42,.41,.39,.80).lerp(Color(.23,.22,.21,.92),damage)
		# The puff holds together for most of its way, then tears apart.
		PixelArt.smoke_puff(node,at,3.0+age*(7.0+damage*7.0),tone,index+floori(cycle)*3,pow(age,1.7),clampf(1.0-age*4.0,0.0,1.0)*damage*.8)
	node.draw_set_transform_matrix(Transform2D.IDENTITY)

## Rotors and propellers as a pixel artist draws them: a stepped blur disc in
## whole world texels (denser where the blade tips dwell at the edges of the
## foreshortened disc) and the blade itself as a few smear keys that cycle at
## SMEAR_FPS, never a freely turned rectangle. Reduced effects keep the
## disc and one still blade. Grid shapes (pixel_effect_art.gd) rasterise on
## the world texel grid however the hull is pitched or mirrored.
const SMEAR_FPS := 20.0
const BLUR := Color(.62,.62,.52)
const BLADE_LIGHT := Color("8a8b73")
## Projected blade length (share of the span) and depth offset per smear key.
const SMEAR_KEYS := [Vector2(1.0,0.0),Vector2(.62,1.0),Vector2(.22,0.0),Vector2(.62,-1.0)]

static func _smear_key(clock: float, index: int, quiet: bool) -> int:
	return 0 if quiet else posmod(floori(clock*SMEAR_FPS)+index*2,SMEAR_KEYS.size())

static func _rotor(node: Node2D, point: Vector2, axis: Vector2, span: float, key: int, quiet: bool) -> void:
	var down := Vector2(-axis.y,axis.x)
	# Blur disc: a translucent band across the whole sweep, darker towards the
	# rims where the foreshortened blades dwell.
	PixelArt.grid_oval(node,point,Vector2(span,1.5),Color(DARK,.24 if quiet else .30),3,.15)
	for side in [-1.0,1.0]:
		PixelArt.grid_line(node,point+axis*side*span*.62,point+axis*side*(span-.5),Color(DARK,.30),2.0)
	var shape: Vector2 = SMEAR_KEYS[key]
	var half := maxf(1.5,span*shape.x)
	var at := (point+down*(shape.y-.5)).floor()
	# The blade: a lit upper row over a dark lower row, whole texels.
	PixelArt.grid_line(node,at-axis*half,at+axis*half,BLADE_LIGHT)
	PixelArt.grid_line(node,at-axis*half+down,at+axis*half+down,DARK)
	# Mast and hub cap.
	PixelArt.grid_line(node,point+down,point+down*3.0,RUST,2.0)

static func propulsion(machine: Node2D, node: Node2D) -> void:
	var size: Vector2 = machine.profile.body_size
	var clock: float = machine.visual_age()
	var family: String = machine.profile.propulsion
	var quiet := reduced(machine)
	var points := AircraftArtCatalog.engine_points(machine.kind,size.x)
	if not PixelArt.supports_grid(node):
		# Without the actor material (bare previews) only the hubs remain.
		for point: Vector2 in points: Quads.rect(node,Rect2(point.round()-Vector2.ONE,Vector2(2,2)),RUST)
		return
	for index in points.size():
		var point: Vector2 = points[index]
		var key := _smear_key(clock,index,quiet)
		if family in ["rotor","tiltrotor","vtol"]:
			var span := clampf(size.x*(.30 if machine.kind=="gunship" else .23),11,29)
			if machine.kind=="sky_fortress": span=15
			var tilt := clampf(-machine.flight_velocity.x*.0014,-.15,.15) if family=="tiltrotor" else clampf(-machine.flight_velocity.x*.00045,-.06,.06)
			# The disc tilts with forward flight in authored steps, not per frame.
			tilt = snappedf(tilt,.05)
			_rotor(node,point,Vector2(cos(tilt),sin(tilt)),span,key,quiet)
		elif family in ["propeller","airship"]:
			var span := clampf(size.y*.44,9,21) if family=="propeller" else 9.0
			# A propeller disc faces along the flight: seen edge-on as an upright oval.
			PixelArt.grid_oval(node,point,Vector2(1.6,span),Color(BLUR,.18 if quiet else .24),5,.30)
			for side in [-1.0,1.0]:
				PixelArt.grid_line(node,point+Vector2(0,side*(span-3.0)),point+Vector2(0,side*(span-.5)),Color(DARK,.50))
			var shape: Vector2 = SMEAR_KEYS[key]
			var half := maxf(1.5,span*shape.x)
			var at := point+Vector2(shape.y,0)
			PixelArt.grid_line(node,at-Vector2(0,half),at+Vector2(0,half),DARK,2.0)
			PixelArt.grid_line(node,at-Vector2(-1,half),at+Vector2(1,half-2.0),BLADE_LIGHT)
			PixelArt.grid_blob(node,point,2.0,RUST)
		else:
			var thrust := clampf(machine.flight_velocity.length()/float(machine.profile.speed),.18,1.0)
			# Jet flame in stepped keys of the same smear clock.
			var length := roundf(5+thrust*8+(float(key%2)*2.0-1.0)*1.5)
			PixelArt.grid_petal(node,point,point+Vector2(length,0),4.0,Color("d78e50"))
			PixelArt.grid_line(node,point,point+Vector2(roundf(length*.60),0),Color("f5d7a0"))
	if machine.kind=="gunship":
		# The tail rotor turns in the view plane: eight stepped attitudes.
		var tail := local_socket(machine,Vector2(721,211))
		PixelArt.grid_blob(node,tail,7.0,Color(BLUR,.16 if quiet else .22),2,.35)
		var blade := Vector2.from_angle(0.0 if quiet else float(floori(clock*SMEAR_FPS))*TAU/8.0+.39)*7.0
		PixelArt.grid_line(node,tail-blade,tail+blade,DARK,2.0)
		PixelArt.grid_line(node,tail-Vector2.ONE,tail,BLADE_LIGHT)

static func weapon(machine: Node2D, node: Node2D) -> void:
	var flavor: String = machine.profile.flavor
	var recoil: float = machine.weapon_recoil
	if flavor=="bomb":
		# The bay itself is part of the hull (body); this node holds the bomb.
		if machine.windup>0 or machine.burst_remaining>0:
			node.draw_texture_rect(Surface._texture(Vector2i(8,12),STEEL,3),Rect2(-3,1,6,9),false)
			Quads.rect(node,Rect2(-3,7,6,2),RUST)
	else:
		_pod(machine,node,recoil)
	if machine.windup>0 and PixelArt.supports_grid(node):
		_charge(machine,node,flavor,clampf(machine.windup/float(machine.profile.windup),0,1))
	if flavor!="bomb":
		var heavy: bool=machine.kind in ["sky_fortress","heavy_zeppelin"]
		# The recoil-adjusted mouth is also AirMachine.muzzle_global()'s actual
		# launch point. Keep bomb release unflashed and the arc family cold.
		WeaponEffectArt.muzzle(node,Vector2(-24+recoil,0),machine.muzzle_flash,.22 if heavy else .10,-1,.72 if heavy else .50,machine.attack_count,reduced(machine),flavor=="arc")

static func pod_row(machine: Node2D) -> int:
	if machine.kind in ["sky_fortress","heavy_zeppelin"]: return POD_HEAVY_ROW
	return int(POD_ROWS.get(str(machine.profile.flavor),1))

## The pod in its nearest aim key: cancel the node's turn and size so the
## baked texels sit upright (mirror kept), pivot on the recoiled mount.
static func _pod(machine: Node2D, node: Node2D, recoil: float) -> void:
	var mirror := -1.0 if node.scale.x < 0.0 else 1.0
	var ratio := absf(node.scale.y)/POD_SCALE
	var key := posmod(roundi(node.rotation*mirror/TAU*float(POD_KEYS)),POD_KEYS)
	var turned := Transform2D(node.rotation,node.scale,0.0,Vector2.ZERO)
	var upright := turned.affine_inverse()*Transform2D(Vector2(mirror*ratio,0.0),Vector2(0.0,ratio),Vector2.ZERO)
	upright.origin = Vector2(recoil,0.0)
	# The pod's texels share the world grid with the hull it hangs on.
	node.draw_set_transform_matrix(WorldTexels.on_grid(node,upright))
	# A badly damaged aircraft's pod is scorched (tint only, same texels).
	var tint := SCORCHED if float(machine.hp) < float(machine.max_hp)*.45 else Color.WHITE
	node.draw_texture_rect_region(PODS,Rect2(-Vector2.ONE*POD_CELL*.5,Vector2.ONE*POD_CELL),Rect2(float(key)*POD_CELL,float(pod_row(machine))*POD_CELL,POD_CELL,POD_CELL),tint)
	node.draw_set_transform_matrix(Transform2D.IDENTITY)

## The attack tell, in the world and on the texel grid: the weapon heats up
## along its barrel from the breech to the mouth (dull red, orange, a white-hot
## mouth just before it fires; the arc family charges cold blue), and a faint
## designator beam runs from the mouth to the locked aim, with a few brighter
## pulses travelling down it and a spot that tightens on the target. Bombers
## glow in the open bay instead of a beam. Presentation only: it follows the
## replicated windup and locked aim, the attack timing is untouched.
const CHARGE_WARM := [Color("6e2a1c"), Color("b8461f"), Color("f08a3a"), Color("ffd27a"), Color("fff6dc")]
const CHARGE_COLD := [Color("1d4a6e"), Color("2f86c0"), Color("6fd0f4"), Color("c4f4ff"), Color("f2fffd")]

static func _charge(machine: Node2D, node: Node2D, flavor: String, charge: float) -> void:
	var ramp: Array = CHARGE_COLD if flavor=="arc" else CHARGE_WARM
	var step := clampi(int(charge*4.0),0,4)
	var quiet := reduced(machine)
	if flavor=="bomb":
		# The open bay glows from inside as the release nears.
		PixelArt.grid_oval(node,Vector2(0,6),Vector2(2.0+charge*2.0,1.0+charge),Color(ramp[step],.85),2)
		return
	var recoil: float = machine.weapon_recoil
	# Barrel heat: segments light from the breech forward, the newest hottest.
	var lit := 1+int(charge*3.99)
	for segment in lit:
		var from := Vector2(-4.0-float(segment)*5.0+recoil,0.0)
		var tone: Color = ramp[clampi(step-(lit-1-segment),0,4)]
		PixelArt.grid_line(node,from,from+Vector2(-4.0,0.0),Color(tone,.95),2.0)
	var mouth := Vector2(-24.0+recoil,0.0)
	PixelArt.grid_blob(node,mouth,1.5+charge*2.0,Color(ramp[maxi(step-1,0)],1.0),machine.attack_count)
	PixelArt.grid_blob(node,mouth,.8+charge*1.2,Color(ramp[step],1.0),machine.attack_count+1)
	var aim: Vector2 = machine.locked_aim
	if quiet or not aim.is_finite() or aim==Vector2.ZERO: return
	# The designator: drawn in world axes from the mouth to the aim.
	var start := node.to_global(mouth)
	node.draw_set_transform_matrix(node.get_global_transform().affine_inverse())
	var span := aim-start
	var length := span.length()
	if length > 8.0:
		var along := span/length
		var beam := Color(ramp[2],.16+.22*charge)
		PixelArt.grid_line(node,start+along*4.0,aim-along*3.0,beam)
		# Pulses run down the beam faster as the charge builds.
		var clock: float = machine.visual_age()
		for pulse in 3:
			var travel := fposmod(clock*(1.2+charge*2.4)+float(pulse)/3.0,1.0)
			var at := start+along*(4.0+travel*(length-10.0))
			PixelArt.grid_line(node,at,at+along*3.0,Color(ramp[3],.55+.35*charge))
	# The spot on the target: wide and dim first, tight and bright at the end.
	PixelArt.grid_blob(node,aim,lerpf(3.5,1.5,charge),Color(ramp[2+mini(step,2)],.45+.5*charge),machine.attack_count+3,lerpf(.45,0.0,charge))
	node.draw_set_transform_matrix(Transform2D.IDENTITY)
