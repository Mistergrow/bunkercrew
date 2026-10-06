class_name NetworkJoinCode
extends RefCounted
## Address codes work without a central lookup service. Every complete invitation
## includes a random secret authenticated by discovery and NetworkSession.

const SECRET_SYMBOLS := 16 # 80 random bits for authenticated LAN discovery.
const DEFAULT_PORT := 24777
const ALPHABET := "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

static func new_invitation() -> String:
	var secret:=""
	for value in Crypto.new().generate_random_bytes(SECRET_SYMBOLS): secret+=ALPHABET[value & 31]
	return secret

static func compact(value: String) -> String:
	return value.strip_edges().to_upper().replace("-", "").replace(" ", "")

static func is_lan_code(value: String) -> bool:
	var code := compact(value)
	if code.length() != SECRET_SYMBOLS: return false
	for character in code:
		if character not in ALPHABET: return false
	return true

static func lan(secret: String) -> String:
	return _groups(compact(secret)) if is_lan_code(secret) else ""

static func invite(address: String, port: int, secret: String) -> String:
	var base:=encode(address,port)
	if base.is_empty() or not is_lan_code(secret): return ""
	return base+"-"+_groups(compact(secret))

static func encode(address: String, port: int = DEFAULT_PORT) -> String:
	var octets := _octets(address)
	if octets.size() != 4 or port < 1 or port > 65535:
		return ""
	var number := 0
	for octet in octets:
		number = (number << 8) | octet
	var count := 8
	if port == DEFAULT_PORT:
		number = (number << 8) | _checksum(octets)
	else:
		octets.append((port >> 8) & 255)
		octets.append(port & 255)
		number = (((number << 16) | port) << 7) | _checksum(octets, 7)
		count = 11
	var result := ""
	for index in count:
		result = ALPHABET[number & 31] + result
		number >>= 5
	return _groups(result)

static func decode(value: String) -> Dictionary:
	var code := compact(value)
	if code.length() in [8+SECRET_SYMBOLS,11+SECRET_SYMBOLS]:
		var secret:=code.right(SECRET_SYMBOLS)
		for character in secret:
			if character not in ALPHABET: return {"ok":false,"error":"Im Beitrittscode steht ein ungültiges Zeichen."}
		var decoded:=decode(code.left(code.length()-SECRET_SYMBOLS))
		if decoded.get("ok",false):
			decoded.invite=secret
			decoded.code=invite(decoded.address,decoded.port,secret)
		return decoded
	if code.length() not in [8, 11]:
		return {"ok":false, "error":"Bitte den vollständigen Beitrittscode eingeben."}
	var number := 0
	for character in code:
		var digit := ALPHABET.find(character)
		if digit < 0:
			return {"ok":false, "error":"Im Beitrittscode steht ein ungültiges Zeichen."}
		number = (number << 5) | digit
	var extended := code.length() == 11
	var checksum := number & (127 if extended else 255)
	number >>= 7 if extended else 8
	var port := DEFAULT_PORT
	if extended:
		port = number & 65535
		number >>= 16
	var octets := PackedInt32Array()
	for shift in [24, 16, 8, 0]:
		octets.append((number >> shift) & 255)
	var address := "%d.%d.%d.%d" % [octets[0], octets[1], octets[2], octets[3]]
	if extended:
		octets.append((port >> 8) & 255)
		octets.append(port & 255)
	if _checksum(octets, 7 if extended else 8) != checksum or port == 0:
		return {"ok":false, "error":"Der Beitrittscode enthält einen Tippfehler. Bitte erneut prüfen."}
	if octets[0] == 0 or octets[0] >= 224:
		return {"ok":false, "error":"Dieser Beitrittscode enthält keine erreichbare Rechneradresse."}
	return {"ok":true, "address":address, "port":port, "scope":"public" if is_public_address(address) else "lan", "code":encode(address,port)}

static func is_public_address(address: String) -> bool:
	var a := _octets(address)
	if a.size() != 4:
		return false
	if a[0] in [0, 10, 127] or a[0] >= 224:
		return false
	if a[0] == 100 and a[1] >= 64 and a[1] <= 127:
		return false # Shared carrier-grade NAT range.
	if a[0] == 169 and a[1] == 254:
		return false
	if a[0] == 172 and a[1] >= 16 and a[1] <= 31:
		return false
	if a[0] == 192 and (a[1] == 168 or (a[1] == 0 and a[2] in [0, 2])):
		return false
	if a[0] == 198 and (a[1] in [18, 19] or (a[1] == 51 and a[2] == 100)):
		return false
	if a[0] == 203 and a[1] == 0 and a[2] == 113:
		return false
	return true

static func _octets(address: String) -> PackedInt32Array:
	var parts := address.split(".")
	var result := PackedInt32Array()
	if parts.size() != 4:
		return result
	for part in parts:
		if part.is_empty() or part.length() > 3:
			return PackedInt32Array()
		for character in part:
			if character < "0" or character > "9":
				return PackedInt32Array()
		var octet := part.to_int()
		if octet > 255:
			return PackedInt32Array()
		result.append(octet)
	return result

static func _checksum(values: PackedInt32Array, width: int = 8) -> int:
	if width == 7:
		var short_crc := 0x27
		for value in values:
			for bit in 8:
				var mix := ((short_crc >> 6) ^ (value >> (7 - bit))) & 1
				short_crc = ((short_crc << 1) & 127) ^ (0x09 if mix else 0)
		return short_crc
	var crc := 0xA7
	for value in values:
		crc ^= value
		for bit in 8:
			crc = ((crc << 1) ^ 0x07) & 255 if crc & 128 else (crc << 1) & 255
	return crc

static func _groups(code: String) -> String:
	var groups := PackedStringArray()
	for index in range(0,code.length(),4): groups.append(code.substr(index,4))
	return "-".join(groups)
