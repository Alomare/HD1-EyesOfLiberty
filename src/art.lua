-- The mod's own HUD art (tools/build_hud.py): a screen gui with the material "eyesofliberty/hud" on the
-- world the camera draws, made once per mission. The game's guis can't draw these images, as a gui
-- draws only the materials it was made with.
--
-- Sprites: "eol_idle" (the game's idle aim cursor), "eol_ring" (a white ring) and "eol_hurt" (the edges
-- of the screen). Each is drawn whole, tinted by the colour of the draw.
local M = {}

M.MATERIAL = "eyesofliberty/hud"

local function g(name) return rawget(_G, name) end

-- The gui is kept for one mission only. Kept by world alone (0.12.0), the gui of the level before came
-- back in a later level after the engine had freed it with its world, and drawing on it ended the game
-- (crash in Gui.bitmap_uv). The world handle of the next level can compare equal to the old one. So
-- the gui is dropped as soon as the game leaves the mission, and is also keyed on the game state
-- object, a Lua table held here, which can't be reused while held.
local held = { state = nil, world = nil, gui = nil }
local env_of = nil

function M.forget()
	held.state, held.world, held.gui = nil, nil, nil
end

-- The game state object while in a mission, or nil.
local function mission(env)
	local game = env and env.api and env.api.game
	if not (game and game.in_mission and game.state) then return nil end
	local ok, inside = pcall(game.in_mission)
	if not ok or not inside then return nil end
	local got, state = pcall(game.state)
	if not got or type(state) ~= "table" then return nil end
	return state
end

-- The gui for the world the camera draws now, or nil outside a mission.
function M.gui()
	local state = mission(env_of)
	if state == nil then M.forget() return nil end
	local cm = g("CameraManager")
	if type(cm) ~= "table" or not cm.viewport then return nil end
	local ok, world = pcall(function() return cm.viewport:get_world_proxy():get_world() end)
	if not ok or world == nil then return nil end
	if held.gui and held.state == state and held.world == world then return held.gui end
	local made, gui = pcall(g("World").create_screen_gui, world, "immediate", "material", M.MATERIAL)
	if not made or gui == nil then return nil end
	held.state, held.world, held.gui = state, world, gui
	return gui
end

function M.start(env)
	env_of = env
	obsidian.on_frame(function()
		if held.gui and mission(env) ~= held.state then M.forget() end
	end, env.VIEW)
end

-- Draws a sprite with the bottom left corner at (x, y) pixels from the bottom left of the window, w by
-- h, at layer z, tinted (a, r, g, b).
function M.draw(gui, sprite, x, y, w, h, z, a, r, gc, b)
	local V2, V3, C = g("Vector2"), g("Vector3"), g("Color")
	g("Gui").bitmap_uv(gui, sprite, V2(0, 0), V2(1, 1), V3(x, y, z or 0), V2(w, h), C(a, r, gc, b))
end

return M
