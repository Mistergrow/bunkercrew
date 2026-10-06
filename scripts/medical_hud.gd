class_name MedicalHud
extends RefCounted
## Small readable field-dressing and trauma marks in the game's steel/olive palette.
static func status(canvas: CanvasItem, worker, at: Vector2) -> void:
	var medical: WorkerMedical = worker.medical
	if medical.incapacitated():
		canvas.draw_rect(Rect2(at,Vector2(2,25)),UiArt.RED)
	for index in MedicalCatalog.MAX_CHARGES:
		var pos := at+Vector2(11+index*19,8)
		var available := index<medical.charges
		canvas.draw_rect(Rect2(pos-Vector2.ONE,Vector2(15,10)),Color("233538"))
		canvas.draw_rect(Rect2(pos,Vector2(13,8)),Color("b8b79b") if available else Color("3d443e"))
		canvas.draw_rect(Rect2(pos+Vector2(4,1),Vector2(5,6)),Color("ded5b4") if available else Color("596057"))
		for dx in [1,10]:
			canvas.draw_rect(Rect2(pos+Vector2(dx,3),Vector2(2,2)),Color("6d725f"))
	var message := medical.status_text()
	if is_instance_valid(medical.aid_target):
		message = LocaleText.format("HILFE · %d%%", roundi(medical.aid_progress*100))
	elif medical.incapacitated():
		message = LocaleText.text("KRITISCH · Partner: 8s wiederbeleben") if medical.state=="critical" else LocaleText.text("BEWUSSTLOS · Partner: 5s wiederbeleben")
	elif medical.bleeding==0 and not medical.fractured:
		message = LocaleText.format("%s · %d Verbände%s", [LocaleText.text("VERLETZT") if worker.hp<worker.max_hp-0.01 else LocaleText.text("ERSTE HILFE"),medical.charges,LocaleText.text(" · am Kern auffüllen") if medical.charges<2 else ""])
	UiArt.text(canvas,at+Vector2(54,17),message,10,UiArt.RED if medical.bleeding>0 or medical.incapacitated() else UiArt.MUTED)
	if medical.fractured:
		# A bound splint, not a floating hospital symbol.
		canvas.draw_rect(Rect2(at+Vector2(508,5),Vector2(4,16)),Color("9d8057"))
		for y in [8,15]: canvas.draw_rect(Rect2(at+Vector2(505,y),Vector2(10,3)),Color("cbc4a5"))

static func brief_status(worker: Node) -> String:
	var medical = worker.medical
	if is_instance_valid(medical.aid_target):
		return LocaleText.format("HILFE · %d%%",roundi(medical.aid_progress*100))
	if medical.incapacitated():
		return LocaleText.text("KRITISCH · Partner: 8s wiederbeleben") if medical.state=="critical" else LocaleText.text("BEWUSSTLOS · Partner: 5s wiederbeleben")
	if medical.bleeding>0 or medical.fractured: return medical.status_text()
	return ""
