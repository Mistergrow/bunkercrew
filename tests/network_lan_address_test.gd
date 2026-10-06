extends SceneTree
const Transport := preload("res://scripts/network_transport.gd")
const Code := preload("res://scripts/network_join_code.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var wifi := {"name":"wlo1", "friendly":"wlo1", "addresses":["192.168.0.248", "fe80::1"]}
	var vpn := {"name":"tun1313", "friendly":"tun1313", "addresses":["10.15.4.7"]}
	var bridge := {"name":"br-container", "addresses":["172.19.0.1"]}
	var docker := {"name":"docker0", "addresses":["172.17.0.1"]}
	for adapters in [[vpn,bridge,docker,wifi], [docker,wifi,vpn,bridge], [wifi,vpn]]:
		check(Transport.lan_addresses(adapters) == PackedStringArray(["192.168.0.248"]), "VPN/container ordering never displaces the real Wi-Fi address")
	var windows_vpn := {"name":"{A-VPN-GUID}", "friendly":"ProtonVPN TUN", "addresses":["10.15.4.7"]}
	var ethernet := {"name":"{B-LAN-GUID}", "friendly":"Ethernet", "addresses":["10.20.30.40"]}
	check(Transport.lan_addresses([windows_vpn,ethernet]) == PackedStringArray(["10.20.30.40"]), "Windows adapter GUIDs use the friendly VPN name")
	check(Transport.lan_addresses([wifi,ethernet,wifi]).size() == 2, "Both physical interfaces survive without duplicate addresses")
	check(Transport.lan_addresses([vpn]) == PackedStringArray(["10.15.4.7"]), "A VPN-only machine retains its explicitly available network")
	check(Transport.lan_addresses([{"name":"lo", "addresses":["127.0.0.1","::1"]}]).is_empty(), "Loopback is never advertised as a LAN address")
	check(Transport.lan_addresses([{"name":"eth0", "addresses":["169.254.4.8","0.0.0.0","224.0.0.1","invalid"]}]).is_empty(), "Unusable, wildcard and multicast candidates are excluded")
	check(Transport.lan_addresses([{"name":"eth0", "addresses":["8.8.4.4"]}])[0] == "8.8.4.4", "A physically assigned public IPv4 remains supported")
	var secret := Code.new_invitation()
	check(Code.lan(secret).length() == 19 and Code.compact(Code.lan(secret)) == secret, "The short LAN code preserves every invitation bit in four groups")
	check(Code.is_lan_code("  "+Code.lan(secret).to_lower()+"  "), "Pasted lowercase LAN codes normalize")
	for bad in ["", "1234-OOOO", "ABCDEFG", "ABCDEFGHJ"]:
		check(not Code.is_lan_code(bad), "Wrong size or ambiguous invalid symbols are rejected")
	var direct := Code.invite("192.168.0.248",24777,secret)
	check(Code.decode(direct).invite == secret and not Code.is_lan_code(direct), "Long direct invitations remain distinct and authenticated")
	print("LAN ADDRESS: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
