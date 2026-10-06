extends RefCounted
const C=preload("res://scripts/perimeter_catalog.gd")

static func valid(state: Dictionary) -> bool:
	if state.get("role") not in C.VALID_ROLES or state.get("side") not in [-1,1]: return false
	if not state.get("slot_index") is int or state.slot_index<0 or state.slot_index>5: return false
	if state.role!=C.SITES[state.slot_index%C.SITES.size()].role: return false
	if not state.get("tier") is int or state.tier<0 or state.tier>C.max_tier(state.role): return false
	if not state.get("builder_player_id") is int or state.builder_player_id<0 or state.builder_player_id>PartyConfig.MAX_PLAYERS: return false
	if not state.get("burst_left") is int or state.burst_left<0 or state.burst_left>2: return false
	if state.role=="fence" and state.burst_left!=0: return false
	if not state.get("shot_serial") is int or state.shot_serial<0 or state.shot_serial>1000000000: return false
	for key in ["hp","max_hp","work","cure","gate_amount","cooldown","flash","recoil","hit_flash"]:
		if not (state.get(key) is int or state.get(key) is float) or not is_finite(float(state[key])) or state[key]<0: return false
	for key in ["ruined","gate_open"]:
		if not state.get(key) is bool: return false
	if state.tier==0:
		if state.hp!=0 or state.max_hp!=0 or state.cure!=0 or state.ammo!=0 or state.gate_amount!=0 or state.gate_open or state.burst_left!=0: return false
	else:
		var spec: Dictionary=C.spec(state.role,state.tier)
		if state.max_hp!=spec.hp or state.hp<=0 or state.hp>state.max_hp or state.ruined or state.cure>spec.cure: return false
	if state.gate_amount>1 or state.work>3.5 or state.cooldown>1.7 or state.flash>.1 or state.recoil>4 or state.hit_flash>.18: return false
	if not state.get("ammo") is int or state.ammo<0 or state.ammo>(0 if state.role=="fence" else C.GUNS[state.role].capacity): return false
	if state.role!="fence" and (state.gate_open or state.gate_amount!=0): return false
	if not state.get("aim_angle") is float or not is_finite(state.aim_angle) or absf(state.aim_angle)>TAU: return false
	if not state.get("materials") is Dictionary or not state.get("transfer") is Dictionary: return false
	var cost: Dictionary=C.spec(state.role,mini(C.max_tier(state.role),state.tier+1)).cost
	for key in state.materials:
		if not cost.has(key) or not state.materials[key] is int or state.materials[key]<0 or state.materials[key]>cost[key]: return false
	if state.tier==C.max_tier(state.role) and not state.materials.is_empty(): return false
	for key in state.transfer:
		if key not in ["1","2","3","4"] or not (state.transfer[key] is float or state.transfer[key] is int) or not is_finite(float(state.transfer[key])) or state.transfer[key]<0 or state.transfer[key]>C.TRANSFER_TIME: return false
	return true
