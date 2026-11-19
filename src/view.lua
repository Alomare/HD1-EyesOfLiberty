-- What the shoulder camera sees that the top-down one never did: the distance and a sky. Each applies
-- only while third person steers the view, and goes back with it.
--
--   far_view    the camera's far range and distant models keeping their detail (API detail, the
--               lod_object_multiplier setting). The fog is left to Reduce fog (src/look.lua).
--   fix_sky     a sky around the camera for the time of the mission: dawn, day, dusk or night
--               (res/sky_*, drawn by tools/build_sky.py), turned so its sun stands where the level's
--               sun is, added when the option is on at launch, with the render config that clears the
--               picture past the level (Photo Mode's bytes, so the two mods never clash)

local M = {}

local function g(name) return rawget(_G, name) end

M.FAR = 2400          -- metres the camera sees with the long view
M.DETAIL = 2          -- distant models keep detail this many times further
M.SKY_RADIUS = 1800   -- metres
M.SKY_MADE = 500      -- the dome's own radius
-- The skies, by the time of the mission (generated_level.time_of_day: dawn, day, dusk or night).
M.TIMES = { dawn = true, day = true, dusk = true, night = true }
M.SKY_UNIT = "eyesofliberty/sky/"
-- Photo Mode draws its skies at intensity 1, as made. Before 0.8.0 the planet-coloured domes of this
-- mod went to 2 and more, and every sky glowed.
M.SKY_INTENSITY = 1

-- The sky for a mission's time of day, day when unknown. The proving grounds keep their own times,
-- which fall back to day.
function M.sky_name(time)
	if type(time) == "string" and M.TIMES[time] then return time end
	return "day"
end

-- The turn of the dome about the up axis (radians) that puts its sun (drawn at +x) where the level's
-- sun is. sun_direction is the way the sunlight travels (the shading value of that name); nil when the
-- sun stands straight up or the value is missing.
function M.sky_yaw(sun_direction)
	local d = sun_direction
	if type(d) ~= "table" or type(d[1]) ~= "number" or type(d[2]) ~= "number" then return nil end
	if d[1] * d[1] + d[2] * d[2] < 1e-6 then return nil end
	return math.atan2(-d[2], -d[1])
end

-- Far view ------------------------------------------------------------------------------------------

-- range: the camera's far range is held at FAR (the long view, and the sky, which sits 1800 m out).
-- look: the detail of distant models, for the long view only.
local far = { range = false, saved = nil, look = false }

local function look_apply(env)
	if far.look then return end
	far.look = true
	local api = env.api
	if not (api and api.world) then return end
	if api.world.detail then pcall(api.world.detail, M.DETAIL) end
end

local function look_release(env)
	if not far.look then return end
	far.look = false
	local api = env.api
	if api and api.world then
		if api.world.detail then pcall(api.world.detail, nil) end
	end
end

local function range_apply(view)
	local C = g("Camera")
	if not far.range then
		far.range = true
		local ok, f = pcall(C.far_range, view.camera)
		far.saved = ok and f or nil
	end
	pcall(C.set_far_range, view.camera, math.max(far.saved or 0, M.FAR))
end

local function range_release(cm)
	if not far.range then return end
	far.range = false
	if far.saved and type(cm) == "table" and cm.viewport then
		pcall(function() g("Camera").set_far_range(cm.viewport:get_camera(), far.saved) end)
	end
	far.saved = nil
end

-- Sky -----------------------------------------------------------------------------------------------

local sky = { unit = nil, world = nil, name = nil }

-- The skies are in the game only when the option was on at launch: spawning a unit the game hasn't
-- loaded stops the game, past any pcall.
function M.sky_available()
	local ok, on = pcall(obsidian.settings.get, "fix_sky")
	return ok and on == true
end

local function sky_remove()
	if sky.unit and sky.world then
		pcall(function()
			if g("Unit").alive(sky.unit) then g("World").destroy_unit(sky.world, sky.unit) end
		end)
	end
	sky.unit, sky.world, sky.name = nil, nil, nil
end

local function sky_brightness(unit, value)
	local U, Mesh, Mat = g("Unit"), g("Mesh"), g("Material")
	pcall(function()
		for i = 0, U.num_meshes(unit) - 1 do
			local mesh = U.mesh(unit, i)
			for j = 0, Mesh.num_materials(mesh) - 1 do Mat.set_scalar(Mesh.material(mesh, j), "intensity", value) end
		end
	end)
end

-- The time of day of the mission: the generated level of the game state, as Photo Mode reads it
-- (generated_level.lua 34: time_of_day, the same as shading_environment_setting), then the camera
-- manager's copy. Before 0.8.2 only the camera manager's was read, and every mission got the day sky.
function M.mission_time(api)
	local levels = {}
	local ok, st = pcall(function() return api and api.game and api.game.state and api.game.state() end)
	if ok and type(st) == "table" then levels[#levels + 1] = st.generated_level end
	local cm = g("CameraManager")
	if type(cm) == "table" then levels[#levels + 1] = cm.generated_level end
	for _, level in ipairs(levels) do
		if type(level) == "table" then
			local t = level.time_of_day or level.shading_environment_setting
			if type(t) == "string" then return t end
		end
	end
	return nil
end

local function sky_update(env, view)
	local U, V3 = g("Unit"), g("Vector3")
	if not (sky.unit and sky.world == view.world and U.alive(sky.unit)) then
		sky_remove()
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return end
		local name = M.sky_name(M.mission_time(api))
		local ok, unit = pcall(g("World").spawn_unit, view.world, M.SKY_UNIT .. name, V3(view.position.x, view.position.y, 0))
		if not ok or not unit then return end
		sky.unit, sky.world, sky.name = unit, view.world, name
		pcall(U.set_local_scale, unit, 0, V3(M.SKY_RADIUS / M.SKY_MADE, M.SKY_RADIUS / M.SKY_MADE, M.SKY_RADIUS / M.SKY_MADE))
		local ok_s, sun = pcall(function() return api.world.planet_shading("sun_direction") end)
		local yaw = ok_s and M.sky_yaw(sun) or nil
		if yaw then pcall(U.set_local_rotation, unit, 0, g("Quaternion")(V3(0, 0, 1), yaw)) end
		sky_brightness(unit, M.SKY_INTENSITY)
	end
	pcall(U.teleport_local_position, sky.unit, 0, V3(view.position.x, view.position.y, 0))
	pcall(g("World").update_unit, sky.world, sky.unit)
end

function M.start(env)
	local config = env.config
	table.insert(env.on_pose, function(view, cm)
		local long = config.get("far_view") and true or false
		if long then look_apply(env) else look_release(env) end
		if M.sky_available() then sky_update(env, view) else sky_remove() end
		if long or sky.unit then range_apply(view) else range_release(cm) end
	end)
	table.insert(env.on_release, function(cm)
		look_release(env)
		range_release(cm)
		sky_remove()
	end)
end

M._far, M._sky = far, sky -- for tests
return M
