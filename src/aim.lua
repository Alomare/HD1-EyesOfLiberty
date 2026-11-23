-- Aim under the shoulder camera: a ray from the camera through the middle of the screen finds the
-- crosshair point, and the game's aim, shots, grenades and stratagem balls go there.
--
-- Everything here is scoped to one call of the game (src/scoped.lua):
--   InputComponent.queue_command_master   the character's aim input points at the crosshair point
--   <weapon>.update_slaves, LauncherComponent.do_fire
--                                          Quaternion.forward answers the crosshair way for this
--                                          player's weapons, and WeaponUtility.get_random_spread
--                                          drops the dip that makes a level shot meet the ground
--   LauncherComponent.do_fire             the state's z_direction is the crosshair way's
--   LaserSightComponent.update_slaves     the laser line goes to the crosshair point
--   Character*Throw.update                 CameraManager.screen_to_world answers the crosshair point
--   CharacterComponent.do_throw, ThrowableComponent.command_master "thrown"
--                                          the grenade or stratagem ball flies to the crosshair point
--                                          on a low arc (src/arc.lua aimed)
--   WeaponUtility.shoot_beam_callback     a laser beam that hits nothing is drawn along the way it
--                                          was fired, not the Helldiver's flat facing
--   ArcweaponComponent.command_slave "show_hits"
--                                          an arc that finds no target flies toward the crosshair
--   CharacterSubstateMachine.update        the Helldiver turns at the handling of src/ergo.lua
--
-- On foot, shots leave along the way the weapon faces (src/ergo.lua): its heading, and a pitch that
-- swings to the crosshair point while aiming or firing. The crosshair is drawn where that way meets
-- something, so it shows where shots go while the weapon swings in.
local rig = obsidian.module("src/rig")
local ergo = obsidian.module("src/ergo")
local frustum = obsidian.module("src/frustum")
local scoped = obsidian.module("src/scoped")
local shake = obsidian.module("src/shake")

local M = {}

local function g(name) return rawget(_G, name) end

M.RANGE = 300 -- metres the crosshair ray reaches
M.ORIGIN = { x = 0, y = 0, z = 1.5 } -- where shots start over the root until a weapon reports it

-- The weapon's way on foot (src/ergo.lua), each frame of the view: pitch in radians, dir, origin, the
-- frame it was worked out, and the frame a laser of this player last fired. cross: 0 to 1, how far the
-- crosshair has moved from the middle of the view to the weapon's point.
M.gun = { pitch = nil, dir = nil, origin = nil, frame = -10, laser = -100, cross = 0 }

-- Whether a unit hit by the crosshair ray belongs to this player: the body, the vehicle, or something the
-- Helldiver carries (a backpack such as the shield generator pack, whose shield surrounds the body).
local function own_hit(unit, view)
	if unit == nil then return false end
	if unit == view.avatar or unit == view.target then return true end
	local EA = g("EntityAux")
	if not EA then return false end
	local ok, wielder = pcall(function(u)
		if EA.has_component(u, "equipment") then return EA.state(u, "equipment").wielder end
		return nil
	end, unit)
	return ok and wielder ~= nil and (wielder == view.avatar or wielder == view.target)
end

-- The crosshair point (and the unit there, for pings): the first thing along the view past the pivot that isn't this player's own body,
-- vehicle or gear, or the far end of the ray. Every hit along the ray is asked for at once: the ray
-- starts inside a shield bubble when the Helldiver carries one, and a hit at the start (a shape the ray
-- starts in) doesn't count either.
function M.find_point(view)
	local f = view.forward
	return M.cast(view, rig.add(view.position, f, rig.ray_start(view.position, f, view.pivot)), f)
end

-- The first thing along a ray from `start` along `f` that isn't this player's own, or the far end.
function M.cast(view, start, f)
	local PW, V3, W, Actor = g("PhysicsWorld"), g("Vector3"), g("World"), g("Actor")
	local pw = W.physics_world(view.world)
	local hits = PW.immediate_raycast(pw, V3(start.x, start.y, start.z), V3(f.x, f.y, f.z), M.RANGE,
		"all", "collision_filter", "damage_ray")
	local best, best_distance, best_unit = nil, math.huge, nil
	if type(hits) == "table" then
		for _, h in ipairs(hits) do
			local pos, distance, actor = h[1], h[2], h[4]
			if pos and type(distance) == "number" and distance > 0.05 and distance < best_distance then
				local unit = actor and Actor and Actor.unit(actor)
				if not own_hit(unit, view) then best, best_distance, best_unit = pos, distance, unit end
			end
		end
	end
	if best then return { x = best.x, y = best.y, z = best.z }, true, best_unit end
	return rig.add(start, f, M.RANGE), false, nil
end

-- Where the crosshair is drawn: the middle of the view, in pixels from the bottom left of the window.
function M.centre(cm)
	local w, h, x0, y0 = cm.viewport:window()
	return { x = (x0 or 0) + w / 2, y = (y0 or 0) + h / 2 }
end

