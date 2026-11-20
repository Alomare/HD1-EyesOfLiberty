-- Explosion kick: an explosion near the Helldiver knocks the shoulder camera like an uppercut. The view
-- rolls away from the blast, tips up and rises, sharply, then springs back.
--
-- Explosions are heard two ways, and the same blast heard twice (within MERGE_TIME and MERGE_DIST) counts once:
--   ExplosionManager.do_explosion(self, unit, position, info, ...)  every damaging explosion on the
--       machine that owns it (explosive, mine, airstrike, napalm strike, missile, flow explosions): info
--       holds blast_radius, blast_power, center_radius, center_power.
--   CameraManager.add_shake(self, template, position)  the visual shake each machine plays for a blast
--       it sees (unit flow, airstrikes): the template's name tells what blew up (camera_shake_settings.lua).
--       Only the explosion templates in TEMPLATE count; weapon fire and footsteps use the same call.
--
-- Strength: an energy E, center_power * center_radius + blast_power * blast_radius (a frag grenade about
-- 1900, an airstrike 5800, a satchel 6850), or TEMPLATE's for a shake. Below LEAST nothing happens
-- (napalm and gas areas tick small explosions all the time). The kick reaches REACH * (E / BASE)^0.6
-- metres and is KICK * (E / BASE)^0.6 strong at the blast, up to 1, fading with the distance's share of
-- the reach to the power 1.5: a grenade kicks lightly within about 6 m, a Hellbomb hard and out to 35 m.
--
-- Hellpods: a pod landing raises an explosion of its own (through the level's flow), and the Hellpod
-- camera has its own landing shake, so it kicks nothing. A blast is a pod's when one of its units has
-- the hellpod component, or when it goes off within POD_NEAR metres of a pod that came down within
-- POD_FRESH seconds (HellpodComponent.setup_slave, on every machine).
--
-- Repeats: each kick adds its strength to a fatigue that wears off at FATIGUE_RATE a second, and a new
-- kick is exp(-TIRE * fatigue) as strong, so a barrage gives a few strong kicks and then small ones.
local M = {}

local function g(name) return rawget(_G, name) end

M.BASE = 2000         -- energy of a frag grenade, about
M.REACH = 6           -- metres a BASE blast reaches
M.KICK = 0.45         -- strength of a BASE blast at its centre (1 is the full kick)
M.LEAST = 500         -- energy below which a blast kicks nothing
M.TEMPLATE = {        -- energy of a blast heard only through its camera shake
	grenade = 2000, mine_explosion = 2500, bugnest_explode = 2500, recoilless = 2500,
	artillery = 4500, airstrike = 5800, hellbomb_explosion = 40000,
}
M.MERGE_TIME, M.MERGE_DIST = 0.2, 4
M.POD_NEAR, M.POD_FRESH = 5, 10

-- The full kick (strength 1): degrees of roll away from the blast, degrees of tip up, metres up. Five
-- times the first tuning (0.14.0: 10, 4, 0.22), which players found too weak at every size.
M.ROLL, M.PITCH, M.LIFT = 50, 20, 1.1
-- The spring each part follows: natural frequency (radians a second) and damping ratio. A kick sets
-- the part moving at the speed that peaks at its size, so it snaps out and settles back.
M.OMEGA, M.DAMPING = 11, 0.5
M.TIRE, M.FATIGUE_RATE = 1.6, 0.8

-- The energy of an explosive_info, or 0.
function M.energy(info)
	if type(info) ~= "table" then return 0 end
	local function n(v) return type(v) == "number" and v > 0 and v or 0 end
	return n(info.center_power) * n(info.center_radius) + n(info.blast_power) * n(info.blast_radius)
end

-- How strong the kick of a blast of energy `e` is `d` metres away, 0 to 1.
function M.strength(e, d)
	if type(e) ~= "number" or e < M.LEAST or type(d) ~= "number" then return 0 end
	local share = e / M.BASE
	local reach = M.REACH * share ^ 0.6
	if d >= reach then return 0 end
	local f = 1 - d / reach
	return math.min(1, M.KICK * share ^ 0.6) * f ^ 1.5
end

-- The roll's direction for a blast `to` (flat way from the camera to the blast) and the camera's
-- flat `right`: -1 for a blast on the right (the view rolls left, away from it), 1 on the left. Straight
-- ahead or behind, `coin` (1 or -1) picks.
function M.side(to, right, coin)
	local d = (to.x or 0) * (right.x or 0) + (to.y or 0) * (right.y or 0)
	if math.abs(d) < 0.2 then return coin or 1 end
	return d > 0 and -1 or 1
end

-- The springs: roll (degrees), pitch (degrees), lift (metres), each { x, v }.
M.springs = { roll = { x = 0, v = 0 }, pitch = { x = 0, v = 0 }, lift = { x = 0, v = 0 } }
M.fatigue = 0

-- The speed that makes a spring at rest peak at `size`.
function M.launch(size)
	local z = M.DAMPING
	local wd = M.OMEGA * math.sqrt(1 - z * z)
	local t = math.atan2(wd, z * M.OMEGA) / wd -- time of the first peak
	return size * wd / (math.exp(-z * M.OMEGA * t) * math.sin(wd * t))
end

-- A kick of `strength` (0 to 1, before fatigue), rolling `side` (1 left, -1 right). Answers the
-- strength used.
function M.kick(strength, side)
	if strength <= 0 then return 0 end
	local s = strength * math.exp(-M.TIRE * M.fatigue)
	M.fatigue = M.fatigue + strength
	local sp = M.springs
	sp.roll.v = sp.roll.v + M.launch(M.ROLL * s * (side or 1))
	sp.pitch.v = sp.pitch.v + M.launch(M.PITCH * s)
	sp.lift.v = sp.lift.v + M.launch(M.LIFT * s)
	return s
end

-- Moves the springs on by dt. Answers roll, pitch (degrees) and lift (metres), times `factor`.
function M.step(dt, factor)
	dt = math.max(0, math.min(dt or 0, 0.05))
	M.fatigue = M.fatigue * math.exp(-M.FATIGUE_RATE * dt)
	-- The spring's exact motion over dt, so the peak is the same at any frame rate.
	local w, z = M.OMEGA, M.DAMPING
	local a, wd = z * w, w * math.sqrt(1 - z * z)
	local e, c, sn = math.exp(-a * dt), math.cos(wd * dt), math.sin(wd * dt)
	for _, s in pairs(M.springs) do
		local x0, v0 = s.x, s.v
		s.x = e * (x0 * c + (v0 + a * x0) / wd * sn)
		s.v = e * (v0 * c - (a * v0 + w * w * x0) / wd * sn)
		if math.abs(s.x) < 1e-4 and math.abs(s.v) < 1e-3 then s.x, s.v = 0, 0 end
	end
	local f = factor or 1
	return M.springs.roll.x * f, M.springs.pitch.x * f, M.springs.lift.x * f
end

function M.clear()
	for _, s in pairs(M.springs) do s.x, s.v = 0, 0 end
	M.fatigue = 0
end

-- Recent blasts, to hear each once: { t, x, y, z }.
local recent = {}
local clock = 0

-- Pods that came down lately: { unit, t }.
M.pods = {}

-- Whether a blast at `p` from these units is a Hellpod landing.
function M.from_pod(p, units)
	local EA, U = g("EntityAux"), g("Unit")
	for _, u in ipairs(units or {}) do
		if u ~= nil then
			local ok, yes = pcall(EA.has_component, u, "hellpod")
			if ok and yes then return true end
		end
	end
	if not p then return false end
	for i = #M.pods, 1, -1 do
		local pod = M.pods[i]
		if clock - pod.t > M.POD_FRESH then
			table.remove(M.pods, i)
		else
			local ok, q = pcall(function() return U.alive(pod.unit) and U.world_position(pod.unit, 0) end)
			if ok and q then
				local dx, dy = q.x - p.x, q.y - p.y
				if dx * dx + dy * dy <= M.POD_NEAR * M.POD_NEAR then return true end
			end
		end
	end
	return false
end

-- A blast of energy `e` at `p`: kicks the camera when it's near enough. Answers the strength.
function M.blast(env, e, p)
	if not (p and env.state.active and not env.state.watching) then return 0 end
	if env.config.get("explosion_kick") == false then return 0 end
	for i = #recent, 1, -1 do
		local r = recent[i]
		if clock - r.t > M.MERGE_TIME then table.remove(recent, i)
		else
			local dx, dy, dz = r.x - p.x, r.y - p.y, r.z - p.z
			if dx * dx + dy * dy + dz * dz < M.MERGE_DIST * M.MERGE_DIST then return 0 end
		end
	end
	recent[#recent + 1] = { t = clock, x = p.x, y = p.y, z = p.z }
	local view = env.view
	if not (view and view.position) then return 0 end
	-- The distance to the Helldiver, or to the camera when there's none.
	local at = view.pivot or view.position
	local dx, dy, dz = p.x - at.x, p.y - at.y, p.z - at.z
	local s = M.strength(e, math.sqrt(dx * dx + dy * dy + dz * dz))
	if s <= 0 then return 0 end
	local right = obsidian.module("src/rig").right(view.yaw or 0)
	local cx, cy = p.x - view.position.x, p.y - view.position.y
	local len = math.sqrt(cx * cx + cy * cy)
	local to = len > 0 and { x = cx / len, y = cy / len } or { x = 0, y = 0 }
	return M.kick(s, M.side(to, right, math.random() < 0.5 and 1 or -1))
end

local function point(boxed)
	if type(boxed) ~= "table" and type(boxed) ~= "userdata" then return nil end
	local ok, v = pcall(function()
		local V3A = g("Vector3Aux")
		local p = V3A and V3A.unbox(boxed) or boxed
		return { x = p.x, y = p.y, z = p.z }
	end)
	if ok and v and type(v.x) == "number" then return v end
	return nil
end

function M.start(env)
	local names = nil -- template table: name
	local function template_name(t)
		if names == nil then
			names = {}
			for name, v in pairs(g("CameraShakeSettings") or {}) do names[v] = name end
		end
		return names[t]
	end
	obsidian.hook("ExplosionManager", "do_explosion", function(original, self, unit, position, info, attacker, owner, ...)
		pcall(function()
			local p = point(position)
			if M.from_pod(p, { unit, attacker, owner }) then return end
			M.blast(env, M.energy(info), p)
		end)
		return original(self, unit, position, info, attacker, owner, ...)
	end, env.VIEW)
	obsidian.hook("HellpodComponent", "setup_slave", function(original, self, unit, ...)
		M.pods[#M.pods + 1] = { unit = unit, t = clock }
		return original(self, unit, ...)
	end, env.VIEW)
	obsidian.hook("CameraManager", "add_shake", function(original, self, template, position, ...)
		pcall(function()
			local e = M.TEMPLATE[template_name(template) or ""]
			if e then M.blast(env, e, point(position)) end
		end)
		return original(self, template, position, ...)
	end, env.VIEW)
	obsidian.on_frame(function()
		clock = clock + (rawget(_G, "ENGINE_DT") or 0.016)
	end, env.VIEW)
	table.insert(env.on_release, function() M.clear() end)
end

return M
