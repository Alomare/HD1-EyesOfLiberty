-- Weapon handling on foot in third person: shots leave along the way the weapon faces, not the
-- camera's, and the weapon swings into the crosshair while the Helldiver aims or fires, at a speed set
-- by its ergonomics (0 to 100, higher is faster). The crosshair is drawn where the weapon points.
--
-- Turning left and right is the game's own: CharacterComponent.update_masters turns the Helldiver to
-- the aim input with Quaternion.slerp(target, now, keep ^ dt), keep taken from the weapon's turn_speed_*
-- or, when the state machine set one this frame, state.forced_rotation_speed (reset to nil before the
-- state machines run, read after CharacterSubstateMachine.update). The mod sets that keep from the
-- ergonomics, so every weapon turns at the same handling. Up and down is the mod's (src/aimpose.lua
-- bends the body to the pitch here). Plain numbers only, so tests can run it.
local M = {}

M.ERGONOMICS = 92     -- every weapon: the swing is quick, a small lag to see, not to fight
M.LASER_FIRING = 60   -- a laser while it fires swings slower
M.TAU_MIN = 0.03      -- seconds: the time constant at ergonomics 100
M.TAU_SPAN = 0.5      -- seconds more at ergonomics 0
M.LASER_HOLD = 4      -- frames a laser counts as firing after its last beam
M.CROSS_TAU = 0.05    -- seconds: the crosshair moving between the middle and the weapon's point

-- Character states in which the Helldiver holds the weapon up to shoot. Names of globals.
M.AIM_STATES = { "CharacterStateAim", "CharacterStateAimWalk", "CharacterStateAimFire",
	"CharacterStateAimWalkFire", "CharacterStateFire", "CharacterStateWalkFire" }

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- The time constant of the swing, in seconds, for an ergonomics value.
function M.tau(ergonomics)
	return M.TAU_MIN + M.TAU_SPAN * (100 - clamp(ergonomics or M.ERGONOMICS, 0, 100)) / 100
end

-- The keep factor the game's turn takes (the share of the old facing kept after one second).
function M.keep(tau)
	return math.exp(-1 / math.max(tau, 1e-3))
end

-- The ergonomics now: lower while a laser fires.
function M.ergonomics(laser_firing)
	return laser_firing and M.LASER_FIRING or M.ERGONOMICS
end

-- One step of an eased value toward `want`.
function M.ease(now, want, tau, dt)
	if now == nil then return want end
	return want + (now - want) * math.exp(-(dt or 0) / math.max(tau, 1e-3))
end

-- The pitch in radians from a point to another, nil for a point straight above or under.
function M.pitch_to(from, to)
	local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
	local flat = math.sqrt(dx * dx + dy * dy)
	if flat < 1e-3 then return nil end
	return math.atan2(dz, flat)
end

-- The way a weapon faces: its flat heading, turned by `turn` radians (anticlockwise seen from above),
-- and a pitch in radians. nil without a heading.
function M.dir(flat, pitch, turn)
	local l = math.sqrt(flat.x * flat.x + flat.y * flat.y)
	if l < 1e-6 then return nil end
	local x, y = flat.x / l, flat.y / l
	if turn and turn ~= 0 then
		local c, s = math.cos(turn), math.sin(turn)
		x, y = x * c - y * s, x * s + y * c
	end
	local c = math.cos(pitch or 0)
	return { x = x * c, y = y * c, z = math.sin(pitch or 0) }
end

-- The turn that makes a shot from `origin` along the Helldiver's facing meet `point` once the facing
-- has settled: the game turns the Helldiver to face the point from its root, and shots start beside
-- the root (probe 2026-11-21: 12 px right of the middle at rest without it). Radians, within half a turn.
function M.converge(root, origin, point)
	local a = math.atan2(point.y - origin.y, point.x - origin.x)
	local b = math.atan2(point.y - root.y, point.x - root.x)
	local d = a - b
	while d > math.pi do d = d - 2 * math.pi end
	while d < -math.pi do d = d + 2 * math.pi end
	return d
end

-- With Weapon ergonomics off, the game's own turn sets the pace: the share of the heading error the
-- game's turn closed in one frame (e0 before, e1 after, radians) as a rate a second, or nil when the
-- error was too small to tell. The pitch then eases at that rate, so it is never faster than the turn.
M.MEASURE_FROM = 0.05 -- radians of heading error below which a frame tells nothing
M.RATE_MAX = 200      -- a second: a turn faster than this counts as instant
M.GAME_TAU = 0.1      -- seconds: the pace until the game's turn has been measured
function M.measured_rate(e0, e1, dt)
	if not (e0 and e1 and dt) or e0 < M.MEASURE_FROM or dt <= 0 then return nil end
	local left = math.max(1e-9, math.min(1, e1 / e0))
	return math.min(M.RATE_MAX, -math.log(left) / dt)
end

-- The time constant for a measured rate a second (nil: GAME_TAU).
function M.tau_of_rate(rate)
	if not rate or rate <= 0 then return M.GAME_TAU end
	return 1 / rate
end

-- The flat angle in radians between two directions.
function M.flat_angle(a, b)
	local la, lb = math.sqrt(a.x * a.x + a.y * a.y), math.sqrt(b.x * b.x + b.y * b.y)
	if la < 1e-6 or lb < 1e-6 then return nil end
	local c = (a.x * b.x + a.y * b.y) / (la * lb)
	return math.acos(math.max(-1, math.min(1, c)))
end

-- One frame of the weapon's pitch. raised: the Helldiver aims or fires; the weapon swings to the
-- crosshair's pitch, else back to level as the animations carry it.
function M.step_pitch(now, want, raised, tau, dt)
	return M.ease(now, raised and want or 0, tau, dt)
end

-- A screen point kept inside a w by h viewport (pixels from the bottom left).
function M.inside(x, y, w, h)
	return clamp(x, 0, w), clamp(y, 0, h)
end

return M
