extends RefCounted
## Tiny body-language animations per expression (happy bounce, angry shake,
## surprised hop...). Each step is [offset in sprite pixels, scale, seconds];
## the actor plays them on top of its walking bob / idle breathing.

const MOTIONS := {
	"happy": [[Vector2(0, -1), Vector2(1.08, 0.9), 0.06], [Vector2(0, 9), Vector2(0.94, 1.08), 0.12], [Vector2(0, -1), Vector2(1.06, 0.92), 0.08], [Vector2(0, 5), Vector2(0.97, 1.04), 0.1], [Vector2.ZERO, Vector2.ONE, 0.1]],
	"surprised": [[Vector2(0, -1), Vector2(1.06, 0.92), 0.05], [Vector2(0, 12), Vector2(0.88, 1.16), 0.12], [Vector2(0, 10), Vector2(0.94, 1.08), 0.12], [Vector2.ZERO, Vector2.ONE, 0.18]],
	"angry": [[Vector2(-1.5, 0), Vector2(1.04, 1.0), 0.04], [Vector2(1.5, 0), Vector2(1.04, 1.0), 0.04], [Vector2(-1.5, 0), Vector2(1.04, 1.0), 0.04], [Vector2(1.5, 0), Vector2(1.04, 1.0), 0.04], [Vector2.ZERO, Vector2.ONE, 0.05]],
	"sad": [[Vector2(0, -1), Vector2(1.04, 0.92), 0.35], [Vector2(0, -1), Vector2(1.04, 0.92), 0.4], [Vector2.ZERO, Vector2.ONE, 0.35]],
	"embarrassed": [[Vector2(-1, 0), Vector2(0.97, 0.97), 0.12], [Vector2(1, 0), Vector2(0.97, 0.97), 0.12], [Vector2(-1, 0), Vector2(0.97, 0.97), 0.12], [Vector2.ZERO, Vector2.ONE, 0.12]],
	"sleepy": [[Vector2(-1.5, -1), Vector2(1.0, 0.96), 0.8], [Vector2(1.5, -1), Vector2(1.0, 0.96), 0.8], [Vector2.ZERO, Vector2.ONE, 0.5]],
	"thinking": [[Vector2(1, 1), Vector2(1.0, 1.02), 0.2], [Vector2(1, 1), Vector2(1.0, 1.02), 0.5], [Vector2.ZERO, Vector2.ONE, 0.2]],
}


static func steps(emotion: String) -> Array:
	return MOTIONS.get(emotion, [])


## A matching wiggle for 2D portraits: [rotation (radians), scale, seconds].
static func portrait_steps(emotion: String) -> Array:
	var out: Array = []
	for s in steps(emotion):
		var off: Vector2 = s[0]
		var sc: Vector2 = s[1]
		out.append([off.x * 0.03, Vector2(sc.x, sc.y), s[2]])
	return out
