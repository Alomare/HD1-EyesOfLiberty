-- Ship-bound stratagems (part ship_strikes, session): Hellpods and orbital shells come down
-- along the way from the Super Destroyer in the sky (src/ship.lua) instead of straight down.
--
-- The way: the bearing the ship is seen at, from the planet's sunlight (ship.bearing, the same on
-- every machine of the lobby), at ship.ELEVATION above the horizon.
--
--   Hellpods       the fall is the pod unit's own animation along its up axis (probe 2026-11-23: a pod
--                  turned 40 degrees came down along that line, from about 117 m, and landed 1.5 s after
--                  it appeared). HellpodComponent.setup_slave turns a falling pod (drop_state 1) so its
--                  up axis points at the ship; once its parts reach the ground it stands upright again.
--   Strikes        the orbital barrage, smoke and missile barrages (ArtilleryComponent "explosion") and
--                  the precision strike, missile strike and Railcannon (TargetedStrikeComponent
--                  update_slaves) find where each shot lands with a ray from 25 m straight above the
--                  spot. The ray runs from the ship's way instead, from the same height, so a shot meets
--                  what stands between the ship and the spot. Every machine casts it, which is why this
--                  is a session part: machines must agree on where each shot lands.
--   Shell units    the unit each shot spawns where it lands (the falling shell is drawn inside it, along
--                  its up axis: probe 2026-11-23) spawns turned toward the ship.
--   Orbital laser  the beam is drawn inside the laser unit (gameobjects/orbital_strike) along its up axis,
--                  and reaches far up (probe 2026-11-23: the unit turned 40 degrees showed the beam leaning
--                  off the screen). HomingComponent.update_slaves places and turns the unit each frame
--                  while it roams; right after, the unit is turned so the beam leans toward the ship. The
--                  explosions stay at the unit's root, on the ground.
-- Eagles fly their own runs and are left alone.
local ship = obsidian.module("src/ship")

local M = {}

local function g(name) return rawget(_G, name) end

M.SHELLS = {
	["gameobjects/gameobject_artillery"] = true, ["gameobjects/gameobject_artillery_smoke"] = true,
	["gameobjects/gameobject_missile"] = true, ["gameobjects/gameobject_missile_toxic"] = true,
	["gameobjects/gameobject_precision_artillery"] = true, ["gameobjects/gameobject_missilestrike"] = true,
	["gameobjects/gameobject_railcannon_strike"] = true,
}
M.LANDED = 1.5   -- metres: a pod whose parts are all this close to its root has landed
-- A shell unit's fall starts about 18 m up its axis and takes about 2 s (probe 2026-11-23). With the
-- parts right under the root put STRETCH times as far out each frame, the shell starts that many times
-- farther up the ship's way and falls that many times as fast, landing at the same moment (the user:
-- come from way up, as fast as it takes). Scaling the unit did the same but stretched the shell and
-- its explosion with it (seen in game, 2026-11-23).
M.STRETCH = 10
M.SHELL_TIME = 6 -- seconds a shell is watched at the most
M.POD_TIME = 4   -- seconds a pod is watched at the most

-- The way up toward the ship, a unit vector.
function M.toward(bearing)
	local c = math.cos(ship.ELEVATION)
	return { x = c * math.cos(bearing), y = c * math.sin(bearing), z = math.sin(ship.ELEVATION) }
end

-- The turn that takes straight up to the way toward the ship: about the flat axis across the bearing.
function M.tilt(bearing)
	return { x = -math.sin(bearing), y = math.cos(bearing), z = 0 }, math.pi / 2 - ship.ELEVATION
end

