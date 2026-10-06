extends RefCounted
## Validate control envelopes before touching session state or allocating a world.
const Voice := preload("res://scripts/voice_codec.gd")
const Chat := preload("res://scripts/network_chat.gd")
const MAX_SEQUENCE := 9007199254740991

static func integer(value: Variant, minimum: int=0, maximum: int=MAX_SEQUENCE) -> bool:
	return value is int and value>=minimum and value<=maximum

static func string_value(value: Variant, maximum: int) -> bool:
	return value is String and value.length()<=maximum

static func valid_content_fingerprint(value: Variant) -> bool:
	if not value is String or value.length()!=64: return false
	for digit in value:
		if digit not in "0123456789abcdef": return false
	return true

static func valid(message: Dictionary, host: bool) -> bool:
	# Hello/Welcome negotiate the world rules before any campaign is allocated.
	# Old envelopes still reach the session's clear version rejection.
	var maximum := 16
	if message.get("kind") == "welcome":
		if message.get("voice_member_keys") == true: maximum += 1
		if message.has("world_revision"): maximum += 1
		if message.has("content_fingerprint"): maximum += 1
	if message.size()>maximum or not string_value(message.get("kind"),24): return false
	if message.has("voice_member_keys") and not message.voice_member_keys is bool: return false
	if message.has("world_revision") and not integer(message.world_revision,1,255): return false
	if message.has("content_fingerprint") and (message.get("kind") not in ["hello","welcome"] or not valid_content_fingerprint(message.content_fingerprint)): return false
	var kind:String=message.kind
	if host and kind not in ["hello","command","ready","input","snapshot_ack","resync","pause","ping","pong","leave","voice","chat_send","chat_private_send","chat_name","crew_identity","crew_preferences"]: return false
	if not host and kind not in ["welcome","reject","lobby","start","snapshot","pause","ping","pong","notice","effects","leave","voice","chat_message","chat_history","chat_ack"]: return false
	match kind:
		"hello":
			return integer(message.get("version"),1,255) and string_value(message.get("build"),64) and string_value(message.get("resume"),48) and string_value(message.get("invite",""),NetworkJoinCode.SECRET_SYMBOLS) and Chat.valid_name(message.get("name",""),true)
		"welcome":
			return integer(message.get("version"),1,255) and string_value(message.get("build"),64) and string_value(message.get("token"),48) and str(message.token).length()==48 and integer(message.get("player_id",2),2,4) and _lobby(message)
		"reject": return string_value(message.get("message"),240)
		"lobby": return _lobby(message)
		"start":
			if not integer(message.get("count",2),2,4) or not _lobby(message) or not integer(message.get("generation"),1) or not message.get("reset") is bool: return false
			if message.has("expedition"):
				if not preload("res://scripts/expedition_controller.gd").valid_transition(message.expedition): return false
				if message.expedition.options!=message.options or message.expedition.checkpoint.player_count!=int(message.get("count",2)) or message.expedition.checkpoint.character_ids!=message.characters: return false
			return true
		"resync": return integer(message.get("generation"),1)
		"ready": return integer(message.get("generation"),1)
		"snapshot_ack": return integer(message.get("generation"),1) and integer(message.get("seq"),1)
		"input": return integer(message.get("generation"),1) and integer(message.get("seq"),1) and message.get("input") is Dictionary and message.input.size()<=5
		"command": return integer(message.get("generation")) and _command(message)
		"snapshot":
			if message.has("music") and (not message.music is Dictionary or not preload("res://scripts/live_music.gd").valid_music_state(message.music)): return false
			return integer(message.get("generation"),1) and integer(message.get("seq"),1) and message.get("paused") is bool and message.get("world") is Dictionary and message.get("achievements",[]) is Array and message.get("achievements",[]).size()<=64
		"pause": return integer(message.get("generation"),1) and message.get("paused") is bool
		"ping","pong":
			var at=message.get("at")
			return (at is int or at is float) and is_finite(float(at)) and at>=0 and at<1.0e12
		"notice": return LocaleText.valid_message_payload(message.get("message"))
		"effects": return integer(message.get("generation"),1) and message.get("events") is Array and message.events.size()<=64
		"voice": return Voice.valid(message)
		"chat_send": return message.size()==4 and integer(message.get("request"),1) and Chat.valid_content(message.get("text"),message.get("preset"))
		"chat_private_send": return message.size()==4 and integer(message.get("request"),1) and integer(message.get("recipient_id"),1,4) and Chat.valid_text(message.get("text"))
		"crew_identity": return message.size()==2 and message.get("identity") is Dictionary and (message.identity.is_empty() or preload("res://scripts/network_social.gd").valid_identity(message.identity))
		"crew_preferences":
			if message.size()!=2 or not message.get("blocked") is Array or message.blocked.size()>3: return false
			var seen: Array=[]
			for slot in message.blocked:
				if not integer(slot,1,4) or slot in seen: return false
				seen.append(slot)
			return true
		"chat_name": return message.size()==2 and Chat.valid_name(message.get("name"),true)
		"chat_message": return message.size()==2 and Chat.valid_row(message.get("message"))
		"chat_history": return message.size()==2 and Chat.valid_history(message.get("messages"))
		"chat_ack": return message.size()==4 and integer(message.get("request"),1) and message.get("accepted") is bool and message.get("error_code") is String and ((message.accepted and message.error_code.is_empty()) or (not message.accepted and message.error_code in Chat.ERRORS))
		"leave": return message.size()==1
	return false

