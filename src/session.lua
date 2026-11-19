-- The session parts: ballistics revamp (max weapon range with damage falloff), far enemy detection, free movement, throw range and patrols
-- that stay in view.
--
-- Both change the shared game, so each hook is registered with the options of the part. In a lobby
-- that isn't cleared the loader calls only the original, which is why every change here is made
-- around one call of the game and undone right after it: the game keeps no changed value, and the
-- part goes off at once when a player without the mod joins. Nothing needs undoing on the way out.
--
-- Max weapon range (part weapon_range)
--   Weapon components copy weapon_info.range into the state of each weapon when it is set up.
--   Firearms cast a fixed 100 m ray and use range to dip each shot so it meets the ground at that
--   distance (WeaponUtility.get_random_spread subtracts muzzle height / range from the direction).
--   Beams cast a ray as long as range, launchers dip like firearms, laser sights draw to range.
--   While each of those runs, state.range is raised to MAX_RANGE and put back after. Ranges under
--   MIN_RANGE (melee reach) stay as they are. Flame and arc weapons have their own reach settings
--   and stay as in the game.
--
-- Far enemy detection (part enemy_detection)
--   EnemyComponent.update_target keeps players inside enemy_info.aggro_range (80 m for most
--   enemies) in the aggro table, and an enemy that isn't patrolling chases the strongest target
--   there. While update_target runs, the enemy sees settings with aggro_range raised to AGGRO_RANGE.
--   Patrols only look for players inside enemy_info.patrol_range (12 m for most), and the same
--   check raises the alarm that calls reinforcements. EnemyUtility.wander already walks a patrol
--   toward a player it can see, so before wander runs, a patrol with a player between patrol_range
--   and SIGHT_RANGE casts the same sight ray the game casts, only longer. The patrol then comes
--   closer, and the alarm still needs the player inside patrol_range, as in the game.
local M = {}

-- Every hook of the session parts passes straight to the game while env.off (the old id of this mod
-- is loaded too, and both would change the same call: a throw four times as far).
local env_ref = nil
local function hook(target, method, fn, opts)
	obsidian.hook(target, method, function(original, ...)
		if env_ref and env_ref.off then return original(...) end
		return fn(original, ...)
	end, opts)
end

M.MAX_RANGE = 100
M.MIN_RANGE = 5
M.AGGRO_RANGE = 150
M.SIGHT_RANGE = 80
M.SIGHT_INTERVAL = 0.25

-- Weapon range -------------------------------------------------------------------------------------

local function raised(range)
	return type(range) == "number" and range >= M.MIN_RANGE and range < M.MAX_RANGE
end

-- Runs fn(...) with state.range raised in every context of `entities` (unit -> { state = ... }),
-- then puts each range back, also when fn fails.
function M.with_entities(entities, fn, ...)
	local kept
	if type(entities) == "table" then
		for _, context in pairs(entities) do
			local state = type(context) == "table" and context.state
			if type(state) == "table" and raised(state.range) then
				kept = kept or {}
				kept[state] = state.range
				state.range = M.MAX_RANGE
			end
		end
	end
	if not kept then return fn(...) end
	local results = { pcall(fn, ...) }
	for state, range in pairs(kept) do state.range = range end
	if not results[1] then error(results[2], 0) end
	return unpack(results, 2, table.maxn(results))
end

-- The same for one state table.
function M.with_state(state, fn, ...)
	if type(state) ~= "table" or not raised(state.range) then return fn(...) end
	local range = state.range
	state.range = M.MAX_RANGE
	local results = { pcall(fn, ...) }
	state.range = range
	if not results[1] then error(results[2], 0) end
	return unpack(results, 2, table.maxn(results))
end

-- Damage falloff (part weapon_range, with the range) --------------------------------------------------
--
-- With every bullet reaching MAX_RANGE, a bullet weapon hits as hard far past its own range as next to
-- it. So past the weapon's own range (weapon_info.range, which the game keeps as it is: only the state's
-- copy is raised) a hit loses damage, down to FALLOFF_LEAST at FALLOFF_SPAN metres past it, and stays
-- there. One rule for every bullet weapon, custom ones included, as each carries its own range.
--
-- A firearm's shots deal damage in the callback of its raycast (WeaponUtility.shoot_ray_callback), made
-- once when the weapon is set up and run when the physics answers, outside any call this mod could
-- wrap. Every such callback is wrapped as it is made (the hook is in the view part, so weapons set up in
-- any lobby get it), and the wrapper does nothing unless this part ran FirearmComponent.update_slaves
-- for that weapon within LIVE_FOR seconds: in a lobby that isn't cleared the part's hooks stop, and
-- with them the falloff, at once. Beam (laser) weapons have no such callback and stay as they are.
--
-- The game takes a hit's damage as power less armor (HealthComponent.calculate_damage, run again by the
-- machine that owns the target from the command's power). Lowering power by a share would cut more than
-- that share from an armored target, or all of it. So while the wrapped callback runs, the "do_damage"
-- command it queues gets the power that leaves exactly the share of the damage: power - (1 - share) *
-- damage, with damage worked out as the target's machine will.
M.FALLOFF_SPAN = 30
M.FALLOFF_LEAST = 0.25
M.LIVE_FOR = 1

