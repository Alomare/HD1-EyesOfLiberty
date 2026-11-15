-- Unleashed Camera: third and first person cameras built on Obsidian hooks. Formerly Integrated Third
-- Person (id alomare.integratedthirdperson until 0.7.0). Obsidian doesn't update a mod to another id, so
-- that mod stays installed beside this one until the player removes it; while it is loaded, this one
-- stays off (env.off), as both would hook the same game functions.
-- Based on Third Person Camera (HD2 Style) by yukiorsrs, used with permission.
--
-- The mod is split into parts (obsidian.json "parts"):
--   view             client: third and first person cameras, aim, crosshair, view distance, sky, fog,
--                    depth of field, enemy indicators
--   weapon_range     session: every weapon reaches as far as the farthest one
--   enemy_detection  session: enemies notice the squad from farther away
--   free_movement    session: the Helldiver can leave the shared top-down screen
--   throw_range      session: grenades and stratagem balls fly twice as far
-- Every hook, frame function and key is registered with the options of the part it belongs to ({ part = "..." }),
-- so a lobby that isn't cleared switches only the session parts off. A loader without parts ignores
-- the extra argument and gates everything, the safe fallback.

local api = obsidian.import("obsidian.api")
local config = obsidian.module("src/config")

local VIEW = { part = "view" }
local KEY_VIEW = { part = "view", always = true }

-- Shared between the modules. camera.lua and aim.lua write it, the others read it.
local state = {
	active = false,     -- third person is steering the view this frame
	vehicle = false,    -- the player sits in a vehicle or a turret
	aiming = false,     -- the aim button is held
	firing = false,     -- fire or a throw is held
	crosshair = nil,    -- { x, y } in pixels from the bottom left, where shots go
	claimed_by = nil,   -- id of a mod that draws the crosshair instead of this one
	sprint_fade = 1,    -- 1, down to 0 while sprinting: the crosshair fades out
}

local env = {
	api = api,
	config = config,
	state = state,
	VIEW = VIEW,
	KEY_VIEW = KEY_VIEW,
	part = function(id) return { part = id } end,
	log = function(...) obsidian.log(...) end,
	parts = obsidian.capabilities and obsidian.capabilities.parts or false,
	-- Filled by src/camera.lua: fn(view, camera_manager, dt) after each frame's pose, fn(camera_manager)
	-- when the view goes back to the top-down camera, and the pose itself while third person is on.
	-- true while Integrated Third Person, the old id of this mod, is loaded too: everything stays off.
	off = false,
	on_pose = {},
	on_release = {},
	view = nil,
}

config.start(env)

local started = {}
for _, name in ipairs({ "src/camera", "src/aim", "src/crosshair", "src/view", "src/radar", "src/hits", "src/look", "src/session" }) do
	local ok, err = pcall(function()
		local m = obsidian.module(name)
		if m and m.start then m.start(env) end
		started[name] = m
	end)
	if not ok then obsidian.log("Unleashed Camera: " .. name .. " did not start: " .. tostring(err)) end
end

-- What other mods get from obsidian.import("alomare.unleashedcamera").
-- The old id of this mod, loaded beside it: this one steps aside and says so once. Asked after every
-- mod has started, whichever loaded first.
local OLD_ID = "alomare.integratedthirdperson"
local function old_one()
	local ok, mod = pcall(obsidian.import, OLD_ID)
	if not (ok and type(mod) == "table") then return end
	env.off = true
	obsidian.log("Unleashed Camera: Integrated Third Person is loaded too; staying off until it is removed")
	obsidian.toast("Unleashed Camera stays off: Integrated Third Person, the old version, is still installed. Remove it in Obsidian.", 10)
end
if type(obsidian.after_startup) == "function" then obsidian.after_startup(old_one) else old_one() end

local export = { version = "0.8.1" }

-- Where shots go on screen while third person steers the view: { x, y, aiming, firing, vehicle }, in
-- pixels from the bottom left (the coordinates of obsidian.ui.canvas). aiming: the aim button is held;
-- firing (since 0.4.2): fire or a throw is held, which also brings up the aiming cursor of the game in
-- the top-down view. fade (since 0.6.0): from 1 down to 0 as the Helldiver sprints; a crosshair drawn
-- there fades with it. nil while the top-down camera is on.
function export.crosshair()
	if not state.active or not state.crosshair then return nil end
	return { x = state.crosshair.x, y = state.crosshair.y, aiming = state.aiming, firing = state.firing,
		vehicle = state.vehicle, fade = state.sprint_fade or 1 }
end

-- Another mod draws the crosshair from now on (Custom Crosshair does this). Unleashed Camera
-- stops drawing the game's crosshair at the middle of the view. Answers true.
function export.claim_crosshair(mod_id)
	state.claimed_by = mod_id or obsidian.caller and obsidian.caller() or "unknown"
	return true
end

-- true while the mod steers the view, in third or first person.
function export.active()
	return state.active
end

-- The camera mode (since 0.6.0): "default" (the game's top-down camera), "third" or "first".
function export.mode()
	local camera = env.camera
	return camera and camera.mode or "default"
end

-- The shoulder the camera sits over while third person steers the view: 1 right, -1 left, nil in the
-- top-down view. During a swap, the shoulder the camera is moving to. In a vehicle, 0 while the camera
-- sits in the middle; 0 in first person on foot.
function export.shoulder()
	if not state.active then return nil end
	local camera = env.camera
	if state.vehicle and camera and camera.ride and camera.ride.kind then return camera.ride.side end
	if camera and camera.mode == "first" then return 0 end
	local side = camera and camera.view and camera.view.side
	return side == -1 and -1 or 1
end

return export
