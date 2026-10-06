extends RefCounted
## Articulated scenery uses the same painted metal as the working machinery.
## Bases are rigid; only lenses, chains, rotors and needles move.
const Surface := preload("res://scripts/station_surface_art.gd")
const INK := Color("17211b")
const RUST := Color("815237")
const EDGE := Color("b4a58a")
const KINDS := ["generator","pump","transformer","relay_antenna","crane_hook","cargo_beacon"]

static func draw(canvas: Node2D,kind: String,tint: Color,accent: Color,time: float,phase: float,gust: float,origin: Vector2,motion: float) -> void:
	match kind:
		"generator": generator(canvas,tint,accent,time,phase,origin,motion)
		"pump": pump(canvas,tint,accent,time,phase,origin,motion)
		"transformer": transformer(canvas,tint,accent,time,phase,motion)
		"relay_antenna": antenna(canvas,tint,time,phase,gust,origin)
		"crane_hook": crane(canvas,tint,accent,time,phase,gust)
		"cargo_beacon": beacon(canvas,tint,accent,time,phase,motion)

static func line(c: Node2D,a: Vector2,b: Vector2,tint: Color,width: float=1.0) -> void:
	c.draw_line(a.round(),b.round(),tint,width,false)

static func disc(c: Node2D,at: Vector2,radius: float,tint: Color) -> void:
	var points:=PackedVector2Array()
	for i in 12: points.append((at+Vector2.from_angle(i*TAU/12)*radius).round())
	c.draw_colored_polygon(points,tint)

static func base(c: Node2D,width: float,tint: Color) -> void:
	Surface.face(c,Rect2(-width*.5,-6,width,6),tint.darkened(.2),3)
	for x in [-width*.5+4,width*.5-7]:
		c.draw_rect(Rect2(x,-3,3,2),INK)
		c.draw_rect(Rect2(x,-3,2,1),EDGE)

static func chips(c: Node2D,rect: Rect2,seed_value: int) -> void:
	for i in 9:
		var at:=rect.position+Vector2(posmod(i*17+seed_value,int(rect.size.x)),posmod(i*23+seed_value,int(rect.size.y)))
		c.draw_rect(Rect2(at.round(),Vector2(2+i%3,1+i%2)),RUST.darkened(.1*(i%3)))
		c.draw_rect(Rect2(at.round()+Vector2(0,1),Vector2.ONE),INK)

static func gauge(c: Node2D,at: Vector2,time: float,phase: float) -> void:
	disc(c,at,7,INK)
	disc(c,at,6,EDGE.darkened(.23))
	disc(c,at,4,Color("3c4438"))
	for angle in [-2.6,-1.5,-.4]: line(c,at+Vector2.from_angle(angle)*3,at+Vector2.from_angle(angle)*4,EDGE)
	line(c,at,at+Vector2.from_angle(-1.7+sin(time*.9+phase)*.35)*3,Color("d8be8c"))
	c.draw_rect(Rect2(at,Vector2.ONE),INK)

static func lamp(c: Node2D,at: Vector2,radius: float,color: Color,active: bool,brightness: float=1.0) -> void:
	disc(c,at,radius+2,INK)
	disc(c,at+Vector2(0,1),radius+1,Color("676c57"))
	disc(c,at,radius,color.darkened(.18 if active else .77))
	line(c,at+Vector2(-radius+1,-1),at+Vector2(radius-1,-1),color.darkened(.35 if active else .68))
	c.draw_rect(Rect2(at+Vector2(-1,-radius+1),Vector2(2,1)),color.lightened(.35) if active else EDGE.darkened(.55))
	if active:
		c.draw_rect(Rect2(at+Vector2(-1,-1),Vector2(2,2)),color.lightened(.45)*brightness)
		var glow:=Color(color,.13*brightness)
		c.draw_rect(Rect2(at-Vector2(radius+4,2),Vector2(radius*2+8,4)),glow)
		c.draw_rect(Rect2(at-Vector2(2,radius+4),Vector2(4,radius*2+8)),glow)

