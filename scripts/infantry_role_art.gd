extends RefCounted
## Six field kits share native worker anatomy and the existing painted cloth
## and metal surfaces. Fixed material tiles keep animated equipment caches bounded.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Metal := preload("res://scripts/machine_surface_details.gd")
const INK := Color("202926")
const CLOTH := preload("res://assets/workers/branko_torso.png")
const BASE := {"torso":"mara", "stride":9.0, "lift":6.0, "bob":1.4, "lean":2.0, "spread":10.0,
	"hip_y":-25.0, "kneel_y":-15.0, "kneel_lean":1.0, "carry":0.23, "gun_y":7.0,
	"muzzle":Vector2(32,0), "standing_height":65.0, "kneeling_height":55.0,
	"reload_time":0.9, "magazine":2, "tint":Color(.70,.77,.70), "crown":-13.0}
const ROLES := {
	"rifle_guard": {},
	"grenadier": {"torso":"branko", "stride":8.0, "lift":4.5, "spread":12.0, "reload_time":1.4, "magazine":1, "tint":Color(.71,.74,.66)},
	"scout": {"torso":"ivo", "stride":11.5, "lift":8.0, "bob":1.8, "lean":5.0, "spread":8.0, "kneel_y":-18.0, "kneel_lean":4.0, "carry":0.36,
		"muzzle":Vector2(27,0), "standing_height":61.0, "kneeling_height":53.0, "reload_time":0.55, "magazine":3, "tint":Color(.74,.77,.65), "crown":-8.0},
	"heavy_gunner": {"torso":"branko", "stride":6.5, "lift":3.5, "bob":0.7, "lean":4.0, "spread":13.0, "hip_y":-24.0, "kneel_y":-18.0, "kneel_lean":4.0, "carry":0.05,
		"muzzle":Vector2(44,0), "standing_height":68.0, "kneeling_height":59.0, "reload_time":1.5, "magazine":4, "tint":Color(.66,.70,.64), "crown":-14.0},
	"marksman": {"torso":"mara", "stride":7.0, "lift":3.0, "bob":0.55, "lean":1.0, "spread":12.0, "kneel_y":-12.0, "kneel_lean":0.0, "carry":0.13, "gun_y":-1.0,
		"muzzle":Vector2(49,0), "standing_height":65.0, "kneeling_height":52.0, "reload_time":0.65, "magazine":1, "tint":Color(.66,.72,.64), "crown":-13.0},
	"combat_medic": {"torso":"ivo", "stride":8.5, "lift":5.0, "bob":1.0, "lean":2.0, "spread":9.0, "carry":0.40,
		"muzzle":Vector2(25,0), "standing_height":65.0, "kneeling_height":55.0, "reload_time":0.8, "magazine":3, "tint":Color(.77,.80,.72)},
}
static var _specs: Dictionary = {}

static func spec(kind: String) -> Dictionary:
	if not ROLES.has(kind): kind="rifle_guard"
	if not _specs.has(kind):
		var data := BASE.duplicate()
		data.merge(ROLES.get(kind, {}), true)
		_specs[kind] = data
	return _specs[kind]

