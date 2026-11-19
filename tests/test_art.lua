-- The mod's own HUD art: the screen gui lasts one mission. The next level's world can compare equal to
-- the old one (a bare pointer at a reused address), so a gui kept by world alone was drawn on after
-- the engine freed it.
local E = dofile("tests/engine.lua")

local function setup()
	local e = E.install()
	local made = {}
	World.create_screen_gui = function(world, ...)
		local gui = { world = world, n = #made + 1 }
		made[#made + 1] = gui
		return gui
	end
	local game = { name = "game", obj = {} }
	local api = { game = {
		in_mission = function() return game.name == "game" end,
		state = function() return game.obj, game.name end,
	} }
	local env = E.env(api)
	local art = obsidian.module("src/art")
	art.start(env)
	local function frame() for _, f in ipairs(FRAMES) do f.fn() end end
	return art, made, game, frame
end

return {
	{ "the gui is made once and kept through a mission", function()
		local art, made = setup()
		local a = art.gui()
		assert(a, "a gui in the mission")
		eq(art.gui(), a, "the same gui on the next call")
		eq(#made, 1, "made once")
		E.remove()
	end },

	{ "a new mission on a world that compares equal gets a new gui", function()
		local art, made, game, frame = setup()
		local a = art.gui()
		game.name = "mission_end"
		frame()
		eq(art.gui(), nil, "no gui outside a mission")
		game.name, game.obj = "game", {}
		local b = art.gui()
		assert(b and b ~= a, "a new gui for the new mission")
		eq(#made, 2, "made again")
		E.remove()
	end },

	{ "a new game state is a new mission even without a frame in between", function()
		local art, made, game = setup()
		local a = art.gui()
		game.obj = {}
		local b = art.gui()
		assert(b and b ~= a, "the old gui is not given back")
		E.remove()
	end },
}
