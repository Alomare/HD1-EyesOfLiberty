-- The session parts: max weapon range, far enemy detection, free movement and throw range.
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

local function start_weapon_range(env)
	local opts = env.part("weapon_range")
	local function over_entities(original, self, entities, ...)
		return M.with_entities(entities, original, self, entities, ...)
	end
	hook("FirearmComponent", "update_slaves", over_entities, opts)
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

function M.start(env)
	env_ref = env
	if env.config.get("throw_range") ~= false then start_throw_range(env) end
	if env.config.get("max_weapon_range") ~= false then start_weapon_range(env) end
	if env.config.get("far_detection") ~= false then start_enemy_detection(env) end
	if env.config.get("free_movement") ~= false then start_free_movement(env) end
end

return M
