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
--
-- A crosshair shows only while the Helldiver can shoot (state.armed, set each pose): alive, not dropping
-- in the Hellpod, not sitting in a Hellpod on the Super Destroyer (a seat with the drop_pod component,
-- gameobjects/gameobject_hellpod_menu), not putting in a stratagem, the map shut and the death cam off. Down and carrying,
-- the Helldiver still shoots, and the crosshair stays. The export hands the same flag to the other mod, so its crosshair hides at the same moments.
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

-- Whether a Helldiver can shoot, from the HUD state the game shows for it (CharacterComponent.get_hud_state:
-- "normal", "dead", "map", "stratagems" or a vehicle's own).
function M.can_shoot(hud)
	return not (hud == "dead" or hud == "map" or hud == "stratagems")
end

-- Whether the Helldiver's seat in a vehicle has a weapon of its own: a weapon of the seat component
-- (seat_weapon_units) that belongs to the seat the Helldiver sits in (weapon_index_to_seat, nil for
-- every seat), as src/aim.lua own_units reads it. A vehicle with no seat component (a turret) counts as
-- armed. The driver of a vehicle whose guns are on another seat has none.
function M.seat_armed(view)
	if not (view and view.vehicle and view.target and view.avatar) then return true end
	local EA = g("EntityAux")
	local ok, armed = pcall(function()
		if not EA.has_component(view.target, "seat") then return true end
		local seat = EA.state(view.target, "seat")
		local cs = EA.state(view.avatar, "character")
		for i in ipairs(seat.seat_weapon_units or {}) do
			local index = seat.weapon_index_to_seat and seat.weapon_index_to_seat[i]
			if index == nil or index == cs.current_seat_index then return true end
		end
		return false
	end)
	if not ok then return true end
	return armed and true or false
end

-- Which crosshair a vehicle seat shows: the driver of a vehicle with no gun at the seat never gets the
-- aiming one (only the idle one, when the game keeps the crosshair up); a seat with a gun shows the
-- aiming crosshair while firing and nothing else. Answers "aim", "idle" or nil.
function M.vehicle_look(seat_armed, firing, always)
	if not seat_armed then return always and "idle" or nil end
	return firing and "aim" or nil
end

-- Whether a seat is a Hellpod of the Super Destroyer, which the Helldiver climbs into to get ready.
function M.drop_pod(seat)
	local EA = g("EntityAux")
	if seat == nil or not EA then return false end
	local ok, yes = pcall(EA.has_component, seat, "drop_pod")
	return ok and yes and true or false
end

-- Whether the Helldiver of the view can shoot now (M.can_shoot), out of the death cam and the Hellpod.
function M.armed(env, view)
	if not view or view.watching or env.state.dropping or not view.avatar then return false end
	if view.vehicle and M.drop_pod(view.target) then return false end
	local unit, EA = view.avatar, g("EntityAux")
	local hud = nil
	local cc = g("CharacterComponent")
	if cc and cc.get_hud_state then
		local ok, h = pcall(cc.get_hud_state, unit)
		if ok then hud = h end
	end
	if EA then
		local ok, hs = pcall(EA.state, unit, "health")
		if ok and type(hs) == "table" and hs.is_dead then return false end
	end
	return M.can_shoot(hud)
end

-- Which cursor shows now: "aim", "idle" or nil. env.api may be nil. always: the game option above.
function M.look(env, always)
	local state = env.state
	if not state.active or not state.crosshair or state.claimed_by or state.dropping then return nil end
	if state.armed == false then return nil end
	-- The game's own aiming cursor is up, held at the middle (src/camera.lua M.vanilla).
	if env.camera and env.camera.vanilla then return nil end
	if (state.sprint_fade or 1) <= 0.01 then return nil end
	local camera = env.camera
	local input = camera and camera.input
	if input and not input.look then return nil end
	local kind
	if state.vehicle then kind = M.vehicle_look(state.seat_armed ~= false, state.firing, always)
	else kind = (state.aiming or state.firing) and "aim" or (always and "idle") or nil end
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
	env.state.armed = nil
	table.insert(env.on_pose, function(view)
		env.state.armed = M.armed(env, view)
		env.state.seat_armed = M.seat_armed(view)
	end)
	table.insert(env.on_release, function() env.state.armed, env.state.seat_armed = nil, nil end)
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