-- The share of damage left `distance` metres from the muzzle, for a weapon of `range` metres.
function M.falloff(distance, range)
	if type(distance) ~= "number" or type(range) ~= "number" or range < M.MIN_RANGE then return 1 end
	local past = distance - range
	if past <= 0 then return 1 end
	if past >= M.FALLOFF_SPAN then return M.FALLOFF_LEAST end
	return 1 - (1 - M.FALLOFF_LEAST) * past / M.FALLOFF_SPAN
end

-- The power for a hit that keeps `share` of the damage `damage` that `power` deals.
function M.lowered_power(power, damage, share)
	if type(power) ~= "number" or type(damage) ~= "number" or damage <= 0 or share >= 1 then return power end
	return power - (1 - share) * damage
end

local live = setmetatable({}, { __mode = "k" }) -- weapon state -> clock when the part last saw it
local clock = os and os.clock or function() return 0 end

-- Whether laser bolts: a weapon whose hit or tracer effect names a laser keeps its damage.
local function is_laser(info)
	for _, k in ipairs({ "effect_hit", "tracer", "tracer_effect", "muzzle_effect" }) do
		local v = info[k]
		if type(v) == "string" and v:lower():find("laser", 1, true) then return true end
	end
	return false
end

-- Runs a firearm's shot callback with its damage commands lowered by distance.
function M.with_falloff(context, fn, ...)
	local st = type(context) == "table" and context.state
	local seen = type(st) == "table" and live[st]
	local info = seen and st.weapon_info
	if not (seen and clock() - seen <= M.LIVE_FOR and type(info) == "table" and type(info.range) == "number"
		and info.range >= M.MIN_RANGE and info.range < M.MAX_RANGE and not is_laser(info)) then
		return fn(...)
	end
	local EA, V3A, HC = rawget(_G, "EntityAux"), rawget(_G, "Vector3Aux"), rawget(_G, "HealthComponent")
	local from = st.last_ray_from
	if not (EA and V3A and HC and from) then return fn(...) end
	local queue = EA.queue_command_interface
	local range = info.range
	EA.queue_command_interface = function(unit, interface, command, data, ...)
		if command == "do_damage" and interface == "damageable" and type(data) == "table" and type(data.power) == "number" and data.position then
			pcall(function()
				local a, b = V3A.unbox(from), V3A.unbox(data.position)
				local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
				local share = M.falloff(math.sqrt(dx * dx + dy * dy + dz * dz), range)
				if share < 1 then
					local damage = HC.calculate_damage(unit, data.power, nil, data.armorpiercing, data.angle_incidence, data.angle_hit, nil, data.ignore_armor)
					data.power = M.lowered_power(data.power, damage, share)
				end
			end)
		end
		return queue(unit, interface, command, data, ...)
	end
	local results = { pcall(fn, ...) }
	EA.queue_command_interface = queue
	if not results[1] then error(results[2], 0) end
	return unpack(results, 2, table.maxn(results))
end

-- Notes the firearms whose range the part raises this frame, for the falloff.
function M.note_live(entities)
	if type(entities) ~= "table" then return end
	local now = clock()
	for _, context in pairs(entities) do
		local st = type(context) == "table" and context.state
		if type(st) == "table" and raised(st.range) then live[st] = now end
	end
end

local function start_falloff(env)
	hook("WeaponUtility", "shoot_ray_callback", function(original, unit, context, ...)
		local callback = original(unit, context, ...)
		if type(callback) ~= "function" then return callback end
		return function(...)
			return M.with_falloff(context, callback, ...)
		end
	end, env.VIEW)
end

local function start_weapon_range(env)
	local opts = env.part("weapon_range")
	local function over_entities(original, self, entities, ...)
		return M.with_entities(entities, original, self, entities, ...)
	end
	hook("FirearmComponent", "update_slaves", function(original, self, entities, ...)
		M.note_live(entities)
		return M.with_entities(entities, original, self, entities, ...)
	end, opts)
	hook("BeamweaponComponent", "update_slaves", over_entities, opts)
	hook("LaserSightComponent", "update_slaves", over_entities, opts)
	hook("LauncherComponent", "do_fire", function(original, self, unit, state, ...)
		return M.with_state(state, original, self, unit, state, ...)
	end, opts)
end

-- Enemy detection ----------------------------------------------------------------------------------

local shadows = setmetatable({}, { __mode = "k" })

