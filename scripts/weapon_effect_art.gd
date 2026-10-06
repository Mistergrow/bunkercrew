class_name WeaponEffectArt
extends RefCounted
## Shared pixel silhouettes for the actual articulated weapon mouths. These
## helpers only draw: recoil, ammunition and swept damage stay with each gun.

static func reduced(game: Node) -> bool:
	return is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects

static func recover_recoil(value: float, delta: float, rate: float = 18.0) -> float:
	var remaining := maxf(0.0,value)*exp(-maxf(0.0,delta)*rate)
	return 0.0 if remaining<0.04 else remaining

static func muzzle(node: CanvasItem, tip: Vector2, remaining: float, duration: float, facing: float = 1.0, strength: float = 1.0, tick: int = 0, quiet: bool = false, electric: bool = false) -> void:
	if remaining<=0 or duration<=0: return
	var life := clampf(remaining/duration,0,1)
	# A hot compact ignition, then a longer ochre tongue and a quick decay.
	# Integer vertices keep the irregular silhouette crisp at native resolution.
	var growth := 0.52+sin((1.0-life)*PI)*0.48
	var reach := (20.0+float(tick%3)*5.0)*strength*growth*(0.62 if quiet else 1.0)
	var width := (3.0+3.0*life)*sqrt(strength)*(0.65 if quiet else 1.0)
	var amber := Color("abbed8") if electric else Color("e8994e")
	var hot := Color("e0f6f0") if electric else Color("fff0b9")
	var alpha := smoothstep(0.0,0.42,life)
	var points := PackedVector2Array()
	for point: Vector2 in [Vector2(-1,-width*.48),Vector2(reach*.29,-width),Vector2(reach*.23,-width*.18),Vector2(reach,0),Vector2(reach*.37,width*.2),Vector2(reach*.43,width*.81),Vector2(-1,width*.5)]:
		points.append((tip+point*Vector2(facing,1)).round())
	node.draw_colored_polygon(points,Color(amber,alpha))
	node.draw_line(tip.round(),(tip+Vector2(facing*reach*.64,0)).round(),Color(hot,alpha),2 if strength<1.5 else 3,false)
	if not quiet:
		node.draw_circle(tip,11.0*strength,Color(amber,0.05*life))
		if life>0.68:
			node.draw_rect(Rect2((tip-Vector2(2,2)).round(),Vector2(4,4)),Color(hot,(life-.68)*2.0))

static func tracer(node: CanvasItem, direction: Vector2, length: float, quiet: bool = false, heavy: bool = false) -> void:
	if length<=0.0: return
	var tail := -direction*length
	if not quiet:
		node.draw_line(tail.round(),Vector2.ZERO,Color(0.94,0.53,0.23,0.10),5 if heavy else 3,false)
	node.draw_line((tail*.82).round(),Vector2.ZERO,Color("e8b16e"),2 if heavy else 1,false)
	node.draw_line((-direction*minf(length,8.0)).round(),Vector2.ZERO,Color("fff1c1"),2 if heavy else 1,false)
