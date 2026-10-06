extends RefCounted
## Additional authored performances. Coordinates are native game pixels and
## both boot anchors remain fixed throughout anticipation, action and recovery.

const CATALOG := {
	"horizon_scan":{"character":"mara","trigger":"idle","duration":3.8,"label":"Horizont absuchen"},
	"glove_tighten":{"character":"mara","trigger":"idle","duration":2.9,"label":"Handschuh festziehen"},
	"route_note":{"character":"mara","trigger":"idle","duration":4.4,"label":"Route notieren"},
	"bootlace_check":{"character":"mara","trigger":"idle","duration":3.8,"label":"Stiefelschnürung prüfen"},
	"sleeve_dust":{"character":"mara","trigger":"work_finished","duration":2.7,"label":"Ärmel abklopfen"},
	"clear_salute":{"character":"mara","trigger":"wave_clear","duration":2.8,"label":"Entwarnung geben"},
	"knuckle_flex":{"character":"branko","trigger":"idle","duration":3.6,"label":"Finger lockern"},
	"apron_brush":{"character":"branko","trigger":"idle","duration":3.4,"label":"Mantel ausstreichen"},
	"canteen_drink":{"character":"branko","trigger":"idle","duration":4.6,"label":"Feldflasche trinken"},
	"belt_settle":{"character":"branko","trigger":"idle","duration":3.3,"label":"Werkzeuggürtel richten"},
	"brow_wipe":{"character":"branko","trigger":"work_finished","duration":3.2,"label":"Stirn abwischen"},
	"satisfied_nod":{"character":"branko","trigger":"wave_clear","duration":3.2,"label":"Zufrieden zunicken"},
	"pocket_inventory":{"character":"ivo","trigger":"idle","duration":3.2,"label":"Taschen abtasten"},
	"spring_test":{"character":"ivo","trigger":"idle","duration":3.8,"label":"Feder prüfen"},
	"lens_polish":{"character":"ivo","trigger":"idle","duration":3.5,"label":"Brillenglas putzen"},
	"antenna_tune":{"character":"ivo","trigger":"idle","duration":4.0,"label":"Messgerät einstellen"},
	"finger_shake":{"character":"ivo","trigger":"work_finished","duration":2.6,"label":"Hände ausschütteln"},
	"fist_pump":{"character":"ivo","trigger":"wave_clear","duration":2.4,"label":"Kleiner Faustjubel"},
	"blueprint_check":{"character":"nora","trigger":"idle","duration":3.8,"label":"Bauplan prüfen"},
	"gauge_check":{"character":"nora","trigger":"idle","duration":3.4,"label":"Messgerät prüfen"},
	"engineer_dust":{"character":"nora","trigger":"work_finished","duration":2.7,"label":"Arbeitshandschuhe abklopfen"},
	"plan_complete":{"character":"nora","trigger":"wave_clear","duration":2.8,"label":"Bauplan abhaken"},
	"radio_listen":{"character":"levin","trigger":"idle","duration":3.0,"label":"Funk abhören"},
	"scout_watch":{"character":"levin","trigger":"idle","duration":3.5,"label":"Umgebung beobachten"},
	"scout_reset":{"character":"levin","trigger":"work_finished","duration":2.6,"label":"Ausrüstung richten"},
	"all_clear":{"character":"levin","trigger":"wave_clear","duration":2.5,"label":"Entwarnung funken"},
	"kit_check":{"character":"selma","trigger":"idle","duration":3.6,"label":"Sanitätstasche prüfen"},
	"bandage_check":{"character":"selma","trigger":"idle","duration":3.2,"label":"Verband prüfen"},
	"clean_gloves":{"character":"selma","trigger":"work_finished","duration":2.8,"label":"Handschuhe säubern"},
	"medic_relief":{"character":"selma","trigger":"wave_clear","duration":3.1,"label":"Erleichtert durchatmen"},
	"lamp_check":{"character":"oskar","trigger":"idle","duration":3.1,"label":"Grubenlampe prüfen"},
	"pack_tighten":{"character":"oskar","trigger":"idle","duration":3.6,"label":"Trageriemen straffen"},
	"dustcoat_brush":{"character":"oskar","trigger":"work_finished","duration":2.9,"label":"Staubmantel abklopfen"},
	"miner_release":{"character":"oskar","trigger":"wave_clear","duration":3.0,"label":"Schultern entlasten"},
	"headset_check":{"character":"rika","trigger":"idle","duration":3.0,"label":"Ohrhörer prüfen"},
	"cable_check":{"character":"rika","trigger":"idle","duration":3.5,"label":"Kabelverbindung prüfen"},
	"socket_reset":{"character":"rika","trigger":"work_finished","duration":2.7,"label":"Stecker verstauen"},
	"signal_clear":{"character":"rika","trigger":"wave_clear","duration":2.8,"label":"Freies Signal melden"},
}

