-- The mod's own HUD art (tools/build_hud.py): a screen gui with the material "eyesofliberty/hud" on the
-- world the camera draws, made once per world. The game's guis can't draw these images, as a gui
-- draws only the materials it was made with.
--
-- Sprites: "eol_idle" (the game's idle aim cursor), "eol_ring" (a white ring) and "eol_hurt" (the edges
-- of the screen). Each is drawn whole, tinted by the colour of the draw.
local M = {}

M.MATERIAL = "eyesofliberty/hud"

local function g(name) return rawget(_G, name) end

local held = { world = nil, gui = nil }

-- The gui for the world the camera draws now, or nil outside a level.
function M.gui()
	local cm = g("CameraManager")
	if type(cm) ~= "table" or not cm.viewport then return nil end
	local ok, world = pcall(function() return cm.viewport:get_world_proxy():get_world() end)
	if not ok or world == nil then return nil end
	if held.gui and held.world == world then return held.gui end
	-- A gui goes with the world it was made on: one from an earlier level is only forgotten.
	local made, gui = pcall(g("World").create_screen_gui, world, "immediate", "material", M.MATERIAL)
	if not made or gui == nil then return nil end
	held.world, held.gui = world, gui
	return gui
end

-- Draws a sprite with the bottom left corner at (x, y) pixels from the bottom left of the window, w by
-- h, at layer z, tinted (a, r, g, b).
function M.draw(gui, sprite, x, y, w, h, z, a, r, gc, b)
	local V2, V3, C = g("Vector2"), g("Vector3"), g("Color")
	g("Gui").bitmap_uv(gui, sprite, V2(0, 0), V2(1, 1), V3(x, y, z or 0), V2(w, h), C(a, r, gc, b))
end

return M
