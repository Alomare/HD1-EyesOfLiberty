-- The game's own crosshair at the middle of the view while third person steers it.
--
-- In the top-down view the game shows its aiming cursor as a hardware cursor at the mouse
-- (CursorManager, "hud/cursors/game"). Under the shoulder camera the mouse turns the view and is kept
-- near the middle of the window, so that cursor stays hidden (src/camera.lua) and the image the game
-- draws for it, "cursor_game" of the input component's cursor gui, is drawn at the crosshair instead:
-- in a vehicle always, on foot while the aim button, fire or a throw is held. Between shots the game
-- shows the idle cursor ("hud/cursors/game_inactive", a faint dot) when the game option keeps the crosshair
-- up, and nothing otherwise; the shoulder view does the same with that cursor's image, "eol_idle" of
-- the mod's art (src/art.lua). Another mod that draws the crosshair (claim_crosshair in
-- main.lua, as Custom Crosshair does) turns this one off. While sprinting the crosshair fades out
-- (state.sprint_fade, from src/camera.lua), and the export hands the same fade to the other mod.
local scoped = obsidian.module("src/scoped")
local art = obsidian.module("src/art")

local M = {}

M.SPRITE = "cursor_game"
M.IDLE = "eol_idle"
M.SIZE = 32

local function g(name) return rawget(_G, name) end

-- The game option that keeps the crosshair up between shots.
function M.always_on()
	local save = g("SaveManager")
	if type(save) ~= "table" or type(save.get) ~= "function" then return false end
	local ok, on = pcall(save.get, save, "crosshair_always_visible")
	return ok and on and true or false
end

-- Which cursor shows now: "aim", "idle" or nil. env.api may be nil. always: the game option above.
function M.look(env, always)
	local state = env.state
	if not state.active or not state.crosshair or state.claimed_by or state.dropping then return nil end
	if (state.sprint_fade or 1) <= 0.01 then return nil end
	local camera = env.camera
	local input = camera and camera.input
	if input and not input.look then return nil end
	local kind = (state.vehicle or state.aiming or state.firing) and "aim" or (always and "idle") or nil
	if not kind then return nil end
	local api = env.api
	if api then
		if api.capture and api.capture.busy then
			local ok, busy = pcall(api.capture.busy)
			if ok and busy then return nil end
		end
		if api.map and api.map.is_open then
			local ok, open = pcall(api.map.is_open)
			if ok and open then return nil end
		end
	end
	return kind
end

-- Whether a cursor shows now.
function M.visible(env, always)
	return M.look(env, always) ~= nil
end

-- Where the image goes: its bottom left corner and size, centred on (x, y).
function M.rect(x, y)
	local s = M.SIZE
	return x - s / 2, y - s / 2, s
end

function M.draw(gui, env, kind)
	local G, V2 = g("Gui"), g("Vector2")
	local c = env.state.crosshair
	local x, y, s = M.rect(c.x, c.y)
	local alpha = math.floor(255 * math.max(0, math.min(1, env.state.sprint_fade or 1)) + 0.5)
	if kind == "idle" then
		local own = art.gui()
		if own then art.draw(own, M.IDLE, x, y, s, s, 0, alpha, 255, 255, 255) end
		return
	end
	G.bitmap_uv(gui, M.SPRITE, V2(0, 0), V2(1, 1), V2(x, y), V2(s, s), g("Color")(alpha, 255, 255, 255))
end

function M.start(env)
	local failed = false
	-- The game draws its cursor images while it reads input; the crosshair goes on the same gui then.
	obsidian.hook("InputComponent", "update_masters", function(original, self, ...)
		local r = scoped.pack(original(self, ...))
		local kind = not failed and type(self) == "table" and self.cursor_gui and M.look(env, M.always_on())
		if kind then
			local ok, err = pcall(M.draw, self.cursor_gui, env, kind)
			if not ok then
				failed = true
				env.log("Eyes of Liberty: crosshair stopped: " .. tostring(err))
			end
		end
		return unpack(r, 1, r.n)
	end, env.VIEW)
end

return M
