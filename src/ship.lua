-- The Super Destroyer in the sky: in third person during a mission, the ship of the loading screen
-- (menu/menu_spaceship_01) hangs over the level, side on, SHIP_ELEVATION above the horizon, on the
-- side the sunlight travels toward, so it is seen lit with the sun behind the viewer.
--
-- It rides with the camera at DISTANCE, as the sky does (src/view.lua), so walking never brings it
-- closer, and it is made LENGTH long to fill about 25 degrees of the view: closer than the fog of the
-- level builds up (probe 2026-11-23: at 80 m and more the fog of a desert turned it into a flat
-- glowing shape, at 25 m it keeps the grey of the hull). It casts no shadow and has no collision.
--
-- The ship comes in resource_packages/mission_start, which the game unloads when the mission starts.
-- In a mission that package is loaded again in the background, and unloaded once the mission is over,
-- after the world that held the ship is gone. Spawning a unit the game hasn't loaded stops the game
-- past any pcall, so the ship is spawned only once the package is online.
local M = {}

local function g(name) return rawget(_G, name) end

M.PACKAGE = "resource_packages/mission_start"
M.UNIT = "menu/menu_spaceship_01"
M.MADE = 2.18                  -- metres, the model's length as made (Unit.box, probe 2026-11-23)
-- Twice as high over the horizon as the first try (30 degrees at 25 m, the user: too low), at the
-- same flat distance: 49 degrees up, 33 m out, made longer to fill the same part of the view.
M.ELEVATION = math.atan(2 * math.tan(math.rad(30)))         -- above the horizon
M.DISTANCE = 25 * math.cos(math.rad(30)) / math.cos(M.ELEVATION) -- metres from the camera
M.LENGTH = 11 * M.DISTANCE / 25                              -- metres long at that distance

-- The bearing (radians, from +x toward +y) the ship is seen at: the flat way the sunlight travels
-- (sun_direction), so the sun stands behind the viewer. 0 with no sun or the sun straight up.
function M.bearing(sun)
	if type(sun) ~= "table" or type(sun[1]) ~= "number" or type(sun[2]) ~= "number" then return 0 end
	if sun[1] * sun[1] + sun[2] * sun[2] < 1e-6 then return 0 end
	return math.atan2(sun[2], sun[1])
end

-- Where the ship stands for a camera at `at`, seen at `bearing`.
function M.place(at, bearing)
	local flat = math.cos(M.ELEVATION) * M.DISTANCE
	return { x = at.x + math.cos(bearing) * flat, y = at.y + math.sin(bearing) * flat, z = at.z + math.sin(M.ELEVATION) * M.DISTANCE }
end

-- The ship's long axis is its local y: turned by the bearing about the up axis, it lies across the
-- line of sight.
function M.turn(bearing) return bearing end

local ship = { unit = nil, world = nil, state = nil, bearing = 0 }
local ours = false -- this mod loaded the package and unloads it

-- Drops the ship. The unit is destroyed only while its world is the one of the mission it was made
-- in; after that the engine has freed it with the world.
local function remove(alive_world)
	if ship.unit and alive_world then
		pcall(function()
			if g("Unit").alive(ship.unit) then g("World").destroy_unit(ship.world, ship.unit) end
		end)
	end
	ship.unit, ship.world, ship.state, ship.at = nil, nil, nil, nil
end

-- Where the ship in the sky stands this frame, or nil while there is none in view.
function M.where() return ship.unit and ship.at or nil end

local function spawn(env, view, state)
	local U, V3, W = g("Unit"), g("Vector3"), g("World")
	local pm = g("Boot").package_manager
	if not pm:has_package(M.PACKAGE) then
		pm:load_package(M.PACKAGE, false)
		ours = true
		return
	end
	if not pm:is_package_online(M.PACKAGE) then return end
	local p = view.position
	local made, unit = pcall(W.spawn_unit, view.world, M.UNIT, V3(p.x, p.y, p.z + M.DISTANCE))
	if not made or not unit then return end
	ship.unit, ship.world, ship.state = unit, view.world, state
	local s = M.LENGTH / M.MADE
	pcall(U.set_local_scale, unit, 0, V3(s, s, s))
	for i = 0, U.num_meshes(unit) - 1 do pcall(U.set_mesh_visibility, unit, i, false, "shadow_caster") end
	local ok, sun = pcall(env.api.world.planet_shading, "sun_direction")
	ship.bearing = M.bearing(ok and sun or nil)
	env.log("Eyes of Liberty: Super Destroyer in the sky")
end

local function update(env, view)
	local api = env.api
	if env.config.get("sky_ship") == false or not (api and api.game and api.game.in_mission()) then
		remove(ship.world == view.world)
		return
	end
	local state = api.game.state()
	if ship.unit and (ship.state ~= state or ship.world ~= view.world) then remove(false) end
	if not ship.unit then spawn(env, view, state) end
	if not ship.unit then return end
	local U, V3, Q = g("Unit"), g("Vector3"), g("Quaternion")
	local at = M.place(view.position, ship.bearing)
	ship.at = at
	pcall(U.teleport_local_position, ship.unit, 0, V3(at.x, at.y, at.z))
	pcall(U.teleport_local_rotation, ship.unit, 0, Q(V3(0, 0, 1), M.turn(ship.bearing)))
	pcall(g("World").update_unit, ship.world, ship.unit)
end

-- Out of the mission: the ship is gone with the world, and the package this mod loaded is unloaded.
-- The mission start screen loads and unloads the package for itself.
local function settle(env)
	local api = env.api
	local name = api and api.game and api.game.state_name()
	if name == "game" then return end
	if ship.unit then remove(false) end
	if ours then
		ours = false
		if name ~= "mission_start" then pcall(function() g("Boot").package_manager:unload_package(M.PACKAGE) end) end
	end
end

function M.start(env)
	local warned = false
	table.insert(env.on_pose, function(view)
		local ok, err = pcall(update, env, view)
		if not ok and not warned then
			warned = true
			env.log("Eyes of Liberty: ship: " .. tostring(err))
		end
	end)
	-- Back to top-down: the ship goes, while its world still stands.
	table.insert(env.on_release, function()
		local inside = pcall(function() return env.api.game.in_mission() end) and env.api.game.in_mission()
		remove(inside)
	end)
	obsidian.on_frame(function() pcall(settle, env) end, env.VIEW)
end

M._ship = ship -- for tests
M._ours = function() return ours end
return M
