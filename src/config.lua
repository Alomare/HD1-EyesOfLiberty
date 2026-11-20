-- Option values for the modules. Starts from what the player set in Obsidian, and follows the rows
-- of the in-game settings page (Obsidian API mod_settings, bound to the obsidian.json options), so a
-- change in the pause menu applies at once.
local M = {}

local values = {}
local listeners = {}

local function set(id, value)
	if values[id] == value then return end
	values[id] = value
	for _, fn in ipairs(listeners[id] or {}) do pcall(fn, value) end
end

function M.get(id)
	local v = values[id]
	if v == nil then v = obsidian.settings.get(id) end
	return v
end

-- Calls fn(value) whenever the option changes in game.
function M.on_change(id, fn)
	listeners[id] = listeners[id] or {}
	table.insert(listeners[id], fn)
end

M.set = set

-- Rows of the in-game page, in the order and groups of obsidian.json (tests/test_settings.lua keeps
-- the two in step): every option that applies at once. The Sky option needs a deploy, and the session
-- features switch parts of the mod on and off, which needs one too, so those stay in Obsidian only.
-- The page has no headings, so labels name what they belong to ("Ammo bar scale", not "Scale").
local ROWS = {
	{ kind = "choice", id = "camera_mode",
		choices = { { id = "default", label = { en = "Default" } }, { id = "third", label = { en = "Third person" } } },
		label = { en = "Camera mode" },
		info = { en = "The camera a mission starts with. The camera key switches in a mission." } },
	{ kind = "number", id = "look_speed", min = 0.1, max = 3, step = 0.05,
		label = { en = "Look sensitivity" },
		info = { en = "How fast the camera turns with the mouse or the right stick." } },
	{ kind = "toggle", id = "invert_y",
		label = { en = "Invert vertical look" },
		info = { en = "Moving the mouse up looks down." } },
	{ kind = "choice", id = "shoulder",
		choices = { { id = "right", label = { en = "Right" } }, { id = "left", label = { en = "Left" } } },
		label = { en = "Shoulder" },
		info = { en = "The side of the Helldiver the camera sits on." } },
	{ kind = "number", id = "foot_distance", min = 1, max = 10, step = 0.5,
		label = { en = "Distance on foot (m)" },
		info = { en = "Metres between the camera and the Helldiver on foot." } },
	{ kind = "toggle", id = "scroll_distance",
		label = { en = "Scroll camera distance" },
		info = { en = "The mouse wheel moves the camera closer or farther instead of switching weapons." } },
	{ kind = "number", id = "foot_fov", min = 40, max = 110, step = 1,
		label = { en = "Field of view on foot (degrees)" },
		info = { en = "Vertical field of view on foot." } },
	{ kind = "number", id = "camera_height", min = -1, max = 1.5, step = 0.1,
		label = { en = "Overall camera height (m)" },
		info = { en = "Raises or lowers the camera everywhere." } },
	{ kind = "number", id = "ship_distance", min = 0.5, max = 10, step = 0.5,
		label = { en = "Distance on the Super Destroyer (m)" },
		info = { en = "Metres between the camera and the Helldiver on the Super Destroyer." } },
	{ kind = "toggle", id = "hellpod_camera",
		label = { en = "Hellpod camera" },
		info = { en = "The camera rides down above the Hellpod when the Helldiver drops in." } },
	{ kind = "toggle", id = "dive_camera",
		label = { en = "Dive camera" },
		info = { en = "The camera comes down during a dive." } },
	{ kind = "toggle", id = "downed_camera",
		label = { en = "Downed camera" },
		info = { en = "The camera sits low and farther back while the Helldiver is down." } },
	{ kind = "toggle", id = "death_cam",
		label = { en = "Death cam" },
		info = { en = "After a death the camera stays on the body, then follows an ally." } },
	{ kind = "toggle", id = "extraction_camera",
		label = { en = "Extraction camera" },
		info = { en = "The camera rides the shuttle out after extraction." } },
	{ kind = "choice", id = "camera_shake",
		choices = { { id = "off", label = { en = "Off" } }, { id = "weak", label = { en = "Weak" } }, { id = "medium", label = { en = "Medium" } }, { id = "strong", label = { en = "Strong" } } },
		label = { en = "Camera shake strength" },
		info = { en = "How much explosions, impacts and the Hellpod landing shake the camera." } },
	{ kind = "toggle", id = "explosion_kick",
		label = { en = "Explosion kick" },
		info = { en = "Explosions nearby knock the camera. Follows the shake strength." } },
	{ kind = "number", id = "vehicle_distance", min = 3, max = 20, step = 0.5,
		label = { en = "Vehicle camera distance (m)" },
		info = { en = "Metres between the camera and the vehicle." } },
	{ kind = "number", id = "vehicle_fov", min = 40, max = 120, step = 1,
		label = { en = "Vehicle field of view (degrees)" },
		info = { en = "Vertical field of view in a vehicle." } },
	{ kind = "toggle", id = "throw_arc",
		label = { en = "Throw arc" },
		info = { en = "A dashed line shows where a held grenade or stratagem ball would fly." } },
	{ kind = "toggle", id = "blocked_shot",
		label = { en = "Blocked shot mark" },
		info = { en = "A red X marks where something close would stop the shots." } },
	{ kind = "toggle", id = "aim_pose",
		label = { en = "Weapon follows aim" },
		info = { en = "The Helldiver bends up or down so the weapon points at the crosshair." } },
	{ kind = "toggle", id = "ammo_bar",
		label = { en = "Ammo bar" },
		info = { en = "A short arc by the crosshair shows the magazine, laser heat or arc charge." } },
	{ kind = "choice", id = "ammo_bar_position",
		choices = { { id = "top", label = { en = "Top" } }, { id = "bottom", label = { en = "Bottom" } }, { id = "oppose", label = { en = "Opposite the Helldiver" } }, { id = "same", label = { en = "Same side as the Helldiver" } } },
		label = { en = "Ammo bar position" },
		info = { en = "Where the ammo bar sits around the crosshair." } },
	{ kind = "toggle", id = "ammo_bar_curved",
		label = { en = "Curved ammo bar" },
		info = { en = "On, the bar curves around the crosshair. Off, it is straight." } },
	{ kind = "number", id = "ammo_bar_scale", min = 0.5, max = 2, step = 0.1,
		label = { en = "Ammo bar scale" },
		info = { en = "The size of the ammo bar and how far it sits from the crosshair." } },
	{ kind = "toggle", id = "compass",
		label = { en = "Compass" },
		info = { en = "A compass at the top of the screen with objectives and map markers." } },
	{ kind = "choice", id = "compass_width",
		choices = { { id = "short", label = { en = "Short" } }, { id = "medium", label = { en = "Medium" } }, { id = "wide", label = { en = "Wide" } } },
		label = { en = "Compass width" },
		info = { en = "How wide the compass is." } },
	{ kind = "number", id = "compass_opacity", min = 0, max = 1, step = 0.1,
		label = { en = "Compass background opacity" },
		info = { en = "How solid the panel behind the compass is." } },
	{ kind = "toggle", id = "compass_angle",
		label = { en = "Show view angle" },
		info = { en = "The middle line of the compass and the heading in degrees." } },
	{ kind = "toggle", id = "pings",
		label = { en = "Pings" },
		info = { en = "The ping key marks what the crosshair is on for the squad." } },
	{ kind = "toggle", id = "radar",
		label = { en = "Enemy indicators" },
		info = { en = "A ring around the crosshair shows enemies close by on the sides and behind." } },
	{ kind = "number", id = "radar_range", min = 5, max = 40, step = 2.5,
		label = { en = "Enemy indicator range (m)" },
		info = { en = "How close an enemy must be to show on the ring." } },
	{ kind = "toggle", id = "edge_markers",
		label = { en = "Edge markers" },
		info = { en = "Stratagem beacons out of view show at the edge of the screen." } },
	{ kind = "toggle", id = "names_above",
		label = { en = "Names above heads" },
		info = { en = "Name cards of players show above their heads." } },
	{ kind = "toggle", id = "hit_indicators",
		label = { en = "Hurt indicator" },
		info = { en = "A bar near the crosshair points to where a hit came from." } },
	{ kind = "toggle", id = "hurt_feedback",
		label = { en = "Hurt feedback" },
		info = { en = "The screen edges flash red and the camera shakes on a hit." } },
	{ kind = "toggle", id = "alarm_effect",
		label = { en = "Alarm effect" },
		info = { en = "An alarm pulses the screen edges red instead of the game's overlay." } },
	{ kind = "number", id = "reduce_fog", min = 0, max = 1, step = 0.1,
		label = { en = "Reduce fog" },
		info = { en = "How fast the fog builds up with distance. 1 is the game's fog, 0 no fog." } },
	{ kind = "choice", id = "depth_of_field",
		choices = { { id = "game", label = { en = "Game default" } }, { id = "helldiver", label = { en = "Focus on the Helldiver" } }, { id = "off", label = { en = "Off" } } },
		label = { en = "Depth of field" },
		info = { en = "Which part of the picture stays sharp." } },
	{ kind = "toggle", id = "far_view",
		label = { en = "Long view distance" },
		info = { en = "The view and the detail of distant models reach farther." } },
}

M.ROWS = ROWS

-- The words a number row shows.
function M.number_text(v)
	return string.format("%g", v)
end

function M.start(env)
	local api = env.api
	if not (api and api.mod_settings and api.mod_settings.BINDS) then return end
	local page = api.mod_settings.page("Eyes of Liberty")
	for _, row in ipairs(ROWS) do
		local start = page[row.kind](page, row.id, {
			option = true,
			label = row.label,
			info = row.info,
			min = row.min, max = row.max, step = row.step,
			choices = row.choices,
			default = obsidian.settings.get(row.id),
			format = row.kind == "number" and M.number_text or nil,
			on_change = function(v) set(row.id, v) end,
		})
		if start ~= nil then values[row.id] = start end
	end
end

return M
