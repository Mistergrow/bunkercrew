extends RefCounted
## Authored buses are the listening baseline. Player sliders are relative to it.
## Never replace the live layout: private spatial buses and capture FX are live.
const Defaults:=preload("res://scripts/audio_defaults.gd")
const CHANNELS:=["Music","SFX","Voice"]
const FALLBACK_DB:={"Music":-9.11034656,"SFX":-6.02059991,"Voice":-14.89455}
const POLL_SECONDS:=.5
const MAX_LAYOUT_BYTES:=262144
const MAX_DEPENDENCIES:=64
const MAX_SOURCE_BYTES:=1048576
const AUTHORED_EFFECT_META:=&"bunkercrew_authored_bus_effect"
var baseline_db: Dictionary=FALLBACK_DB.duplicate()
var authored_flags: Dictionary={}
var layout_path: String
var source_hash: String
var watching:=false
var _last_poll_usec:=0
var _rejected_hash: String
var _accepted_channels: Array[String]=[]
var _validated_layout_hash: String
var _external_paths: Array[String]=[]

func setup(path: String) -> bool:
	layout_path=path
	source_hash=""
	_rejected_hash=""
	_validated_layout_hash=""
	_external_paths.clear()
	baseline_db=FALLBACK_DB.duplicate()
	_accepted_channels.clear()
	watching=OS.has_feature("editor") and OS.is_debug_build()
	_last_poll_usec=Time.get_ticks_usec()
	for channel: String in CHANNELS:
		authored_flags[channel]={"mute":false,"solo":false,"bypass_fx":false}
	return _reload()

func apply(channel: String,slider: float) -> bool:
	if not CHANNELS.has(channel) or not is_finite(slider): return false
	var index:=AudioServer.get_bus_index(channel)
	if index<0: return false
	var value:=clampf(slider,0,1)
	var reference_gain: float=Defaults.REFERENCE_GAINS[channel]
	var relative:=Defaults.channel_gain(channel,value)/reference_gain
	AudioServer.set_bus_volume_db(index,float(baseline_db[channel])+linear_to_db(maxf(relative,.0001)))
	var flags: Dictionary=authored_flags.get(channel,{})
	AudioServer.set_bus_mute(index,bool(flags.get("mute",false)) or value<=0)
	AudioServer.set_bus_solo(index,bool(flags.get("solo",false)))
	AudioServer.set_bus_bypass_effects(index,bool(flags.get("bypass_fx",false)))
	return true

func poll() -> bool:
	if not watching: return false
	var now:=Time.get_ticks_usec()
	if now-_last_poll_usec<int(POLL_SECONDS*1000000): return false
	_last_poll_usec=now
	return _reload()

