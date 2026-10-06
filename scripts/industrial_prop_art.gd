extends RefCounted
## Raster material shared with the sentries; cloth keeps separate moving joints.
const ATLAS = preload("res://assets/perimeter/components_v3.png")
const PIPE = Rect2(46,560,370,344)
const POST = Rect2(556,490,107,414)
const MAST = Rect2(851,515,182,389)
const CLOTH = Rect2(1165,653,347,149)
const PIPE_SCALE = 62.0/344.0
const POST_SCALE = 98.0/414.0
const MAST_SCALE = 106.0/389.0

static func tint(base: Color) -> Color:
	return Color.WHITE.lerp(base,.22)

static func paint(canvas: CanvasItem,region: Rect2,anchor: Vector2,at: Vector2,pixel_scale: float,color: Color) -> void:
	canvas.draw_texture_rect_region(ATLAS,Rect2(at+(region.position-anchor)*pixel_scale,region.size*pixel_scale),region,color)

static func pipe(canvas: Node2D,color: Color,time: float,phase: float,gust: float) -> void:
	paint(canvas,PIPE,Vector2(118,904),Vector2(-23,0),PIPE_SCALE,tint(color))
	for index in 3:
		var age:=fposmod(time*.48+float(index)/3.0+phase,1.0)
		var point:=Vector2(24+gust*age*2,-43+age*age*42).round()
		canvas.draw_rect(Rect2(point,Vector2(1,minf(2+age*2,-point.y))),Color(.58,.73,.71,(1-age)*.6))

static func cable_posts(canvas: Node2D,color: Color) -> void:
	for x in [-35.0,35.0]:
		paint(canvas,POST,Vector2(610,904),Vector2(x,0),POST_SCALE,tint(color))

static func windsock_points(time: float,phase: float,gust: float,motion: float,pressure_strength: float = -1.0) -> PackedVector2Array:
	var points:=PackedVector2Array()
	var pressure:=clampf(absf(gust)*1.6 if pressure_strength<0.0 else pressure_strength,0,1)
	for joint in 9:
		var amount:=float(joint)/8.0
		var wave:=sin(time*3.7+phase-amount*5.8)*amount*3.5*motion*maxf(.06,pressure)
		points.append(Vector2(31+54*amount*(.42+.58*pressure),-90+(1-pressure)*amount*amount*27+wave))
	return points

static func windsock(canvas: Node2D,color: Color,time: float,phase: float,gust: float,motion: float,pressure_strength: float) -> void:
	paint(canvas,MAST,Vector2(903,904),Vector2.ZERO,MAST_SCALE,tint(color))
	var joints:=windsock_points(time,phase,gust,motion,pressure_strength)
	var uv_size:=ATLAS.get_size()
	var cloth_tint:=tint(color)
	# Eight textured strips bend about the attachment, keeping the mast rigid.
	for index in 8:
		var a:=joints[index]
		var b:=joints[index+1]
		var u0:=CLOTH.position.x+CLOTH.size.x*float(index)/8.0
		var u1:=CLOTH.position.x+CLOTH.size.x*float(index+1)/8.0
		var points:=PackedVector2Array([a+Vector2(0,-11.5),b+Vector2(0,-11.5),b+Vector2(0,11.5),a+Vector2(0,11.5)])
		var uv:=PackedVector2Array([Vector2(u0,CLOTH.position.y)/uv_size,Vector2(u1,CLOTH.position.y)/uv_size,Vector2(u1,CLOTH.end.y)/uv_size,Vector2(u0,CLOTH.end.y)/uv_size])
		canvas.draw_polygon(points,PackedColorArray([cloth_tint]),uv,ATLAS)