static func names(character_id: String,trigger: String="") -> Array[String]:
	character_id = CharacterCatalog.presentation_id(character_id,"motion")
	var result: Array[String] = []
	for kind: String in CATALOG:
		var entry: Dictionary = CATALOG[kind]
		if entry.character==character_id and (trigger.is_empty() or entry.trigger==trigger):
			result.append(kind)
	return result

static func _target(base: Dictionary,changes: Dictionary) -> Dictionary:
	var target := base.duplicate(true)
	for key: String in changes:
		if key!="t":
			target[key] = changes[key]
	return target

static func _mix(a: Dictionary,b: Dictionary,weight: float) -> Dictionary:
	var result := a.duplicate(true)
	var eased := smoothstep(0.0,1.0,clampf(weight,0.0,1.0))
	for key in ["hip","shoulder","head_shift"]:
		result[key] = Vector2(a[key]).lerp(Vector2(b[key]),eased)
	for index in 2:
		result.hands[index] = Vector2(a.hands[index]).lerp(Vector2(b.hands[index]),eased)
	result.head_tilt = lerpf(float(a.head_tilt),float(b.head_tilt),eased)
	return result

static func sample(kind: String,phase: float,base: Dictionary) -> Dictionary:
	var keys := _keys(kind,base)
	var before := base.duplicate(true)
	var previous_time := 0.0
	var result := base.duplicate(true)
	for key: Dictionary in keys:
		var at := float(key.t)
		var after := _target(base,key)
		if phase<=at:
			result = _mix(before,after,(phase-previous_time)/maxf(0.001,at-previous_time))
			break
		before = after
		previous_time = at
	# Props leave their pocket only after the grasp and return before release.
	if phase>0.14 and phase<0.89:
		match kind:
			"route_note", "blueprint_check", "plan_complete": result.prop = "notebook"
			"canteen_drink": result.prop = "canteen"
			"spring_test": result.prop = "spring"
			"lens_polish", "bandage_check", "clean_gloves": result.prop = "cloth"
			"antenna_tune", "gauge_check": result.prop = "meter"
	if kind in ["radio_listen","all_clear"] and phase>.2 and phase<.85: result.prop = "radio"
	if kind in ["cable_check","socket_reset"] and phase>.18 and phase<.84: result.prop="meter"
	if kind=="signal_clear" and phase>.2 and phase<.85: result.prop="radio"
	if kind=="satisfied_nod":
		result.blink = phase>0.43 and phase<0.55
	return result

