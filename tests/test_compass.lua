-- Compass: bearings, the marks across the span, and which objectives show.
local E = dofile("tests/engine.lua")

local function compass() return obsidian.module("src/compass") end

-- A kit that records what it draws.
local function recorder()
	local calls = {}
	local kit = setmetatable({}, { __index = function(_, name)
		return function(_, ...)
			calls[#calls + 1] = { name, ... }
			if name == "icon" then return true end
		end
	end })
	kit.clip = function(_, x, y, w, h, fn) calls[#calls + 1] = { "clip", x, y, w, h } fn(kit) end
	return kit, calls
end

return {
	{ "bearings run clockwise from north, and gaps take the short way round", function()
		local c = compass()
		eq(c.bearing(0, 1), 0, "north")
		eq(c.bearing(1, 0), 90, "east")
		eq(c.bearing(0, -1), 180, "south")
		eq(c.bearing(-1, 0), 270, "west")
		eq(c.gap(350, 10), 20, "past north to the right")
		eq(c.gap(10, 350), -20, "past north to the left")
	end },

	{ "letters on the cardinal points, numbers on the 45s between, ticks on the rest", function()
		local c = compass()
		local by = {}
		for _, m in ipairs(c.marks(0)) do by[m[1]] = m end
		eq(by[0][3], "N")
		eq(by[45][3], "45")
		eq(by[315][3], "315")
		eq(by[15][2], "tick")
		eq(by[90], nil, "east is past the edge of a 120 degree span")
		local east = {}
		for _, m in ipairs(c.marks(90)) do east[m[1]] = m end
		eq(east[90][3], "E")
		eq(east[135][3], "135")
		local x, inside = c.place(0, 30, 480)
		eq(x, 120, "30 degrees right is a quarter of the trough right of the middle")
		eq(inside, true)
	end },

	{ "only objectives found and not done show, each place once", function()
		local c = compass()
		local list = {
			{ icon = "a", state = "pending", position = { { x = 1, y = 2 } } },
			{ icon = "b", state = "pending", position = { { x = 3, y = 4 } }, objective_hidden_data = { radius = 30 } },
			{ icon = "c", state = "complete", position = { { x = 5, y = 6 } } },
			{ icon = "d", state = "pending", position = { { x = 7, y = 8 }, { x = 9, y = 10 } } },
		}
		local shown = c.objectives(list, function(b) return b end)
		eq(#shown, 3, "a and both places of d")
		eq(shown[1].icon, "a")
		eq(shown[3].x, 9)
	end },

	{ "the strip draws in third person in a mission and shows an objective at its bearing", function()
		local e = E.install()
		local kit, calls = recorder()
		obsidian.ui = { canvas = function() return kit end }
		e.units.me = { position = { x = 0, y = 0, z = 0 } }
		local mm = { get_objectives = function() return { { icon = "icon_obj", state = "pending", position = { { x = 100, y = 0, z = 0 } } } } end }
		local api = { game = { in_mission = function() return true end, my_unit = function() return "me" end, state = function() return { mission_manager = mm } end } }
		local env = E.env(api)
		env.config.get = function() return nil end
		env.view = { forward = { x = 1, y = 0, z = 0 } }
		compass().start(env)
		local function frame() for _, f in ipairs(FRAMES) do f.fn() end end
		frame()
		eq(#calls, 0, "top-down: nothing")
		env.state.active = true
		frame()
		local icon, letters = nil, {}
		for _, call in ipairs(calls) do
			if call[1] == "icon" and call[2] == "icon_obj" then icon = call end
			if call[1] == "text" then letters[call[2]] = true end
		end
		assert(icon, "the objective's icon")
		near(icon[3] + icon[5] / 2, 960, "east of the Helldiver while facing east: the middle of the screen")
		assert(letters.E and letters["45"] and letters["135"], "E with 45 and 135 beside it")
		obsidian.ui = nil
		E.remove()
	end },
}
