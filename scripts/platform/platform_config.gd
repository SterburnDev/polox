extends RefCounted
## Platform Mode's feel, all in one place (1 unit = 1 block). Tune here.
##
## Jump: apex = JUMP_VELOCITY^2 / (2 GRAVITY) = 1.35 blocks, so a 1-block
## ledge is cleared and a 2-block wall isn't.

const WALK_SPEED := 4.0
const RUN_SPEED := 7.0
const GROUND_ACCEL := 40.0        # units/s^2 toward the wanted speed
const GROUND_DECEL := 46.0        # stopping when you let go
const AIR_ACCEL := 16.0           # air control
const SLIPPERY_ACCEL := 5.0       # on slippery tiles: slow to start...
const SLIPPERY_DECEL := 2.5       # ...and slower to stop
const GRAVITY := 28.0
const JUMP_VELOCITY := 8.69       # sqrt(2 * 28 * 1.35)
const MAX_FALL_SPEED := 26.0
const SLOW_FALL_SPEED := 3.2      # the Slow-fall assist
const COYOTE_TIME := 0.12         # a jump still works this long after walking off an edge
const JUMP_BUFFER := 0.12         # a jump pressed this long before landing still happens
const STEP_HEIGHT := 0.55         # half-block lips are walked up, full blocks need a jump
const AUTO_JUMP_HEIGHT := 1.05    # the Auto-jump assist hops ledges up to this high
const FLOOR_MAX_ANGLE_DEG := 50.0 # ramps (45 degrees) are walkable
const FLOOR_SNAP := 0.6

const CAPSULE_RADIUS := 0.28
const CAPSULE_HEIGHT := 1.2
const KILL_DEPTH := 6.0           # falling this far below the floor = back to the checkpoint
const RESPAWN_FADE := 0.25        # seconds of soft fade each way
const LAND_TIME := 0.14           # the "land" pose lasts this long

const JUMP_PAD_STRENGTH := 14.0   # default launch speed (about 3.5 blocks high)
const MOVER_SPEED := 1.5          # default moving-platform speed (blocks/s)

const CAMERA_DISTANCE := 5.5
const CAMERA_MIN := 2.5
const CAMERA_MAX := 10.0
const CAMERA_PITCH_DEG := 22.0
const CAMERA_ASSIST_RATE := 2.2   # how quickly Camera assist swings behind you
const CAMERA_ASSIST_PAUSE := 2.0  # seconds after you turn the camera yourself
const JOYSTICK_RADIUS := 70.0     # px: pushing fully runs
const JOYSTICK_RUN_AT := 0.85

# Physics layers (BlockFactory uses 1, 2 and 4).
const LAYER_SOLID := 8            # merged chunk colliders, moving platforms
const LAYER_ONE_WAY := 16
const LAYER_AREAS := 32           # pads, hazards, checkpoints, shards
const LAYER_PLAYER := 64
const LAYER_BOUNDS := 128         # the invisible walls at a place's edges (the camera looks past them)

## Where a jump can take you from standing on a block: [max rise, max gap at the same height].
static func jump_reach(running: bool = true) -> Vector2:
	var apex := JUMP_VELOCITY * JUMP_VELOCITY / (2.0 * GRAVITY)
	var air := 2.0 * JUMP_VELOCITY / GRAVITY
	return Vector2(floorf(apex), floorf((RUN_SPEED if running else WALK_SPEED) * air))