static func rail_signal(c: Node2D,tint: Color,time: float,phase: float) -> void:
	Surface.face(c,Rect2(-4,-112,8,108),tint.darkened(.32),2)
	line(c,Vector2(-2,-109),Vector2(-2,-7),EDGE.darkened(.4))
	Surface.face(c,Rect2(11,-111,5,57),tint.darkened(.53),4)
	Surface.panel(c,Rect2(-13,-111,25,56),tint.darkened(.23),5)
	chips(c,Rect2(-12,-109,23,52),7)
	var cycle:=fposmod(time*.55+phase,8.0)
	var active:=0 if cycle<4.0 else 1 if cycle<5.2 else 2
	for i in 3:
		var at:=Vector2(0,-101+i*17)
		lamp(c,at,4,[Color("bc663b"),Color("d9b466"),Color("90ad74")][i],i==active)
		Surface.face(c,Rect2(-9,at.y-8,18,3),tint.darkened(.42),i)
		line(c,Vector2(-9,at.y-5),Vector2(-7,at.y-2),INK,2)
		line(c,Vector2(8,at.y-5),Vector2(6,at.y-2),INK,2)
	Surface.panel(c,Rect2(-10,-28,20,20),tint.darkened(.15),1)
	for y in [-24,-20,-16]: line(c,Vector2(-6,y),Vector2(2,y),INK)
	c.draw_rect(Rect2(5,-22,2,4),RUST)
	base(c,28,tint)

static func cart(c: Node2D,tint: Color,accent: Color,time: float,phase: float,gust: float) -> void:
	for y in [-5,-1]: Surface.face(c,Rect2(-45,y,90,1),tint.darkened(.2),3)
	for x in [-37,-13,11,35]: Surface.face(c,Rect2(x,-4,5,4),RUST.darkened(.4),2)
	var wall:=PackedVector2Array([Vector2(-36,-39),Vector2(34,-39),Vector2(26,-12),Vector2(-28,-12)])
	c.draw_colored_polygon(wall,INK)
	Surface.polygon(c,PackedVector2Array([Vector2(-33,-37),Vector2(31,-37),Vector2(23,-14),Vector2(-25,-14)]),tint,4)
	for i in 7:
		var x:float=-29+i*8
		var top:float=-46-i%3*3
		var rock:=PackedVector2Array([Vector2(x,-37),Vector2(x+2,top),Vector2(x+8,top-1),Vector2(x+14,-38)])
		Surface.polygon(c,rock,tint.darkened(.38+(i%2)*.13),i)
		line(c,Vector2(x+2,top),Vector2(x+8,top-1),tint.lightened(.15))
		line(c,Vector2(x+7,top+3),Vector2(x+10,-39),INK)
	Surface.face(c,Rect2(-37,-39,74,4),tint.lightened(.1),1)
	for x in [-25,0,25]: Surface.face(c,Rect2(x,-35,3,20),tint.darkened(.16),2)
	Surface.panel(c,Rect2(-10,-30,19,10),accent.darkened(.34),4)
	for x in [-5,2]: line(c,Vector2(x,-29),Vector2(x+4,-24),INK,2)
	chips(c,Rect2(-28,-33,56,16),5)
	for x in [-22,20]:
		disc(c,Vector2(x,-8),7,INK)
		disc(c,Vector2(x,-8),5,tint.darkened(.27))
		disc(c,Vector2(x,-8),2,EDGE)
	var swing:=sin(time*1.7+phase)*gust*2
	line(c,Vector2(32,-34),Vector2(34+swing,-21),INK,3)
	for i in 4:
		c.draw_rect(Rect2(Vector2(32+swing*i/4,-33+i*3).round(),Vector2(3,2)),EDGE.darkened(.35))

static func bollard(c: Node2D,tint: Color,accent: Color,time: float,phase: float,gust: float) -> void:
	for x in [-34,34]:
		Surface.face(c,Rect2(x-9,-28,18,27),tint.darkened(.17),3)
		Surface.face(c,Rect2(x+4,-26,5,24),tint.darkened(.53),2)
		Surface.panel(c,Rect2(x-14,-30,28,6),tint,4)
		Surface.face(c,Rect2(x-12,-3,24,3),tint.darkened(.3),1)
		chips(c,Rect2(x-8,-23,13,18),3)
	var previous:=Vector2(-34,-24)
	for i in range(1,17):
		var t:=i/16.0
		var point:=Vector2(-34+68*t,-24+sin(t*PI)*(15+gust*3)).round()
		line(c,previous,point,INK,3)
		line(c,previous+Vector2(0,-1),point+Vector2(0,-1),accent.darkened(.1))
		c.draw_rect(Rect2(point-Vector2(1,1),Vector2(2,1)),EDGE.darkened(.26))
		previous=point
	var at:=Vector2(31+sin(time*1.2+phase)*gust,-17).round()
	disc(c,at,10,INK)
	disc(c,at,9,accent.darkened(.31))
	disc(c,at,5,INK)
	for y in [-8,6]: Surface.face(c,Rect2(at+Vector2(-2,y),Vector2(4,3)),EDGE,1)
	line(c,at+Vector2(-6,-5),at+Vector2(-7,3),accent.lightened(.12))

