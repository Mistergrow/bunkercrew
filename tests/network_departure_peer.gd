extends "res://tests/network_gameplay_peer.gd"
## Verify the reliable leave packet survives closing the actual ENet socket.

func host_run() -> void:
	game.network.host_room()
	if not check(game.network.active,"Host opens a real direct room"):
		await finish(false,"host start")
		return
	publish("room",{"code":NetworkJoinCode.invite("127.0.0.1",game.network.listen_port,game.network._invite_secret)})
	if not await barrier("authenticated"):
		await finish(false,"guest authentication")
		return
	game.network.leave()
	publish("left")
	if not await barrier("closed"):
		await finish(false,"guest closure")
		return
	await finish(failures==0,"intentional host departure")

func guest_run() -> void:
	if not await barrier("room"):
		await finish(false,"host room")
		return
	game.network.join_room("",str(read_stage("room").code))
	if not await wait_for(func():return game.network._authenticated,"guest authentication"):
		await finish(false,"authentication")
		return
	publish("authenticated")
	if not await wait_for(func():return game.network.state=="error","immediate host closure",2.0):
		await finish(false,"closure")
		return
	check(game.network.error_message.contains("geschlossen") and game.network._reconnect_deadline==0,"Host leave closes immediately instead of starting a thirty-second retry")
	publish("closed")
	await finish(failures==0,"reliable leave arrived before socket retirement")
