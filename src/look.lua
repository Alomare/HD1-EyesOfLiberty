-- The look of a mission: fog and depth of field, through Obsidian API's shading (unguarded,
-- this player's picture alone).
--
--   reduce_fog      Reduce fog, the only option that changes the fog: a multiplier from 0.1 to 1 on
--                   how fast it builds up with distance (0.5 by default: half as fast), in either view. The
--                   game's fog shader has no strength of its own: it thickens with distance at
--                   1 / (end - start) of fog_depth_range, from the start on (an exponential fog, which
--                   also thins with height at the same rate). So the start stays and the span from
--                   start to end is 1 / the multiplier times as long. 1 leaves the game's fog.
--   depth_of_field  "game" leaves the planet's, "off" takes it away, "helldiver" keeps the Helldiver
--                   sharp and blurs what is nearer or farther, as Photo Mode's focus on the player does
--
-- While another mod holds the camera (Photo Mode does), nothing is sent: the fog goes
-- back to the planet's, the depth of field is left to that mod, and everything is sent again once
-- the camera is free.
local rig = obsidian.module("src/rig")

local M = {}

M.FOG_LEAST = 0.1             -- the thinnest Reduce fog: a tenth
M.FOG_DEFAULT = 0.5
-- Photo Mode keeps 6 m sharp around a player about 12 m off; with the shoulder camera 3 m off, that
-- left nothing nearer than 9 m blurred, and the option looked like it did nothing.
M.DOF_BLUR = 1                -- the strongest blur Photo Mode offers
M.DOF_DEPTH = 2               -- metres around the focus kept sharp
M.DOF_RAMP = 1.5              -- metres from sharp to the full blur
M.CHEST = 1.2                 -- metres above the feet the focus sits

M.FOG = { "fog_depth_range" }
M.DOF = { "dof_amount", "dof_near_setting", "dof_far_setting" }
M.KIND = { fog_depth_range = "vector2", dof_amount = "scalar",
	dof_near_setting = "vector2", dof_far_setting = "vector2" }

local function g(name) return rawget(_G, name) end

-- What the options ask of the shading now, by name: a value, or false for the planet's own.
-- o: fog (Reduce fog, FOG_LEAST to 1), planet_fog,
-- dof ("game", "off" or "helldiver"), focus (metres to the Helldiver, nil when unknown).
function M.wanted(o)
	local out = {}
	local planet = type(o.planet_fog) == "table" and tonumber(o.planet_fog[1]) and tonumber(o.planet_fog[2]) and o.planet_fog
	local thin = 1 / math.max(M.FOG_LEAST, math.min(1, tonumber(o.fog) or 1))
	if planet and thin > 1 then
		out.fog_depth_range = { planet[1], planet[1] + (planet[2] - planet[1]) * thin }
	else
		out.fog_depth_range = false
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

local planet = { fog = nil, read = false }

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
	if not planet.read and world.planet_shading then
		planet.read = true
		local ok, fog = pcall(world.planet_shading, "fog_depth_range")
		planet.fog = ok and fog or nil
	end
	local config = env.config
	local dof = config.get("depth_of_field") or "off"
	M.apply(world.shading, M.wanted({
		fog = tonumber(config.get("reduce_fog")) or M.FOG_DEFAULT,
		planet_fog = planet.fog,
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