static func generator(c: Node2D,tint: Color,accent: Color,time: float,phase: float,origin: Vector2,motion: float) -> void:
	base(c,96,tint)
	Surface.face(c,Rect2(36,-52,8,46),tint.darkened(.42),2)
	Surface.panel(c,Rect2(-42,-52,78,45),tint,5)
	Surface.face(c,Rect2(-43,-56,88,5),tint.lightened(.06),3)
	for x in [-34,-29,-24,-19,-14]:
		c.draw_rect(Rect2(x,-42,3,22),INK)
		line(c,Vector2(x,-20),Vector2(x+2,-20),EDGE.darkened(.38))
	gauge(c,Vector2(7,-40),time,phase)
	lamp(c,Vector2(25,-40),2,Color("c9ac62"),sin(time*2+phase)>.2)
	Surface.panel(c,Rect2(0,-28,30,14),tint.darkened(.25),2)
	c.draw_rect(Rect2(3,-25,24,8),INK)
	var rotor:=Vector2(9,-21)
	c.draw_set_transform(origin+rotor,time*3.2+phase)
	line(c,Vector2(-5,0),Vector2(5,0),EDGE,2)
	line(c,Vector2(0,-5),Vector2(0,5),accent.darkened(.25),2)
	c.draw_set_transform(origin)
	line(c,Vector2(9,-21),Vector2(24,-21),Color("2a3026"),2)
	Surface.face(c,Rect2(28,-72,6,17),tint.darkened(.3),1)
	Surface.face(c,Rect2(23,-76,12,5),tint.darkened(.15),3)
	for i in 4:
		var age:=fposmod(time*.48+i*.25+phase,1)
		var at:=Vector2(28+sin(age*3+phase)*age*6,-78-age*12).round()
		c.draw_rect(Rect2(at,Vector2(3+age*3,2)),Color(.48,.47,.40,(1-age)*.18*motion))
	chips(c,Rect2(-39,-50,72,40),5)

static func pump(c: Node2D,tint: Color,accent: Color,time: float,phase: float,origin: Vector2,motion: float) -> void:
	base(c,88,tint)
	Surface.panel(c,Rect2(-20,-46,48,37),tint,3)
	Surface.face(c,Rect2(-42,-23,27,11),tint.darkened(.24),1)
	Surface.face(c,Rect2(25,-45,15,10),tint.darkened(.2),2)
	Surface.face(c,Rect2(33,-44,9,38),tint.darkened(.32),5)
	for x in [-32,-27]: Surface.panel(c,Rect2(x,-25,3,15),accent.darkened(.48),2)
	disc(c,Vector2(-4,-26),18,INK)
	disc(c,Vector2(-4,-26),16,tint.darkened(.12))
	c.draw_set_transform(origin+Vector2(-4,-26),time*1.5+phase)
	for i in 4:
		var angle:=i*PI*.5
		line(c,Vector2.from_angle(angle)*5,Vector2.from_angle(angle)*12,EDGE.darkened(.25),3)
	c.draw_set_transform(origin)
	disc(c,Vector2(-4,-26),5,INK)
	disc(c,Vector2(-4,-26),3,accent.darkened(.2))
	gauge(c,Vector2(19,-53),time,phase)
	line(c,Vector2(19,-46),Vector2(19,-38),INK,3)
	for i in 3:
		var age:=fposmod(time*.8+phase+i/3.0,1)
		c.draw_rect(Rect2(39,-34+age*age*25,1,2),Color(.63,.75,.72,(1-age)*.6*motion))
	chips(c,Rect2(-18,-43,42,32),3)

static func transformer(c: Node2D,tint: Color,accent: Color,time: float,phase: float,motion: float) -> void:
	base(c,80,tint)
	Surface.panel(c,Rect2(-29,-63,58,57),tint,3)
	Surface.face(c,Rect2(29,-60,8,53),tint.darkened(.35),2)
	for x in range(-22,23,6):
		Surface.face(c,Rect2(x,-47,4,33),tint.darkened(.13),x+3)
	for x in [-19,0,19]:
		line(c,Vector2(x,-84),Vector2(x,-62),INK,4)
		for i in 4:
			Surface.face(c,Rect2(x-5,-81+i*4,10,3),EDGE.darkened(.19+i*.03),i)
		line(c,Vector2(x,-85),Vector2(x+4,-88),RUST)
	Surface.panel(c,Rect2(-10,-61,20,10),accent.darkened(.25),2)
	line(c,Vector2(0,-59),Vector2(-3,-56),INK,2)
	line(c,Vector2(-3,-56),Vector2(2,-55),INK)
	lamp(c,Vector2(22,-55),2,Color("b7bc82"),sin(time*.8+phase)>.2,motion*.2+.8)
	chips(c,Rect2(-26,-61,51,50),5)

