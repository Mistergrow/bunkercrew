class_name BunkerCore
extends Node2D
const DamageArt := preload("res://scripts/structure_damage_art.gd")

var game
var hp: float = Balance.CORE_HP
var max_hp: float = Balance.CORE_HP
var elapsed: float = 0.0
var repair_work: float = 0.0
var hit_flash: float = 0.0

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("core")

func _process(delta: float) -> void:
	elapsed += delta
	hit_flash = maxf(0,hit_flash-delta)
	queue_redraw()

func interaction_point() -> Vector2:
	return global_position + Vector2(0,-30)

func impact_sound() -> String:
	# Resolved projectile/machine contacts and direct damage share this bank.
	# Keep the core's dry steel strike separate from generic resonant metal hits.
	return "impact_core"

func interaction_title() -> String:
	if _outpost(): return LocaleText.text(str(CampaignCatalog.objective(game.campaign.pending_node).title))
	return LocaleText.text("Bunkerkern")

func prompt(_player) -> String:
	if _outpost(): return game.expedition.outpost_prompt()
	if hp <= 0:
		return LocaleText.text("Bunkerkern\nZerstört · Schicht verloren")
	if hp >= max_hp:
		return LocaleText.text("Bunkerkern\nIntakt · vor Angriffen schützen")
	return LocaleText.format("Bunkerkern\n%d/%d LP · Reparatur: +%d LP\n1 Stahl oder 1 Schrott mitbringen · halten", [ceili(hp),int(max_hp),int(repair_amount())])

func interaction_progress(_player) -> float:
	return repair_work

func interact(player, delta: float) -> void:
	if not is_instance_valid(player) or not is_finite(delta) or delta <= 0.0:
		return
	if _outpost():
		game.expedition.secure_outpost(player,delta)
		return
	if hp <= 0 or hp >= max_hp:
		return
	var resource: String = "steel" if int(player.inventory.get("steel",0)) > 0 else "scrap"
	if int(player.inventory.get(resource,0)) <= 0:
		return
	var rate: float = game.upgrades.repair_multiplier() if is_instance_valid(game) and is_instance_valid(game.get("upgrades")) and game.upgrades.has_method("repair_multiplier") else 1.0
	repair_work += delta * rate / Balance.CORE_REPAIR_TIME
	if repair_work >= 1.0:
		repair_work = 0.0
		if player.take_item(resource,1):
			var repaired := minf(max_hp-hp,repair_amount())
			hp += repaired
			var events = game.get("combat_events") if is_instance_valid(game) else null
			if is_instance_valid(events) and events.has_method("record_role"): events.record_role(player,"repair",repaired*0.06)
			if is_instance_valid(game):
				preload("res://scripts/spatial_sound.gd").emit(game,"build",global_position)
				game.fx(global_position+Vector2(0,-35),Art.CYAN,6)

func take_damage(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0 or hp <= 0:
		return
	var multiplier: float = game.upgrades.core_damage_multiplier() if is_instance_valid(game) and is_instance_valid(game.get("upgrades")) and game.upgrades.has_method("core_damage_multiplier") else 1.0
	var previous_hp:=hp
	hp = maxf(0,hp-amount*multiplier)
	if hp<previous_hp: set_meta("achievement_core_damaged",true)
	hit_flash = 0.15
	if is_instance_valid(game):
		if get_meta("impact_contact_frame", -1) != Engine.get_physics_frames():
			ImpactBurst.emit(game, global_position + Vector2(28,-33), "metal", Vector2.RIGHT, 0.9)
			preload("res://scripts/spatial_sound.gd").emit(game,impact_sound(),global_position)
		if hp <= 0:
			ImpactBurst.emit(game, global_position + Vector2(0,-36), "explosion", Vector2.UP, 1.5)
			game.on_core_destroyed()

func _draw() -> void:
	draw_rect(Rect2(-43,-4,91,6),Color(0,0,0,0.38))
	var tint := Color("ffd0ab") if hit_flash>0 else Color.WHITE
	if hp<=0: tint=Color("55574e")
	MachineryArt.paint(self,"core",Rect2(-43,-100,90,100),tint)
	DamageArt.core(self, hp, max_hp)
	var pulse := 0.8+sin(elapsed*2.4)*0.14
	if hp>0:
		for r in range(4,0,-1):
			draw_circle(Vector2(-10,-33),r*12,Color(1.0,0.60,0.25,0.018*pulse))
		draw_rect(Rect2(16,-60,15,13),Color("30392e"))
		draw_polyline(PackedVector2Array([Vector2(17,-54),Vector2(20,-54),Vector2(22,-58),Vector2(24,-50),Vector2(27,-54),Vector2(30,-54)]),Color("c1c992") if hp>max_hp*0.4 else Art.RED,1)
		var scan_y := DamageArt.monitor_scan_y(elapsed)
		draw_line(Vector2(17,scan_y),Vector2(30,scan_y),Color(0.66,0.73,0.49,0.4),1)
	UiArt.world_label(self,Vector2(0,-123),interaction_title(),LocaleText.text("Intakt") if hp>=max_hp else LocaleText.format("%d/%d LP", [ceili(hp),int(max_hp)]),UiArt.MUTED if hp>=max_hp else UiArt.RED)
	if hp<max_hp:
		Art.bar(self,Rect2(-40,-103,80,3),hp/max_hp,Art.RED)

func repair_amount() -> float:
	return Balance.CORE_REPAIR * CampaignBonus.repair_multiplier(game)

func _outpost() -> bool:
	return is_instance_valid(game) and "expedition" in game and is_instance_valid(game.expedition) and game.expedition.outpost_pending()
