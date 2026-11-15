-- First person weapon motion in plain numbers: where the held weapon sits in front of the camera, frame by
-- frame. Everything is in the camera's own axes: x right, y forward, z up, metres and degrees. The
-- weapon's own axes match when it points straight ahead (the barrel along +y, the top along +z).
--
-- A pose is { pos = { x, y, z }, rot = { yaw, pitch, roll } }. The motion is layered, as first person
-- games do it:
--   hold     where the family holds the weapon: from the hip, or raised while aiming
--   moves    whole-body moves that blend in and out: sprint, reload, switch (and other busy states),
--            melee, dive, downed
--   bob      the step of walking and running
--   breath   a slow rise and fall when still
--   sway     the weapon trailing the turn of the view
--   recoil   the kick of each shot, springing back
-- Families share the moves; a family only names its holds and how hard it kicks, so a new weapon type
-- is a few numbers. Unknown weapons take the rifle family, sidearms the pistol family.
local M = {}

local function P(x, y, z, yaw, pitch, roll)
	return { pos = { x = x, y = y, z = z }, rot = { yaw = yaw or 0, pitch = pitch or 0, roll = roll or 0 } }
end

M.FAMILIES = {
	rifle = {
		hip = P(0.165, 0.36, -0.215, 3, 1.5, -5),
		aim = P(0.085, 0.33, -0.19, 2, 0.5, -1.5),
		sprint = P(-0.05, -0.04, -0.10, 38, -24, -28),
		reload = P(-0.07, -0.02, -0.05, 14, 14, 32),
		dive = P(-0.04, -0.05, -0.07, 12, -6, 36),
		downed = P(-0.01, -0.03, -0.05, 4, -6, -14),
		kick = { back = 0.032, pitch = 3.2, yaw = 1.0 },
	},
	pistol = {
		hip = P(0.12, 0.40, -0.19, 3, 1, -3),
		aim = P(0.0, 0.36, -0.13, 0, 0, 0),
		sprint = P(-0.02, -0.06, -0.10, 12, -38, -12),
		reload = P(-0.04, -0.04, -0.03, 10, 22, 26),
		dive = P(-0.03, -0.06, -0.06, 8, -10, 30),
		downed = P(0.0, -0.04, -0.04, 3, -4, -10),
		kick = { back = 0.024, pitch = 6.5, yaw = 1.4 },
	},
}

-- Out of view: switching weapons, throwing, calling stratagems, using things.
M.AWAY = P(0.02, -0.12, -0.36, 0, -55, 0)
-- A melee strike: the weapon thrust forward and turned on its side.
M.MELEE = P(-0.07, 0.15, 0.04, 28, 6, -45)

-- How fast each move comes and goes (ease rates, per second).
M.RATES = { aim = 13, sprint = 8, reload = 7, away = 11, dive = 10, downed = 6, melee = 18 }

M.BOB = { side = 0.011, up = 0.010, roll = 1.6, stride = 2.3, full_speed = 4.5, aim_keep = 0.3, sprint = 1.8 }
M.BREATH = { rate = 1.35, up = 0.0032, pitch = 0.45, aim_keep = 0.35 }
M.SWAY = { per_degree = 0.22, most = 6, rate = 9, shift = 0.0018, aim_keep = 0.45 }
M.RECOIL = { rate = 15, most_pitch = 9, most_back = 0.07, aim_keep = 0.6 }

local function share(rate, dt) return 1 - math.exp(-rate * math.max(0, dt)) end
local function ease(v, to, rate, dt) return v + (to - v) * share(rate, dt) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- The family of a weapon by its unit name (the equipment path) and whether it is a sidearm.
M.RIFLES = { ["equipment/wep_assaultrifle_01"] = true, ["equipment/wep_assaultrifle_02"] = true, ["equipment/wep_assaultrifle_03"] = true }
M.PISTOLS = { ["equipment/wep_pistol_01"] = true }
function M.family_of(name, sidearm)
	if name and M.RIFLES[name] then return "rifle", true end
	if name and M.PISTOLS[name] then return "pistol", true end
	return sidearm and "pistol" or "rifle", false
end

function M.new()
	return {
		w = { aim = 0, sprint = 0, reload = 0, away = 1, dive = 0, downed = 0, melee = 0 },
		phase = 0, time = 0, speed = 0,
		sway = { yaw = 0, pitch = 0 },
		kick = { back = 0, pitch = 0, yaw = 0 },
		seed = 0,
	}
end

-- A small repeatable random number in [-1, 1], so tests see the same kicks.
local function wobble(st)
	st.seed = (st.seed * 1103515245 + 12345) % 2147483648
	return (st.seed / 2147483648) * 2 - 1
end