static func antenna(c: Node2D,tint: Color,time: float,phase: float,gust: float,origin: Vector2) -> void:
	base(c,58,tint)
	Surface.face(c,Rect2(-4,-85,8,80),tint.darkened(.12),3)
	Surface.panel(c,Rect2(-14,-30,28,24),tint,2)
	for y in [-23,-19,-15]: line(c,Vector2(-9,y),Vector2(3,y),INK)
	lamp(c,Vector2(8,-18),2,Color("be9b58"),sin(time*1.9+phase)>.6)
	var angle:=sin(time*.25+phase)*.18
	c.draw_set_transform(origin+Vector2(0,-79),angle)
	var shape:=PackedVector2Array([Vector2(-28,-10),Vector2(-21,10),Vector2(-10,18),Vector2(8,20),Vector2(24,11),Vector2(30,-7)])
	c.draw_colored_polygon(shape,INK)
	Surface.polygon(c,shape,tint,4)
	for x in [-21,-9,4,17]: line(c,Vector2(x,-6),Vector2(x*.65,12),tint.darkened(.36))
	line(c,Vector2(-25,-8),Vector2(27,-6),EDGE,2)
	line(c,Vector2(2,13),Vector2(11,-21),INK,3)
	c.draw_rect(Rect2(8,-24,7,5),EDGE.darkened(.1))
	c.draw_set_transform(origin)
	var previous:=Vector2(6,-56)
	for i in range(1,9):
		var point:=Vector2(6+sin(i*PI/8)*(8+gust),-56+i*4)
		line(c,previous,point,INK,2)
		previous=point

static func crane(c: Node2D,tint: Color,accent: Color,time: float,phase: float,gust: float) -> void:
	base(c,76,tint)
	Surface.face(c,Rect2(-24,-101,8,95),tint.darkened(.12),2)
	Surface.face(c,Rect2(-26,-104,70,7),tint,3)
	line(c,Vector2(-18,-73),Vector2(28,-97),INK,4)
	line(c,Vector2(-18,-73),Vector2(28,-97),EDGE.darkened(.37),2)
	Surface.panel(c,Rect2(-32,-41,24,29),tint.darkened(.14),5)
	Surface.face(c,Rect2(-30,-14,20,3),accent.darkened(.27),2)
	var hook:=Vector2(34+sin(time*.8+phase)*gust*3,-49)
	var previous:=Vector2(34,-97)
	for i in range(1,13):
		var point:=Vector2(34,-97).lerp(hook,i/12.0)
		line(c,previous,point,INK,3)
		c.draw_rect(Rect2(point.round()-Vector2(1,0),Vector2(2,2)),EDGE.darkened(.34))
		previous=point
	Surface.panel(c,Rect2(hook-Vector2(7,4),Vector2(14,12)),accent.darkened(.43),2)
	line(c,hook+Vector2(0,7),hook+Vector2(0,17),INK,5)
	line(c,hook+Vector2(0,17),hook+Vector2(-6,20),INK,5)
	line(c,hook+Vector2(-6,20),hook+Vector2(-10,15),INK,5)
	line(c,hook+Vector2(-10,15),hook+Vector2(-9,11),INK,4)
	line(c,hook+Vector2(-1,8),hook+Vector2(-1,17),EDGE,2)
	line(c,hook+Vector2(-1,17),hook+Vector2(-7,18),EDGE,2)
	chips(c,Rect2(-24,-94,7,72),4)

static func beacon(c: Node2D,tint: Color,accent: Color,time: float,phase: float,motion: float) -> void:
	base(c,66,tint)
	Surface.face(c,Rect2(-23,-48,47,41),tint,3)
	Surface.face(c,Rect2(24,-44,7,37),tint.darkened(.34),4)
	Surface.panel(c,Rect2(-25,-50,51,6),tint.lightened(.04),2)
	for x in [-17,13]: Surface.face(c,Rect2(x,-42,4,32),tint.darkened(.2),1)
	Surface.panel(c,Rect2(-10,-36,20,13),accent.darkened(.4),2)
	for x in [-5,2]: line(c,Vector2(x,-33),Vector2(x+4,-28),INK,2)
	Surface.face(c,Rect2(-4,-69,8,19),tint.darkened(.3),4)
	var brightness:=.6+.4*pow(maxf(0,sin(time*2.4+phase)),2)
	lamp(c,Vector2(0,-64),5,Color("d5a659"),true,brightness)
	for x in [-8,7]: line(c,Vector2(x,-72),Vector2(x,-56),INK,2)
	line(c,Vector2(-9,-73),Vector2(9,-73),EDGE.darkened(.2),2)
	for y in [-69,-58]: line(c,Vector2(-7,y),Vector2(7,y),INK)
	if motion>.3: c.draw_rect(Rect2(-2,-65,2,1),Color("f6d496")*brightness)
	chips(c,Rect2(-21,-42,43,32),7)