static func _keys(kind: String,base: Dictionary) -> Array[Dictionary]:
	var keys: Array[Dictionary] = []
	match kind:
		"lamp_check":
			keys=[{"t":.22,"hands":[Vector2(-12,-28),Vector2(12,-58)],"head_shift":Vector2(1,1)}, {"t":.44,"hands":[Vector2(-12,-28),Vector2(14,-61)],"head_tilt":-.07}, {"t":.66,"hands":[Vector2(-12,-28),Vector2(10,-60)],"head_tilt":.05}, {"t":.84,"hands":[Vector2(-12,-27),Vector2(12,-38)]}]
		"pack_tighten":
			keys=[{"t":.18,"hands":[Vector2(-10,-35),Vector2(6,-30)]}, {"t":.38,"hands":[Vector2(-8,-40),Vector2(10,-31)],"shoulder":Vector2(-2,-43)}, {"t":.56,"hands":[Vector2(-11,-33),Vector2(7,-29)],"shoulder":Vector2(-3,-40)}, {"t":.73,"hands":[Vector2(-8,-39),Vector2(9,-31)],"shoulder":Vector2(-2,-43)}]
		"dustcoat_brush":
			keys=[{"t":.21,"hands":[Vector2(-12,-31),Vector2(-3,-37)],"head_shift":Vector2(-1,3)}, {"t":.40,"hands":[Vector2(-12,-28),Vector2(4,-22)]}, {"t":.58,"hands":[Vector2(-12,-31),Vector2(-2,-36)]}, {"t":.77,"hands":[Vector2(-12,-28),Vector2(8,-23)],"head_shift":Vector2(1,2)}]
		"miner_release":
			keys=[{"t":.23,"shoulder":Vector2(-3,-44),"hands":[Vector2(-14,-34),Vector2(12,-35)]}, {"t":.47,"shoulder":Vector2(-3,-40),"hands":[Vector2(-13,-27),Vector2(11,-28)],"head_shift":Vector2(1,1)}, {"t":.66,"shoulder":Vector2(-2,-42),"head_tilt":.11}, {"t":.83,"head_shift":Vector2(0,1),"head_tilt":-.03}]
		"headset_check":
			keys=[{"t":.19,"hands":[Vector2(-7,-51),Vector2(12,-34)],"head_shift":Vector2(-1,0)}, {"t":.41,"hands":[Vector2(-7,-54),Vector2(12,-34)],"head_tilt":-.08}, {"t":.63,"hands":[Vector2(-5,-53),Vector2(12,-34)],"head_shift":Vector2(2,1)}, {"t":.84,"hands":[Vector2(-8,-38),Vector2(12,-34)]}]
		"cable_check", "socket_reset":
			keys=[{"t":.18,"hands":[Vector2(2,-32),Vector2(11,-33)],"head_shift":Vector2(1,2)}, {"t":.36,"hands":[Vector2(7,-36),Vector2(20,-36)],"head_shift":Vector2(3,3)}, {"t":.54,"hands":[Vector2(8,-37),Vector2(14,-37)]}, {"t":.71,"hands":[Vector2(4,-33),Vector2(17,-34)],"head_shift":Vector2(1,2)}, {"t":.86,"hands":[Vector2(-4,-30),Vector2(10,-31)]}]
		"signal_clear":
			keys=[{"t":.20,"hands":[Vector2(-8,-31),Vector2(11,-50)],"head_shift":Vector2(1,0)}, {"t":.42,"hands":[Vector2(-8,-31),Vector2(13,-53)],"head_tilt":-.05}, {"t":.63,"hands":[Vector2(-8,-31),Vector2(17,-48)],"head_shift":Vector2(2,-1)}, {"t":.81,"hands":[Vector2(-8,-31),Vector2(15,-38)]}]
		"blueprint_check", "plan_complete":
			keys = [{"t":.20,"hands":[Vector2(7,-34),Vector2(13,-35)],"head_shift":Vector2(2,3)}, {"t":.45,"hands":[Vector2(9,-35),Vector2(17,-38)],"shoulder":Vector2(-1,-42),"head_shift":Vector2(3,4)}, {"t":.67,"hands":[Vector2(9,-35),Vector2(12,-37)],"head_shift":Vector2(2,3)}, {"t":.86,"hands":[Vector2(4,-31),Vector2(10,-30)]}]
		"gauge_check":
			keys = [{"t":.20,"hands":[Vector2(10,-39),Vector2(16,-41)],"head_shift":Vector2(2,2)}, {"t":.43,"hands":[Vector2(10,-40),Vector2(13,-42)],"head_tilt":.08}, {"t":.63,"hands":[Vector2(10,-38),Vector2(18,-39)],"head_shift":Vector2(3,3)}, {"t":.82,"hands":[Vector2(4,-32),Vector2(13,-34)]}]
		"engineer_dust", "clean_gloves":
			keys = [{"t":.20,"hands":[Vector2(2,-30),Vector2(8,-31)],"head_shift":Vector2(1,3)}, {"t":.40,"hands":[Vector2(5,-34),Vector2(12,-32)]}, {"t":.56,"hands":[Vector2(0,-30),Vector2(7,-29)]}, {"t":.72,"hands":[Vector2(6,-33),Vector2(10,-34)]}]
		"radio_listen", "all_clear":
			keys = [{"t":.20,"hands":[Vector2(-7,-48),Vector2(11,-37)],"shoulder":Vector2(4,-43)}, {"t":.43,"hands":[Vector2(-8,-54),Vector2(11,-37)],"head_shift":Vector2(-2,-1),"head_tilt":-.09}, {"t":.65,"hands":[Vector2(-7,-53),Vector2(13,-35)],"head_shift":Vector2(2,-1)}, {"t":.83,"hands":[Vector2(-8,-42),Vector2(11,-37)]}]
		"scout_watch":
			keys = [{"t":.20,"hip":Vector2(0,-22),"shoulder":Vector2(7,-38),"hands":[Vector2(-3,-27),Vector2(13,-49)]}, {"t":.45,"hip":Vector2(0,-20),"shoulder":Vector2(8,-37),"hands":[Vector2(0,-27),Vector2(14,-53)],"head_shift":Vector2(3,-1)}, {"t":.68,"hip":Vector2(0,-21),"shoulder":Vector2(5,-38),"hands":[Vector2(-3,-27),Vector2(9,-52)],"head_shift":Vector2(-2,0)}]
		"scout_reset":
			keys = [{"t":.22,"hands":[Vector2(-8,-30),Vector2(8,-27)],"shoulder":Vector2(5,-42)}, {"t":.43,"hands":[Vector2(-9,-27),Vector2(3,-30)],"head_shift":Vector2(-1,3)}, {"t":.65,"hands":[Vector2(-7,-31),Vector2(9,-33)],"shoulder":Vector2(6,-44)}]
		"kit_check":
			keys = [{"t":.20,"hands":[Vector2(-14,-24),Vector2(-7,-26)],"head_shift":Vector2(-2,3)}, {"t":.43,"hip":Vector2(-2,-24),"shoulder":Vector2(-4,-40),"hands":[Vector2(-15,-25),Vector2(-11,-29)],"head_shift":Vector2(-2,4)}, {"t":.63,"hands":[Vector2(-13,-28),Vector2(-4,-30)],"head_shift":Vector2(-1,3)}, {"t":.84,"hands":[Vector2(-14,-27),Vector2(4,-29)]}]
		"bandage_check":
			keys = [{"t":.20,"hands":[Vector2(0,-33),Vector2(9,-34)],"head_shift":Vector2(1,2)}, {"t":.43,"hands":[Vector2(-2,-38),Vector2(15,-37)],"head_shift":Vector2(2,3)}, {"t":.63,"hands":[Vector2(2,-37),Vector2(11,-39)],"head_shift":Vector2(1,2)}, {"t":.83,"hands":[Vector2(-7,-31),Vector2(7,-32)]}]
		"medic_relief":
			keys = [{"t":.23,"shoulder":Vector2(-2,-43),"hands":[Vector2(-12,-31),Vector2(2,-36)],"head_shift":Vector2(0,-1)}, {"t":.46,"shoulder":Vector2(-1,-44),"hands":[Vector2(-11,-32),Vector2(3,-38)],"head_tilt":-.08}, {"t":.69,"shoulder":Vector2(0,-41),"hands":[Vector2(-13,-28),Vector2(8,-29)],"head_shift":Vector2(1,1)}]
		"horizon_scan":
			keys = [
				{"t":0.17,"hands":[Vector2(-9,-29),Vector2(14,-57)],"shoulder":Vector2(2,-43)},
				{"t":0.38,"hands":[Vector2(-9,-29),Vector2(14,-59)],"shoulder":Vector2(3,-43),"head_shift":Vector2(3,0),"head_tilt":-0.07},
				{"t":0.63,"hands":[Vector2(-9,-29),Vector2(11,-59)],"shoulder":Vector2(0,-43),"head_shift":Vector2(-2,0),"head_tilt":0.05},
				{"t":0.79,"hands":[Vector2(-9,-29),Vector2(13,-56)],"head_shift":Vector2(2,0)},
			]
		"glove_tighten":
			keys = [
				{"t":0.22,"hands":[Vector2(7,-35),Vector2(16,-37)],"head_shift":Vector2(2,3)},
				{"t":0.38,"hands":[Vector2(7,-34),Vector2(12,-34)],"shoulder":Vector2(-2,-42),"head_shift":Vector2(2,3)},
				{"t":0.53,"hands":[Vector2(11,-36),Vector2(17,-38)],"head_shift":Vector2(2,2)},
				{"t":0.70,"hands":[Vector2(5,-34),Vector2(13,-35)],"shoulder":Vector2(-2,-42),"head_shift":Vector2(1,2)},
			]
		"route_note":
			keys = [
				{"t":0.15,"hands":[Vector2(-6,-29),Vector2(5,-30)],"head_shift":Vector2(1,2)},
				{"t":0.30,"hands":[Vector2(8,-36),Vector2(14,-38)],"head_shift":Vector2(3,4),"head_tilt":0.08},
				{"t":0.43,"hands":[Vector2(8,-36),Vector2(11,-39)],"head_shift":Vector2(3,4)},
				{"t":0.52,"hands":[Vector2(8,-36),Vector2(17,-38)],"head_shift":Vector2(3,4)},
				{"t":0.62,"hands":[Vector2(8,-36),Vector2(11,-37)],"head_shift":Vector2(2,3)},
				{"t":0.75,"hands":[Vector2(8,-36),Vector2(16,-39)],"head_shift":Vector2(2,3)},
				{"t":0.88,"hands":[Vector2(-6,-29),Vector2(5,-30)],"head_shift":Vector2(1,1)},
			]
		"bootlace_check":
			keys = [
				{"t":0.23,"hip":Vector2(-2,-15),"shoulder":Vector2(4,-31),"hands":[Vector2(-5,-19),Vector2(13,-16)],"head_shift":Vector2(2,4),"head_tilt":0.12},
				{"t":0.42,"hip":Vector2(-3,-10),"shoulder":Vector2(5,-25),"hands":[Vector2(3,-7),Vector2(11,-7)],"head_shift":Vector2(2,4),"head_tilt":0.12},
				{"t":0.55,"hip":Vector2(-3,-10),"shoulder":Vector2(5,-25),"hands":[Vector2(0,-10),Vector2(14,-10)],"head_shift":Vector2(2,4),"head_tilt":0.12},
				{"t":0.66,"hip":Vector2(-3,-10),"shoulder":Vector2(5,-25),"hands":[Vector2(3,-7),Vector2(11,-7)],"head_shift":Vector2(2,4),"head_tilt":0.12},
				{"t":0.81,"hip":Vector2(-2,-17),"shoulder":Vector2(3,-33),"hands":[Vector2(-6,-21),Vector2(13,-20)],"head_shift":Vector2(1,2)},
			]
		"sleeve_dust":
			keys = [
				{"t":0.23,"hands":[Vector2(-9,-33),Vector2(-6,-42)],"head_shift":Vector2(-2,3)},
				{"t":0.39,"hands":[Vector2(-10,-31),Vector2(-9,-36)],"shoulder":Vector2(-1,-41)},
				{"t":0.52,"hands":[Vector2(-9,-33),Vector2(-5,-43)],"head_shift":Vector2(-2,2)},
				{"t":0.67,"hands":[Vector2(-10,-31),Vector2(-9,-35)],"shoulder":Vector2(-1,-41)},
				{"t":0.81,"hands":[Vector2(-9,-28),Vector2(3,-30)]},
			]
		"clear_salute":
			keys = [
				{"t":0.21,"hands":[Vector2(-9,-28),Vector2(13,-51)],"shoulder":Vector2(1,-43)},
				{"t":0.39,"hands":[Vector2(-9,-28),Vector2(15,-58)],"head_shift":Vector2(2,-1),"head_tilt":-0.03},
				{"t":0.60,"hands":[Vector2(-9,-28),Vector2(15,-58)],"head_shift":Vector2(3,1),"head_tilt":0.07},
				{"t":0.76,"hands":[Vector2(-9,-28),Vector2(20,-45)],"head_shift":Vector2(1,0)},
			]
		"knuckle_flex":
			keys = [
				{"t":0.24,"hands":[Vector2(1,-34),Vector2(9,-35)],"head_shift":Vector2(1,3)},
				{"t":0.43,"hands":[Vector2(6,-35),Vector2(13,-37)],"shoulder":Vector2(-2,-42),"head_shift":Vector2(1,3)},
				{"t":0.57,"hands":[Vector2(-2,-33),Vector2(6,-34)],"shoulder":Vector2(1,-41),"head_shift":Vector2(-1,2)},
				{"t":0.73,"hands":[Vector2(4,-35),Vector2(11,-36)],"shoulder":Vector2(-2,-42)},
			]
		"apron_brush":
			keys = [
				{"t":0.20,"hands":[Vector2(-9,-31),Vector2(-3,-41)],"head_shift":Vector2(-1,3)},
				{"t":0.40,"hands":[Vector2(-12,-29),Vector2(11,-28)],"shoulder":Vector2(-2,-40),"head_shift":Vector2(2,4)},
				{"t":0.54,"hands":[Vector2(-9,-31),Vector2(-3,-41)],"head_shift":Vector2(-1,3)},
				{"t":0.73,"hands":[Vector2(-12,-29),Vector2(12,-28)],"shoulder":Vector2(-2,-40)},
			]
		"canteen_drink":
			keys = [
				{"t":0.15,"hands":[Vector2(-10,-29),Vector2(8,-29)],"head_shift":Vector2(2,2)},
				{"t":0.32,"hands":[Vector2(-8,-35),Vector2(13,-50)],"head_shift":Vector2(0,-1),"head_tilt":-0.10},
				{"t":0.51,"hands":[Vector2(-8,-35),Vector2(13,-51)],"shoulder":Vector2(-2,-43),"head_shift":Vector2(-1,-2),"head_tilt":-0.14},
				{"t":0.67,"hands":[Vector2(-8,-35),Vector2(13,-50)],"head_shift":Vector2(0,-1),"head_tilt":-0.08},
				{"t":0.87,"hands":[Vector2(-10,-29),Vector2(8,-29)],"head_shift":Vector2(1,2)},
			]
		"belt_settle":
			keys = [
				{"t":0.22,"hands":[Vector2(-8,-28),Vector2(6,-28)],"shoulder":Vector2(-1,-40),"head_shift":Vector2(1,3)},
				{"t":0.40,"hands":[Vector2(-10,-31),Vector2(8,-31)],"hip":Vector2(0,-25),"shoulder":Vector2(-1,-43)},
				{"t":0.55,"hands":[Vector2(-8,-28),Vector2(6,-28)],"shoulder":Vector2(-1,-40),"head_shift":Vector2(1,2)},
				{"t":0.71,"hands":[Vector2(-11,-30),Vector2(9,-30)],"hip":Vector2(0,-25),"shoulder":Vector2(-1,-42)},
			]
		"brow_wipe":
			keys = [
				{"t":0.22,"hands":[Vector2(-12,-27),Vector2(14,-51)],"head_shift":Vector2(2,2)},
				{"t":0.40,"hands":[Vector2(-12,-27),Vector2(13,-56)],"head_shift":Vector2(0,2),"head_tilt":0.05},
				{"t":0.61,"hands":[Vector2(-12,-27),Vector2(3,-55)],"shoulder":Vector2(-2,-42),"head_shift":Vector2(-2,2),"head_tilt":-0.04},
				{"t":0.80,"hands":[Vector2(-12,-27),Vector2(18,-38)],"head_shift":Vector2(0,1)},
			]
		"satisfied_nod":
			keys = [
				{"t":0.25,"hands":[Vector2(7,-36),Vector2(-7,-37)],"shoulder":Vector2(-1,-43),"head_shift":Vector2(1,0)},
				{"t":0.44,"hands":[Vector2(7,-36),Vector2(-7,-37)],"head_shift":Vector2(2,3),"head_tilt":0.12},
				{"t":0.63,"hands":[Vector2(7,-36),Vector2(-7,-37)],"shoulder":Vector2(-1,-43),"head_shift":Vector2(0,0),"head_tilt":-0.03},
				{"t":0.79,"hands":[Vector2(7,-35),Vector2(-7,-36)],"head_shift":Vector2(1,1)},
			]
		"pocket_inventory":
			keys = [
				{"t":0.18,"hands":[Vector2(-4,-28),Vector2(12,-29)],"head_shift":Vector2(-2,4)},
				{"t":0.34,"hands":[Vector2(-7,-24),Vector2(12,-32)],"shoulder":Vector2(1,-42),"head_shift":Vector2(-2,4)},
				{"t":0.49,"hands":[Vector2(-4,-30),Vector2(8,-25)],"shoulder":Vector2(4,-42),"head_shift":Vector2(2,4)},
				{"t":0.64,"hands":[Vector2(-4,-32),Vector2(3,-38)],"head_shift":Vector2(1,3)},
				{"t":0.80,"hands":[Vector2(0,-37),Vector2(12,-33)],"head_shift":Vector2(-1,2)},
			]
		"spring_test":
			keys = [
				{"t":0.15,"hands":[Vector2(0,-29),Vector2(7,-29)],"head_shift":Vector2(1,2)},
				{"t":0.30,"hands":[Vector2(6,-38),Vector2(20,-38)],"head_shift":Vector2(3,3)},
				{"t":0.44,"hands":[Vector2(10,-38),Vector2(15,-38)],"shoulder":Vector2(4,-43),"head_shift":Vector2(2,4)},
				{"t":0.57,"hands":[Vector2(6,-38),Vector2(20,-38)],"head_shift":Vector2(3,3)},
				{"t":0.70,"hands":[Vector2(10,-38),Vector2(15,-38)],"shoulder":Vector2(4,-43),"head_shift":Vector2(2,4)},
				{"t":0.87,"hands":[Vector2(0,-29),Vector2(7,-29)],"head_shift":Vector2(1,2)},
			]
		"lens_polish":
			keys = [
				{"t":0.16,"hands":[Vector2(-6,-32),Vector2(4,-32)]},
				{"t":0.31,"hands":[Vector2(-5,-51),Vector2(14,-54)],"head_shift":Vector2(1,1)},
				{"t":0.42,"hands":[Vector2(-5,-51),Vector2(10,-56)],"head_shift":Vector2(1,2)},
				{"t":0.53,"hands":[Vector2(-5,-51),Vector2(14,-53)],"head_shift":Vector2(1,2)},
				{"t":0.64,"hands":[Vector2(-5,-51),Vector2(10,-55)],"head_shift":Vector2(1,1)},
				{"t":0.75,"hands":[Vector2(-5,-49),Vector2(14,-52)],"head_shift":Vector2(1,1)},
				{"t":0.88,"hands":[Vector2(-6,-32),Vector2(4,-32)]},
			]
		"antenna_tune":
			keys = [
				{"t":0.15,"hands":[Vector2(1,-31),Vector2(10,-32)],"head_shift":Vector2(1,2)},
				{"t":0.29,"hands":[Vector2(9,-39),Vector2(20,-45)],"head_shift":Vector2(3,3),"head_tilt":0.07},
				{"t":0.43,"hands":[Vector2(9,-39),Vector2(15,-46)],"head_shift":Vector2(2,3)},
				{"t":0.55,"hands":[Vector2(9,-39),Vector2(20,-44)],"head_shift":Vector2(3,2)},
				{"t":0.68,"hands":[Vector2(9,-39),Vector2(15,-46)],"head_shift":Vector2(3,3)},
				{"t":0.78,"hands":[Vector2(9,-39),Vector2(18,-40)],"head_shift":Vector2(1,0)},
				{"t":0.88,"hands":[Vector2(1,-31),Vector2(10,-32)],"head_shift":Vector2(1,2)},
			]
		"finger_shake":
			keys = [
				{"t":0.17,"hands":[Vector2(-11,-31),Vector2(18,-31)],"shoulder":Vector2(3,-44)},
				{"t":0.29,"hands":[Vector2(-12,-35),Vector2(19,-28)],"shoulder":Vector2(2,-43)},
				{"t":0.41,"hands":[Vector2(-10,-28),Vector2(17,-35)],"shoulder":Vector2(4,-43)},
				{"t":0.53,"hands":[Vector2(-12,-35),Vector2(19,-28)],"shoulder":Vector2(2,-43)},
				{"t":0.65,"hands":[Vector2(-10,-28),Vector2(17,-35)],"shoulder":Vector2(4,-43)},
				{"t":0.79,"hands":[Vector2(-11,-31),Vector2(18,-31)],"shoulder":Vector2(3,-44)},
			]
		"fist_pump":
			keys = [
				{"t":0.20,"hands":[Vector2(-8,-34),Vector2(12,-42)],"hip":Vector2(0,-25),"shoulder":Vector2(3,-42)},
				{"t":0.39,"hands":[Vector2(-8,-34),Vector2(14,-60)],"shoulder":Vector2(3,-44),"head_shift":Vector2(1,-2),"head_tilt":-0.08},
				{"t":0.55,"hands":[Vector2(-8,-34),Vector2(11,-46)],"hip":Vector2(0,-25),"shoulder":Vector2(3,-42),"head_shift":Vector2(2,0)},
				{"t":0.71,"hands":[Vector2(-8,-34),Vector2(14,-56)],"shoulder":Vector2(3,-44),"head_shift":Vector2(1,-1)},
			]
	keys.append({"t":1.0,"hip":base.hip,"shoulder":base.shoulder,"hands":base.hands,"head_shift":base.head_shift,"head_tilt":base.head_tilt})
	return keys
