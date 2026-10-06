extends RefCounted
## Fixed-size PCM speech frames. No external codec or executable is needed.
const RATE := 16000
const FRAMES := 320
const BYTES := FRAMES * 2

static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	if samples.size()!=FRAMES: return PackedByteArray()
	var data:=PackedByteArray()
	data.resize(BYTES)
	for i in FRAMES:
		if not is_finite(samples[i]): return PackedByteArray()
		data.encode_s16(i*2,roundi(clampf(samples[i],-1.0,1.0)*32767.0))
	return data

static func decode(data: PackedByteArray) -> PackedVector2Array:
	if data.size()!=BYTES: return PackedVector2Array()
	var samples:=PackedVector2Array()
	samples.resize(FRAMES)
	for i in FRAMES:
		var value:=clampf(float(data.decode_s16(i*2))/32767.0,-1.0,1.0)
		samples[i]=Vector2(value,value)
	return samples

static func valid(message: Dictionary) -> bool:
	if message.size() not in [5,6,7]: return false
	for key in message:
		if key not in ["kind", "seq", "generation", "rate", "pcm", "player_id", "member_key"]: return false
	if message.has("member_key") and (not message.has("player_id") or not message.member_key is String or message.member_key.length()!=48 or not message.member_key.is_valid_hex_number(false)): return false
	if message.has("player_id") and (not message.player_id is int or message.player_id<1 or message.player_id>4): return false
	return message.get("kind")=="voice" and message.get("seq") is int and message.seq>0 and message.seq<9007199254740991 and message.get("generation") is int and message.generation>=0 and message.get("rate")==RATE and message.rate is int and message.get("pcm") is PackedByteArray and message.pcm.size()==BYTES
