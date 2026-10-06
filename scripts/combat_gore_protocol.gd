extends RefCounted
## Small cosmetic descriptions only; resource names and executable data never cross the wire.
const FIELDS=["material","point","direction","strength","part","joint","tip","character","front","facing","player_id"]

static func valid_data(data: Dictionary) -> bool:
	if data.size()!=FIELDS.size(): return false
	for field in FIELDS:
		if not data.has(field): return false
	if data.material not in ["flesh","oil"] or not data.character is String: return false
	if data.character!="infantry" and not CharacterCatalog.contains(data.character): return false
	for field in ["point","direction","joint","tip"]:
		if not data[field] is Vector2 or not data[field].is_finite() or absf(data[field].x)>32768 or absf(data[field].y)>32768: return false
	if data.direction.length_squared()>1.021: return false
	if not (data.strength is float or data.strength is int) or not is_finite(float(data.strength)) or data.strength<.2 or data.strength>2.0: return false
	if not data.part is int or data.part not in [0,1,2,4,8]: return false
	if not data.front is bool or not (data.facing is float or data.facing is int) or (float(data.facing)!=-1.0 and float(data.facing)!=1.0): return false
	if not data.player_id is int or data.player_id not in [0,1,2,3,4]: return false
	if (data.player_id==0)!=(data.character=="infantry"): return false
	if data.material=="oil" and (data.part!=0 or data.player_id!=0): return false
	if data.part==0:
		if data.joint!=data.point or data.tip!=data.point or data.front: return false
	else:
		if data.front!=(data.part in [2,8]) or data.joint.distance_to(data.tip)>70 or data.joint.distance_to(data.point)>160: return false
	return true

static func valid_event(payload: Dictionary) -> bool:
	if payload.size()!=3 or not payload.get("serial") is int or payload.serial<1 or payload.serial>1000000000: return false
	if not payload.get("actor") is String or not payload.get("data") is Dictionary or not valid_data(payload.data): return false
	if payload.data.player_id>0: return payload.actor=="player:%d"%payload.data.player_id
	if not payload.actor.begins_with("dynamic:"): return false
	var number: String=payload.actor.trim_prefix("dynamic:")
	return number.is_valid_int() and number.to_int()>0 and number.to_int()<=1000000000 and str(number.to_int())==number
