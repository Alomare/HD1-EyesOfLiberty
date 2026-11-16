-- Edge markers: where an out-of-view thing goes on the edge, and what the HUD gui is asked to draw.
local E = dofile("tests/engine.lua")

local function edge() return obsidian.module("src/edge") end
local function cam()
	return obsidian.module("src/frustum").camera_from({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, math.rad(60))
end

-- A HUD with a gui that records its calls.
local function hud(players, objectives, beacons)
	local calls = {}
	local gui = { ui_scale = 1.5, calls = calls }
	function gui:set_ignore_position_scale(v) calls[#calls + 1] = { "pos_scale", v } end
	function gui:set_ignore_size_scale(v) calls[#calls + 1] = { "size_scale", v } end
	function gui:image(icon, p, s, c) calls[#calls + 1] = { "image", icon, p, s, c } end
	function gui:rotated_image(icon, p, s, a, c) calls[#calls + 1] = { "rotated", icon, p, s, a, c } end
	return {
		hd_gui = gui, players = players or {}, hud_info = {},
		entity_manager = { get_slave_entities = function() return beacons or {} end },
		mission_manager = { get_objectives = function() return objectives or {} end },
	}, calls
end

local function player(unit)
	return { player_go = { exists = function() return true end, get = function() return unit end } }
end

local function setup(units, states)
	local e = E.install()
	for u, p in pairs(units) do e.units[u] = { position = p } end
	_G.EntityAux = { state = function(u, kind) return (states[u] or {})[kind] end }
	_G.Color = function(a, r, gg, b) return { a, r, gg, b } end
	_G.Vector2 = function(x, y) return { x = x, y = y } end
	_G.Vector2Aux = { unbox = function(t) return { x = t.x, y = t.y } end }
	_G.GameSettings = { player_colors = { { 255, 255, 130, 0 }, { 255, 0, 10, 235 } } }
	_G.LoadoutSettings = { stratagems = { [7] = { icon = "stratagem_icon_7" } } }
	_G.HudSettings = nil
	_G.CameraManager = { viewport = { window = function() return 1920, 1080 end } }
	local env = { state = { active = true }, view = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, fov = 60 },
		api = { game = { my_unit = function() return "me" end, in_mission = function() return true end } } }
	return e, env
end

local function drawn(calls, kind)
	local out = {}
	for _, c in ipairs(calls) do if c[1] == kind then out[#out + 1] = c end end
	return out
end

return {
	{ "a point ahead is on screen, one off to the side or behind is not", function()
		local m = edge()
		local on, x, y = m.locate(cam(), { x = 0, y = 10, z = 0 }, 1920, 1080, 0)
		eq(on, true) near(x, 960, "middle") near(y, 540)
		local side, _, _, dx = m.locate(cam(), { x = 30, y = 10, z = 0 }, 1920, 1080, 0)
		eq(side, false, "far right is off screen") assert(dx > 0, "points right")
		local back, _, _, bx, by = m.locate(cam(), { x = 5, y = -10, z = 0 }, 1920, 1080, 0)
		eq(back, false, "behind is off screen") assert(bx > 0, "behind and right points right")
		local dead, _, _, zx, zy = m.locate(cam(), { x = 0, y = -10, z = 0 }, 1920, 1080, 0)
		eq(dead, false) eq(zx, 0) eq(zy, -1, "straight behind points down")
	end },

	{ "the edge point stays the inset inside the screen", function()
		local m = edge()
		local x, y = m.edge(1, 0, 1920, 1080, 40)
		near(x, 1880, "right edge") near(y, 540)
		x, y = m.edge(0, -1, 1920, 1080, 40)
		near(x, 960) near(y, 40, "bottom edge")
		x, y = m.edge(1, 1, 1920, 1080, 40)
		near(y, 1040, "the top comes first on a wide screen") assert(x < 1880)
	end },

	{ "art turns clockwise to point the right way", function()
		local m = edge()
		near(m.turn(math.pi, math.pi), 0, "the left arrow pointing left stays")
		near(m.turn(math.pi, math.pi / 2), math.pi / 2, "left to up is a quarter turn clockwise")
		near(math.abs(m.turn(math.pi, 0)), math.pi, "left to right is half a turn")
	end },

	{ "the bottom inset keeps markers above the player panels", function()
		local _, y = edge().edge(0, -1, 1920, 1080, 40, 150)
		near(y, 150)
		local _, top = edge().edge(0, 1, 1920, 1080, 40, 150)
		near(top, 1040, "the top keeps the plain inset")
	end },

	{ "objectives and beacons out of view get icon and arrow; allies are the game's own marker", function()
		local e, env = setup({ me = { x = 0, y = 0, z = 0 }, ally = { x = 0, y = -20, z = 0 }, near = { x = 0, y = 10, z = 0 },
			downed = { x = 40, y = 5, z = 0 }, beacon = { x = -40, y = 5, z = 0 } },
			{ ally = { health = {} }, near = { health = {} }, downed = { health = { is_downed = true } }, me = { health = {} } })
		local objectives = {
			{ icon = "icon_map_objective_flag_01", state = "pending", position = { { x = 0, y = 500, z = 300 } } },
			{ icon = "icon_map_objective_antenna_01", state = "complete", position = { { x = 0, y = -50, z = 0 } } },
		}
		local beacons = { beacon = { state = { stratagem_id = 7, has_been_enabled = true } } }
		local h, calls = hud({ player("me"), player("ally"), player("near"), player("downed") }, objectives, beacons)
		edge().draw(h, env)
		local rotated, images = drawn(calls, "rotated"), drawn(calls, "image")
		local arrows, players = 0, 0
		for _, c in ipairs(rotated) do
			if c[2] == "icon_arrow_01" then arrows = arrows + 1 end
			if c[2] == "icon_map_player_01" then players = players + 1 end
		end
		eq(players, 0, "no arrows of its own for allies")
		eq(#images, 2, "the beacon and the pending objective above the view")
		eq(arrows, 2, "each with an arrow")
		eq(calls[#calls][1], "size_scale") eq(calls[#calls - 1][2], false, "the gui scales are given back")
		E.remove()
	end },
}
