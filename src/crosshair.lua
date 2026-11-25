-- The game's own crosshair at the middle of the view while third person steers it.
--
-- In the top-down view the game shows its aiming cursor as a Windows cursor at the mouse
-- (CursorManager, "hud/cursors/game"). Under the shoulder camera the mouse turns the view, so that
-- cursor stays hidden (src/camera.lua) and its image, "eol_aim" of the mod's art (src/art.lua), is
-- drawn at the crosshair in the frame, after the pose: on foot while the aim button, fire or a throw
-- is held, in a vehicle by the seat (vehicle_look). Between shots the game shows the idle cursor
-- ("hud/cursors/game_inactive", a faint dot, "eol_idle") when the game option keeps the crosshair up,
-- and nothing otherwise. Between the two the game shows five steps, 35 ms each ("game_transition_01"
-- to "_05", "eol_step1" to "eol_step5"), and so does the shoulder view (M.advance). Another mod that
-- draws the crosshair (claim_crosshair in
-- main.lua, as Custom Crosshair does) turns this one off. While sprinting the crosshair fades out
-- (state.sprint_fade, from src/camera.lua), and the export hands the same fade to the other mod.
--
-- A crosshair shows only while the Helldiver can shoot (state.armed, set each pose): alive, not dropping
-- in the Hellpod, not sitting in a Hellpod on the Super Destroyer (a seat with the drop_pod component,
-- gameobjects/gameobject_hellpod_menu), not putting in a stratagem, the map shut and the death cam off. Down and carrying,
-- the Helldiver still shoots, and the crosshair stays. The export hands the same flag to the other mod, so its crosshair hides at the same moments.
local art = obsidian.module("src/art")

local M = {}

M.AIM = "eol_aim"
M.IDLE = "eol_idle"
M.STEP = "eol_step"
M.STEPS = 5
M.STEP_TIME = 0.035
M.SIZE = 32
M.LAYER = 100         -- the art gui, over the throw ring (97) and the hurt edges (60)

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
		-- A vehicle that is a gun itself (an exosuit's arms, a mannable turret: the weapon interface, as
		-- Obsidian API vehicles.seats reads it) arms the first seat, which steers and fires it.
		local first = cs.current_seat_index == nil or cs.current_seat_index == 1
		if first and EA.has_interface and EA.has_interface(view.target, "weapon") then return true end
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

-- The image shown this frame for the wanted look ("aim", "idle" or nil), stepping as the game's
-- CursorManager does: from one of the two to the other through the five steps, one step a frame at
-- most and only once STEP_TIME has gone by since the last (the step from aim to idle counts up from 1,
-- the other way down from 5); turned back halfway, the next frame steps back the other way. From
-- nothing to either, it shows at once. t keeps current, next, index and timer between frames.
function M.advance(t, want, dt)
	if want == nil then
		t.current, t.next, t.index, t.timer = nil, nil, nil, nil
		return nil
	end
	if t.next then
		if want ~= t.next then t.next, t.timer = want, 0 end
	elseif t.current ~= want then
		if t.current == nil then
			t.current = want
		else
			t.next, t.timer = want, M.STEP_TIME
			t.index = want == "idle" and 1 or M.STEPS
			return M.STEP .. t.index
		end
	end
	if t.next then
		t.timer = t.timer - (dt or 0)
		if t.timer <= 0 then
			t.timer = M.STEP_TIME
			t.index = t.index + (t.next == "aim" and -1 or 1)
			if t.index < 1 or t.index > M.STEPS then
				t.current, t.next, t.index, t.timer = t.next, nil, nil, nil
			end
		end
	end
	if t.next then return M.STEP .. t.index end
	return t.current == "aim" and M.AIM or M.IDLE
end

M.steps = {}

function M.draw(gui, env, sprite)
	local c = env.state.crosshair
	local x, y, s = M.rect(c.x, c.y)
	local alpha = math.floor(255 * math.max(0, math.min(1, env.state.sprint_fade or 1)) + 0.5)
	art.draw(gui, sprite, x, y, s, s, M.LAYER, alpha, 255, 255, 255)
end

function M.start(env)
	local failed = false
	env.state.armed = nil
	table.insert(env.on_pose, function(view, cm, dt)
		env.state.armed = M.armed(env, view)
		env.state.seat_armed = M.seat_armed(view)
		-- After src/aim.lua placed the crosshair for this pose: drawn in the same frame as the view.
		if failed then return end
		local ok, err = pcall(function()
			local sprite = M.advance(M.steps, M.look(env, M.always_on()), dt)
			local gui = sprite and art.gui()
			if gui then M.draw(gui, env, sprite) end
		end)
		if not ok then
			failed = true
			env.log("Eyes of Liberty: crosshair stopped: " .. tostring(err))
		end
	end)
	table.insert(env.on_release, function()
		env.state.armed, env.state.seat_armed = nil, nil
		M.advance(M.steps, nil, 0)
	end)
end

return M