static func _command(message: Dictionary) -> bool:
	if not string_value(message.get("command"),24) or not message.get("args") is Dictionary: return false
	var args:Dictionary=message.args
	match message.command:
		"character","skill","upgrade":
			if not string_value(args.get("id"),64): return false
			for field in args:
				if field not in ["id","player_id"]: return false
			return not args.has("player_id") or integer(args.player_id,1,4)
		"restart","skip_build": return args.is_empty()
		"craft": return args.size()==2 and args.get("action") in ["supply","collect"] and CraftingCatalog.valid_reference(args.get("recipe"))
		"expedition":
			return args.size()==2 and args.get("action") is String and args.get("data") is Dictionary and preload("res://scripts/expedition_controller.gd").valid_command(args.action,args.data)
	return false

static func _lobby(message: Dictionary) -> bool:
	if not message.get("short_code", "") is String or (not str(message.get("short_code", "")).is_empty() and not preload("res://scripts/social_hub.gd").valid_room_alias(message.short_code)): return false
	if message.has("members"):
		if not message.members is Dictionary or message.members.size()>4: return false
		for slot in message.members:
			if not slot is String or slot not in ["1","2","3","4"] or not message.members[slot] is String or message.members[slot].length()!=48 or not message.members[slot].is_valid_hex_number(false): return false
	if message.has("social_service") and (not message.social_service is String or (not message.social_service.is_empty() and preload("res://scripts/social_hub.gd").normalize_url(message.social_service) != message.social_service)): return false
	if message.has("identities"):
		if not message.identities is Dictionary or message.identities.size()>4: return false
		for slot in message.identities:
			if not slot is String or slot not in ["1","2","3","4"] or not preload("res://scripts/network_social.gd").valid_identity(message.identities[slot]): return false
	if not message.get("characters") is Array or message.characters.size() not in [2,3,4]: return false
	var count=message.get("count",2)
	var capacity=message.get("capacity",4)
	if not integer(count,1,4) or not integer(capacity,2,4) or count>capacity or count>message.characters.size(): return false
	if message.has("player_id") and not integer(message.player_id,2,4): return false
	if message.has("slots"):
		if not message.slots is Array or (message.slots.size()>count if message.kind=="start" else message.slots.size()!=count) or not 1 in message.slots: return false
		var seen: Array=[]
		for slot in message.slots:
			if not integer(slot,1,4) or slot in seen: return false
			seen.append(slot)
		if message.has("player_id") and not message.player_id in seen: return false
	if message.has("names"):
		if not message.names is Dictionary or message.names.size()>4: return false
		for slot in message.names:
			if not slot is String or slot not in ["1","2","3","4"] or not Chat.valid_name(message.names[slot]): return false
	for id in message.characters:
		if not id is String or not CharacterCatalog.contains(id): return false
	if not message.get("options") is Dictionary or message.options.size()!=3 or not message.get("story") is bool: return false
	for field in ["environment","build_type","position"]:
		if not message.options.get(field) is String: return false
	return ScenarioCatalog.validate(message.options)==message.options