-- Settings that answer a raised aggro_range and read everything else from `settings`.
function M.shadow(settings)
	if type(settings) ~= "table" then return settings end
	local info = settings.enemy_info
	if type(info) ~= "table" or type(info.aggro_range) ~= "number" or info.aggro_range < M.MIN_RANGE
		or info.aggro_range >= M.AGGRO_RANGE then
		return settings
	end
	local s = shadows[settings]
	if not s then
		local shadow_info = setmetatable({ aggro_range = M.AGGRO_RANGE }, { __index = info })
		s = setmetatable({ enemy_info = shadow_info }, { __index = settings })
		shadows[settings] = s
	end
	return s
end

function M.with_shadow(context, fn, ...)
	if type(context) ~= "table" then return fn(...) end
	local settings = context.settings
	local s = M.shadow(settings)
	if s == settings then return fn(...) end
	context.settings = s
	local results = { pcall(fn, ...) }
	context.settings = settings
	if not results[1] then error(results[2], 0) end
	return unpack(results, 2, table.maxn(results))
end

local last_cast = setmetatable({}, { __mode = "k" })

-- Casts the sight ray of a patrol out to SIGHT_RANGE when the closest player stands between
-- patrol_range and SIGHT_RANGE. `now` is a clock in seconds. Answers true when a ray went out.
function M.far_sight(unit, state, settings, now)
	if type(state) ~= "table" or not state.patroling or state.alerted then return false end
	if state.waiting_for_see_closest_target_raycast then return false end
	local ray = state.can_see_closest_target_raycast
	local target = state.closest_target_unit
	if not ray or not target or not Unit.alive(target) then return false end
	local info = type(settings) == "table" and settings.enemy_info
	local near = info and info.patrol_range
	if type(near) ~= "number" then return false end
	if last_cast[state] and now - last_cast[state] < M.SIGHT_INTERVAL then return false end

	local from = Vector3Aux.unbox(state.position)
	local to = Unit.world_position(target, 0)
	local distance = Vector3.distance(from, to)
	if distance < near or distance >= M.SIGHT_RANGE then return false end

	local eye = Vector3(0, 0, 1)
	from = from + eye
	ray:cast(from, Vector3.normalize((to + eye) - from), M.SIGHT_RANGE)
	state.waiting_for_see_closest_target_raycast = true
	last_cast[state] = now
	return true
end

local function start_enemy_detection(env)
	local opts = env.part("enemy_detection")
	-- wander runs once per patrol per frame, so the dt it gets can't make a clock; os.clock can.
	local clock = os and os.clock or function() return 0 end
	hook("EnemyComponent", "update_target", function(original, self, unit, context, ...)
		return M.with_shadow(context, original, self, unit, context, ...)
	end, opts)
	hook("EnemyUtility", "wander", function(original, unit, dt, component, state, settings, ...)
		pcall(M.far_sight, unit, state, settings, clock())
		return original(unit, dt, component, state, settings, ...)
	end, opts)
end

-- Free movement (part free_movement) ---------------------------------------------------------------

