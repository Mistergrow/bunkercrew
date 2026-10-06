extends RefCounted
## Contact-centered damage remains in the rock after the worker lets go.
## No floating cell outline; the interaction HUD owns the progress indicator.
const INK := Color("171b17")
const EDGE := Color("736e58")

static func fractures(canvas: Node2D, contact: Vector2, work: float, kind: String, cell: Vector2i) -> void:
	var progress := clampf(work,0,1)
	if progress <= 0: return
	var at := contact.clamp(Vector2(-22,-22),Vector2(22,22)).round()
	var inward := -at.normalized() if at.length_squared() > 1 else Vector2.RIGHT
	var along := inward.orthogonal()
	var depth := 3.0 + floorf(progress*22.0)
	var seed_value := posmod(cell.x*31+cell.y*17,11)
	# Small chipped facets expose darker recesses behind the existing minerals.
	var chip := PackedVector2Array()
	for point in [at-along*3,at+inward*3-along*4,at+inward*(5+progress*4)+along,at+inward*2+along*4]:
		chip.append(Vector2(point).clamp(Vector2(-23,-23),Vector2(23,23)).round())
	canvas.draw_colored_polygon(chip,Color("22251f"))
	var highlight := EDGE if kind != "limestone" else Color("939180")
	for branch in 3:
		if progress < branch*0.23: continue
		var axis := inward.rotated((branch-1)*0.63)
		var points := PackedVector2Array([at])
		for step in range(1,5):
			var distance := depth*step*.25
			var offset := float(posmod(seed_value+branch*7+step*5,5)-2)
			points.append((at+axis*distance+axis.orthogonal()*offset).clamp(Vector2(-23,-23),Vector2(23,23)).round())
		canvas.draw_polyline(points,INK,2 if progress>.60 else 1)
		for index in range(1,points.size()):
			if (index+branch)%2==0:
				canvas.draw_line(points[index-1]+Vector2(0,-1),points[index]+Vector2(0,-1),Color(highlight,.55),1)
