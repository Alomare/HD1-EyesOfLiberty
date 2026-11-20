-- The look of a mission: fog and depth of field, through Obsidian API's shading (unguarded,
-- this player's picture alone).
--
--   reduce_fog      Reduce fog, the only option that changes the fog: a multiplier from 0 to 1 on
--                   how fast it builds up with distance (0.5 by default: half as fast), in either view. The
--                   game's fog shader (depth_fog) has no strength of its own: it thickens with distance at
--                   1 / (end - start) of fog_depth_range, from the start on (an exponential fog, which
--                   also thins with height at the same rate). So the start stays and the span from
--                   start to end is 1 / the multiplier times as long. 1 leaves the game's fog, 0 pushes
--                   it past anything drawn (Photo Mode's None).
--                   The same shader turns the fog toward sun_color * fog_sun_blend.z where the view
--                   faces the sun, by fog_sun_blend.x * dot(view, sun) ^ fog_sun_blend.y. Planets tune
--                   that for a camera looking down; looking along the ground at the sun, that colour
--                   (a median 2 and up to 700 times as bright as fog_color over the 220 planet
--                   environments) made a bright wall. Below 1, the blend shrinks with the multiplier and
--                   the sun side is held to SUN_CAP times the brightness of the fog colour.
--   depth_of_field  "game" leaves the planet's, "off" takes it away, "helldiver" keeps the Helldiver
--                   sharp and blurs what is nearer or farther, as Photo Mode's focus on the player does
--
-- While another mod holds the camera (Photo Mode does), nothing is sent: the fog goes
-- back to the planet's, the depth of field is left to that mod, and everything is sent again once
-- the camera is free.
local rig = obsidian.module("src/rig")

local M = {}

M.FOG_LEAST = 0.1             -- the thinnest Reduce fog above none: a tenth
M.NO_FOG = { 5000, 5001 }     -- Reduce fog 0: fog that starts past anything the camera draws
M.SUN_CAP = 1.5               -- the sun side of the fog at most this times as bright as the fog colour
M.FOG_DEFAULT = 0.5
-- Photo Mode keeps 6 m sharp around a player about 12 m off; with the shoulder camera 3 m off, that
-- left nothing nearer than 9 m blurred, and the option looked like it did nothing.
M.DOF_BLUR = 1                -- the strongest blur Photo Mode offers
M.DOF_DEPTH = 2               -- metres around the focus kept sharp
M.DOF_RAMP = 1.5              -- metres from sharp to the full blur
M.CHEST = 1.2                 -- metres above the feet the focus sits

M.FOG = { "fog_depth_range", "fog_sun_blend" }
M.DOF = { "dof_amount", "dof_near_setting", "dof_far_setting" }
M.KIND = { fog_depth_range = "vector2", fog_sun_blend = "vector3", dof_amount = "scalar",
	dof_near_setting = "vector2", dof_far_setting = "vector2" }

local function g(name) return rawget(_G, name) end

-- What the options ask of the shading now, by name: a value, or false for the planet's own.
-- o: fog (Reduce fog, 0 to 1), planet_fog (fog_depth_range), planet_sun (fog_sun_blend, sun_color and
-- fog_color of the planet, each nil when unknown), dof ("game", "off" or "helldiver"), focus (metres to the Helldiver, nil when unknown).
function M.wanted(o)
	local out = {}
	local planet = type(o.planet_fog) == "table" and tonumber(o.planet_fog[1]) and tonumber(o.planet_fog[2]) and o.planet_fog
	local m = math.min(1, tonumber(o.fog) or 1)
	out.fog_depth_range, out.fog_sun_blend = false, false
	if m <= 0 then
		out.fog_depth_range = { M.NO_FOG[1], M.NO_FOG[2] }
	elseif m < 1 then
		m = math.max(M.FOG_LEAST, m)
		if planet then
			out.fog_depth_range = { planet[1], planet[1] + (planet[2] - planet[1]) / m }
		end
		out.fog_sun_blend = M.sun_blend(o.planet_sun, m)
	end
	if o.dof == "off" then
		out.dof_amount, out.dof_near_setting, out.dof_far_setting = 0, false, false
	elseif o.dof == "helldiver" and type(o.focus) == "number" then
		local ramp = M.DOF_RAMP
		out.dof_amount = M.DOF_BLUR
		out.dof_near_setting = { math.max(0, o.focus - M.DOF_DEPTH / 2), ramp }
		out.dof_far_setting = { o.focus + M.DOF_DEPTH / 2, ramp }
	else
		out.dof_amount, out.dof_near_setting, out.dof_far_setting = false, false, false
	end
	return out
end

local function vec3(v)
	return type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) and tonumber(v[3]) and v or nil
end

