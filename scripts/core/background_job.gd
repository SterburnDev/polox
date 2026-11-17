extends Node
## Slow checks for a screen (the firewall, Tailscale, the Doctor, an address test), done on a thread of their
## own: run() returns a box ({"done", "result"}) the screen reads once "done" is true. A screen closed meanwhile
## doesn't wait for the work (closing Settings used to freeze the game for as long as the firewall check took,
## about ten seconds) and the work never writes into the closed screen: pass it a function that only uses
## what it's given. This node, kept under the scene tree's root, joins the threads that have finished.
##
## Closing the game joins every thread still running. Work that can take long (a helper program that
## runs for minutes) passes `stop`: it is called first, so that work ends at once instead of holding
## the closing game open.

static var _keeper: Node

var _jobs: Array = []   # [[Thread, box, stop]]


## `stop` (optional, no arguments): called on the main thread when the game closes while `work` still
## runs. It must only make `work` return soon (set a flag `work` looks at); it must not wait.
static func run(work: Callable, stop: Callable = Callable()) -> Dictionary:
	var box := {"done": false, "result": null}
	var t := Thread.new()
	t.start(func() -> void:
		box["result"] = work.call()
		box["done"] = true)
	_keeper_node()._jobs.append([t, box, stop])
	return box


static func _keeper_node() -> Node:
	if _keeper == null or not is_instance_valid(_keeper):
		_keeper = load("res://scripts/core/background_job.gd").new()
		_keeper.name = "BackgroundJobs"
		# By instance id: shutdown() may free the keeper before this frame's deferred calls run, and
		# a call that carries a freed node is an engine error.
		_adopt.call_deferred(_keeper.get_instance_id())
	return _keeper


static func _adopt(keeper_id: int) -> void:
	var keeper := instance_from_id(keeper_id) as Node
	var tree := Engine.get_main_loop() as SceneTree
	if keeper and tree and keeper.get_parent() == null:
		tree.root.add_child(keeper)


## The game is closing. A keeper made in the very last frame never reached the tree (it joins it a
## moment after it's made), so nothing would join its threads or free it: that happens here.
static func shutdown() -> void:
	if _keeper != null and is_instance_valid(_keeper) and _keeper.get_parent() == null:
		_keeper._finish_all()
		_keeper.free()
		_keeper = null


func _process(_delta: float) -> void:
	for j in _jobs.duplicate():
		var t: Thread = j[0]
		if not t.is_alive():
			t.wait_to_finish()
			_jobs.erase(j)


func _exit_tree() -> void:
	_finish_all()


## Tells the work that can stop to stop, then waits for all of it. This node is the root's last child,
## so it leaves the tree before the screens that started the work: none of them has cancelled yet.
func _finish_all() -> void:
	for j in _jobs:
		var stop: Callable = j[2]
		if stop.is_valid() and (j[0] as Thread).is_alive():
			stop.call()
	for j in _jobs:
		(j[0] as Thread).wait_to_finish()
	_jobs.clear()