-- One frame. feel: dt, family, aim, sprint, reload, away, dive, downed, melee (booleans), speed (metres a
-- second along the ground), shots (fired since the last frame), turn = { yaw, pitch } (degrees the view
-- turned this frame), firing_beam (a beam weapon is firing). Answers the pose of the weapon.
function M.step(st, feel)
	local dt = math.max(0, math.min(feel.dt or 0.016, 0.1))
	local fam = M.FAMILIES[feel.family] or M.FAMILIES.rifle
	local w = st.w
	for k, rate in pairs(M.RATES) do w[k] = ease(w[k], feel[k] and 1 or 0, rate, dt) end
	-- Aiming gives way to the moves that take the weapon down.
	local aim = w.aim * (1 - math.max(w.sprint, w.away, w.melee, w.reload * 0.7))

	local pos = {
		x = fam.hip.pos.x + (fam.aim.pos.x - fam.hip.pos.x) * aim,
		y = fam.hip.pos.y + (fam.aim.pos.y - fam.hip.pos.y) * aim,
		z = fam.hip.pos.z + (fam.aim.pos.z - fam.hip.pos.z) * aim,
	}
	local rot = {
		yaw = fam.hip.rot.yaw + (fam.aim.rot.yaw - fam.hip.rot.yaw) * aim,
		pitch = fam.hip.rot.pitch + (fam.aim.rot.pitch - fam.hip.rot.pitch) * aim,
		roll = fam.hip.rot.roll + (fam.aim.rot.roll - fam.hip.rot.roll) * aim,
	}
	local function layer(move, weight)
		if weight <= 1e-4 then return end
		pos.x, pos.y, pos.z = pos.x + move.pos.x * weight, pos.y + move.pos.y * weight, pos.z + move.pos.z * weight
		rot.yaw, rot.pitch, rot.roll = rot.yaw + move.rot.yaw * weight, rot.pitch + move.rot.pitch * weight, rot.roll + move.rot.roll * weight
	end
	layer(fam.sprint, w.sprint * (1 - w.away))
	layer(fam.reload, w.reload * (1 - w.away))
	layer(fam.dive, w.dive)
	layer(fam.downed, w.downed * (1 - w.dive))
	layer(M.AWAY, w.away)
	layer(M.MELEE, w.melee * (1 - w.away))

	-- Bob: a figure of eight with each pair of steps, stronger running, weaker aiming.
	st.speed = ease(st.speed, math.max(0, feel.speed or 0), 10, dt)
	local pace = clamp(st.speed / M.BOB.full_speed, 0, 1.4)
	st.phase = (st.phase + dt * st.speed * M.BOB.stride) % (math.pi * 4)
	local bob = pace * (1 - (1 - M.BOB.aim_keep) * aim) * (1 + (M.BOB.sprint - 1) * w.sprint) * (1 - w.away)
	pos.x = pos.x + math.sin(st.phase) * M.BOB.side * bob
	pos.z = pos.z - math.abs(math.cos(st.phase)) * M.BOB.up * bob
	rot.roll = rot.roll + math.sin(st.phase) * M.BOB.roll * bob

	-- Breath: when still.
	st.time = st.time + dt
	local still = (1 - clamp(pace * 2, 0, 1)) * (1 - (1 - M.BREATH.aim_keep) * aim)
	local b = math.sin(st.time * M.BREATH.rate)
	pos.z = pos.z + b * M.BREATH.up * still
	rot.pitch = rot.pitch + b * M.BREATH.pitch * still

	-- Sway: the weapon trails a turn and settles back.
	local turn = feel.turn or {}
	local sw = st.sway
	sw.yaw = clamp(sw.yaw - (turn.yaw or 0) * M.SWAY.per_degree, -M.SWAY.most, M.SWAY.most)
	sw.pitch = clamp(sw.pitch - (turn.pitch or 0) * M.SWAY.per_degree, -M.SWAY.most, M.SWAY.most)
	sw.yaw, sw.pitch = ease(sw.yaw, 0, M.SWAY.rate, dt), ease(sw.pitch, 0, M.SWAY.rate, dt)
	local keep = 1 - (1 - M.SWAY.aim_keep) * aim
	rot.yaw = rot.yaw + sw.yaw * keep
	rot.pitch = rot.pitch + sw.pitch * keep
	pos.x = pos.x - sw.yaw * M.SWAY.shift * keep
	pos.z = pos.z + sw.pitch * M.SWAY.shift * keep

	-- Recoil: each shot kicks back and up, and springs home.
	local k = st.kick
	local kick = fam.kick
	for _ = 1, math.min(feel.shots or 0, 4) do
		k.back = math.min(M.RECOIL.most_back, k.back + kick.back)
		k.pitch = math.min(M.RECOIL.most_pitch, k.pitch + kick.pitch * (0.85 + 0.3 * (wobble(st) + 1) / 2))
		k.yaw = clamp(k.yaw + kick.yaw * wobble(st), -M.RECOIL.most_pitch, M.RECOIL.most_pitch)
	end
	if feel.firing_beam then
		k.pitch = k.pitch + 0.25 * wobble(st)
		k.yaw = k.yaw + 0.25 * wobble(st)
	end
	k.back, k.pitch, k.yaw = ease(k.back, 0, M.RECOIL.rate, dt), ease(k.pitch, 0, M.RECOIL.rate, dt), ease(k.yaw, 0, M.RECOIL.rate, dt)
	local rk = 1 - (1 - M.RECOIL.aim_keep) * aim
	pos.y = pos.y - k.back * rk
	rot.pitch = rot.pitch + k.pitch * rk
	rot.yaw = rot.yaw + k.yaw * rk

	return { pos = pos, rot = rot }, w
end

return M
