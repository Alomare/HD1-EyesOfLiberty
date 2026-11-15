-- Look: fog and depth of field, and Photo Mode taking over while it holds the camera.
local E = dofile("tests/engine.lua")

local function look() return obsidian.module("src/look") end

-- A fake API: shading calls are recorded as { name, kind, value }.
local function api(calls, opts)
	return {
		game = { in_mission = function() return opts.mission ~= false end, my_unit = function() return nil end },
		world = {
			camera = { taken = function() return opts.taken == true end },
			planet_shading = function(name)
				if name == "fog_depth_range" then return { 20, 120 } end
				if name == "bloom_threshold_offset" then return { 0.3, 0.4 } end
			end,
			shading = function(name, kind, value) calls[#calls + 1] = { name, kind, value } return true end,
		},
	}
end

local function started(calls, opts)
	local e = E.install()
	local env = E.env(api(calls, opts))
	env.config.start(env)
	local l = look()
	l.applied = {}
	l._planet.read = false
	l.start(env)
	return e, env
end

local function frame() for _, f in ipairs(FRAMES) do f.fn() end end

local function last(calls, name)
	for i = #calls, 1, -1 do if calls[i][1] == name then return calls[i] end end
end

local function count(calls, name)
	local n = 0
	for _, c in ipairs(calls) do if c[1] == name then n = n + 1 end end
	return n
end

return {
	{ "what each option asks of the shading", function()
		local l = look()
		local w = l.wanted({ no_fog = true, dof = "off" })
		eq(w.fog_depth_range[1], l.NO_FOG[1])
		eq(w.bloom_threshold_offset, nil, "bloom left to the game")
		eq(w.dof_amount, 0) eq(w.dof_near_setting, false)
		w = l.wanted({ far = true, planet_fog = { 20, 120 }, dof = "game" })
		eq(w.fog_depth_range[2], 300, "the long view")
		eq(w.dof_amount, false, "the planet's depth of field")
		w = l.wanted({ dof = "helldiver", focus = 3 })
		eq(w.dof_amount, l.DOF_BLUR)
		eq(w.dof_near_setting[1], 2) eq(w.dof_far_setting[1], 4, "blurred from 4 m on, past the Helldiver 3 m off")
		eq(w.dof_far_setting[2], l.DOF_RAMP)
		near(l.focus({ view = { first = true, position = { x = 0, y = 0, z = 0 } }, state = { aim_point = { x = 0, y = 20, z = 0 } } }, {}),
			20, "first person: the crosshair point")
		eq(l.focus({ view = { first = true, position = { x = 0, y = 0, z = 0 } }, state = { aim_point = { x = 0, y = 0.2, z = 0 } } }, {}),
			l.FP_FOCUS_MIN, "never closer than a metre")
		eq(l.wanted({}).fog_depth_range, false, "the planet's fog")
	end },

	{ "by default the fog and the depth of field go, once each, and the bloom stays", function()
		local calls = {}
		started(calls, {})
		frame()
		eq(last(calls, "fog_depth_range")[3][1], look().NO_FOG[1])
		eq(count(calls, "bloom_threshold_offset"), 0, "bloom untouched")
		eq(last(calls, "dof_amount")[3], 0)
		local n = #calls
		frame()
		eq(#calls, n, "nothing sent again while nothing changes")
		E.remove()
	end },

	{ "Photo Mode holding the camera gets the planet's fog, and the values come back after", function()
		local calls = {}
		local opts = {}
		started(calls, opts)
		frame()
		opts.taken = true
		frame()
		local fog = last(calls, "fog_depth_range")
		eq(fog[3], nil, "the planet's fog") eq(fog[2], "vector2")
		eq(count(calls, "dof_amount"), 1, "the depth of field is Photo Mode's to set")
		frame()
		eq(count(calls, "fog_depth_range"), 2, "nothing more while it holds the camera")
		opts.taken = false
		frame()
		eq(last(calls, "fog_depth_range")[3][1], look().NO_FOG[1], "no fog again")
		eq(count(calls, "dof_amount"), 2, "the depth of field sent again")
		E.remove()
	end },

	{ "options off leave the planet's look, and nothing is sent off a mission", function()
		OPTIONS.no_fog, OPTIONS.depth_of_field, OPTIONS.far_view = false, "game", false
		local calls = {}
		started(calls, {})
		frame()
		eq(#calls, 0)
		local calls2 = {}
		started(calls2, { mission = false })
		frame()
		eq(#calls2, 0, "on the ship")
		E.remove()
	end },
}