-- The game's cast for a shot, from `from` straight down (dir z -1) over `length`, turned to come from
-- the ship: from the spot below `from` back along the ship's way to the same height, and as much longer.
-- Answers from, dir, length; a cast that isn't straight down is answered as it was.
function M.cast(from, dir, length, bearing, height)
	if not (dir and dir.z < -0.99) then return from, dir, length end
	local d = M.toward(bearing)
	local spot = { x = from.x, y = from.y, z = from.z - height }
	local k = height / d.z
	return { x = spot.x + d.x * k, y = spot.y + d.y * k, z = spot.z + d.z * k }, { x = -d.x, y = -d.y, z = -d.z }, length / d.z
end

M.GAME_HEIGHT = 25 -- metres above the spot the game casts from (artillery and targeted strikes)

-- The bearing of the ship for this mission, worked out once per game state.
local cached = { state = nil, bearing = 0 }
function M.bearing(env)
	local api = env.api
	local st = api and api.game and api.game.state and api.game.state()
	if st ~= nil and cached.state == st then return cached.bearing end
	local ok, sun = pcall(api.world.planet_shading, "sun_direction")
	cached.state, cached.bearing = st, ship.bearing(ok and sun or nil)
	return cached.bearing
end

-- A stand-in for a raycast object that turns the game's straight-down casts toward the ship.
local function turned(real, bearing)
	local V3 = g("Vector3")
	return { cast = function(_, from, dir, length, ...)
		local f, d, l = M.cast({ x = from.x, y = from.y, z = from.z }, { x = dir.x, y = dir.y, z = dir.z }, length, bearing, M.GAME_HEIGHT)
		return real:cast(V3(f.x, f.y, f.z), V3(d.x, d.y, d.z), l, ...)
	end }
end

-- Runs fn with each state's bomb_ray swapped for one turned toward the ship.
local function with_rays(states, bearing, fn, ...)
	local kept = {}
	for _, st in ipairs(states) do
		if st.bomb_ray then
			kept[#kept + 1] = { st = st, ray = st.bomb_ray }
			st.bomb_ray = turned(st.bomb_ray, bearing)
		end
	end
	local r = { pcall(fn, ...) }
	for _, k in ipairs(kept) do k.st.bomb_ray = k.ray end
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2, table.maxn(r))
end

-- Shells falling now: { unit, world, t, nodes (the parts right under the root), last (index: the
-- position put there last frame) }.
M.shells = {}

