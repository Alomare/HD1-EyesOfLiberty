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
				if name == "fog_sun_blend" then return { 1, 1, 1 } end
				if name == "sun_color" then return opts.sun or { 8, 8, 8 } end
				if name == "fog_color" then return { 2, 2, 2 } end
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
	l.SETTLE = opts.settle or 0
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
		local w = l.wanted({ fog = 0.1, planet_fog = { 20, 120 }, dof = "off" })
		eq(w.fog_depth_range[1], 20, "the fog starts where it did")
		eq(w.fog_depth_range[2], 1020, "and thickens a tenth as fast: the span ten times as long")
		near(l.wanted({ fog = 0.2, planet_fog = { 20, 120 } }).fog_depth_range[2], 520, "0.2: five times slower")
		eq(l.wanted({ fog = 1, planet_fog = { 20, 120 } }).fog_depth_range, false, "1: the game's fog")
		near(l.wanted({ fog = 0.01, planet_fog = { 20, 120 } }).fog_depth_range[2], 1020, "above none, never below a tenth")
		local none = l.wanted({ fog = 0, planet_fog = { 20, 120 } })
		eq(none.fog_depth_range[1], l.NO_FOG[1], "0: no fog") eq(none.fog_sun_blend, false)
		eq(l.wanted({ fog = 0 }).fog_depth_range[1], l.NO_FOG[1], "no fog without reading the planet")
		local sun = { blend = { 1, 1.3, 1 }, color = { 8, 8, 8 }, fog = { 2, 2, 2 } }
		local sb = l.wanted({ fog = 0.5, planet_fog = { 20, 120 }, planet_sun = sun }).fog_sun_blend
		near(sb[1], 0.5, "the sun blend halves with the fog") near(sb[2], 1.3, "the same spread")
		near(sb[3] * 8, l.SUN_CAP * 2, "the sun side held to SUN_CAP times the fog colour")
		sun.color = { 1, 1, 1 }
		near(l.wanted({ fog = 0.5, planet_sun = sun }).fog_sun_blend[3], 1, "a dim sun keeps its strength")
		eq(l.wanted({ fog = 1, planet_sun = sun }).fog_sun_blend, false, "1: the game's sun blend")
		eq(l.wanted({ fog = 0.5, planet_sun = { blend = { 1, 1, 1 } } }).fog_sun_blend, false, "colours unknown: left")
		eq(l.wanted({ fog = 0.1 }).fog_depth_range, false, "the planet's fog not read yet: left alone")
		eq(w.bloom_threshold_offset, nil, "bloom left to the game")
		eq(w.dof_amount, 0) eq(w.dof_near_setting, false)
		w = l.wanted({ far = true, fog = 1, planet_fog = { 20, 120 }, dof = "game" })
		eq(w.fog_depth_range, false, "the long view leaves the fog alone")
		eq(w.dof_amount, false, "the planet's depth of field")
		w = l.wanted({ dof = "helldiver", focus = 3 })
		eq(w.dof_amount, l.DOF_BLUR)
		eq(w.dof_near_setting[1], 2) eq(w.dof_far_setting[1], 4, "blurred from 4 m on, past the Helldiver 3 m off")
		eq(w.dof_far_setting[2], l.DOF_RAMP)
		eq(l.wanted({}).fog_depth_range, false, "the planet's fog")
	end },

	{ "the fog waits for the level to settle before it is stretched", function()
		local calls = {}
		started(calls, { settle = 3 })
		for _ = 1, 3 do frame() end
		eq(last(calls, "fog_depth_range"), nil, "nothing sent while the planet's fog may still change")
		frame()
		near(last(calls, "fog_depth_range")[3][2], 20 + 100 / look().FOG_DEFAULT, "then the settled fog, stretched")
		E.remove()
	end },

	{ "by default the fog is reduced and the depth of field goes, once each, and the bloom stays", function()
		local calls = {}
		started(calls, {})
		frame()
		near(last(calls, "fog_depth_range")[3][2], 20 + 100 / look().FOG_DEFAULT)
		near(last(calls, "fog_sun_blend")[3][1], look().FOG_DEFAULT, "the sun blend thinned too")
		near(last(calls, "fog_sun_blend")[3][3], look().SUN_CAP * 2 / 8, "the sun side held down")
		eq(last(calls, "fog_sun_blend")[2], "vector3")
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
		eq(last(calls, "fog_sun_blend")[3], nil, "the planet's sun blend")
		eq(count(calls, "dof_amount"), 1, "the depth of field is Photo Mode's to set")
		frame()
		eq(count(calls, "fog_depth_range"), 2, "nothing more while it holds the camera")
		opts.taken = false
		frame()
		near(last(calls, "fog_depth_range")[3][2], 20 + 100 / look().FOG_DEFAULT, "reduced fog again")
		eq(count(calls, "dof_amount"), 2, "the depth of field sent again")
		E.remove()
	end },

	{ "options off leave the planet's look, and nothing is sent off a mission", function()
		OPTIONS.reduce_fog, OPTIONS.depth_of_field, OPTIONS.far_view = 1, "game", false
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

	{ "leaving the mission gives the planet's look back, so the ship and menu keep theirs", function()
		local calls, opts = {}, {}
		started(calls, opts)
		frame()
		local sent = {}
		for _, c in ipairs(calls) do sent[c[1]] = true end
		opts.mission = false
		frame()
		for name in pairs(sent) do
			local c = last(calls, name)
			eq(c[3], nil, name .. " given back") eq(c[2], look().KIND[name], name .. " kind")
		end
		eq(next(look().applied), nil, "nothing held")
		local n = #calls
		frame()
		eq(#calls, n, "once")
		opts.mission = nil
		frame()
		near(last(calls, "fog_depth_range")[3][2], 20 + 100 / look().FOG_DEFAULT, "sent again in the next mission")
		E.remove()
	end },

	{ "the sun colour is read again as the level settles", function()
		local calls, opts = {}, { sun = { 80, 80, 80 } }
		started(calls, opts)
		frame()
		near(last(calls, "fog_sun_blend")[3][3], look().SUN_CAP * 2 / 80, "a bright sun in the first frame")
		opts.sun = { 8, 8, 8 }
		for _ = 1, look().READ_EVERY do frame() end
		near(last(calls, "fog_sun_blend")[3][3], look().SUN_CAP * 2 / 8, "the settled sun")
		E.remove()
	end },
}
