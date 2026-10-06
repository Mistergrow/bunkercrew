extends SceneTree

const CODE = preload("res://scripts/network_join_code.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 194601
	for index in 200:
		var address := "%d.%d.%d.%d" % [rng.randi_range(1,223),rng.randi_range(0,255),rng.randi_range(0,255),rng.randi_range(0,255)]
		for port in [24777, rng.randi_range(1024,65535)]:
			var code: String = CODE.encode(address,port)
			var decoded: Dictionary = CODE.decode(code)
			check(decoded.get("ok",false) and decoded.get("address","")==address and decoded.get("port",0)==port, "address and port round trip")
			check(CODE.decode(" " + code.to_lower().replace("-"," ") + " ").get("ok",false), "pasted lowercase code")
	var known: String = CODE.encode("93.184.216.34")
	check(known.length()==9, "default port uses eight symbols")
	check(CODE.encode("93.184.216.34",28000).length()==13, "custom port travels in code")
	for original in [known,CODE.encode("93.184.216.34",28000)]:
		var compact: String = original.replace("-","")
		for index in compact.length():
			for replacement in CODE.ALPHABET:
				if replacement == compact[index]:
					continue
				var corrupted := compact.substr(0,index) + replacement + compact.substr(index+1)
				check(not CODE.decode(corrupted).get("ok",false), "single-symbol checksum corruption")
	for address in ["10.1.2.3","127.0.0.1","192.168.12.34","172.16.0.1","172.31.255.1","169.254.1.1","100.64.0.1","100.127.255.255","198.18.0.1","192.0.2.5","203.0.113.2","198.51.100.1","0.0.0.0","224.0.0.1","255.255.255.255"]:
		check(not CODE.is_public_address(address), "private, CGNAT, or reserved address")
	for address in ["93.184.216.34","1.1.1.1","100.63.255.254","100.128.0.1","172.15.0.1","172.32.0.1"]:
		check(CODE.is_public_address(address), "public IPv4 classification")
	for invalid in ["", "ABC", "OOOOOOOO", "11111111", "abcdefghijklmnop"]:
		check(not CODE.decode(invalid).get("ok",false), "reject malformed invitation")
	for address in ["", "::1", "localhost", "256.1.2.3", "-1.1.2.3", "1.2.3", "1.2.3.4.5", "1.2.3.+4"]:
		check(CODE.encode(address).is_empty(), "reject invalid IPv4")
	print("Network join codes: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(label)
