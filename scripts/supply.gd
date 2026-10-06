class_name Supply
extends Node2D

const NetInput = preload("res://scripts/network_input.gd")
const InputLabels := preload("res://scripts/input_labels.gd")
const CrateArt = preload("res://scripts/supply_art.gd")
const Storage = preload("res://scripts/medic_storage.gd")
@export var kind: String = "ammo"
@export var amount: int = 12
var game
var transfer: Dictionary = {}
# Stable player IDs also make this progress readable on the guest's replica.
var deposit_transfer: Dictionary = {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_to_group("interactables")
	add_to_group("supplies")
	queue_redraw()

func authoritative() -> bool:
	var session=NetInput.for_game(game)
	return session==null or session.is_host

func _physics_process(delta: float) -> void:
	if not authoritative(): return
	Storage.refill(self)
	if not is_instance_valid(game) or not "players" in game or ("started" in game and not game.started):
		return
	for player in game.players:
		if not is_instance_valid(player):
			continue
		var id: int = player.player_id
		if player.focus != self or NetInput.is_pressed(player,"interact") or not NetInput.is_pressed(player,"craft_next"):
			deposit_transfer.erase(id)
			continue
		var speed: float = player.work_multiplier() if player.has_method("work_multiplier") else 1.0
		deposit(player,delta*speed)

func interaction_point() -> Vector2:
	return global_position + Vector2(0, -20)

func can_interact(player) -> bool:
	# Empty crates remain available for new deliveries.
	return _transfer_reachable(player)

func interaction_title() -> String:
	return LocaleText.format("Vorrat · %s", Balance.RESOURCE_NAMES.get(kind, kind))

func action_hint(player) -> String:
	if _selected_deposit(player):
		return LocaleText.text("Material einlagern") if Storage.can_deposit(self) else LocaleText.text("Lager voll · Material aufnehmen")
	if amount <= 0:
		return LocaleText.text("Leer · passendes Material einlagern")
	return LocaleText.text("Inventar voll") if player.carried_count() >= Balance.capacity_for(player) else LocaleText.text("Material aufnehmen")

func controls_hint(player) -> String:
	var actions := PackedStringArray()
	if kind=="ammo" and amount>0:
		actions.append(LocaleText.format("%s: Waffenreserve auffüllen", InputLabels.action(player, "reload")))
	if amount>0 and player.carried_count()<Balance.capacity_for(player):
		actions.append(LocaleText.format("%s halten: aufnehmen", InputLabels.action(player, "interact")))
	if Storage.can_deposit(self) and _selected_deposit(player):
		actions.append(LocaleText.format("%s halten: einlagern", InputLabels.action(player, "craft_next")))
	elif Storage.can_deposit(self) and int(player.inventory.get(kind,0))>0:
		actions.append(LocaleText.format("%s: %s auswählen", [InputLabels.action(player, "cycle_material"),Balance.RESOURCE_NAMES.get(kind,kind)]))
	if not actions.is_empty():
		return " · ".join(actions)
	return LocaleText.text("Inventarplatz freimachen") if player.carried_count()>=Balance.capacity_for(player) else LocaleText.text("Passendes Material mitbringen")

func prompt(player) -> String:
	var heading := interaction_title() + "\n"
	var stock := LocaleText.format("%s gelagert", Balance.resource_quantity(kind, amount))
	var details := PackedStringArray([stock])
	if kind=="ammo": details.append(LocaleText.text("Nachladen am Vorrat füllt die Waffenreserve direkt. Angebrochene Kisten bleiben erhalten."))
	if amount <= 0:
		details.append(LocaleText.text("Kiste leer · kann wieder befüllt werden"))
	elif not Storage.can_deposit(self):
		details.append(LocaleText.text("Lager voll · Material aufnehmen"))
	elif player.carried_count() >= Balance.capacity_for(player):
		details.append(LocaleText.text("Inventar voll · erst Material einlagern oder abgeben"))
	if _selected_deposit(player):
		details.append(LocaleText.format("%s im Inventar · zum Einlagern ausgewählt", Balance.resource_quantity(kind,int(player.inventory.get(kind,0)))))
	else:
		details.append(LocaleText.format("Hier lässt sich %s einlagern", Balance.RESOURCE_NAMES.get(kind,kind)))
	# Material kind remains an explicit catalog/map selector, never display text.
	var reserve:=int(Storage.visible_reserve(game).get(kind,0))
	if reserve>0:
		details.append(LocaleText.format("%s Lagerreserve · wird beim Entnehmen nachgefüllt",Balance.resource_quantity(kind,reserve)))
	return heading + "\n".join(details)

func interaction_progress(player) -> float:
	var deposited: float = deposit_transfer.get(int(player.player_id),0.0) if "player_id" in player else 0.0
	if deposited > 0.0:
		return clampf(deposited/Balance.TRANSFER_TIME,0.0,1.0)
	return float(transfer.get(_transfer_key(player), 0.0)) / Balance.TRANSFER_TIME

func _transfer_key(player) -> int:
	return int(player.player_id) if "player_id" in player else player.get_instance_id()

func _selected_deposit(player) -> bool:
	return is_instance_valid(player) and player.has_method("selected_material") and player.selected_material()==kind and int(player.inventory.get(kind,0))>0

func _transfer_reachable(player) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(player) or not player is Node2D or player.is_queued_for_deletion() or not player.is_inside_tree():
		return false
	if player.get("game")!=game or player.get_world_2d()!=get_world_2d():
		return false
	if player.has_method("can_act") and not player.can_act():
		return false
	var center: Vector2 = player.global_position-Vector2(0,20)
	var point := interaction_point()
	if absf(center.y-point.y)>68.0 or center.distance_to(point)>83.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(center,point,1|2)
	query.hit_from_inside = true
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func deposit(player, delta: float) -> void:
	if not authoritative(): return
	if not is_finite(delta) or delta<=0.0 or not is_instance_valid(player) or not "player_id" in player:
		return
	var id: int = player.player_id
	if "mounted_turret" in player and is_instance_valid(player.mounted_turret):
		deposit_transfer.erase(id)
		return
	if not Storage.can_deposit(self) or not _selected_deposit(player) or not _transfer_reachable(player):
		deposit_transfer.erase(id)
		return
	transfer.erase(_transfer_key(player))
	deposit_transfer[id] = minf(Balance.TRANSFER_TIME,float(deposit_transfer.get(id,0.0))+delta)
	if float(deposit_transfer[id]) < Balance.TRANSFER_TIME:
		return
	deposit_transfer.erase(id)
	# Debit first; a failed transaction must never create a stored resource.
	if not player.take_item(kind,1):
		return
	# All checks and the debit run on the authority's main thread. A reserved
	# warehouse may receive a returned unit without exceeding the visible cap.
	if not Storage.store_unit(self):
		player.add_item(kind,1)
		return
	if "last_transfer_kind" in player:
		player.last_transfer_kind = kind
	if "drop_animation" in player:
		player.drop_animation = 0.36
	if is_instance_valid(game):
		preload("res://scripts/spatial_sound.gd").emit(game,"pickup",global_position)
	queue_redraw()

func interact(player, delta: float) -> void:
	if not authoritative(): return
	if not is_finite(delta) or delta<=0.0 or not can_interact(player):
		return
	Storage.refill(self)
	if "player_id" in player:
		deposit_transfer.erase(int(player.player_id))
	if amount <= 0 or player.carried_count() >= Balance.capacity_for(player):
		return
	var id := _transfer_key(player)
	transfer[id] = float(transfer.get(id, 0.0)) + delta
	if transfer[id] >= Balance.TRANSFER_TIME:
		transfer[id] = 0.0
		var added: int = player.add_item(kind, 1)
		amount -= added
		Storage.refill(self)
		if added > 0 and is_instance_valid(game):
			preload("res://scripts/spatial_sound.gd").emit(game,"pickup",global_position)
		queue_redraw()

func _draw() -> void:
	var tint: Color = Balance.RESOURCE_COLORS.get(kind, Art.AMBER)
	CrateArt.draw(self,kind,amount)
	UiArt.world_label(self, Vector2(0, -60), Balance.RESOURCE_NAMES.get(kind, kind), LocaleText.format("%d verfügbar", amount) if amount > 0 else LocaleText.text("Leer"), tint if amount > 0 else Art.MUTED, 78.0)