func _reload() -> bool:
	if layout_path.ends_with(".res") and FileAccess.file_exists(layout_path):
		return _reload_packaged()
	var bytes:=_source_bytes()
	if bytes.is_empty():
		if FileAccess.file_exists(layout_path+".remap"): return _reload_packaged()
		return false
	var layout_hash:=_hash(bytes)
	if layout_hash==_rejected_hash: return false
	if layout_hash!=_validated_layout_hash:
		var text:=bytes.get_string_from_utf8()
		if not _safe_text(text):
			_rejected_hash=layout_hash
			return false
		_external_paths=_external_resources(text)
		if _external_paths.size()>MAX_DEPENDENCIES: return false
		_validated_layout_hash=layout_hash
	var sources: Dictionary={}
	var total:=bytes.size()
	for path: String in _external_paths:
		var content:=_read_bytes(path)
		if content.is_empty(): return false
		total+=content.size()
		if total>MAX_SOURCE_BYTES: return false
		sources[path]=content
	var candidate_hash:=layout_hash
	if not sources.is_empty():
		var digest:=HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(layout_hash.to_utf8_buffer())
		for path: String in sources:
			digest.update(path.to_utf8_buffer())
			digest.update(_hash(sources[path]).to_utf8_buffer())
		candidate_hash=digest.finish().hex_encode()
	if candidate_hash==source_hash or candidate_hash==_rejected_hash: return false
	for path: String in sources:
		if path.ends_with(".tres") and not _safe_text(PackedByteArray(sources[path]).get_string_from_utf8(),true):
			_rejected_hash=candidate_hash
			return false
	if not _sources_current(bytes,sources): return false
	var layout:=ResourceLoader.load(layout_path,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioBusLayout
	if layout==null: return false
	return _accept_layout(layout,candidate_hash,bytes,sources)

func _hash(bytes: PackedByteArray) -> String:
	var digest:=HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

func _external_resources(text: String) -> Array[String]:
	var declaration:=RegEx.new()
	declaration.compile('^\\[ext_resource [^\\n]*path="((?:[^"\\\\]|\\\\.)*)"[^\\n]*\\]$')
	var result: Array[String]=[]
	# Match the same whitespace/CRLF-normalized declarations as _safe_text.
	for raw: String in text.split("\n"):
		var entry:=declaration.search(raw.strip_edges())
		if entry!=null:
			var path: String=JSON.parse_string('"'+entry.get_string(1)+'"')
			if path not in result: result.append(path)
	result.sort()
	return result

func _sources_current(bytes: PackedByteArray,sources: Dictionary) -> bool:
	if _source_bytes()!=bytes: return false
	for path: String in sources:
		if _read_bytes(path)!=sources[path]: return false
	return true

func _reload_packaged() -> bool:
	# Exports convert .tres to remapped binary .res. FileAccess intentionally
	# cannot see the original text; ResourceLoader resolves the packaged graph.
	if not source_hash.is_empty() or not ResourceLoader.exists(layout_path,"AudioBusLayout"): return false
	var layout:=ResourceLoader.load(layout_path,"AudioBusLayout",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AudioBusLayout
	if layout==null: return false
	watching=false
	return _accept_layout(layout,"packaged:"+layout_path,PackedByteArray())

func _accept_layout(layout: AudioBusLayout,candidate_hash: String,bytes: PackedByteArray,sources: Dictionary={}) -> bool:
	var properties: Dictionary={}
	for entry in layout.get_property_list():
		var key:=str(entry.name)
		if key.begins_with("bus/"): properties[key]=layout.get(key)
	var updated_db: Dictionary=FALLBACK_DB.duplicate()
	var updated_flags: Dictionary={}
	var updated_effects: Dictionary={}
	var master: Dictionary={}
	var seen: Dictionary={}
	for key: String in properties:
		if not key.ends_with("/name"): continue
		var name:=str(properties[key])
		if name!="Master" and not CHANNELS.has(name): continue
		if seen.has(name): _rejected_hash=candidate_hash; return false
		seen[name]=true
		var prefix:=key.trim_suffix("name")
		var db: Variant=properties.get(prefix+"volume_db",0.0)
		if not (db is float or db is int) or not is_finite(float(db)): _rejected_hash=candidate_hash; return false
		var flags:={"mute":bool(properties.get(prefix+"mute",false)),"solo":bool(properties.get(prefix+"solo",false)),"bypass_fx":bool(properties.get(prefix+"bypass_fx",false))}
		var entries: Array[Dictionary]=[]
		for slot in 64:
			var effect: Variant=properties.get(prefix+"effect/%d/effect"%slot)
			if not effect is AudioEffect: continue
			entries.append({"effect":effect,"enabled":bool(properties.get(prefix+"effect/%d/enabled"%slot,true))})
		updated_effects[name]=entries
		if name=="Master":
			master={"db":float(db),"flags":flags,"pre_gain_db":0.0,"ceiling_db":-1.0}
			for field: String in properties:
				if not field.begins_with(prefix+"effect/") or not field.ends_with("/effect"): continue
				var effect: Variant=properties[field]
				if effect is AudioEffectHardLimiter:
					if not is_finite(effect.pre_gain_db) or not is_finite(effect.ceiling_db): _rejected_hash=candidate_hash; return false
					master.pre_gain_db=effect.pre_gain_db
					master.ceiling_db=minf(effect.ceiling_db,-1.0)
					break
		else:
			updated_db[name]=float(db)
			updated_flags[name]=flags
	# A file truncated at a complete line may still be syntactically valid.
	# During polling, retain previously present core buses rather than treating
	# that partial write as a fresh legacy Master-only layout.
	for channel: String in _accepted_channels:
		if not seen.has(channel): _rejected_hash=candidate_hash; return false
	if not bytes.is_empty() and not _sources_current(bytes,sources): return false
	for channel: String in CHANNELS:
		if not updated_flags.has(channel): updated_flags[channel]={"mute":false,"solo":false,"bypass_fx":false}
	baseline_db=updated_db
	authored_flags=updated_flags
	for channel: String in CHANNELS:
		_adopt_effects(channel,updated_effects.get(channel,[]),false)
	_adopt_effects("Master",updated_effects.get("Master",[]),bool(master.get("flags",{}).get("bypass_fx",false)))
	if not master.is_empty(): _apply_master(master)
	source_hash=candidate_hash
	_accepted_channels.assign(seen.keys())
	_rejected_hash=""
	return true

func _source_bytes() -> PackedByteArray:
	return _read_bytes(layout_path)

func _read_bytes(path: String) -> PackedByteArray:
	if path.is_empty() or not FileAccess.file_exists(path): return PackedByteArray()
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_LAYOUT_BYTES or file.get_length()<=0: return PackedByteArray()
	return file.get_buffer(file.get_length())

func _adopt_effects(channel: String,entries: Array,master_bypass: bool) -> void:
	var bus:=AudioServer.get_bus_index(channel)
	if bus<0: return
	var paths: Array[String]=[]
	for entry: Dictionary in entries:
		var path:=str(entry.effect.resource_path)
		if not path.is_empty(): paths.append(path)
	var remove: Array[int]=[]
	var insertion:=0
	for index in AudioServer.get_bus_effect_count(bus):
		var effect:=AudioServer.get_bus_effect(bus,index)
		if channel=="Master" and effect is AudioEffectHardLimiter: continue
		var owner: Variant=effect.get_meta(AUTHORED_EFFECT_META,{})
		var marked: bool=owner is Dictionary and owner.get("channel")==channel
		var path:=str(effect.resource_path)
		var from_source:=not path.is_empty() and (path.begins_with(layout_path+"::") or paths.has(path))
		if marked or from_source: remove.append(index)
	if not remove.is_empty(): insertion=remove[0]
	for index in range(remove.size()-1,-1,-1): AudioServer.remove_bus_effect(bus,remove[index])
	if channel=="Master":
		# Authored DSP always precedes the safety ceiling. Passive runtime capture
		# nodes and private effect objects remain present throughout a reload.
		for index in AudioServer.get_bus_effect_count(bus):
			if AudioServer.get_bus_effect(bus,index) is AudioEffectHardLimiter: insertion=mini(insertion,index);break
	for entry: Dictionary in entries:
		var source:=entry.effect as AudioEffect
		if channel=="Master" and source is AudioEffectHardLimiter: continue
		# A single external resource can be shared by several authored buses.
		# Per-bus copies keep ownership and live DSP instances independent.
		var effect:=source.duplicate(true) as AudioEffect
		effect.set_meta(AUTHORED_EFFECT_META,{"path":layout_path,"channel":channel})
		AudioServer.add_bus_effect(bus,effect,insertion)
		AudioServer.set_bus_effect_enabled(bus,insertion,bool(entry.enabled) and not (channel=="Master" and master_bypass))
		insertion+=1

func _apply_master(authored: Dictionary) -> void:
	var master:=AudioServer.get_bus_index("Master")
	if master<0: return
	var limiter: AudioEffectHardLimiter=null
	var limiter_index:=-1
	# Remove only accidental extra safety limiters, retaining every private FX.
	for index in range(AudioServer.get_bus_effect_count(master)-1,-1,-1):
		var effect:=AudioServer.get_bus_effect(master,index)
		if not effect is AudioEffectHardLimiter: continue
		if limiter!=null: AudioServer.remove_bus_effect(master,limiter_index)
		limiter=effect
		limiter_index=index
	if limiter==null:
		limiter=AudioEffectHardLimiter.new()
		limiter.resource_name="BunkercrewOutputCeiling"
		AudioServer.add_bus_effect(master,limiter)
		limiter_index=AudioServer.get_bus_effect_count(master)-1
	limiter.pre_gain_db=float(authored.pre_gain_db)+float(authored.db)
	limiter.ceiling_db=minf(float(authored.ceiling_db),-1.0)
	AudioServer.set_bus_effect_enabled(master,limiter_index,true)
	AudioServer.set_bus_bypass_effects(master,false)
	AudioServer.set_bus_volume_db(master,0.0)
	AudioServer.set_bus_mute(master,bool(authored.flags.mute))
	AudioServer.set_bus_solo(master,bool(authored.flags.solo))

func _safe_text(text: String,effect_resource: bool=false) -> bool:
	# Godot's loader reports parser errors even on recoverable incomplete saves.
	# Validate native editor bus files before loading. Unknown/custom serialization
	# conservatively leaves the last good mix intact instead of logging every poll.
	var numbers:=RegEx.new()
	numbers.compile("^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$")
	var attrs_pattern:=RegEx.new()
	attrs_pattern.compile('([A-Za-z_]+)=("(?:[^"\\\\]|\\\\.)*"|[0-9]+)')
	var bus_pattern:=RegEx.new()
	bus_pattern.compile("^bus/([0-9]+)/(name|send|solo|mute|bypass_fx|volume_db|effect/([0-9]+)/(effect|enabled))$")
	var reference_pattern:=RegEx.new()
	reference_pattern.compile('^(SubResource|ExtResource)\\(("(?:[^"\\\\]|\\\\.)*")\\)$')
	var declarations: Dictionary={}
	var current: AudioEffect=null
	var current_properties: Dictionary={}
	var section:=""
	var main_seen:=false
	var header_seen:=false
	for raw: String in text.split("\n"):
		var line:=raw.strip_edges()
		if line.is_empty() or line.begins_with(";"): continue
		if line.begins_with("["):
			if not line.ends_with("]") or main_seen: return false
			var body:=line.substr(1,line.length()-2)
			var split:=body.find(" ")
			section=body if split<0 else body.left(split)
			var attributes: Dictionary={}
			var attributes_text:="" if split<0 else body.substr(split+1)
			var end:=0
			for match_value in attrs_pattern.search_all(attributes_text):
				if not attributes_text.substr(end,match_value.get_start()-end).strip_edges().is_empty(): return false
				var parsed:=_scalar(match_value.get_string(2),numbers)
				if not parsed.ok: return false
				attributes[match_value.get_string(1)]=parsed.value
				end=match_value.get_end()
			if not attributes_text.substr(end).strip_edges().is_empty(): return false
			if not header_seen:
				if section!="gd_resource" or int(attributes.get("format",0)) not in [2,3]: return false
				var type:=str(attributes.get("type",""))
				if effect_resource:
					if not ClassDB.class_exists(type) or not ClassDB.can_instantiate(type) or not ClassDB.is_parent_class(type,"AudioEffect"): return false
					current=ClassDB.instantiate(type) as AudioEffect
					for property in current.get_property_list(): current_properties[str(property.name)]=int(property.type)
				elif type!="AudioBusLayout": return false
				header_seen=true
			elif effect_resource and section!="resource": return false
			elif section=="sub_resource":
				var type:=str(attributes.get("type",""))
				var id:=str(attributes.get("id",""))
				if id.is_empty() or declarations.has("SubResource:"+id) or not ClassDB.class_exists(type) or not ClassDB.can_instantiate(type) or not ClassDB.is_parent_class(type,"AudioEffect"): return false
				current=ClassDB.instantiate(type) as AudioEffect
				current_properties={}
				for property in current.get_property_list(): current_properties[str(property.name)]=int(property.type)
				declarations["SubResource:"+id]=true
			elif section=="ext_resource":
				var id:=str(attributes.get("id",""))
				var path:=str(attributes.get("path",""))
				var type:=str(attributes.get("type",""))
				if id.is_empty() or declarations.has("ExtResource:"+id) or not ClassDB.class_exists(type) or not ClassDB.is_parent_class(type,"AudioEffect") or not ResourceLoader.exists(path,type): return false
				declarations["ExtResource:"+id]=true
			elif section=="resource":
				if not attributes.is_empty(): return false
				main_seen=true
			else: return false
			continue
		var equals:=line.find(" = ")
		if equals<1: return false
		var key:=line.left(equals)
		var literal:=line.substr(equals+3)
		var scalar:=_scalar(literal,numbers)
		var resource_reference:=reference_pattern.search(literal)
		if not scalar.ok and resource_reference==null: return false
		if resource_reference!=null:
			var id:=_scalar(resource_reference.get_string(2),numbers)
			if not id.ok or not declarations.has(resource_reference.get_string(1)+":"+str(id.value)): return false
		if section=="sub_resource" or effect_resource:
			if not current_properties.has(key) or resource_reference!=null: return false
			var expected:=int(current_properties[key])
			var actual:=typeof(scalar.value)
			if expected==TYPE_FLOAT:
				if actual not in [TYPE_INT,TYPE_FLOAT]: return false
			elif expected in [TYPE_STRING,TYPE_STRING_NAME]:
				if actual!=TYPE_STRING: return false
			elif actual!=expected: return false
		elif section=="resource":
			var bus:=bus_pattern.search(key)
			if bus==null or int(bus.get_string(1))>63 or (not bus.get_string(3).is_empty() and int(bus.get_string(3))>63): return false
			var field:=bus.get_string(2)
			if field.ends_with("/effect"):
				if resource_reference==null and scalar.value!=null: return false
			elif resource_reference!=null: return false
			elif field in ["name","send"]:
				if not scalar.value is String: return false
			elif field=="volume_db":
				if not (scalar.value is int or scalar.value is float): return false
			elif not scalar.value is bool: return false
		else: return false
	return header_seen and main_seen

func _scalar(literal: String,numbers: RegEx) -> Dictionary:
	if literal=="true": return {"ok":true,"value":true}
	if literal=="false": return {"ok":true,"value":false}
	if literal=="null": return {"ok":true,"value":null}
	if numbers.search(literal)!=null:
		var number:=literal.to_float()
		if not literal.contains(".") and not literal.to_lower().contains("e"):
			if literal.trim_prefix("+").trim_prefix("-").length()>18: return {"ok":false,"value":null}
			return {"ok":true,"value":literal.to_int()}
		return {"ok":is_finite(number),"value":number}
	var value:=literal.substr(1) if literal.begins_with('&"') else literal
	if value.begins_with('"'):
		var json:=JSON.new()
		if json.parse(value)==OK and json.data is String: return {"ok":true,"value":json.data}
	return {"ok":false,"value":null}
