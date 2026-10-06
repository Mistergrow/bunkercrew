extends RefCounted
## Small angular inclusions cut from one deterministic world-space deposit field.
## The same shard is clipped identically by either neighbor at a mining boundary.
const GRID := 38.0
const REACH := 40.0
const PALETTES := {
	"ore": [Color("59483d"), Color("94704c"), Color("af875a")],
	"limestone": [Color("646653"), Color("969981"), Color("b3b39a")],
	"tungsten": [Color("464952"), Color("737987"), Color("9b9f9c")],
	"sand": [Color("443e30"), Color("65583e"), Color("7b694b")],
}

static func facets(kind: String, bounds: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not bounds.has_area():
		return result
	var colors: Array = PALETTES.get(kind, PALETTES.sand)
	var clip := PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)])
	var first := Vector2i(((bounds.position-Vector2.ONE*REACH)/GRID).floor())
	var last := Vector2i(((bounds.end+Vector2.ONE*REACH)/GRID).ceil())
	for row in range(first.y,last.y+1):
		for column in range(first.x,last.x+1):
			var random := RandomNumberGenerator.new()
			random.seed = int(column)*73856093 ^ int(row)*19349663 ^ 174931
			if random.randf() < (.48 if kind == "sand" else .19):
				continue
			var center := (Vector2(column,row)*GRID+Vector2(random.randf_range(4,34),random.randf_range(5,33))).round()
			var slope := random.randf_range(-.72,.62)
			var count := random.randi_range(2,4)
			for shard in count:
				var at := center+Vector2((shard-float(count-1)*.5)*random.randf_range(5,9),random.randf_range(-5,5))
				var length := random.randf_range(5,11)
				var thickness := random.randf_range(2,5) * (1.25 if kind == "limestone" else .75 if kind == "sand" else 1.0)
				var shape := PackedVector2Array()
				for point in [Vector2(-length,-thickness*.1),Vector2(-length*.52,-thickness),Vector2(length*.45,-thickness*.65),Vector2(length,thickness*.15),Vector2(length*.3,thickness),Vector2(-length*.8,thickness*.65)]:
					shape.append((at+point.rotated(slope)).round())
				var tone: Color = colors[1].lerp(colors[0],random.randf_range(.05,.4))
				if kind == "sand":
					tone.a = .65
				_append_clipped(result, shape, clip, tone)
				var shadow := PackedVector2Array([shape[0],shape[5],shape[4],shape[3],shape[3]+Vector2(0,2),shape[4]+Vector2(0,2),shape[5]+Vector2(0,2)])
				_append_clipped(result, shadow, clip, Color(.035,.039,.035,.5), false)
				var glint := PackedVector2Array([shape[0],shape[1],shape[2],shape[2].lerp(at,.36).round(),shape[1].lerp(at,.24).round()])
				var highlight: Color = colors[2]
				highlight.a = .56 if kind != "sand" else .20
				_append_clipped(result, glint, clip, highlight)
	return result

static func _append_clipped(result: Array[Dictionary], shape: PackedVector2Array, clip: PackedVector2Array, color: Color, textured: bool = true) -> void:
	if shape.size() < 3 or Geometry2D.triangulate_polygon(shape).is_empty():
		return
	for fragment in Geometry2D.intersect_polygons(shape,clip):
		if fragment.size() >= 3 and not Geometry2D.triangulate_polygon(fragment).is_empty():
			result.append({"points":fragment,"color":color,"textured":textured})
