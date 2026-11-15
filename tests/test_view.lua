-- View: the long view and the sky.
local E = dofile("tests/engine.lua")

local function view() return obsidian.module("src/view") end

local function started(api)
	local e = E.install()
	local env = E.env(api)
	env.config.start(env)
	obsidian.module("src/camera").start(env)
	view().start(env)
	return e, env
end

local function frame(e, env, masters)
	E.hook("InputComponent", "update_masters")(function() end, {}, masters, 0.016)
	E.hook("CameraManager", "update")(function() end, CameraManager, 0.016)
end

-- A fake API that records shading and detail calls.
local function api(calls, in_mission)
	return {
		game = { in_mission = function() return in_mission end },
		world = {
			planet_shading = function(name)
				if name == "fog_depth_range" then return { 20, 120 } end
				if name == "fog_color" then return { 0.31, 0.30, 0.275 } end
			end,
			shading = function(name, kind, value) calls[#calls + 1] = { name, kind, value } return true end,
			detail = function(v) calls.detail = v return true end,
		},
	}
end

return {
	{ "fog range, sky choice and sky brightness", function()
		local v = view()
		local r = v.fog_range({ 20, 120 }, 2.5)
		eq(r[1], 50) eq(r[2], 300)
		eq(v.fog_range(nil, 2), nil)
		for _, t in ipairs({ "dawn", "day", "dusk", "night" }) do eq(v.sky_name(t), t, t) end
		eq(v.sky_name("ghost_town"), "day", "another time: day")
		eq(v.sky_name(nil), "day", "unknown: day")
		eq(v.SKY_INTENSITY, 1, "Photo Mode's brightness")
		-- The sun of a level whose light travels toward -x stands at +x: no turn. Toward -y: a quarter turn.
		near(v.sky_yaw({ -1, 0, -1 }), 0, "sun at +x")
		near(v.sky_yaw({ 0, -1, -0.5 }), math.pi / 2, "sun at +y")
		eq(v.sky_yaw({ 0, 0, -1 }), nil, "straight up")
		eq(v.sky_yaw(nil), nil, "no value")
		-- The time comes from the game state's level, the camera manager's after.
		local api = { game = { state = function() return { generated_level = { time_of_day = "night" } } end } }
		eq(v.mission_time(api), "night", "the game state's level")
		CameraManager = { generated_level = { shading_environment_setting = "dusk" } }
		eq(v.mission_time({ game = { state = function() return {} end } }), "dusk", "the camera manager's copy")
		CameraManager = nil
	end },

	{ "the long view pushes the far range and the detail out, and gives them back", function()
		OPTIONS.far_view = true
		local calls = {}
		local e, env = started(api(calls, true))
		local masters = E.player(e, "me")
		frame(e, env, masters)
		eq(#calls, 0, "the fog is src/look.lua's")
		eq(calls.detail, view().DETAIL)
		eq(e.calls.set_far_range[2], view().FAR)
		KEYS.toggle_view.fn() KEYS.toggle_view.fn() -- first person, then top-down
		frame(e, env, masters)
		eq(calls.detail, nil, "the game's detail back")
		E.remove()
	end },

	{ "no sky is spawned when the skies were not deployed", function()
		OPTIONS.fix_sky = false
		local e, env = started(api({}, true))
		local spawned = 0
		World.spawn_unit = function() spawned = spawned + 1 return "dome" end
		frame(e, env, E.player(e, "me"))
		eq(spawned, 0)
		OPTIONS.fix_sky = true
		World.units = function() return {} end
		Unit.set_local_scale = function() end
		Unit.teleport_local_position = function() end
		e.units.dome = { position = { x = 0, y = 0, z = 0 } }
		local name = nil
		World.spawn_unit = function(_, n) name = n spawned = spawned + 1 return "dome" end
		frame(e, env, E.player(e, "me"))
		eq(spawned, 1) eq(name, "unleashedcamera/sky/day", "the day sky when the time is unknown")
		frame(e, env, E.player(e, "me"))
		eq(spawned, 1, "one dome, moved with the camera")
		E.remove()
	end },
}
