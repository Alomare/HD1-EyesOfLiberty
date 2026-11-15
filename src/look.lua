-- The look of a mission: fog, bloom and depth of field, through Obsidian API's shading (unguarded,
-- this player's picture alone).
--
--   no_fog          the planet's fog pushed out of sight (fog_depth_range), in either view
--   far_view        without no_fog, the fog pushed out by FOG_SCALE while third person steers the view
--   no_bloom        the bloom threshold raised past anything on screen (bloom_threshold_offset)
--   depth_of_field  "game" leaves the planet's, "off" takes it away, "helldiver" keeps the Helldiver
--                   sharp and blurs what is nearer or farther, as Photo Mode's focus on the player does
--
-- While another mod holds the camera (Photo Mode does), nothing is sent: the fog and the bloom go
-- back to the planet's, the depth of field is left to that mod, and everything is sent again once
-- the camera is free.
local rig = obsidian.module("src/rig")

local M = {}

M.NO_FOG = { 5000, 5001 }     -- fog that starts past anything the camera draws, as Photo Mode's None
M.FOG_SCALE = 2.5             -- the long view: the planet's fog range times this
M.NO_BLOOM = 100              -- a bloom threshold no surface reaches
M.BLOOM_Y = 0.385             -- the second bloom value when the planet's can't be read
M.DOF_BLUR = 0.7              -- Photo Mode's blur
M.DOF_DEPTH = 6               -- metres around the Helldiver kept sharp
M.CHEST = 1.2                 -- metres above the feet the focus sits

M.FOG = { "fog_depth_range" }
M.BLOOM = { "bloom_threshold_offset" }
M.DOF = { "dof_amount", "dof_near_setting", "dof_far_setting" }
M.KIND = { fog_depth_range = "vector2", bloom_threshold_offset = "vector2", dof_amount = "scalar",
	dof_near_setting = "vector2", dof_far_setting = "vector2" }

local function g(name) return rawget(_G, name) end

-- What the options ask of the shading now, by name: a value, or false for the planet's own.
-- o: no_fog, far (the long view with third person on), planet_fog, no_bloom, planet_bloom,
-- dof ("game", "off" or "helldiver"), focus (metres to the Helldiver, nil when unknown).
function M.wanted(o)
	local out = {}
	if o.no_fog then
		out.fog_depth_range = { M.NO_FOG[1], M.NO_FOG[2] }
	elseif o.far and type(o.planet_fog) == "table" and tonumber(o.planet_fog[1]) and tonumber(o.planet_fog[2]) then
		out.fog_depth_range = { o.planet_fog[1] * M.FOG_SCALE, o.planet_fog[2] * M.FOG_SCALE }
	else
		out.fog_depth_range = false
	end
	if o.no_bloom then
		local y = type(o.planet_bloom) == "table" and tonumber(o.planet_bloom[2]) or M.BLOOM_Y
		out.bloom_threshold_offset = { M.NO_BLOOM, y }
	else
		out.bloom_threshold_offset = false
	end
	if o.dof == "off" then
		out.dof_amount, out.dof_near_setting, out.dof_far_setting = 0, false, false
	elseif o.dof == "helldiver" and type(o.focus) == "number" then
		local ramp = math.max(1, M.DOF_DEPTH * 0.6)
		out.dof_amount = M.DOF_BLUR
		out.dof_near_setting = { math.max(0, o.focus - M.DOF_DEPTH / 2), ramp }
		out.dof_far_setting = { o.focus + M.DOF_DEPTH / 2, ramp }
	else
		out.dof_amount, out.dof_near_setting, out.dof_far_setting = false, false, false
	end
	return out
end

local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for i = 1, math.max(#a, #b) do
		if math.abs((a[i] or 0) - (b[i] or 0)) > 0.02 then return false end
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
		elseif now == nil or not same(now, value) then
			local ok, done = pcall(shading, name, M.KIND[name], value)
			if ok and done then M.applied[name] = value end
		end
	end
end

-- Another mod holds the camera: the fog and the bloom go back to the planet's, and the depth of field
-- is forgotten without a call, as that mod sets its own.
function M.step_aside(shading)
	for _, list in ipairs({ M.FOG, M.BLOOM }) do
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
	if env.view and env.view.avatar then unit = env.view.avatar
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

local planet = { fog = nil, bloom = nil, read = false }

function M.frame(env)
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
		local got, bloom = pcall(world.planet_shading, "bloom_threshold_offset")
		planet.bloom = got and bloom or nil
	end
	local config = env.config
	local dof = config.get("depth_of_field") or "off"
	M.apply(world.shading, M.wanted({
		no_fog = config.get("no_fog") ~= false,
		far = config.get("far_view") ~= false and env.state.active,
		planet_fog = planet.fog,
		no_bloom = config.get("no_bloom") ~= false,
		planet_bloom = planet.bloom,
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
			env.log("Unleashed Camera: look stopped: " .. tostring(err))
		end
	end, env.VIEW)
end

M._planet = planet -- for tests
return M
