extends RefCounted
## A room identity is verified against the same authenticated social service.
## Only a short-lived, link-scoped HMAC travels through the game transport.
const Hub := preload("res://scripts/social_hub.gd")
var session
var identities: Dictionary = {}
var member_keys: Dictionary = {}
var verified: Dictionary = {}
var pending: Dictionary = {}
var rejected: Dictionary = {}
var _name_refresh_slots: Dictionary = {}
var muted: Dictionary = {}
var blocked: Dictionary = {}
var _hub: Node
var _host_context := ""
var _local_identity: Dictionary = {}
var _identity_pending := false
var _serial := 0
var _retry_at := 0.0
var _last_preferences: Array = []

static func valid_identity(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 4: return false
	for key in ["code", "service", "context", "proof"]:
		if not value.get(key) is String: return false
	return Hub.valid_code(value.code) and Hub.compact_code(value.code) == value.code and Hub.normalize_url(value.service) == value.service and value.context.length() == 48 and value.context == value.context.to_lower() and value.context.is_valid_hex_number(false) and value.proof.length() == 64 and value.proof == value.proof.to_lower() and value.proof.is_valid_hex_number(false)

func refresh(hub: Node) -> void:
	for request in pending.keys():
		if session._clock >= float(pending[request].get("deadline", 0.0)): pending.erase(request)
	if _hub != hub:
		if is_instance_valid(_hub) and _hub.crew_identity_verified.is_connected(_verified): _hub.crew_identity_verified.disconnect(_verified)
		_hub = hub
		if is_instance_valid(_hub): _hub.crew_identity_verified.connect(_verified)
	if not session.active or not is_instance_valid(_hub): return
	if _host_context.is_empty(): _host_context = Crypto.new().generate_random_bytes(24).hex_encode()
	var context: String = _host_context if session.is_host else str(session._client_token).sha256_text().left(48)
	if not session.is_host and session._client_token.is_empty(): context = ""
	var identity: Dictionary = _hub.crew_identity(context)
	if identity != _local_identity:
		_local_identity = identity
		if session.is_host:
			identities.erase("1")
			verified.erase(1)
			if not identity.is_empty():
				identities["1"] = identity
				verified[1] = {"code":identity.code, "name":_hub.display_name}
			session._send_lobby()
		else:
			_identity_pending = true
			verified.erase(session.local_player_id)
			if not identity.is_empty(): verified[session.local_player_id] = {"code":identity.code, "name":_hub.display_name}
	if not session.is_host and session._authenticated and _identity_pending:
		if session._send({"kind":"crew_identity", "identity":_local_identity}, true): _identity_pending = false
	for slot in range(1, 5): sync_voice(slot)
	preferences()
	if _hub.connection_state != "online": return
	if session._clock < _retry_at: return
	_retry_at = session._clock + 2.0
	for slot in _name_refresh_slots.keys(): refresh_name(int(slot))
	for slot_key in identities:
		var slot := int(slot_key)
		if slot == session.local_player_id or verified.has(slot) or rejected.get(slot) == identities[slot_key] or pending.values().any(func(item): return item.slot == slot): continue
		var claim: Dictionary = identities[slot_key]
		if claim.service != _hub.server_url: continue
		_serial += 1
		var request := "%d:%d" % [session.get_instance_id(), _serial]
		if _hub.verify_crew_identity(claim, request): pending[request] = {"slot":slot, "identity":claim.duplicate(true), "deadline":session._clock + 8.5}

func accept(slot: int, identity: Dictionary) -> void:
	identities.erase(str(slot))
	verified.erase(slot)
	rejected.erase(slot)
	_name_refresh_slots.erase(slot)
	if not identity.is_empty(): identities[str(slot)] = identity.duplicate(true)
	for request in pending.keys():
		if int(pending[request].slot) == slot: pending.erase(request)
	_retry_at = 0.0
	session.changed.emit()

func refresh_name(slot: int) -> void:
	if slot < 1 or slot > 4 or slot == session.local_player_id: return
	_name_refresh_slots[slot] = true
	if not is_instance_valid(_hub) or _hub.connection_state != "online" or not identities.has(str(slot)): return
	if slot == session.local_player_id or pending.values().any(func(item): return int(item.slot) == slot): return
	_serial += 1
	var request := "%d:%d" % [session.get_instance_id(), _serial]
	var claim: Dictionary = identities[str(slot)]
	if _hub.verify_crew_identity(claim, request): pending[request] = {"slot":slot, "identity":claim.duplicate(true), "deadline":session._clock + 8.5}

func apply_roster(roster: Dictionary, members: Dictionary = {}) -> void:
	var remapped_mutes: Dictionary = {}
	var remapped_blocks: Dictionary = {}
	for old_slot in range(1, 5):
		var old_key: String = str(member_keys.get(str(old_slot), ""))
		var next_slot := old_slot
		if not old_key.is_empty():
			next_slot = 0
			for new_key in members:
				if members[new_key] == old_key: next_slot = int(new_key); break
		if next_slot > 0:
			if muted.has(old_slot): remapped_mutes[next_slot] = true
			if blocked.has(old_slot): remapped_blocks[next_slot] = true
	muted = remapped_mutes
	blocked = remapped_blocks
	member_keys = members.duplicate()
	for slot in verified.keys():
		if identities.get(str(slot), {}) != roster.get(str(slot), {}): verified.erase(slot)
	identities = roster.duplicate(true)
	for request in pending.keys():
		var item: Dictionary = pending[request]
		if identities.get(str(item.slot), {}) != item.identity: pending.erase(request)
	_retry_at = 0.0
	for slot in range(1, 5): sync_voice(slot)

func remap_slots(mapping: Dictionary) -> void:
	for field in ["identities", "verified", "rejected", "muted", "blocked", "member_keys", "_name_refresh_slots"]:
		var source: Dictionary = get(field)
		var replacement: Dictionary = {}
		for old_key in source:
			var old_slot := int(old_key)
			if old_slot != 1 and not mapping.has(old_slot): continue
			var next_slot := 1 if old_slot == 1 else int(mapping[old_slot])
			var next_key: Variant = next_slot
			if field in ["identities", "member_keys"]: next_key = str(next_slot)
			replacement[next_key] = source[old_key]
		set(field, replacement)
	for request in pending.keys():
		var slot := int(pending[request].slot)
		if mapping.has(slot): pending[request].slot = mapping[slot]
		else: pending.erase(request)
	for slot in range(1, 5): sync_voice(slot)

func remove_member(slot: int) -> void:
	identities.erase(str(slot))
	member_keys.erase(str(slot))
	verified.erase(slot)
	rejected.erase(slot)
	_name_refresh_slots.erase(slot)
	muted.erase(slot)
	blocked.erase(slot)
	sync_voice(slot)

func _verified(request: String, result: Dictionary) -> void:
	var item: Dictionary = pending.get(request, {})
	if item.is_empty(): return
	pending.erase(request)
	var slot := int(item.slot)
	if identities.get(str(slot), {}) != item.identity: return
	if bool(result.get("valid", false)) and result.code == item.identity.code:
		verified[slot] = {"code":result.code, "name":result.name}
		_name_refresh_slots.erase(slot)
		sync_voice(slot)
		if session.is_host: session._send_lobby()
		session.changed.emit()
	elif result.get("code") == item.identity.code:
		rejected[slot] = item.identity.duplicate(true)
		session.changed.emit()

func crew_members() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not session.active: return result
	var slots: Array = [1] + session._slots.keys() if session.is_host else session._connected_slots.duplicate()
	slots.sort()
	for slot_value in slots:
		var slot := int(slot_value)
		var claim: Dictionary = _local_identity if slot == session.local_player_id else identities.get(str(slot), {})
		var confirmed: Dictionary = verified.get(slot, {})
		if slot == session.local_player_id and is_instance_valid(_hub) and _hub.connection_state == "online" and not claim.is_empty(): confirmed = {"code":_hub.friend_code, "name":_hub.display_name}
		var name_value: String = str(session.chat_names.get(str(slot), "P%d" % slot))
		if not confirmed.is_empty(): name_value = str(confirmed.name)
		if is_instance_valid(_hub) and not confirmed.is_empty():
			if slot == session.local_player_id: name_value = str(_hub.display_name)
			else:
				for friend in _hub.friends:
					if friend.code == confirmed.code: name_value = str(friend.name); break
		var character := ""
		var identity_status := "verified"
		if confirmed.is_empty():
			identity_status = "unavailable" if claim.is_empty() else "pending"
			if not is_instance_valid(_hub) or _hub.connection_state != "online": identity_status = "service_offline"
			elif not claim.is_empty() and claim.service != _hub.server_url: identity_status = "other_service"
			elif rejected.get(slot) == claim: identity_status = "unverified"
		if is_instance_valid(session.game) and slot <= session.game.selected_characters.size(): character = str(session.game.selected_characters[slot - 1])
		result.append({"player_id":slot, "member_key":str(member_keys.get(str(slot), "")), "name":name_value, "character_id":character, "friend_code":str(confirmed.get("code", "")), "friend_service":str(claim.get("service", "")), "identity_status":identity_status, "identity_pending":identity_status == "pending", "is_local":slot == session.local_player_id, "is_host":slot == 1, "connected":session.is_player_connected(slot)})
	return result

func is_blocked(slot: int) -> bool:
	if blocked.has(slot): return true
	if is_instance_valid(_hub) and verified.has(slot):
		return _hub.blocked.any(func(entry): return entry.code == verified[slot].code)
	return false

func set_muted(slot: int, value: bool) -> bool:
	if slot < 1 or slot > 4 or slot == session.local_player_id: return false
	if value: muted[slot] = true
	else: muted.erase(slot)
	sync_voice(slot)
	session.changed.emit()
	return true

func set_blocked(slot: int, value: bool) -> bool:
	if slot < 1 or slot > 4 or slot == session.local_player_id: return false
	if is_instance_valid(_hub) and _hub.connection_state == "online" and verified.has(slot):
		var success: bool = _hub.block_friend(verified[slot].code) if value else _hub.unblock_friend(verified[slot].code)
		if not success: return false
	if value: blocked[slot] = true
	else: blocked.erase(slot)
	sync_voice(slot)
	session._refresh_chat_history()
	preferences()
	session.changed.emit()
	return true

func preferences() -> void:
	if not session.active or session.is_host or not session._authenticated: return
	var slots: Array = []
	for slot in range(1, 5):
		if is_blocked(slot): slots.append(slot)
	if slots == _last_preferences: return
	if session._send({"kind":"crew_preferences", "blocked":slots}, true): _last_preferences = slots.duplicate()

func sync_voice(slot: int) -> void:
	if is_instance_valid(session.game) and is_instance_valid(session.game.get("voice")) and session.game.voice.has_method("set_sender_muted"):
		session.game.voice.set_sender_muted(slot, muted.has(slot) or is_blocked(slot))

func clear() -> void:
	if is_instance_valid(_hub) and _hub.crew_identity_verified.is_connected(_verified): _hub.crew_identity_verified.disconnect(_verified)
	_hub = null
	identities.clear()
	member_keys.clear()
	verified.clear()
	pending.clear()
	rejected.clear()
	_name_refresh_slots.clear()
	muted.clear()
	blocked.clear()
	_host_context = ""
	_local_identity.clear()
	_identity_pending = false
	_last_preferences.clear()
	if is_instance_valid(session.game) and is_instance_valid(session.game.get("voice")) and session.game.voice.has_method("clear_sender_mutes"): session.game.voice.clear_sender_mutes()
