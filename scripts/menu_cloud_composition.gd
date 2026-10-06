extends RefCounted
## Menu skies use the existing three-row cloud atlas and gameplay shaders.
## Each row: width, height, altitude relative to panorama height, opacity,
## horizontal phase, distance between copies as a fraction of width.
## Smaller, separated banks leave the painted sky and landmarks readable.
const LAYOUTS := {
	"ash_foundry":[
		[1820.0,138.0,-.22,.46,130.0,.83],
		[1240.0,226.0,-.03,.68,720.0,.81],
		[850.0,144.0,.23,.42,-240.0,.88]],
	"abandoned_harbor":[
		[1470.0,94.0,-.09,.30,560.0,.93],
		[960.0,160.0,.02,.44,-310.0,.88],
		[670.0,112.0,.28,.29,920.0,.95]],
	"basalt_quarry":[
		[1380.0,80.0,-.18,.25,-820.0,1.08],
		[760.0,140.0,.06,.19,450.0,1.10],
		[570.0,90.0,.25,.19,-670.0,1.12]],
	"overgrown_steelworks":[
		[1260.0,95.0,-.24,.28,910.0,1.04],
		[820.0,188.0,-.04,.24,-640.0,1.03],
		[590.0,116.0,.24,.20,230.0,1.08]],
	"frozen_rail_yard":[
		[1580.0,115.0,-.16,.39,270.0,.94],
		[1130.0,162.0,.02,.39,930.0,.90],
		[720.0,118.0,.30,.30,-430.0,1.01]],
	"iron_canyon":[
		[1740.0,80.0,-.17,.21,-540.0,1.12],
		[850.0,123.0,.00,.16,1070.0,1.18],
		[560.0,84.0,.26,.18,380.0,1.16]],
	"flooded_power_station":[
		[1520.0,132.0,-.20,.41,830.0,.83],
		[1190.0,244.0,-.02,.59,160.0,.78],
		[730.0,157.0,.25,.44,-730.0,.83]],
	"mountain_pass":[
		[1630.0,143.0,-.25,.47,-410.0,.78],
		[1440.0,276.0,-.08,.83,480.0,.74],
		[920.0,192.0,.23,.62,1190.0,.77]],
	"storm_dam":[
		[1700.0,162.0,-.22,.50,1050.0,.76],
		[1510.0,295.0,-.03,.90,-850.0,.72],
		[960.0,206.0,.30,.66,380.0,.78]],
	"sulfur_refinery":[
		[1320.0,102.0,-.13,.31,-1060.0,.98],
		[1000.0,198.0,-.05,.43,250.0,.90],
		[630.0,129.0,.25,.30,810.0,.98]],
	"radar_highlands":[
		[1640.0,90.0,-.23,.32,1370.0,1.05],
		[940.0,147.0,.00,.30,-440.0,1.02],
		[650.0,102.0,.26,.25,540.0,1.05]],
	"buried_megafactory":[
		[1440.0,117.0,-.25,.31,540.0,.97],
		[1060.0,214.0,-.02,.41,1180.0,.90],
		[770.0,154.0,.26,.32,-980.0,.94]],
	"sector07":[
		[1840.0,150.0,-.21,.33,160.0,.87],
		[1160.0,216.0,-.02,.39,-520.0,.91],
		[790.0,140.0,.26,.30,840.0,.96]],
}

static func layer(environment: String, depth: int) -> Dictionary:
	var rows: Array = LAYOUTS.get(environment, LAYOUTS.ash_foundry)
	var row: Array = rows[clampi(depth, 0, 2)]
	return {"size":Vector2(row[0],row[1]), "altitude":float(row[2]), "alpha":float(row[3]), "phase":float(row[4]), "spacing":float(row[5])}

static func period(environment: String, depth: int) -> float:
	var definition := layer(environment, depth)
	return definition.size.x * definition.spacing

static func source_uvs(depth: int, mirrored: bool, atlas_height: int = 1024) -> PackedVector2Array:
	var left := 1.0 if mirrored else 0.0
	var right := 0.0 if mirrored else 1.0
	# Stay inside the selected atlas row, even at rasterized polygon edges.
	var margin := .5 / float(maxi(1, atlas_height))
	var top := float(depth) / 3.0 + margin
	var bottom := float(depth + 1) / 3.0 - margin
	return PackedVector2Array([Vector2(left,top),Vector2(right,top),Vector2(right,bottom),Vector2(left,bottom)])

static func tiles(environment: String, depth: int, view: Rect2, panorama: Rect2, travel: float, camera_drift: float = 0.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var definition := layer(environment, depth)
	var dimensions: Vector2 = definition.size
	var distance := dimensions.x * float(definition.spacing)
	var base_top := panorama.position.y + panorama.size.y * float(definition.altitude)
	var row_distance := dimensions.y * 1.65 + 180.0
	var first_row := maxi(0, floori((base_top - dimensions.y * .2 - view.end.y) / row_distance))
	var last_row := maxi(-1, ceili((base_top + dimensions.y * 1.2 - view.position.y) / row_distance))
	for row in range(first_row, mini(first_row + 6, last_row + 1)):
		# Keep distance unwrapped: a bank retains its altitude and silhouette
		# across horizontal periods, including gusts and direction changes.
		var shift := travel + float(definition.phase) + row * dimensions.x * .417 + camera_drift
		var first_tile := floori((view.position.x - shift - dimensions.x * 1.10) / distance)
		var last_tile := ceili((view.end.x - shift) / distance)
		for tile in range(first_tile, mini(first_tile + 12, last_tile + 1)):
			var identity := tile * 1.73 + row * 2.19 + depth * 2.91 + float(definition.phase) * .003
			var size := dimensions * Vector2(1.0 + sin(identity * .71) * .075, 1.0 + cos(identity) * .09)
			var top := base_top - row * row_distance + sin(identity) * dimensions.y * .14
			var rect := Rect2(Vector2(tile * distance + shift, top), size)
			if not rect.intersects(view): continue
			result.append({"rect":rect, "alpha":float(definition.alpha) * (1.0 - row * .06), "mirror":posmod(tile + row + depth + environment.hash(), 2) == 1, "row":row, "tile":tile})
	return result