local function lum(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end

-- The planet's fog_sun_blend for Reduce fog m (between 0 and 1): the blend times m, and the strength
-- lowered so sun_color * strength is at most SUN_CAP times as bright as fog_color. false when unknown.
function M.sun_blend(sun, m)
	if type(sun) ~= "table" then return false end
	local blend, color, fog = vec3(sun.blend), vec3(sun.color), vec3(sun.fog)
	if not (blend and color and fog) then return false end
	local strength = blend[3]
	local bright = lum(color)
	if bright > 0 then strength = math.min(strength, M.SUN_CAP * math.max(0, lum(fog)) / bright) end
	return { blend[1] * m, blend[2], strength }
end

-- Close enough to leave as sent: the focus of the depth of field moves with every step, and a
-- quarter metre more or less of sharp ground doesn't show.
local TOLERANCE = { dof_near_setting = 0.25, dof_far_setting = 0.25 }

local function same(a, b, tolerance)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for i = 1, math.max(#a, #b) do
		if math.abs((a[i] or 0) - (b[i] or 0)) > (tolerance or 0.02) then return false end
	end
	return true
end

-- name -> the value sent last, or nil while the planet's own holds.
M.applied = {}

-- Sends what changed. shading: api.world.shading.
function M.apply(shading, want)
	for name, value in pairs(want) do
		local now = M.applied[name]
		if value == false then
			if now ~= nil then
				pcall(shading, name, M.KIND[name])
				M.applied[name] = nil
			end
		elseif now == nil or not same(now, value, TOLERANCE[name]) then
			local ok, done = pcall(shading, name, M.KIND[name], value)
			if ok and done then M.applied[name] = value end
		end
	end
end

-- Another mod holds the camera: the fog goes back to the planet's, and the depth of field
-- is forgotten without a call, as that mod sets its own.
function M.step_aside(shading)
	for _, list in ipairs({ M.FOG }) do
		for _, name in ipairs(list) do
			if M.applied[name] ~= nil then
				pcall(shading, name, M.KIND[name])
				M.applied[name] = nil
			end
		end
	end
	for _, name in ipairs(M.DOF) do M.applied[name] = nil end
end

-- Metres from the drawn camera to the chest of this player's Helldiver, or nil.
function M.focus(env, api)
	local unit = nil
	if env.view and env.view.watching then unit = env.view.target
	elseif env.view and env.view.avatar then unit = env.view.avatar
	elseif api.game and api.game.my_unit then unit = api.game.my_unit() end
	if unit == nil then return nil end
	local U, C = g("Unit"), g("Camera")
	if not (U and C) then return nil end
	local ok, d = pcall(function()
		if not U.alive(unit) then return nil end
		local p = U.world_position(unit, 0)
		local chest = { x = p.x, y = p.y, z = p.z + M.CHEST }
		local at = env.view and env.view.position
		if not at then
			local cm = g("CameraManager")
			local c = C.local_position(cm.viewport:get_camera())
			at = { x = c.x, y = c.y, z = c.z }
		end
		return rig.length(rig.sub(chest, at))
	end)
	return ok and d or nil
end

M.READ_EVERY = 30             -- frames between reads of the planet's sun and fog colours
-- Frames at the start of a mission the planet's fog is read again each frame before any of it is sent:
-- the first frames hold another environment's (a probe read a fog span of 36 m where the planet's is
-- 127 m, and Reduce fog then stretched the wrong one). Once sent, the fog can't be read back.
M.SETTLE = 120
local planet = { fog = nil, sun = nil, read = false, wait = 0, settle = 0 }

function M.frame(env)
	if env.off then return end
	local api = env.api
	local world = api and api.world
	if not (world and world.shading) then return end
	local in_mission = api.game and api.game.in_mission and api.game.in_mission()
	if not in_mission then
		-- The values hold into the next mission; they are sent again there for its planet.
		M.applied, planet.read = {}, false
		return
	end
	local cam = world.camera
	if cam and cam.taken then
		local ok, taken = pcall(cam.taken)
		if ok and taken then
			M.step_aside(world.shading)
			return
		end
	end
	if world.planet_shading then
		local function read(name)
			local ok, v = pcall(world.planet_shading, name)
			return ok and v or nil
		end
		if not planet.read then
			planet.read, planet.wait, planet.settle = true, 0, M.SETTLE + 1
			planet.sun = {}
		end
		if planet.settle > 0 then
			planet.settle = planet.settle - 1
			planet.fog = read("fog_depth_range") or planet.fog
			planet.sun.blend = read("fog_sun_blend") or planet.sun.blend
		end
		-- The sun and fog colours settle after the first frames of a mission (a probe read another
		-- sun there), and this mod never sets them, so they are read again every READ_EVERY frames.
		planet.wait = planet.wait - 1
		if planet.wait <= 0 then
			planet.wait = M.READ_EVERY
			planet.sun.color = read("sun_color") or planet.sun.color
			planet.sun.fog = read("fog_color") or planet.sun.fog
		end
	end
	local config = env.config
	local dof = config.get("depth_of_field") or "off"
	M.apply(world.shading, M.wanted({
		fog = tonumber(config.get("reduce_fog")) or M.FOG_DEFAULT,
		planet_fog = planet.settle <= 0 and planet.fog or nil,
		planet_sun = planet.settle <= 0 and planet.sun or nil,
		dof = dof,
		focus = dof == "helldiver" and M.focus(env, api) or nil,
	}))
end

function M.start(env)
	local failed = false
	obsidian.on_frame(function()
		if failed then return end
		local ok, err = pcall(M.frame, env)
		if not ok then
			failed = true
			env.log("Eyes of Liberty: look stopped: " .. tostring(err))
		end
	end, env.VIEW)
end

M._planet = planet -- for tests
return M