-- The parts right under a unit's root (all of them when the engine can't tell a part's parent).
function M.top_nodes(U, unit)
	local list = {}
	for i = 1, U.num_scene_graph_items(unit) - 1 do
		local ok, parent = pcall(U.scene_graph_parent, unit, i)
		if not ok or parent == 0 then list[#list + 1] = i end
	end
	return list
end

-- One frame of a shell: each top part the animation placed this frame goes STRETCH times as far from
-- the root. A part still where it was put last frame (the animation left it) stays.
function M.push(U, V3, shell)
	local k = M.STRETCH
	for _, i in ipairs(shell.nodes) do
		local p = U.local_position(shell.unit, i)
		local last = shell.last[i]
		if not (last and math.abs(p.x - last[1]) + math.abs(p.y - last[2]) + math.abs(p.z - last[3]) < 1e-4) then
			local x, y, z = p.x * k, p.y * k, p.z * k
			U.set_local_position(shell.unit, i, V3(x, y, z))
			shell.last[i] = { x, y, z }
		end
	end
end

-- Pods falling now: { unit, was (rotation elements), t }.
M.pods = {}

local function upright(U, Q, pod)
	pcall(U.set_local_rotation, pod.unit, 0, Q.from_elements(pod.was[1], pod.was[2], pod.was[3], pod.was[4]))
end

-- Whether every part of a pod is within LANDED of its root.
function M.landed(U, unit)
	local root = U.world_position(unit, 0)
	local n = U.num_scene_graph_items(unit)
	for i = 1, math.min(n - 1, 8) do
		local p = U.world_position(unit, i)
		local dx, dy, dz = p.x - root.x, p.y - root.y, p.z - root.z
		if dx * dx + dy * dy + dz * dz > M.LANDED * M.LANDED then return false end
	end
	return true
end

M.LASER = "gameobjects/orbital_strike"

-- Which homing units are orbital lasers (weak keys: units come and go).
M.lasers = setmetatable({}, { __mode = "k" })

-- The beam is a particle effect on the laser's root, as long as M.BEAM metres up the root's axis;
-- a root scaled along that axis draws it that much longer (probe 2026-11-23: scale 0.3 shortened the
-- beam, the ground glow stayed; a scaled child node changed nothing). With the ship in the sky, the
-- beam is drawn as long as the way to the ship, so it reaches the ship. Seen in game with 20, the tip
-- came out of the far side of the hull by about 8 percent of the way, with 22 a little less.
M.BEAM = 24

-- How much longer the beam is drawn to reach from `from` to the ship at `at`.
function M.reach(from, at)
	local dx, dy, dz = at.x - from.x, at.y - from.y, at.z - from.z
	return math.sqrt(dx * dx + dy * dy + dz * dz) / M.BEAM
end

-- The forward axis for a laser whose up axis is `up` (unit, z > 0), with the same flat way as the
-- game's forward `f` (flat): f lifted along z until it is square to up. The game picks the laser's
-- next target by the angle from that flat way (HomingComponent nearby_targets_callback reads
-- Quaternion.forward of the unit with z dropped), so the beam leans without changing the targets.
function M.forward(f, up)
	local t = -(f.x * up.x + f.y * up.y) / up.z
	local l = math.sqrt(f.x * f.x + f.y * f.y + t * t)
	return { x = f.x / l, y = f.y / l, z = t / l }
end

-- The way up toward the ship from `from`: at the ship in the sky while there is one (`at`), along
-- the bearing else. The ship in the sky stands about 33 m from the camera, so a beam parallel to the
-- bearing would pass beside it; this one meets it.
local function upward(from, bearing, at)
	if not at then return M.toward(bearing) end
	local dx, dy, dz = at.x - from.x, at.y - from.y, at.z - from.z
	local l = math.sqrt(dx * dx + dy * dy + dz * dz)
	if l < 1e-6 or dz < 1e-3 then return M.toward(bearing) end
	return { x = dx / l, y = dy / l, z = dz / l }
end

-- Turns each orbital laser among `entities` (unit -> context) so the beam points at the ship, keeping
-- the flat forward the game just gave it: at the ship in the sky while there is one (`at`), and drawn
-- long enough to reach it; along the bearing else, as long as the game draws it.
function M.lean(U, Q, V3, entities, bearing, at)
	for unit in pairs(entities) do
		local laser = M.lasers[unit]
		if laser == nil then
			laser = U.is_a(unit, M.LASER) and true or false
			M.lasers[unit] = laser
		end
		if laser then
			local from = U.world_position(unit, 0)
			local up = upward(from, bearing, at)
			local fw = Q.forward(U.local_rotation(unit, 0))
			local fl = math.sqrt(fw.x * fw.x + fw.y * fw.y)
			local f = fl > 1e-6 and { x = fw.x / fl, y = fw.y / fl } or { x = 1, y = 0 }
			local x = M.forward(f, up)
			U.teleport_local_rotation(unit, 0, Q.look(V3(x.x, x.y, x.z), V3(up.x, up.y, up.z)))
			U.set_local_scale(unit, 0, V3(1, 1, at and M.reach(from, at) or 1))
		end
	end
end

function M.start(env)
	if env.config.get("ship_strikes") == false then return end
	local opts = env.part("ship_strikes")
	local clock = 0
	obsidian.hook("ArtilleryComponent", "command_slave", function(original, self, unit, ctx, message, ...)
		local st = type(ctx) == "table" and ctx.state
		if message ~= "explosion" or type(st) ~= "table" then return original(self, unit, ctx, message, ...) end
		return with_rays({ st }, M.bearing(env), original, self, unit, ctx, message, ...)
	end, opts)
	obsidian.hook("TargetedStrikeComponent", "update_slaves", function(original, self, entities, ...)
		if type(entities) ~= "table" or next(entities) == nil then return original(self, entities, ...) end
		local states = {}
		for _, ctx in pairs(entities) do
			if type(ctx) == "table" and type(ctx.state) == "table" then states[#states + 1] = ctx.state end
		end
		return with_rays(states, M.bearing(env), original, self, entities, ...)
	end, opts)
	obsidian.hook("World", "spawn_unit", function(original, world, path, position, rotation, ...)
		if rotation ~= nil or not M.SHELLS[path] or position == nil then return original(world, path, position, rotation, ...) end
		local ok, q = pcall(function()
			local axis, angle = M.tilt(M.bearing(env))
			return g("Quaternion")(g("Vector3")(axis.x, axis.y, axis.z), angle)
		end)
		if not ok then return original(world, path, position, rotation, ...) end
		local unit = original(world, path, position, q, ...)
		if unit ~= nil and M.STRETCH > 1 then
			pcall(function()
				M.shells[#M.shells + 1] = { unit = unit, world = world, t = clock, nodes = M.top_nodes(g("Unit"), unit), last = {} }
			end)
		end
		return unit
	end, opts)
	obsidian.hook("HellpodComponent", "setup_slave", function(original, self, unit, ctx, ...)
		local r = { original(self, unit, ctx, ...) }
		pcall(function()
			local st = type(ctx) == "table" and ctx.state
			if not (st and st.drop_state == 1) then return end
			local U, Q, V3 = g("Unit"), g("Quaternion"), g("Vector3")
			local was = U.local_rotation(unit, 0)
			local x, y, z, w = Q.to_elements(was)
			local axis, angle = M.tilt(M.bearing(env))
			U.set_local_rotation(unit, 0, Q.multiply(Q(V3(axis.x, axis.y, axis.z), angle), was))
			M.pods[#M.pods + 1] = { unit = unit, was = { x, y, z, w }, t = clock }
		end)
		return unpack(r)
	end, opts)
	obsidian.hook("HomingComponent", "update_slaves", function(original, self, entities, ...)
		local r = { original(self, entities, ...) }
		if type(entities) == "table" and next(entities) ~= nil then
			pcall(M.lean, g("Unit"), g("Quaternion"), g("Vector3"), entities, M.bearing(env), ship.where())
		end
		return unpack(r, 1, table.maxn(r))
	end, opts)
	-- Shells: their parts go out just before the scene update of their world, after the animations
	-- placed them (as src/aimpose.lua bends the spine).
	obsidian.hook("World", "update_scene", function(original, world, ...)
		if #M.shells > 0 then
			pcall(function()
				local U, V3 = g("Unit"), g("Vector3")
				for i = #M.shells, 1, -1 do
					local s = M.shells[i]
					-- Old shells go without touching the unit: its world may be gone.
					if clock - s.t > M.SHELL_TIME then table.remove(M.shells, i)
					elseif s.world == world then
						if U.alive(s.unit) then M.push(U, V3, s) else table.remove(M.shells, i) end
					end
				end
			end)
		end
		return original(world, ...)
	end, opts)
	-- Each frame: a pod down stands upright; a pod gone is dropped.
	obsidian.on_frame(function()
		clock = clock + (rawget(_G, "ENGINE_DT") or 0.016)
		if #M.pods == 0 then return end
		local U, Q = g("Unit"), g("Quaternion")
		for i = #M.pods, 1, -1 do
			local pod = M.pods[i]
			local alive = pcall(U.alive, pod.unit) and U.alive(pod.unit)
			if not alive then
				table.remove(M.pods, i)
			else
				local ok, down = pcall(M.landed, U, pod.unit)
				if (ok and down) or clock - pod.t > M.POD_TIME then
					upright(U, Q, pod)
					table.remove(M.pods, i)
				end
			end
		end
	end, opts)
end

return M
