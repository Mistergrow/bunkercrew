extends Node
## Own stopped workers across scene changes; join only after native calls finish.
var jobs: Array = []
var retiring_peers: Array = []

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func adopt(workers: Array) -> void:
	for job in workers:
		job.stop()
		jobs.append(job)

func retire_peer(peer: ENetMultiplayerPeer) -> void:
	peer.host.flush()
	retiring_peers.append({"peer":peer,"until":Time.get_ticks_msec()+250})

func _process(_delta: float) -> void:
	for entry in retiring_peers.duplicate():
		if entry.peer.get_connection_status()!=MultiplayerPeer.CONNECTION_DISCONNECTED:
			entry.peer.poll()
		if entry.peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED or Time.get_ticks_msec()>=entry.until:
			entry.peer.close()
			retiring_peers.erase(entry)
	for job in jobs.duplicate():
		if not job.thread.is_alive():
			if job.thread.is_started(): job.thread.wait_to_finish()
			jobs.erase(job)

func _exit_tree() -> void:
	for entry in retiring_peers: entry.peer.close()
	retiring_peers.clear()
	# Application shutdown must retain native workers until they have returned.
	for job in jobs:
		job.stop()
		if job.thread.is_started(): job.thread.wait_to_finish()
	jobs.clear()
