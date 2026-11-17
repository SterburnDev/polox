extends RefCounted
## Letting go of a sound as its player leaves the tree.
##
## A player that is only freed hands its playback back to the audio server, which retires it on its
## next mix pass. When the game is closing there may be no next pass: the song's file is then still held
## as the engine shuts down ("resources still in use at exit"), and a streamed song (music_player.gd,
## a battle's, the Survey's: PLAYBACK_TYPE_STREAM) keeps its decoder with it. So the players that hold a
## song stop it and drop it themselves in _exit_tree (release), and the audio thread is given the time
## to retire it before the engine goes on closing (settle: only if something was really let go).
##
## settle() waits for mix passes it can see, not for a length of time: the audio thread's passes are
## not regular (70 ms between two was measured where 12 is the rule), so a fixed short wait sometimes
## saw none and the song stayed held.

const MIX_PASSES := 2        # passes that must begin after the release (the first may mix nothing new)
const SETTLE_MAX_MS := 300   # ...and never longer than this (a device whose audio thread is stopped)
const POLL_MS := 2
const SAME_PASS_USEC := 500  # two readings of one pass's time differ by less than this

static var _pending := false
static var _released_usec := 0


## Stops `player` (an AudioStreamPlayer, or its 2D / 3D kin) and takes its stream away. Safe on a
## player that is gone, never played or has nothing loaded. True if it held a stream.
static func release(player: Node) -> bool:
	if player == null or not is_instance_valid(player) or not "stream" in player:
		return false
	var had: bool = player.get("stream") != null
	if player.has_method("stop"):
		player.call("stop")
	player.set("stream", null)
	if had:
		_pending = true
		_released_usec = Time.get_ticks_usec()
	return had


## Something was released since the last time: waits until the audio thread has made MIX_PASSES
## passes that began after it (SETTLE_MAX_MS at most), so the audio server has retired it. Cheap to
## call when nothing was released (it returns at once). Returns the passes it saw (tests).
static func settle() -> int:
	if not _pending:
		return 0
	_pending = false
	var seen := 0
	var last := _released_usec
	var give_up := Time.get_ticks_msec() + SETTLE_MAX_MS
	while Time.get_ticks_msec() < give_up:
		# (Asking takes the audio thread's lock: a pass that has a time has also finished.)
		var began := Time.get_ticks_usec() - int(AudioServer.get_time_since_last_mix() * 1000000.0)
		if began > last + SAME_PASS_USEC:
			last = began
			seen += 1
			if seen >= MIX_PASSES:
				break
		OS.delay_msec(POLL_MS)
	return seen


## (Tests) whether a release is still waiting for its mix passes.
static func pending() -> bool:
	return _pending