-- The character's aim input. The game sets it while the player aims, fires or throws; it now points
-- at the crosshair point. A pad's right stick turns the view, so it no longer turns the Helldiver.
function M.steer(data, input, view, point)
	if type(data) ~= "table" or type(data.aim) ~= "table" then return false end
	-- The map, a menu or the game's own input lock: the game's aim stands.
	if not input.look then return false end
	local a = data.aim
	-- With a mouse the game asks for aim only while aiming, firing or throwing; a pad's aim is the stick.
	local asked = input.aiming or input.fire or input.throw
	if input.kbm and ((a.x or 0) ~= 0 or (a.y or 0) ~= 0) then asked = true end
	if asked and point then
		local from = view.target_position or view.pivot
		local flat = rig.flat_dir(from, point)
		if flat then
			a.x, a.y, a.z = flat.x, flat.y, 0
			return true
		end
	end
	if not input.kbm then a.x, a.y, a.z = 0, 0, 0 end
	return false
end

-- Scroll camera distance: on foot with the mouse, a wheel turn moves the camera, so it doesn't switch
-- weapons too. The game turns the wheel into switch_weapon in the character's input
-- (input_component.lua, switch_weapon_next and switch_weapon_previous from the wheel axis); number keys
-- still switch, unless pressed on the same frame as a wheel turn.
function M.gate_wheel(data, input, env, camera)
	if type(data) ~= "table" or data.switch_weapon == nil then return false end
	if env.config.get("scroll_distance") ~= true or env.state.vehicle or not (input.kbm and input.look) then return false end
	if camera.wheel() == 0 then return false end
	data.switch_weapon = nil
	return true
end

-- This player's units that fire: the avatar and, in a vehicle, the seat and the guns of that seat.
-- Every weapon update of every frame asks, so the set is made once per view (a new view each frame).
local own_cache = setmetatable({}, { __mode = "k" })
local function own_units(view)
	local cached = own_cache[view]
	if cached then return cached end
	local set = { [view.avatar] = true }
	own_cache[view] = set
	if view.vehicle and view.target then
		set[view.target] = true
		local EA = g("EntityAux")
		pcall(function()
			local seat = EA.state(view.target, "seat")
			local cs = EA.state(view.avatar, "character")
			for i, unit in ipairs(seat.seat_weapon_units or {}) do
				local index = seat.weapon_index_to_seat and seat.weapon_index_to_seat[i]
				if index == nil or index == cs.current_seat_index then set[unit] = true end
			end
		end)
	end
	return set
end

local function equipment_wielder(EA, unit)
	if EA.has_component(unit, "equipment") then return EA.state(unit, "equipment").wielder end
	return nil
end

local function wielder_of(unit)
	local ok, w = pcall(equipment_wielder, g("EntityAux"), unit)
	return ok and w or unit
end

-- A flamethrower of this player among the flame weapon masters fires: the hand-held ones and the
-- one of a vehicle seat this player sits in (the Lumberer).
function M.note_flames(masters, view)
	local own = own_units(view)
	for unit, ctx in pairs(masters) do
		local st = type(ctx) == "table" and ctx.state
		if type(st) == "table" and (st.firing_auto or st.firing_single or st.was_firing) then
			if own[unit] or own[wielder_of(unit)] then
				shake.flamed()
				return true
			end
		end
	end
	return false
end

