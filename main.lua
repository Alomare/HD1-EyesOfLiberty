-- Eyes of Liberty: a third person camera built on Obsidian hooks. Formerly Unleashed Camera (id
-- alomare.unleashedcamera, 0.8.0 to 0.9.1) and before that Integrated Third Person (id
-- alomare.integratedthirdperson, up to 0.7.0). Obsidian doesn't update a mod to another id, so an old
-- one stays installed beside this one until the player removes it; while one is loaded, this one stays
-- off (env.off), as both would hook the same game functions.
-- Based on Third Person Camera (HD2 Style) by yukiorsrs, used with permission.
--
-- The mod is split into parts (obsidian.json "parts"):
--   view             client: the third person camera, aim, crosshair, view distance, sky, fog, depth
--                    of field, enemy indicators, compass, pings
--   weapon_range     session (Ballistics revamp): every weapon reaches as far as the farthest one, and
--                    bullets lose damage past their weapon's own range
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
	aim_point = nil,    -- { x, y, z } the crosshair is on (src/aim.lua), and aim_unit, the unit there
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
	-- true while an old id of this mod is loaded too: everything stays off.
	off = false,
	on_pose = {},
	on_release = {},
	view = nil,
}

config.start(env)

local started = {}
for _, name in ipairs({ "src/art", "src/camera", "src/aim", "src/blocked", "src/body", "src/aimpose", "src/crosshair", "src/view", "src/radar", "src/hits", "src/hurt", "src/look", "src/edge", "src/compass", "src/ping", "src/arc", "src/ammobar", "src/alarm", "src/kick", "src/session" }) do
	local ok, err = pcall(function()
		local m = obsidian.module(name)
		if m and m.start then m.start(env) end
		started[name] = m
	end)
	if not ok then obsidian.log("Eyes of Liberty: " .. name .. " did not start: " .. tostring(err)) end
end

-- An old id of this mod, loaded beside it: this one steps aside and says so once. Asked after every
-- mod has started, whichever loaded first.
local OLD_IDS = {
	{ id = "alomare.unleashedcamera", name = "Unleashed Camera" },
	{ id = "alomare.integratedthirdperson", name = "Integrated Third Person" },
}
local function old_one()
	for _, old in ipairs(OLD_IDS) do
		local ok, mod = pcall(obsidian.import, old.id)
		if ok and type(mod) == "table" then
			env.off = true
			obsidian.log("Eyes of Liberty: " .. old.name .. " is loaded too; staying off until it is removed")
			obsidian.toast("Eyes of Liberty stays off: " .. old.name .. ", the old version, is still installed. Remove it in Obsidian.", 10)
			return
		end
	end
end
if type(obsidian.after_startup) == "function" then obsidian.after_startup(old_one) else old_one() end

-- What other mods get from obsidian.import("alomare.eyesofliberty").
local export = { version = obsidian.version or "1.0.1" }

-- Where shots go on screen while third person steers the view: { x, y, aiming, firing, vehicle }, in
-- pixels from the bottom left (the coordinates of obsidian.ui.canvas). aiming: the aim button is held;
-- firing (since 0.4.2): fire or a throw is held, which also brings up the aiming cursor of the game in
-- the top-down view. fade (since 0.6.0): from 1 down to 0 as the Helldiver sprints; a crosshair drawn
-- there fades with it. armed (since 0.14.0): false while the Helldiver can't shoot (dead, in the
-- Hellpod, putting in a stratagem, on the map, the death cam); a crosshair drawn there
-- hides then. nil while the top-down camera is on.
function export.crosshair()
	if not state.active or not state.crosshair then return nil end
	return { x = state.crosshair.x, y = state.crosshair.y, aiming = state.aiming, firing = state.firing,
		vehicle = state.vehicle, fade = state.sprint_fade or 1, armed = state.armed ~= false }
end

-- Another mod draws the crosshair from now on (Custom Crosshair does this). Eyes of Liberty
-- stops drawing the game's crosshair at the middle of the view. Answers true.
function export.claim_crosshair(mod_id)
	state.claimed_by = mod_id or obsidian.caller and obsidian.caller() or "unknown"
	return true
end

-- true while the mod steers the view.
function export.active()
	return state.active
end

-- The camera mode (since 0.6.0): "default" (the game's top-down camera) or "third".
function export.mode()
	local camera = env.camera
	return camera and camera.mode or "default"
end

-- The shoulder the camera sits over while third person steers the view: 1 right, -1 left, nil in the
-- top-down view. During a swap, the shoulder the camera is moving to. In a vehicle, 0 while the camera
-- sits in the middle.
function export.shoulder()
	if not state.active then return nil end
	local camera = env.camera
	if state.vehicle and camera and camera.ride and camera.ride.kind then return camera.ride.side end
	local side = camera and camera.view and camera.view.side
	return side == -1 and -1 or 1
end

-- Whether the ammo bar (since 0.14.0) shows in place of an ammo circle now: the option is on and third
-- person steers the view on foot. Better HUD hides its ammo circle while this is true.
function export.ammo_bar()
	local bar = started["src/ammobar"]
	return bar ~= nil and bar.wanted(env) == true
end

return export
