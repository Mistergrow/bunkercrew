extends RefCounted
## Decode bounded incoming guest packets away from the render thread.
const Protocol := preload("res://scripts/network_protocol.gd")
const MAX_QUEUE := 64
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending: Array = []
var _completed: Array = []
var _stopping := false

func start() -> Error: return _thread.start(_run)

func submit(packet: PackedByteArray, channel: int) -> bool:
	_mutex.lock()
	var accepted := not _stopping and _pending.size()+_completed.size()<MAX_QUEUE
	if accepted: _pending.append({"packet":packet,"channel":channel})
	_mutex.unlock()
	if accepted: _wake.post()
	return accepted

func take() -> Array:
	_mutex.lock()
	var result := _completed
	_completed=[]
	_mutex.unlock()
	return result

func stop() -> void:
	_mutex.lock()
	_stopping=true
	_pending.clear()
	_mutex.unlock()
	_wake.post()
	if _thread.is_started(): _thread.wait_to_finish()

func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		if _stopping: _mutex.unlock(); return
		var item: Dictionary=_pending.pop_front()
		_mutex.unlock()
		var decoded := Protocol.decode(item.packet)
		_mutex.lock()
		_completed.append({"message":decoded,"channel":item.channel})
		_mutex.unlock()