static func _mapped(tx: Transform2D, points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append((tx * point).round())
	return result

static func fabric(canvas: Node2D, tx: Transform2D, points: Array, tint: Color) -> void:
	var bounds := Rect2(points[0], Vector2.ONE)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	var uv := PackedVector2Array()
	for point: Vector2 in points:
		uv.append((Vector2(41,51) + (point-bounds.position) / bounds.size * Vector2(12,11)) / 112.0)
	canvas.draw_polygon(_mapped(tx,points), PackedColorArray([tint]), uv, CLOTH)

static func _cloth_box(canvas: Node2D, tx: Transform2D, at: Vector2, size: Vector2, tint: Color) -> void:
	PoseArt._patch(canvas,tx,at-Vector2.ONE,size+Vector2(2,2),INK)
	fabric(canvas,tx,[at,at+Vector2(size.x,0),at+size,at+Vector2(0,size.y)],tint)
	PoseArt._patch(canvas,tx,at+Vector2(1,1),Vector2(size.x-2,1),Color("909584"))

static func metal(canvas: Node2D, tx: Transform2D, points: Array, finish: String="dark", variation: int=0) -> void:
	var mapped := _mapped(tx,points)
	Metal.polygon(canvas,mapped,finish,variation)
	var rim := mapped.duplicate()
	rim.append(mapped[0])
	canvas.draw_polyline(rim,INK,1,false)

static func rear_kit(canvas: Node2D, body: Transform2D, kind: String, sway: float) -> void:
	match kind:
		"marksman":
			fabric(canvas,body,[Vector2(-10,-4),Vector2(0,-5),Vector2(1,15),Vector2(-8+sway,29),Vector2(-20+sway,24),Vector2(-15,9)],Color(.53,.63,.51))
			for fold in [-12,-7]:
				PoseArt._line(canvas,body*Vector2(fold,4),body*Vector2(fold-3+sway,23),Color("38433b"))
			PoseArt._line(canvas,body*Vector2(-19+sway,24),body*Vector2(-8+sway,29),Color("77806b"))
		"heavy_gunner":
			_cloth_box(canvas,body,Vector2(-21,-1),Vector2(12,23),Color(.61,.66,.55))
			for y in [3,12]:
				PoseArt._patch(canvas,body,Vector2(-22,y),Vector2(14,3),Color("373b31"))
				for x in range(-20,-9,3):
					PoseArt._patch(canvas,body,Vector2(x,y),Vector2(1,3),Color("aa9161"))
		"combat_medic":
			_cloth_box(canvas,body,Vector2(-22,-2),Vector2(12,24),Color(.75,.78,.66))
			_cloth_box(canvas,body,Vector2(-26,8),Vector2(6,12),Color(.58,.66,.57))
			PoseArt._patch(canvas,body,Vector2(-22,6),Vector2(12,3),Color("cec8a8"))
			PoseArt._patch(canvas,body,Vector2(-19,14),Vector2(6,2),Color("63796c"))
			PoseArt._patch(canvas,body,Vector2(-20,-4),Vector2(8,2),Color("d2cdb4"))
		"grenadier":
			_cloth_box(canvas,body,Vector2(-19,0),Vector2(9,22),Color(.65,.69,.57))
			for y in [3,12]:
				PoseArt._patch(canvas,body,Vector2(-19,y),Vector2(8,5),Color("747754"))
				PoseArt._patch(canvas,body,Vector2(-17,y),Vector2(2,4),Color("a89b67"))
		"scout":
			_cloth_box(canvas,body,Vector2(-16,12),Vector2(7,8),Color(.65,.71,.58))

static func torso_kit(canvas: Node2D, body: Transform2D, kind: String) -> void:
	# Common weathered straps tie the field kits into one army without hiding
	# the different packs, plating, cape and chest ammunition underneath.
	fabric(canvas,body,[Vector2(-8,-3),Vector2(-4,-4),Vector2(8,18),Vector2(4,19)],Color(.39,.45,.37))
	if kind == "heavy_gunner":
		metal(canvas,body,[Vector2(-9,-1),Vector2(5,-2),Vector2(9,5),Vector2(7,14),Vector2(-8,15)],"dark",2)
		metal(canvas,body,[Vector2(-11,-5),Vector2(-3,-5),Vector2(-2,1),Vector2(-11,2)],"steel",4)
		metal(canvas,body,[Vector2(3,-4),Vector2(10,-2),Vector2(11,4),Vector2(5,5)],"dark",1)
		for y in [5,10]:
			PoseArt._patch(canvas,body,Vector2(-6,y),Vector2(10,1),Color("a4a48b"))
	elif kind == "grenadier":
		for x in [-7,-2,3]:
			_cloth_box(canvas,body,Vector2(x,5),Vector2(3,11),Color(.75,.72,.50))
			PoseArt._patch(canvas,body,Vector2(x,6),Vector2(3,2),Color("b4a779"))
	elif kind == "scout":
		_cloth_box(canvas,body,Vector2(1,10),Vector2(6,6),Color(.60,.65,.53))
		PoseArt._patch(canvas,body,Vector2(-6,13),Vector2(3,7),Color("aaa38a"))
	elif kind == "marksman":
		fabric(canvas,body,[Vector2(-9,-3),Vector2(5,-3),Vector2(9,7),Vector2(-4,10),Vector2(-12,5)],Color(.58,.65,.55))
		for y in [13,17]:
			for x in [-5,0,5]:
				PoseArt._patch(canvas,body,Vector2(x,y),Vector2(2,3),Color("a49365"))
	else:
		for x in [-7,2]:
			_cloth_box(canvas,body,Vector2(x,11),Vector2(6,7),Color(.59,.67,.58))
		if kind == "combat_medic":
			PoseArt._patch(canvas,body,Vector2(-5,2),Vector2(10,3),Color("d0c9ae"))
			PoseArt._patch(canvas,body,Vector2(-3,3),Vector2(6,1),Color("647c6c"))

static func face(canvas: Node2D, head: Transform2D, kind: String, squad_slot: int, sway: float) -> void:
	PoseArt._panel(canvas,head,[Vector2(-7,-7),Vector2(5,-8),Vector2(8,-3),Vector2(8,5),Vector2(4,10),Vector2(-4,9),Vector2(-7,4)],Color("9a8466"),true)
	PoseArt._patch(canvas,head,Vector2(4,1),Vector2(5,3),Color("b79d78"))
	PoseArt._patch(canvas,head,Vector2(4,2),Vector2(3,2),Color("29322d"))
	PoseArt._patch(canvas,head,Vector2(-5,1),Vector2(3,5),Color("75674e"))
	PoseArt._patch(canvas,head,Vector2(5,6),Vector2(3,1),Color("61563f"))
	PoseArt._patch(canvas,head,Vector2(0,6),Vector2(2,2),Color("887456"))
	if kind == "scout":
		fabric(canvas,head,[Vector2(-9,-2),Vector2(-8,-7),Vector2(3,-8),Vector2(8,-5),Vector2(13,-3),Vector2(12,-1)],Color(.53,.62,.49))
		PoseArt._patch(canvas,head,Vector2(-8,-1),Vector2(18,2),Color("333c33"))
		PoseArt._patch(canvas,head,Vector2(0,-2),Vector2(11,5),INK)
		for x in [1,7]:
			PoseArt._patch(canvas,head,Vector2(x,-1),Vector2(3,2),Color("9cac9f"))
			PoseArt._patch(canvas,head,Vector2(x,-1),Vector2(2,1),Color("d2c6a7"))
		fabric(canvas,head,[Vector2(-8,7),Vector2(6,7),Vector2(4,12),Vector2(-8,14),Vector2(-18+sway,11),Vector2(-12+sway,8)],Color(.78,.65,.43))
	elif kind == "marksman":
		fabric(canvas,head,[Vector2(-11,8),Vector2(-12,-5),Vector2(-7,-12),Vector2(2,-13),Vector2(9,-7),Vector2(8,-3),Vector2(2,-6),Vector2(-3,-3),Vector2(-3,8),Vector2(-7,14)],Color(.56,.64,.52))
		PoseArt._line(canvas,head*Vector2(-7,-9),head*Vector2(-8,6),Color("8a907a"))
		fabric(canvas,head,[Vector2(-5,6),Vector2(7,5),Vector2(6,11),Vector2(-7,12)],Color(.54,.62,.51))
	else:
		var crown := -14.0 if kind == "heavy_gunner" else -13.0
		metal(canvas,head,[Vector2(-9,0),Vector2(-10,-7),Vector2(-6,crown+1),Vector2(4,crown),Vector2(9,-9),Vector2(10,-4),Vector2(12,-2),Vector2(11,0)],"dark",squad_slot+1)
		PoseArt._patch(canvas,head,Vector2(-9,-1),Vector2(19,2),Color("323c34"))
		PoseArt._patch(canvas,head,Vector2(-6,-10),Vector2(8,1),Color("979b86"))
		PoseArt._patch(canvas,head,Vector2(-8,-5),Vector2(3,5),Color("514838"))
		if kind == "heavy_gunner":
			metal(canvas,head,[Vector2(-10,-4),Vector2(-6,-4),Vector2(-5,6),Vector2(-9,8)],"dark",5)
			PoseArt._patch(canvas,head,Vector2(-3,1),Vector2(12,2),Color("4c5547"))
		elif kind == "combat_medic":
			PoseArt._patch(canvas,head,Vector2(-7,-5),Vector2(15,2),Color("c5c0a6"))
		else:
			fabric(canvas,head,[Vector2(-7,7),Vector2(5,7),Vector2(6,11),Vector2(-5,13),Vector2(-9,17)],Color(.76,.59,.46))

static func limb_wear(canvas: Node2D, a: Vector2, b: Vector2, arm: bool, front: bool) -> void:
	var joint := PoseArt._joint(a,b,11 if arm else 12,12,1 if arm else -1)
	var light := Color("8a917d") if front else Color("5e685c")
	for segment in [[a,joint],[joint,b]]:
		var midpoint: Vector2 = Vector2(segment[0]).lerp(segment[1],.55)
		PoseArt._box(canvas,midpoint+Vector2(-1,-1),Vector2(1,2),light)
		PoseArt._box(canvas,midpoint+Vector2(2,1),Vector2(1,1),Color("343d34"))
	if not arm:
		PoseArt._box(canvas,joint+Vector2(-1,-1),Vector2(3,2),Color("686f5d"))

static func gun(canvas: Node2D, tx: Transform2D, kind: String, deployed: float, firing: bool, reload_phase: float, dynamic: bool = true) -> void:
	var muzzle: Vector2 = spec(kind).muzzle
	var long_gun := kind in ["heavy_gunner","marksman"]
	var barrel_start := 18.0 if long_gun else 13.0
	metal(canvas,tx,[Vector2(-11,-3),Vector2(-4,-5),Vector2(10,-5),Vector2(13,-2),Vector2(barrel_start, -2),Vector2(barrel_start,3),Vector2(7,3),Vector2(4,7),Vector2(-2,6),Vector2(-5,2),Vector2(-11,2)],"dark",3)
	PoseArt._patch(canvas,tx,Vector2(-10,-1),Vector2(8,3),Color("6f6148"))
	PoseArt._patch(canvas,tx,Vector2(-8,0),Vector2(4,1),Color("a08e69"))
	metal(canvas,tx,[Vector2(barrel_start,-2),muzzle+Vector2(0,-2),muzzle+Vector2(0,2),Vector2(barrel_start,2)],"dark",2)
	PoseArt._line(canvas,tx*Vector2(barrel_start,-1),tx*(muzzle+Vector2(-2,-1)),Color("9b9f88"))
	PoseArt._patch(canvas,tx,muzzle+Vector2(-1,-2),Vector2(1,4),INK)
	if kind == "grenadier":
		metal(canvas,tx,[Vector2(7,-5),Vector2(25,-5),Vector2(31,-3),Vector2(31,4),Vector2(25,6),Vector2(7,6)],"dark",5)
		for x in [9,15,21]:
			PoseArt._patch(canvas,tx,Vector2(x,-4),Vector2(2,9),Color("929885"))
		PoseArt._patch(canvas,tx,Vector2(30,-3),Vector2(2,6),INK)
	elif kind == "heavy_gunner":
		_cloth_box(canvas,tx,Vector2(3,3),Vector2(10,10),Color(.53,.59,.48))
		metal(canvas,tx,[Vector2(9,-7),Vector2(18,-7),Vector2(24,-3),Vector2(9,-3)],"dark",2)
		for x in [23,27,31,35]:
			PoseArt._patch(canvas,tx,Vector2(x,-1),Vector2(2,2),Color("363e34"))
	elif kind == "marksman":
		for x in [4,12]:
			PoseArt._patch(canvas,tx,Vector2(x,-6),Vector2(3,5),INK)
			PoseArt._patch(canvas,tx,Vector2(x+1,-5),Vector2(1,4),Color("8b9380"))
		PoseArt._patch(canvas,tx,Vector2(0,-9),Vector2(18,4),INK)
		PoseArt._patch(canvas,tx,Vector2(2,-9),Vector2(13,2),Color("929887"))
		PoseArt._patch(canvas,tx,Vector2(15,-8),Vector2(2,2),Color("758e80"))
		PoseArt._patch(canvas,tx,Vector2(4,4),Vector2(4,5),Color("535e4d"))
		PoseArt._patch(canvas,tx,Vector2(36,-3),Vector2(8,1),Color("7c846f"))
	elif kind == "scout":
		PoseArt._patch(canvas,tx,Vector2(1,4),Vector2(4,8),Color("5c6350"))
		PoseArt._patch(canvas,tx,Vector2(13,-3),Vector2(6,2),Color("887855"))
	elif kind == "combat_medic":
		PoseArt._patch(canvas,tx,Vector2(3,4),Vector2(4,6),Color("707561"))
		PoseArt._patch(canvas,tx,Vector2(-11,0),Vector2(6,1),Color("aaa181"))
	else:
		PoseArt._patch(canvas,tx,Vector2(3,4),Vector2(4,7),Color("59614f"))
	if dynamic: gun_details(canvas,tx,kind,deployed,firing,reload_phase)

static func gun_details(canvas: Node2D, tx: Transform2D, kind: String, deployed: float, firing: bool, reload_phase: float) -> void:
	if kind == "heavy_gunner":
		var fold := lerpf(1.0,11.0,deployed)
		for end in [Vector2(24-fold,4+fold),Vector2(31+fold*.5,4+fold)]:
			PoseArt._line(canvas,tx*Vector2(29,2),tx*end,INK,3)
			PoseArt._line(canvas,tx*Vector2(29,2),tx*end,Color("8c917c"))
		var cover := sin(reload_phase*PI)*8.0
		PoseArt._line(canvas,tx*Vector2(3,-5),tx*Vector2(14,-5-cover),Color("909781"),2)
	if firing:
		var muzzle: Vector2 = spec(kind).muzzle
		PoseArt._panel(canvas,tx,[muzzle+Vector2(0,-2),muzzle+Vector2(6,-3),muzzle+Vector2(4,0),muzzle+Vector2(9,1),muzzle+Vector2(3,3),muzzle+Vector2(0,2)],Color("efc887"))

static func front_kit(canvas: Node2D, pose: Dictionary, body: Transform2D, gun_tx: Transform2D, kind: String, treating: bool, reload_phase: float, hidden_limbs: int=0) -> void:
	if kind == "combat_medic":
		if not hidden_limbs&2:
			var upper: Vector2 = Vector2(pose.shoulder).lerp(pose.hands[1],.28)
			PoseArt._box(canvas,upper+Vector2(-3,-2),Vector2(7,4),Color("cfc9ad"))
			PoseArt._box(canvas,upper+Vector2(-1,-1),Vector2(3,2),Color("667b69"))
		if treating and not hidden_limbs&1:
			PoseArt._box(canvas,Vector2(pose.hands[0])+Vector2(-3,-3),Vector2(7,5),Color("d9d0b1"))
			PoseArt._line(canvas,Vector2(pose.hands[0])+Vector2(-2,0),Vector2(pose.hands[0])+Vector2(2,0),Color("8c9883"))
	elif kind == "heavy_gunner":
		var start := body*Vector2(-11,9)
		var end := gun_tx*Vector2(7,5)
		for index in 9:
			var amount := index/8.0
			var at := start.lerp(end,amount)+Vector2(0,sin(amount*PI)*7)
			PoseArt._box(canvas,at-Vector2(1,1),Vector2(3,5),INK)
			PoseArt._box(canvas,at,Vector2(1,3),Color("b7a071"))
	elif kind == "grenadier" and reload_phase>.15 and reload_phase<.75:
		var at: Vector2 = pose.hands[0]
		PoseArt._box(canvas,at+Vector2(-2,-4),Vector2(4,8),Color("999464"))
		PoseArt._box(canvas,at+Vector2(-1,-4),Vector2(2,2),Color("c4b782"))
