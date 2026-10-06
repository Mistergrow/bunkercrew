class_name FlakStation
extends Node2D
## The bunker console builds and services one fixed anti-air tower. All paid
## contributions stay in its shared buffer; no free ammunition on upgrades.
const SPECS := {
	1:{"label":"Flakturm I", "wave":6, "cost":{"steel":3,"concrete":2,"ammo":1}, "time":2.5},
	2:{"label":"Flakturm II", "wave":11, "cost":{"steel":4,"glass":2}, "time":3.0},
	3:{"label":"Flakturm III", "wave":16, "cost":{"alloy":3,"glass":3}, "time":3.5},
}
const DefenseArt := preload("res://scripts/defense_structure_art.gd")
const GUN_POSITION := Vector2(530,35)
const PLATFORM := Rect2(474,35,112,12)
const ACCESS := Rect2(508,-5,44,435)
var gun_position := GUN_POSITION
var platform := PLATFORM
var access := ACCESS
var game: Node
var available := false
var built := false
var tier := 0
var turret: FlakTurret
var materials: Dictionary = {}
var transfer: Dictionary = {}
var construction := 0.0
var builder: Node2D

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("flak_stations")
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	z_index=6
	visible=false

func unlock() -> void:
	available=true
	visible=true
	queue_redraw()

func can_interact(_player: Node) -> bool:
	return available

func interaction_point() -> Vector2:
	return global_position-Vector2(0,24)

func next_spec() -> Dictionary:
	return SPECS[mini(3,tier+1)]

func _wave() -> int:
	return int(game.rounds.wave) if is_instance_valid(game) and "rounds" in game and is_instance_valid(game.rounds) else 1

func _upgrade_available() -> bool:
	return tier<3 and _wave()>=int(next_spec().wave)

func _maintenance(player: Node) -> String:
	if not built:
		return ""
	var selected: String=player.selected_material() if player.has_method("selected_material") else ""
	if turret.hp<turret.max_hp and (selected=="steel" or not _upgrade_available()) and int(player.inventory.get("steel",0))>0:
		return "repair"
	if AmmoTransfer.available(player) and turret.reserve<turret.reserve_capacity() and (selected=="ammo" or AmmoTransfer.remainder(player)>0 or not _upgrade_available()):
		return "ammo"
	return ""

func interaction_title() -> String:
	return LocaleText.text("Flaksteuerung")

func action_hint(player: Node) -> String:
	if not available or (not built and not _upgrade_available()):
		return LocaleText.text("Bauplan noch gesperrt")
	match _maintenance(player):
		"repair": return LocaleText.text("Flakturm reparieren")
		"ammo": return LocaleText.text("Munitionsreserve auffüllen")
	if built and turret.hp <= 0:
		return LocaleText.text("Stahl zur Reparatur mitbringen")
	if tier >= 3:
		return LocaleText.text("Vollständig ausgebaut")
	if not _upgrade_available():
		return LocaleText.format("Ausbau ab Welle %d", int(next_spec().wave))
	return LocaleText.text("Flakturm montieren") if _paid() else LocaleText.text("Baumaterial liefern")

func prompt(player: Node) -> String:
	var heading := interaction_title() + "\n"
	if not available:
		return heading + LocaleText.text("Flakturm ab Welle 6 verfügbar")
	if not built and not _upgrade_available():
		return heading + LocaleText.text("Baupause Welle 6\n3 Stahl + 2 Beton + 1 Munitionskiste\nStartmunition: 20 Schuss")
	var mode := _maintenance(player)
	var status := ""
	if built:
		status = LocaleText.format("Flakturm %s · %d/%d LP\n", [["", "I", "II", "III"][tier], ceili(turret.hp), ceili(turret.max_hp)])
		if mode == "repair":
			return heading + status + LocaleText.text("Halten: reparieren\n1 Stahl stellt 80 LP wieder her")
		if mode == "ammo":
			return heading + status + LocaleText.text("Halten: Reserve auffüllen\n1 Munitionskiste liefert 20 Schuss")
		if turret.hp <= 0:
			return heading + status + LocaleText.text("Außer Betrieb\nStahl auswählen und halten: reparieren")
		var ammunition := LocaleText.format("%d Schuss geladen · %d in Reserve", [turret.ammo, turret.reserve])
		if tier >= 3:
			return heading + status + ammunition + LocaleText.text("\nVollständig ausgebaut · Leiter zum Geschütz")
		if not _upgrade_available():
			return heading + status + ammunition + LocaleText.format("\nAusbau ab Welle %d · Leiter zum Geschütz", int(next_spec().wave))
	var spec := next_spec()
	var parts := PackedStringArray()
	for resource: String in spec.cost:
		parts.append(LocaleText.format("%s %d/%d", [Balance.RESOURCE_NAMES.get(resource, resource), materials.get(resource, 0), spec.cost[resource]]))
	var detail := LocaleText.text("Halten: montieren") if _paid() else LocaleText.text("Halten: Baumaterial liefern")
	var benefit := LocaleText.text("20 Schuss · automatische Luftabwehr") if tier == 0 else LocaleText.text("Mehr Schaden, Feuerrate und Magazinkapazität")
	return heading + LocaleText.format("%s · %s\n%s\n%s", [spec.label, detail, " · ".join(parts), benefit])

func interaction_progress(player: Node) -> float:
	if _paid() and _upgrade_available():
		return construction/float(next_spec().time)
	return float(transfer.get(player.player_id,0.0))/Balance.TRANSFER_TIME