-- The game keeps every Helldiver and vehicle with keep_inside_screen on the shared top-down screen
-- (MoverComponent.update_masters slows movement toward the edge of CameraManager's frustum). While
-- third person steers the view, the movers of this player's avatar and vehicle run that update with
-- keep_inside_screen off, and come out counted as inside the screen, so the downed timer for a
-- Helldiver off screen never starts on them. The flag goes back right after the call.
function M.unleashed(masters, units, fn, ...)
	local kept
	if type(masters) == "table" then
		for unit in pairs(units) do
			local context = masters[unit]
			local state = type(context) == "table" and context.state
			if type(state) == "table" and state.keep_inside_screen then
				kept = kept or {}
				kept[#kept + 1] = state
				state.keep_inside_screen = false
			end
		end
	end
	if not kept then return fn(...) end
	local results = { pcall(fn, ...) }
	for _, state in ipairs(kept) do
		state.keep_inside_screen = true
		state.is_inside_screen = true
	end
	if not results[1] then error(results[2], 0) end
	return unpack(results, 2, table.maxn(results))
end

local function start_free_movement(env)
	hook("MoverComponent", "update_masters", function(original, self, masters, ...)
		local view = env.view
		if not (env.state and env.state.active and view and view.avatar) then return original(self, masters, ...) end
		local units = { [view.avatar] = true }
		if view.target then units[view.target] = true end
		return M.unleashed(masters, units, original, self, masters, ...)
	end, env.part("free_movement"))
end

-- Throw range (part throw_range) -------------------------------------------------------------------

-- ThrowableComponent.command_master "thrown" launches a grenade or a stratagem ball toward a spot
-- throw_distance_min + power * (throw_distance_max - throw_distance_min) metres away (speed
-- sqrt(distance * 18) at 45 degrees, under the game's gravity of 18). power is the charge times the
-- thrower's throw_range_multiplier, 1.5 with the Strong Arm perk. While "thrown" runs, the throwable
-- sees both distances times THROW_SCALE, so every throw lands that many times as far, Strong Arm
-- included.
M.THROW_SCALE = 2

local throw_shadows = setmetatable({}, { __mode = "k" })

-- Settings that answer the throw distances scaled and read everything else from `settings`.
function M.throw_shadow(settings)
	if type(settings) ~= "table" then return settings end
	local info = settings.throwable_info
	if type(info) ~= "table" or type(info.throw_distance_min) ~= "number" or type(info.throw_distance_max) ~= "number" then
		return settings
	end
	local s = throw_shadows[settings]
	if not s then
		local shadow_info = setmetatable({ throw_distance_min = info.throw_distance_min * M.THROW_SCALE,
			throw_distance_max = info.throw_distance_max * M.THROW_SCALE }, { __index = info })
		s = setmetatable({ throwable_info = shadow_info }, { __index = settings })
		throw_shadows[settings] = s
	end
	return s
end

function M.with_throw(context, fn, ...)
	if type(context) ~= "table" then return fn(...) end
	local settings = context.settings
	local s = M.throw_shadow(settings)
	if s == settings then return fn(...) end
	context.settings = s
	local results = { pcall(fn, ...) }
	context.settings = settings
	if not results[1] then error(results[2], 0) end
	return unpack(results, 2, table.maxn(results))
end

local function start_throw_range(env)
	hook("ThrowableComponent", "command_master", function(original, self, unit, context, message, ...)
		if message ~= "thrown" then return original(self, unit, context, message, ...) end
		return M.with_throw(context, original, self, unit, context, message, ...)
	end, env.part("throw_range"))
end

-- Patrols stay in view (part keep_patrols) ----------------------------------------------------------

-- PatrolManager.update_host despawns a patrol after 5 seconds with none of the patrol units inside the
-- top-down screen (is_position_inside_frustum with margins of -0.1, patrol_manager.lua 324), and spawns
-- it again, climbing out of the ground or dropping in, once the patrol place comes back inside the screen
-- (margins -0.5, line 304). The third-person view sees much farther than that screen, so a patrol in
-- plain view vanished and played the arrival again on coming close. While update_host runs, a unit
-- within KEEP_RANGE of a living Helldiver counts as on screen for that despawn check only; spawning
-- still waits for the top-down screen, so no more patrols come than in the game.
M.KEEP_RANGE = 100
M.KEEP_MARGIN = -0.1

-- Whether (x, y) lies within KEEP_RANGE of one of the places in `players` ({ x, y } each).
function M.near_players(players, x, y)
	local r2 = M.KEEP_RANGE * M.KEEP_RANGE
	for i = 1, #players do
		local p = players[i]
		local dx, dy = x - p.x, y - p.y
		if dx * dx + dy * dy <= r2 then return true end
	end
	return false
end

-- The places of the living Helldivers, from the patrol manager's own entity list.
function M.player_places(manager)
	local out = {}
	local em = type(manager) == "table" and manager.entity_manager
	if not em then return out end
	local EA, U = rawget(_G, "EntityAux"), rawget(_G, "Unit")
	for unit in pairs(em:get_slave_entities("character")) do
		local ok, health = pcall(EA.state, unit, "health")
		if not (ok and type(health) == "table" and health.is_dead) then
			local p = U.world_position(unit, 0)
			out[#out + 1] = { x = p.x, y = p.y }
		end
	end
	return out
end

local function start_keep_patrols(env)
	local opts = env.part("keep_patrols")
	local players = nil
	hook("PatrolManager", "update_host", function(original, self, ...)
		local ok, places = pcall(M.player_places, self)
		players = ok and places or nil
		local results = { pcall(original, self, ...) }
		players = nil
		if not results[1] then error(results[2], 0) end
		return unpack(results, 2, table.maxn(results))
	end, opts)
	hook("CameraManager", "is_position_inside_frustum", function(original, self, position, left, ...)
		if not players or left ~= M.KEEP_MARGIN then return original(self, position, left, ...) end
		local a, b, c, d = original(self, position, left, ...)
		if a then return a, b, c, d end
		if position and M.near_players(players, position.x, position.y) then return true, b, c, d end
		return a, b, c, d
	end, opts)
end

function M.start(env)
	env_ref = env
	if env.config.get("keep_patrols") ~= false then start_keep_patrols(env) end
	if env.config.get("throw_range") ~= false then start_throw_range(env) end
	if env.config.get("max_weapon_range") ~= false then
		start_weapon_range(env)
		start_falloff(env)
	end
	if env.config.get("far_detection") ~= false then start_enemy_detection(env) end
	if env.config.get("free_movement") ~= false then start_free_movement(env) end
end

return M
