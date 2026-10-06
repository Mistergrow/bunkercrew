extends RefCounted
## Optional platform adapter. Request acceptance never counts as server storage.
signal changed
const Catalog := preload("res://scripts/achievement_catalog.gd")
const RETRY_SECONDS := 60.0
const STORE_TIMEOUT := 25.0
var pending: Dictionary={}
var confirmed: Dictionary={}
var provider: Object
var inflight: Array[String]=[]
var token:=0
var wait_left:=0.0
var retry_left:=0.0

func enqueue(local_id: String) -> void:
	var name:=Catalog.steam_id(local_id)
	if name.is_empty() or confirmed.has(name) or pending.has(name): return
	pending[name]=true
	changed.emit()

func set_provider(candidate: Object) -> bool:
	if is_instance_valid(provider) and provider.has_signal("achievements_stored") and provider.achievements_stored.is_connected(_stored):
		provider.achievements_stored.disconnect(_stored)
	provider=null
	inflight.clear()
	if candidate==null: return true
	if not candidate.has_method("achievement_ready") or not candidate.has_method("store_achievements") or not candidate.has_signal("achievements_stored"): return false
	provider=candidate
	provider.achievements_stored.connect(_stored)
	retry_left=0
	return true

func advance(delta: float) -> void:
	if not is_finite(delta) or delta<=0: return
	if not inflight.is_empty():
		wait_left-=delta
		if wait_left<=0:
			inflight.clear()
			retry_left=RETRY_SECONDS
		return
	retry_left=maxf(0,retry_left-delta)
	if retry_left>0 or pending.is_empty() or not is_instance_valid(provider) or not provider.achievement_ready(): return
	for entry in Catalog.ENTRIES:
		if pending.has(entry.steam): inflight.append(entry.steam)
	token+=1
	wait_left=STORE_TIMEOUT
	var accepted: bool=provider.store_achievements(inflight.duplicate(),token)
	if not accepted:
		inflight.clear()
		retry_left=RETRY_SECONDS

func _stored(received_token: int, success: bool) -> void:
	if received_token!=token or inflight.is_empty(): return
	if success:
		for id in inflight:
			pending.erase(id)
			confirmed[id]=true
	inflight.clear()
	retry_left=RETRY_SECONDS
	changed.emit()