-- For each weapon of this player in `slaves` (unit to context), the forward the game will compute and
-- the way to the crosshair point. Answers a list of { f, dir }. The way starts where the game's shot
-- starts (firearm, beam, flame and launcher components: the root plus ray_source_offset turned by the
-- weapon's rotation, 1.5 m up by default), so the shot meets the crosshair point and not a spot above
-- it. from_weapon: the root is the weapon's own (LauncherComponent.do_fire), not the wielder's.
function M.collect(slaves, view, point, quaternion_forward, from_weapon)
	local list = {}
	local U, Q, V3A = g("Unit"), g("Quaternion"), g("Vector3Aux")
	local mine = own_units(view)
	local now = M.frame_now and M.frame_now() or 0
	for unit, ctx in pairs(slaves) do
		local wielder = mine[unit] and unit or wielder_of(unit)
		if wielder and (mine[wielder] or mine[unit]) and U.alive(wielder) then
			local st = type(ctx) == "table" and (ctx.state or ctx) or {}
			-- Every weapon component keeps was_firing on its slave while it fires: the camera's rumble.
			if st.was_firing then shake.fired(view.vehicle) end
			for _, node in ipairs({ type(st.attach_node) == "number" and st.attach_node or 0, 0 }) do
				local rot = U.world_rotation(wielder, node)
				local f = quaternion_forward(rot)
				local p = U.world_position(from_weapon and unit or wielder, 0)
				local offset = st.ray_source_offset and V3A.unbox(st.ray_source_offset) or nil
				local origin = rig.shot_origin({ x = p.x, y = p.y, z = p.z }, offset, function(o) return Q.rotate(rot, o) end)
				-- Where this player's shots start, from the Helldiver's root, for the weapon's way
				-- (M.gun_frame).
				if not view.vehicle and wielder == view.avatar then
					local w = U.world_position(wielder, 0)
					M.shot_offset = { x = origin.x - w.x, y = origin.y - w.y, z = origin.z - w.z }
				end
				-- A vehicle gun turns slower than the view: it fires the way it points, at the height of the
				-- crosshair point. On foot the shot goes straight to the crosshair point.
				-- On foot it leaves along the weapon's way (src/ergo.lua): its heading, at the pitch it has
				-- swung to.
				local dir
				if view.vehicle then dir = rig.gun_dir(origin, point, f)
				elseif M.gun_live(wielder, view, now) then dir = ergo.dir(f, M.gun.pitch, M.gun.turn)
				else dir = rig.shot_dir(origin, point, { x = f.x, y = f.y, z = 0 }) end
				if dir then list[#list + 1] = { f = { x = f.x, y = f.y, z = f.z }, dir = dir, unit = unit, firing = st.was_firing and true or false } end
			end
		end
	end
	return list
end

-- Laser sights draw from the weapon's own node, and lower the line by 1.5 / range after asking for
-- the forward: the answer is raised by as much (lift), so the line lands on the crosshair point.
function M.collect_lasers(slaves, view, point, quaternion_forward)
	local list = {}
	local U = g("Unit")
	local mine = own_units(view)
	for unit, ctx in pairs(slaves) do
		local st = type(ctx) == "table" and ctx.state or nil
		local wielder = wielder_of(unit)
		if st and st.laser_enabled and wielder and (mine[wielder] or mine[unit]) and U.alive(unit) then
			local node = type(st.attach_node) == "number" and st.attach_node or 0
			local f = quaternion_forward(U.world_rotation(unit, node))
			local p = U.world_position(unit, node)
			local dir
			if M.gun_live(wielder, view, M.frame_now and M.frame_now() or 0) then dir = ergo.dir(f, M.gun.pitch, M.gun.turn)
			else dir = rig.shot_dir({ x = p.x, y = p.y, z = p.z }, point, { x = f.x, y = f.y, z = 0 }) end
			if dir then
				local lift = type(st.range) == "number" and st.range > 0 and 1.5 / st.range or 0
				list[#list + 1] = { f = { x = f.x, y = f.y, z = f.z }, dir = dir, lift = lift }
			end
		end
	end
	return list
end

local function same(a, b)
	return math.abs(a.x - b.x) < 1e-5 and math.abs(a.y - b.y) < 1e-5 and math.abs(a.z - b.z) < 1e-5
end

-- The way each of this player's lasers fired last: weapon unit -> { dir, frame }.
M.beam_dirs = setmetatable({}, { __mode = "k" })

-- Runs fn(...) with Quaternion.forward of the rotation `rot` answering `dir` ({ x, y, z }). The game
-- asks for the flat facing of the wielder (node 0) where these hooks bend it.
function M.with_forward(rot_forward, dir, fn, ...)
	local Q, V3 = g("Quaternion"), g("Vector3")
	local forward = Q.forward
	local function bent(q, ...)
		local f = forward(q, ...)
		if same(f, rot_forward) then return V3(dir.x, dir.y, dir.z) end
		return f
	end
	return scoped.swap(Q, "forward", bent, fn, ...)
end

-- Runs fn(...) with this player's shots going to the crosshair point.
function M.redirect(list, fn, ...)
	local Q, WU, V3 = g("Quaternion"), g("WeaponUtility"), g("Vector3")
	if #list == 0 or type(Q) ~= "table" or type(WU) ~= "table" then return fn(...) end
	local forward, spread = Q.forward, WU.get_random_spread
	local function aimed_forward(q, ...)
		local f = forward(q, ...)
		for _, o in ipairs(list) do
			if same(f, o.f) then return V3(o.dir.x, o.dir.y, o.dir.z + (o.lift or 0)) end
		end
		return f
	end
	-- The game's spread is made for a level shot: it squashes the up and down part against the world's
	-- up and lowers the shot by offset.z / range so it meets the ground at the end of its range. For
	-- this player's shot the spread is made around the level way with no lowering, then turned up or
	-- down to the crosshair way, so the scatter keeps its shape and centres on the crosshair point.
	local function level_spread(offset, f, ...)
		for _, o in ipairs(list) do
			if f and same(f, o.dir) then
				local flat = rig.normalize({ x = o.dir.x, y = o.dir.y, z = 0 })
				if not flat then return spread(V3(offset.x, offset.y, 0), f, ...) end
				local s = spread(V3(offset.x, offset.y, 0), V3(flat.x, flat.y, 0), ...)
				if s == nil then return s end
				local t = rig.turn_to({ x = s.x, y = s.y, z = s.z }, flat, o.dir)
				return V3(t.x, t.y, t.z)
			end
		end
		return spread(offset, f, ...)
	end
	return scoped.swap(Q, "forward", aimed_forward, scoped.swap, WU, "get_random_spread", level_spread, fn, ...)
end

function M.start(env)
	local state = env.state
	local camera = env.camera
	if not camera then return end
	state.aim_point = nil

	table.insert(env.on_pose, function(view, cm)
		-- The death cam aims nothing and draws no crosshair. On this player's own body, before it moves
		-- to an ally, the point in the middle of the view is still found, for pings only.
		state.ping_centre = nil
		if view.watching then
			state.aim_point, state.aim_hit, state.crosshair, state.aim_unit = nil, nil, nil, nil
			if view.own_body then
				state.aim_point, state.aim_hit, state.aim_unit = M.find_point(view)
				state.ping_centre = M.centre(cm)
			end
			return
		end
		local U = g("Unit")
		local tp = U.world_position(view.target, 0)
		view.target_position = { x = tp.x, y = tp.y, z = tp.z }
		local point, hit, unit = M.find_point(view)
		state.aim_point, state.aim_hit, state.aim_unit = point, hit, unit
		state.centre = M.centre(cm)
		state.crosshair = state.centre
		local ok, err = pcall(M.gun_frame, env, view, cm, rawget(_G, "ENGINE_DT") or 0.016)
		if not ok and not M.gun_failed then
			M.gun_failed = true
			env.log("Eyes of Liberty: weapon handling stopped: " .. tostring(err))
		end
	end)
	table.insert(env.on_release, function()
		state.aim_point, state.aim_hit, state.aim_unit, state.ping_centre, state.centre = nil, nil, nil, nil, nil
		M.gun.pitch, M.gun.dir, M.gun.origin, M.gun.cross = nil, nil, nil, 0
	end)
	M.frame_now = function() return env.frame and env.frame() or 0 end
	M.ergonomics_on = env.config.get("weapon_ergonomics") ~= false
	env.config.on_change("weapon_ergonomics", function(v)
		M.ergonomics_on = v ~= false
		M.gun.cross = 0
	end)

	local function live()
		return state.active and env.view and state.aim_point and camera.input
	end

	obsidian.hook("InputComponent", "queue_command_master", function(original, self, unit, component, command, data, ...)
		if component == "character" and command == "input" and live() and unit == camera.input.unit then
			pcall(camera.pad_buttons, data, camera.input)
			pcall(M.steer, data, camera.input, env.view, state.aim_point)
			pcall(M.gate_wheel, data, camera.input, env, camera)
		end
		return original(self, unit, component, command, data, ...)
	end, env.VIEW)

	-- Firearms, beams, flamers and arc throwers: every machine runs update_slaves for every weapon; on
	-- this machine, this player's own weapons fire along the crosshair.
	for _, class in ipairs({ "FirearmComponent", "BeamweaponComponent", "FlameweaponComponent", "ArcweaponComponent" }) do
		obsidian.hook(class, "update_slaves", function(original, self, slaves, dt, ...)
			if not live() or type(slaves) ~= "table" then return original(self, slaves, dt, ...) end
			local ok, list = pcall(M.collect, slaves, env.view, state.aim_point, g("Quaternion").forward)
			if not ok or #list == 0 then return original(self, slaves, dt, ...) end
			if class == "BeamweaponComponent" then
				local now = env.frame and env.frame() or 0
				for _, o in ipairs(list) do
					M.beam_dirs[o.unit] = { dir = o.dir, frame = now }
					-- A laser firing: slower handling, and a quieter camera (src/shake.lua).
					if o.firing then
						M.gun.laser = now
						shake.quiet(shake.LASER)
					end
				end
			end
			return M.redirect(list, original, self, slaves, dt, ...)
		end, env.VIEW)
	end

	-- A beam that hits nothing is drawn by its raycast's callback from the muzzle along the wielder's
	-- flat facing (WeaponUtility.shoot_beam_callback: Quaternion.forward(Unit.world_rotation(wielder, 0))),
	-- so a laser fired up or down drew level. For this player's lasers that facing answers the way the
	-- beam was fired last (kept by the update_slaves hook above).
	obsidian.hook("WeaponUtility", "shoot_beam_callback", function(original, unit, ...)
		local callback = original(unit, ...)
		if type(callback) ~= "function" then return callback end
		return function(...)
			local kept = M.beam_dirs[unit]
			local now = env.frame and env.frame() or 0
			if not (kept and live() and now - kept.frame <= 3) then return callback(...) end
			local ok, flat = pcall(function()
				local U, Q = g("Unit"), g("Quaternion")
				local f = Q.forward(U.world_rotation(wielder_of(unit), 0))
				return { x = f.x, y = f.y, z = f.z }
			end)
			if not ok then return callback(...) end
			return M.with_forward(flat, kept.dir, callback, ...)
		end
	end, env.VIEW)

	-- An arc weapon's bolt that finds no target flies from 1 m over the wielder's root along its flat
	-- facing (ArcweaponComponent.command_slave "show_hits", and the shotgun's blast): for this player
	-- it flies toward the crosshair point. Targets are picked by direction over the ground, which the
	-- Helldiver's facing (src/aim.lua steer) already turns to the crosshair.
	obsidian.hook("ArcweaponComponent", "command_slave", function(original, self, unit, ctx, message, ...)
		if not ((message == "show_hits" or message == "shotgun_blast") and live()) then
			return original(self, unit, ctx, message, ...)
		end
		local ok, flat, dir = pcall(function()
			local U, Q = g("Unit"), g("Quaternion")
			local wielder = wielder_of(unit)
			if wielder ~= env.view.avatar or env.view.vehicle then return nil end
			local p = U.world_position(wielder, 0)
			local live_gun = M.gun_live(wielder, env.view, M.frame_now and M.frame_now() or 0)
			local d = (live_gun and M.gun.dir) or rig.shot_dir({ x = p.x, y = p.y, z = p.z + 1 }, state.aim_point)
			if not d then return nil end
			local f = Q.forward(U.world_rotation(wielder, 0))
			return { x = f.x, y = f.y, z = f.z }, d
		end)
		if not (ok and flat and dir) then return original(self, unit, ctx, message, ...) end
		return M.with_forward(flat, dir, original, self, unit, ctx, message, ...)
	end, env.VIEW)

	obsidian.hook("LaserSightComponent", "update_slaves", function(original, self, slaves, dt, ...)
		if not live() or type(slaves) ~= "table" then return original(self, slaves, dt, ...) end
		local ok, list = pcall(M.collect_lasers, slaves, env.view, state.aim_point, g("Quaternion").forward)
		if not ok or #list == 0 then return original(self, slaves, dt, ...) end
		return M.redirect(list, original, self, slaves, dt, ...)
	end, env.VIEW)

	-- A flamethrower of this player firing quiets the camera shake (src/shake.lua): the masters of
	-- this machine hold firing_auto while the trigger is held and was_firing for the frame.
	obsidian.hook("FlameweaponComponent", "update_masters", function(original, self, masters, ...)
		local r = scoped.pack(original(self, masters, ...))
		if live() and type(masters) == "table" then pcall(M.note_flames, masters, env.view) end
		return unpack(r, 1, r.n)
	end, env.VIEW)

	-- The Helldiver turns to the aim input at the handling of src/ergo.lua while holding the weapon up:
	-- the keep goes in after the state machines, where the game reads it, unless one of them set its own.
	obsidian.hook("CharacterSubstateMachine", "update", function(original, unit, ctx, ...)
		local r = scoped.pack(original(unit, ctx, ...))
		if live() and not env.view.vehicle and unit == camera.input.unit then pcall(M.turn, ctx, env) end
		return unpack(r, 1, r.n)
	end, env.VIEW)

	-- Weapon ergonomics off: the game's turn is measured, so the pitch keeps its pace.
	obsidian.hook("CharacterComponent", "update_masters", function(original, self, masters, dt, ...)
		local me = live() and M.ergonomics_on == false and camera.input.unit
		local ctx = me and type(masters) == "table" and masters[me]
		if not ctx then return original(self, masters, dt, ...) end
		local r = scoped.pack(original(self, masters, dt, ...))
		pcall(M.measure_turn, ctx, me, dt)
		return unpack(r, 1, r.n)
	end, env.VIEW)

	-- Launchers fire once per call, and set the height of the shot from z_direction. A launcher that
	-- lobs a shell (the Rumbler, the Obliterator) fires along the flat way to the crosshair point at the
	-- angle src/arc.lua gives (M.lob_z): along the crosshair way, a shot at the sky started inside the
	-- Helldiver or came straight back down on it.
	M.arc = obsidian.module("src/arc")
	obsidian.hook("LauncherComponent", "do_fire", function(original, self, unit, st, ...)
		if not live() or type(st) ~= "table" then return original(self, unit, st, ...) end
		local settings = M.arc.lob_settings(st)
		if settings and not env.view.vehicle then
			-- The flat way holds even with the crosshair point right in front, where M.collect finds no way.
			local done, z, list = pcall(M.lob_z, unit, st, settings, env.view, state.aim_point)
			if not done or not z then return original(self, unit, st, ...) end
			shake.fired(false)
			-- The first shell of a Rumbler burst: the arc shown at release stays while the shells fly.
			if st.fire_on_release and not st.burst_round then pcall(M.arc.lob_fired) end
			return scoped.swap(st, "z_direction", z, M.redirect, list, original, self, unit, st, ...)
		end
		local ok, list = pcall(M.collect, { [unit] = { state = st } }, env.view, state.aim_point, g("Quaternion").forward, true)
		if not ok or #list == 0 then return original(self, unit, st, ...) end
		shake.fired(env.view.vehicle)
		local z = list[1].dir.z
		if type(st.z_direction) ~= "number" then return M.redirect(list, original, self, unit, st, ...) end
		return scoped.swap(st, "z_direction", z, M.redirect, list, original, self, unit, st, ...)
	end, env.VIEW)

	-- The Laser sight perk, and the Recoilless Rifle's own laser (the same code, set up for that
	-- weapon alone: EquipmentComponent with lasersight_attached), aim along the flat forward of the
	-- Helldiver's root (perk_settings.lua perk_lasersight.update_slave). For this player's Helldiver
	-- that forward is the way to the crosshair point (M.perk_laser). Both callers look the function up
	-- in PerkSettings each time, so one hook on it covers them; PerkSettings may come after this mod
	-- starts, so the hook goes in on the first frame it is there.
	local perk_hooked = false
	local function hook_perk_laser()
		if perk_hooked then return end
		local ps = g("PerkSettings")
		local perk = type(ps) == "table" and ps.perk_lasersight
		if type(perk) ~= "table" or type(perk.update_slave) ~= "function" then return end
		perk_hooked = true
		obsidian.hook(perk, "update_slave", function(original, unit, component, ctx, ...)
			if not live() or env.view.vehicle or unit ~= env.view.avatar then return original(unit, component, ctx, ...) end
			local ok, list = pcall(M.perk_laser, unit, ctx, env.view, state.aim_point)
			if not ok or not list then return original(unit, component, ctx, ...) end
			return M.redirect(list, original, unit, component, ctx, ...)
		end, env.VIEW)
	end
	hook_perk_laser()
	obsidian.on_frame(hook_perk_laser, env.VIEW)

	-- Grenades and stratagem balls: the game measures the throw from the ground point under the
	-- cursor, through CameraManager:screen_to_world.
	local throwing = false
	local function on() throwing = true end
	local function off() throwing = false end
	for _, class in ipairs({ "CharacterStateThrow", "CharacterStateStratagemsThrow", "CharacterStateDownedThrow",
		"CharacterStateDownedStratagemsThrow" }) do
		obsidian.hook(class, "update", function(original, unit, ...)
			if not live() or unit ~= camera.input.unit then return original(unit, ...) end
			return scoped.around(on, off, original, unit, ...)
		end, env.VIEW)
	end
	obsidian.hook("CameraManager", "screen_to_world", function(original, self, ...)
		local p = state.aim_point
		if throwing and p then return g("Vector3")(p.x, p.y, p.z) end
		return original(self, ...)
	end, env.VIEW)

	-- Aimed throws: CharacterComponent.do_throw of this player's Helldiver marks the throw, and the
	-- "thrown" command of the throwable that follows (InventoryComponent "throw" queues it) launches it
	-- with src/arc.lua's aimed velocity toward the crosshair point instead of the game's 45 degree lob.
	obsidian.hook("CharacterComponent", "do_throw", function(original, self, unit, ctx, ...)
		if live() and unit == camera.input.unit then
			local st = type(ctx) == "table" and ctx.state or {}
			M.pending_throw = { unit = unit, multiplier = st.throw_range_multiplier, frame = env.frame and env.frame() or 0 }
		end
		return original(self, unit, ctx, ...)
	end, env.VIEW)
	obsidian.hook("ThrowableComponent", "command_master", function(original, self, unit, context, message, ...)
		local pending = M.pending_throw
		if message ~= "thrown" or not pending or not live() then return original(self, unit, context, message, ...) end
		local now = env.frame and env.frame() or 0
		if now - pending.frame > 30 then
			M.pending_throw = nil
			return original(self, unit, context, message, ...)
		end
		local ok, set = pcall(M.aimed_setter, unit, context, pending, state.aim_point)
		if not ok or not set then return original(self, unit, context, message, ...) end
		M.pending_throw = nil
		return scoped.swap(g("Actor"), "set_velocity", set, original, self, unit, context, message, ...)
	end, env.VIEW)
end

M.pending_throw = nil

-- The Laser sight perk's line for this player's Helldiver `unit` (ctx: the perk's context), as the
-- list M.redirect takes. The game casts it from the root plus the weapon's ray_source_offset (1.5 m up
-- with none) along the root's forward times 1.05, lowered by 1.5 / (range * range_multiplier), range
-- the weapon's or 30: the forward answered is the way to the crosshair point raised by as much, so the
-- line lands on the point.
function M.perk_laser(unit, ctx, view, point)
	local U, Q, V3A, EA, LSM = g("Unit"), g("Quaternion"), g("Vector3Aux"), g("EntityAux"), g("LuaSettingsManager")
	local rot = U.local_rotation(unit, 0)
	local f = Q.forward(rot)
	local inv = EA.state(unit, "inventory")
	local weapon = inv and inv.current_weapon
	local settings = weapon and LSM and LSM:get_settings_by_unit(weapon)
	local info = type(settings) == "table" and settings.weapon_info or {}
	local p = U.local_position(unit, 0)
	local offset = info.ray_source_offset and V3A.unbox(info.ray_source_offset) or { x = 0, y = 0, z = 1.5 }
	local origin = rig.shot_origin({ x = p.x, y = p.y, z = p.z }, offset, function(o) return Q.rotate(rot, o) end)
	local dir
	if M.gun_live(unit, view, M.frame_now and M.frame_now() or 0) then dir = ergo.dir(f, M.gun.pitch, M.gun.turn)
	elseif point then dir = rig.shot_dir(origin, point, { x = f.x, y = f.y, z = 0 }) end
	if not dir then return nil end
	local range = (tonumber(info.range) or 30) * (type(ctx) == "table" and tonumber(ctx.range_multiplier) or 1)
	return { { f = { x = f.x, y = f.y, z = f.z }, dir = dir, lift = 1.5 / (range * 1.05) } }
end

-- A launcher that lobs: the muzzle point the game fires from (do_fire: the weapon's root plus
-- ray_source_offset turned by the wielder's attach node) and the flat way of the shot, the flat part
-- of the way M.collect gives it (the weapon's way, or toward the crosshair point). Nil when the
-- weapon has no living wielder.
function M.lob_way(weapon, st, view, point)
	local U, Q, V3A = g("Unit"), g("Quaternion"), g("Vector3Aux")
	local wielder = wielder_of(weapon)
	if not (wielder and U.alive(wielder)) then return nil end
	local node = type(st.attach_node) == "number" and st.attach_node or 0
	local rot = U.world_rotation(wielder, node)
	local f = Q.forward(rot)
	local p = U.world_position(weapon, 0)
	local offset = st.ray_source_offset and V3A.unbox(st.ray_source_offset) or nil
	local muzzle = rig.shot_origin({ x = p.x, y = p.y, z = p.z }, offset, function(o) return Q.rotate(rot, o) end)
	local dir
	if point and M.gun_live(wielder, view, M.frame_now and M.frame_now() or 0) then dir = ergo.dir(f, M.gun.pitch, M.gun.turn)
	elseif point then dir = rig.shot_dir(muzzle, point, { x = f.x, y = f.y, z = 0 }) end
	local h = dir and rig.normalize({ x = dir.x, y = dir.y, z = 0 }) or rig.normalize({ x = f.x, y = f.y, z = 0 })
	if not h then return nil end
	return muzzle, h
end

-- The z_direction a lobbing launcher fires with (the game's for a charged launcher, where the charge
-- sets how far; for a set power, the one that lands on the crosshair point), and the list M.redirect
-- takes: each forward the game may ask for (the wielder's attach node and root) answered with the
-- flat way.
function M.lob_z(weapon, st, settings, view, point)
	local muzzle, h = M.lob_way(weapon, st, view, point)
	if not muzzle then return nil end
	local U, Q = g("Unit"), g("Quaternion")
	local wielder = wielder_of(weapon)
	local list = {}
	for _, node in ipairs({ type(st.attach_node) == "number" and st.attach_node or 0, 0 }) do
		local f = Q.forward(U.world_rotation(wielder, node))
		list[#list + 1] = { f = { x = f.x, y = f.y, z = f.z }, dir = { x = h.x, y = h.y, z = 0 }, unit = weapon }
	end
	if st.fire_on_release then return tonumber(st.z_direction) or 1, list end
	local arc = M.arc or obsidian.module("src/arc")
	return math.tan(arc.lob_aim(st, settings, muzzle, h, point, arc.scale_now())), list
end

-- Whether shots of `wielder` leave along the weapon's way: this player's Helldiver on foot, with a way
-- worked out in the last frames.
function M.gun_live(wielder, view, now)
	return M.ergonomics_on ~= false and not view.vehicle and wielder == view.avatar and M.gun.pitch ~= nil and now - (M.gun.frame or -10) <= 2
end

-- Whether a character state holds the weapon up to shoot (ergo.AIM_STATES).
function M.aim_state(current)
	if current == nil then return false end
	for _, name in ipairs(ergo.AIM_STATES) do
		if g(name) == current then return true end
	end
	return false
end

-- Whether a laser of this player fired within the last few frames.
function M.laser_firing(now)
	return now - (M.gun.laser or -100) <= ergo.LASER_HOLD
end

-- The game's turn keep for this player's Helldiver, while the weapon is up.
function M.turn(ctx, env)
	local st = type(ctx) == "table" and ctx.state
	if M.ergonomics_on == false then return false end
	if type(st) ~= "table" or st.forced_rotation_speed ~= nil or not M.aim_state(st.current_state) then return false end
	local now = env.frame and env.frame() or 0
	st.forced_rotation_speed = ergo.keep(ergo.tau(ergo.ergonomics(M.laser_firing(now))))
	return true
end

-- The game's turn of this player's Helldiver over one frame, measured at each CharacterComponent.update_masters:
-- the heading error to last frame's aim input, last frame and now. The game turns the unit after
-- update_masters (probe 2026-11-21: no change within the call), so a frame apart. Kept as M.game_rate
-- (a second), eased so one odd frame doesn't jump it; only while the weapon is up, where the weapon's
-- turn speeds apply.
M.game_rate = nil
M.last_turn = nil -- { f = facing, t = aim input, dt } of the last frame
function M.measure_turn(ctx, unit, dt)
	local st = type(ctx) == "table" and ctx.state
	local U, Q, V3A = g("Unit"), g("Quaternion"), g("Vector3Aux")
	local f = Q.forward(U.local_rotation(unit, 0))
	local now = { x = f.x, y = f.y }
	local last = M.last_turn
	M.last_turn = nil
	if last then
		local rate = ergo.measured_rate(ergo.flat_angle(last.f, last.t), ergo.flat_angle(now, last.t), last.dt)
		if rate then M.game_rate = M.game_rate and (M.game_rate + (rate - M.game_rate) * 0.5) or rate end
	end
	if type(st) ~= "table" or not M.aim_state(st.current_state) then return end
	local aim = st.input and st.input.aim
	if aim == nil then return end
	local a = V3A.unbox(aim)
	M.last_turn = { f = now, t = { x = a.x, y = a.y }, dt = dt }
end

-- One frame of the weapon's way on foot, after the crosshair point is found: the pitch swings to the
-- crosshair point's while aiming or firing, the heading is the Helldiver's, and the crosshair goes
-- where that way meets something (state.crosshair; state.centre stays the middle of the view).
function M.gun_frame(env, view, cm, dt)
	local state, gun = env.state, M.gun
	local now = env.frame and env.frame() or 0
	if view.vehicle or not view.avatar or not state.aim_point or not view.target_position then
		gun.pitch, gun.dir, gun.origin, gun.cross = nil, nil, nil, 0
		return
	end
	local U, Q = g("Unit"), g("Quaternion")
	local root = view.target_position
	local off = M.shot_offset or M.ORIGIN
	local origin = { x = root.x + off.x, y = root.y + off.y, z = root.z + off.z }
	local f = Q.forward(U.world_rotation(view.avatar, 0))
	-- Aiming or firing raises the weapon; a held throw doesn't (state.firing counts throws too).
	local input = env.camera and env.camera.input
	local raised = (state.aiming or (input and input.fire)) and true or false
	-- Weapon ergonomics off: shots go to the crosshair point and the crosshair stays in the middle, as
	-- before 1.1.0; only the pitch eases, at the pace of the game's own turn (M.measure_turn).
	local on = M.ergonomics_on ~= false
	local tau = on and ergo.tau(ergo.ergonomics(M.laser_firing(now))) or ergo.tau_of_rate(M.game_rate)
	local want = ergo.pitch_to(origin, state.aim_point) or gun.pitch or 0
	gun.pitch = ergo.step_pitch(gun.pitch, want, raised, tau, dt)
	if not on then
		gun.dir, gun.origin, gun.frame, gun.cross = nil, origin, now, 0
		return
	end
	gun.turn = ergo.converge(root, origin, state.aim_point)
	gun.dir = ergo.dir({ x = f.x, y = f.y }, gun.pitch, gun.turn)
	gun.origin, gun.frame = origin, now
	gun.cross = ergo.ease(gun.cross, raised and 1 or 0, ergo.CROSS_TAU, dt)
	if not gun.dir or gun.cross < 0.01 then return end
	local spot = M.cast(view, origin, gun.dir)
	local w, h, x0, y0 = cm.viewport:window()
	local cam = frustum.camera_from(view.position, view.forward, math.rad(view.fov or 70))
	local sx, depth, sy = frustum.project(cam, spot, w, h)
	if depth < 0.1 then sx, sy = frustum.behind(cam, spot, w, h) end
	sx, sy = ergo.inside(sx, sy, w, h)
	local c = state.centre
	local px, py = (x0 or 0) + sx, (y0 or 0) + sy
	state.crosshair = { x = c.x + (px - c.x) * gun.cross, y = c.y + (py - c.y) * gun.cross }
end

-- An Actor.set_velocity that launches the throwable `unit` with the aimed velocity, or nil when the
-- throw isn't this player's (more than 3 m from the Helldiver) or the settings lack the distances.
-- The settings are read at the call, after the Increased throw range part has scaled them.
function M.aimed_setter(unit, context, pending, point)
	local U, V3, Actor = g("Unit"), g("Vector3"), g("Actor")
	local arc = obsidian.module("src/arc")
	if not (point and U.alive(unit) and U.alive(pending.unit)) then return nil end
	local p, me = U.world_position(unit, 0), U.world_position(pending.unit, 0)
	local dx, dy, dz = p.x - me.x, p.y - me.y, p.z - me.z
	if dx * dx + dy * dy + dz * dz > 9 then return nil end
	local set = Actor.set_velocity
	return function(actor, v, ...)
		local settings = type(context) == "table" and context.settings
		local info = type(settings) == "table" and settings.throwable_info
		if type(info) ~= "table" or type(info.throw_distance_min) ~= "number" or type(info.throw_distance_max) ~= "number" then
			return set(actor, v, ...)
		end
		local forward = v and { x = v.x, y = v.y } or nil
		local aimed = arc.aimed({ x = p.x, y = p.y, z = p.z }, point, arc.top_speed(info, pending.multiplier), forward)
		return set(actor, V3(aimed.x, aimed.y, aimed.z), ...)
	end
end

return M