func _paid() -> bool:
	if tier>=3: return false
	for kind: String in next_spec().cost:
		if int(materials.get(kind,0))<int(next_spec().cost[kind]): return false
	return true

func interact(player: Node2D,delta: float) -> void:
	if not is_instance_valid(player) or not is_finite(delta) or delta<=0 or not available or (player.has_method("can_act") and not player.can_act()):
		return
	var mode:=_maintenance(player)
	if mode!="":
		transfer[player.player_id]=float(transfer.get(player.player_id,0.0))+delta
		if float(transfer[player.player_id])>=Balance.TRANSFER_TIME:
			transfer[player.player_id]=0.0
			if mode=="repair": turret.repair(player)
			else: turret.accept_ammo(player)
		queue_redraw()
		return
	# The disabled-console prompt requires an explicit steel repair. An already
	# paid upgrade must not revive the gun or consume unrelated cargo here.
	if built and turret.hp<=0:
		return
	if not _upgrade_available(): return
	if _paid():
		construction+=delta
		if construction>=float(next_spec().time):
			_complete()
		queue_redraw()
		return
	var needed:=""
	for kind: String in next_spec().cost:
		if int(materials.get(kind,0))<int(next_spec().cost[kind]) and int(player.inventory.get(kind,0))>0:
			needed=kind
			break
	if needed.is_empty(): return
	transfer[player.player_id]=float(transfer.get(player.player_id,0.0))+delta
	if float(transfer[player.player_id])<Balance.TRANSFER_TIME: return
	transfer[player.player_id]=0.0
	if not player.take_item(needed,1): return
	materials[needed]=int(materials.get(needed,0))+1
	if not is_instance_valid(builder): builder=player
	if is_instance_valid(game): preload("res://scripts/spatial_sound.gd").emit(game,"interact",interaction_point())
	queue_redraw()

func _complete() -> void:
	tier+=1
	materials.clear()
	construction=0.0
	if not built:
		built=true
		if "scenario_bunker" in game and is_instance_valid(game.scenario_bunker):
			game.scenario_bunker.add_flak_passages(self)
		else:
			game.add_terrain(platform)
		game.ladders.append(access)
		if not game.floor_levels.has(35.0):
			game.floor_levels.append(35.0)
			game.floor_levels.sort()
		turret=preload("res://scripts/flak_turret.gd").new()
		turret.game=game
		turret.builder=builder
		game.add_child(turret)
		turret.global_position=gun_position
		turret.ammo=20
		turret.z_index=8
	else:
		turret.set_tier(tier)
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"build",interaction_point())
		game.notify(LocaleText.text("Flakturm I einsatzbereit · 20 Schuss · automatische Luftabwehr aktiv · Nachschub an der Flaksteuerung") if tier==1 else LocaleText.format("Flakturm %s ausgebaut · mehr Schaden, Feuerrate und Magazinkapazität", ["","I","II","III"][tier]))
	queue_redraw()

func _draw() -> void:
	# The engraved gun diagram identifies this roof console; its selected
	# title and exact construction/repair state belong in the action hint.
	DefenseArt.flak_console(self,tier,built,not built or turret.hp>0)
	if built:
		_draw_tower()

func _draw_tower() -> void:
	# World positions keep the shared mast aligned with its real platform and
	# ladder when the console moves independently onto the scenario roof.
	for side in [-1.0,1.0]:
		var world_x: float = gun_position.x+side*45
		DefenseArt.beam(self,to_local(Vector2(world_x,47)),to_local(Vector2(world_x,245)),10,2)
		for y in [64.0,125.0,186.0,237.0]:
			var joint := to_local(Vector2(world_x,y))
			DefenseArt.Surface.panel(self,Rect2(joint-Vector2(7,5),Vector2(14,10)),Color("424c43"),3)
		# The outer footprint ends at gun_x +/- 56, clear of roof supplies.
		DefenseArt.Surface.panel(self,Rect2(to_local(Vector2(world_x-11,239)),Vector2(22,6)),Color("69715e"),4)
	for y in [62.0,122.0,182.0]:
		DefenseArt.beam(self,to_local(Vector2(gun_position.x-41,y)),to_local(Vector2(gun_position.x+41,y+52)),6,1)
		DefenseArt.beam(self,to_local(Vector2(gun_position.x+41,y)),to_local(Vector2(gun_position.x-41,y+52)),4,3)
	var drawn_platform := Rect2(to_local(platform.position),platform.size)
	DefenseArt.Surface.panel(self,drawn_platform,Color("687162"),0)
	# Small worn warning blocks leave the platform's steel grain visible.
	for index in 7:
		var mark := drawn_platform.position+Vector2(7+index*15,3)
		draw_rect(Rect2(mark,Vector2(4,3)),Color("af9c6a"))
	for side in [-1.0,1.0]:
		var x: float = gun_position.x+side*12
		DefenseArt.beam(self,to_local(Vector2(x,15)),to_local(Vector2(x,access.end.y)),5,5)
	for y in range(20,int(access.end.y),14):
		var left := to_local(Vector2(gun_position.x-12,y))
		var right := to_local(Vector2(gun_position.x+12,y))
		DefenseArt.beam(self,left,right,3,1)
		draw_rect(Rect2(left+Vector2(2,-1),Vector2(5,1)),Color("b4a275"))
