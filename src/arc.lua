-- Throw arc: while a grenade or a stratagem ball is held in third person, the way it would fly if let
-- go now shows as a dashed line, with a ring where it first touches the ground.
--
-- The flight is the game's own (CharacterComponent.do_throw, ThrowableComponent.command_master "thrown"):
-- from the right hand ("r_hand_attach"), along the Helldiver's forward with z set to 1 (45 degrees up
-- on flat ground), at sqrt(distance * 18) m/s under the gravity of the level (state_game: -18), where
-- distance = throw_distance_min + power * (throw_distance_max - throw_distance_min) of the throwable,
-- and power is the charge, raised up to 1.5 times by running along the throw, times the thrower's
-- throw_range_multiplier (Strong Arm). The Increased throw range part doubles both distances while it
-- runs (src/session.lua).
--
-- The look: short white dashes scrolling along the flight like the map's moving line (Hud.draw_map),
-- drawn as plain bars (Gui.rect_3d, as HdGui.rotated_rect) since the map's dash art carries its own
-- colour, each with a soft drop shadow (the same bar, dark, a little down and right) so it reads on snow
-- and sky as on rock; where it lands, a plain white ring of the mod's own art (src/art.lua), laid flat
-- on the ground in perspective, with the same shadow.
local frustum = obsidian.module("src/frustum")
local art = obsidian.module("src/art")

local M = {}

M.GRAVITY = 18        -- m/s^2, PhysicsWorld.set_gravity in state_game
M.STEP = 1 / 30       -- seconds per piece of the flight
M.MAX_TIME = 4        -- seconds of flight at the most
M.DASH = 9            -- design pixels (1280 x 720), the length of a dash at 6 m
M.DASH_WIDTH = 3.2    -- design pixels, how thick a dash is at 6 m
M.SHADOW = 1.2        -- design pixels the shadow sits down and right, at 6 m (at least 1)
M.DASH_EVERY = 0.6    -- metres between two dashes along the flight
M.SCROLL = 1.2        -- metres a second the dashes move along the flight
M.RING = 0.9          -- metres, radius of the ring on the ground
M.LAYER = 97
M.ALPHA = 235         -- the dashes, out of 255
M.SHADOW_ALPHA = 110  -- the drop shadows, out of 255
M.RING_ALPHA = 235    -- the ring, out of 255
-- The dash art lies along screen x at rotation 0; Gui rotations turn clockwise (see src/edge.lua).
M.DASH_ART = 0
M.THROW_STATES = { "CharacterStateThrow", "CharacterStateStratagemsThrow", "CharacterStateDownedThrow",
	"CharacterStateDownedStratagemsThrow" }
M.PAUSE = 300

local sqrt, atan2, min, max, floor = math.sqrt, math.atan2, math.min, math.max, math.floor

local function g(name) return rawget(_G, name) end

-- Pure parts ----------------------------------------------------------------------------------------

-- The throw power the game gives: charge, raised by running along the throw (do_throw), times the
-- multiplier. velocity and dir are flat {x, y}.
function M.power(charge, velocity, dir, multiplier)
	local p = charge
	local speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
	if speed > 0 then
		-- The game takes the dot with dir as it is, not made unit (z is 1 there, so only the flat part counts).
		local along = (velocity.x * dir.x + velocity.y * dir.y) / speed
		local run = (along + 1) / 2 * speed
		p = p * max(charge, min(run, 1.5))
	end
	return p * (multiplier or 1)
end

-- The launch velocity of a throw: speed sqrt(distance * 18) along dir made unit.
function M.launch(info, power, dir, scale)
	scale = scale or 1
	local dmin, dmax = info.throw_distance_min * scale, info.throw_distance_max * scale
	local distance = max(0, dmin + power * (dmax - dmin))
	local speed = sqrt(distance * M.GRAVITY)
	local l = sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z)
	if l < 1e-6 then return nil end
	return { x = dir.x / l * speed, y = dir.y / l * speed, z = dir.z / l * speed }, distance
end

-- Aimed throws (third person): the throw flies to the crosshair point on a low arc, LOB degrees above
-- the straight line to it (LOB_MIN above level at the least), as fast as that needs, at most the throwable's top speed (its longest throw
-- with the thrower's multiplier). When that arc needs more, the lowest arc the top speed reaches; past
-- the longest throw, 45 degrees at the top speed toward the point.
M.LOB = 15            -- degrees above the line to the point
M.LOB_MIN = 15        -- degrees above level at the least: a throw at the ground nearby lobs, it is not hurled
M.LOB_MAX = 60        -- degrees, the steepest wanted arc

-- The top speed of a throwable: sqrt(18 * the longest throw), the longest throw being
-- throw_distance_min + multiplier * (throw_distance_max - throw_distance_min) times scale.
function M.top_speed(info, multiplier, scale)
	scale = scale or 1
	local dmin, dmax = info.throw_distance_min * scale, info.throw_distance_max * scale
	return sqrt(max(0, dmin + (multiplier or 1) * (dmax - dmin)) * M.GRAVITY)
end

-- The launch velocity that carries a throw from start to target. forward: a flat way to use when the
-- target is right above or below.
function M.aimed(start, target, top, forward)
	local dx, dy = target.x - start.x, target.y - start.y
	local d = sqrt(dx * dx + dy * dy)
	local hx, hy
	if d > 1e-3 then hx, hy = dx / d, dy / d
	else
		local fl = forward and sqrt(forward.x * forward.x + forward.y * forward.y) or 0
		if fl < 1e-6 then return { x = 0, y = 0, z = 0 } end
		hx, hy = forward.x / fl, forward.y / fl
	end
	d = max(d, 0.3)
	local dz = target.z - start.z
	local gr = M.GRAVITY
	local function along(angle, speed)
		local c, s = math.cos(angle), math.sin(angle)
		return { x = hx * c * speed, y = hy * c * speed, z = s * speed }
	end
	local line = atan2(dz, d)
	local angle = min(max(line + math.rad(M.LOB), math.rad(M.LOB_MIN)), math.rad(M.LOB_MAX))
	local rise = d * math.tan(angle) - dz
	if rise > 1e-6 then
		local c = math.cos(angle)
		local speed = sqrt(gr * d * d / (2 * c * c * rise))
		if speed <= top then return along(angle, speed) end
	end
	local v2 = top * top
	local disc = v2 * v2 - gr * (gr * d * d + 2 * dz * v2)
	if disc >= 0 then return along(math.atan((v2 - sqrt(disc)) / (gr * d)), top) end
	return along(math.pi / 4, top)
end

-- The flight from p with velocity v: calls hit(a, b) for each piece, which answers the point where
-- the piece meets the ground or nil. Answers the points of the flight and the landing point (nil when
-- nothing was hit in MAX_TIME). k: damping per second (LOB_DAMPING for a launcher shell), or none.
function M.fly(p, v, hit, k)
	local points = { { x = p.x, y = p.y, z = p.z } }
	local x, y, z = p.x, p.y, p.z
	local vx, vy, vz = v.x, v.y, v.z
	local decay = math.exp(-(k or 0) * M.STEP)
	local t = 0
	while t < M.MAX_TIME do
		local nx, ny = x + vx * M.STEP, y + vy * M.STEP
		local nz = z + vz * M.STEP - M.GRAVITY * M.STEP * M.STEP / 2
		vz = (vz - M.GRAVITY * M.STEP) * decay
		vx, vy = vx * decay, vy * decay
		local at = hit({ x = x, y = y, z = z }, { x = nx, y = ny, z = nz })
		if at then
			points[#points + 1] = at
			return points, at
		end
		x, y, z = nx, ny, nz
		points[#points + 1] = { x = x, y = y, z = z }
		t = t + M.STEP
	end
	return points, nil
end

-- Launchers that lob a shell (the Rumbler, the Obliterator) ------------------------------------------
--
-- LauncherComponent.do_fire spawns the shell, a throwable, 1 m up and 1 m out along the flat way from
-- the muzzle point (the weapon's root plus ray_source_offset turned by the wielder's attach node), and
-- ThrowableComponent "thrown" launches it along (flat way, z_direction) made unit, at
-- sqrt(18 * distance), distance = throw_distance_min + power * (throw_distance_max - throw_distance_min)
-- of the shell (doubled while the Increased throw range part runs). power is the weapon's; a charged
-- launcher (fire_on_release: the Rumbler) adds charge_max_extra_power times the share of
-- max_charge_time held, fires only once min_charge_time has passed, and lets burst_rounds shells go,
-- each burst_round_power_decrease weaker than the one before. The Obliterator fires at a set power, so
-- third person picks the angle that lands it on the crosshair point; the Rumbler keeps the game's
-- angle and the charge sets how far.
M.LOB_UP, M.LOB_DOWN = math.rad(75), math.rad(-60) -- the steepest angles a set-power shot takes
M.scale_now = function() return 1 end -- set by M.start
M.LINE_PIECE = 0.3    -- metres, the longest straight piece of a blast circle
-- 1/s: a launcher shell slows in flight, every part of the velocity by e^(-k t) (fitted to 8 Rumbler
-- and Obliterator landings in game, 0.15 m rms; without it they came down up to 10 percent short).
M.LOB_DAMPING = 0.083
-- A set-power shell (the Obliterator) lands at least this far past the blast radius from the muzzle:
-- a crosshair point closer than that is pushed out along the way, so the blast misses the Helldiver.
M.LOB_CLEAR = 1.5

local lob_cache = {}

-- The settings of the shell a launcher state fires, when it lobs one (a throwable), or nil.
function M.lob_settings(st)
	if type(st) ~= "table" or type(st.projectile) ~= "string" then return nil end
	local cached = lob_cache[st.projectile]
	if cached ~= nil then return cached or nil end
	local LSM = g("LuaSettingsManager")
	if not LSM then return nil end
	local ok, s = pcall(LSM.get_settings_by_unit_path, LSM, st.projectile)
	if not ok then return nil end
	local info = type(s) == "table" and s.throwable_info
	local lobs = type(info) == "table" and type(info.throw_distance_min) == "number" and type(info.throw_distance_max) == "number"
	lob_cache[st.projectile] = lobs and s or false
	return lobs and s or nil
end

-- How far a charged launcher has charged, 0 to 1.
function M.lob_charge(st)
	local most = tonumber(st.max_charge_time) or 0
	if most <= 0 then return 0 end
	return min(max((tonumber(st.shot_charge_timer) or 0) / most, 0), 1)
end

-- The power of shell `round` (1 first) of a shot let go now. A charge short of min_charge_time counts
-- as min_charge_time: that is the weakest shot that goes. Each shell of a burst takes the power of the
-- one before less (round - 1) decreases, as calculate_charge_power keeps its answer as the next start
-- (seen in game: 2.1, 1.9, 1.5).
function M.lob_power(st, round)
	local p = tonumber(st.power) or 1
	if st.fire_on_release then
		local most = tonumber(st.max_charge_time) or 1
		local held = max(tonumber(st.shot_charge_timer) or 0, tonumber(st.min_charge_time) or 0)
		p = p + (tonumber(st.charge_max_extra_power) or 0) * min(held, most) / max(most, 1e-6)
		local k = (round or 1) - 1
		p = p - k * (k + 1) / 2 * (tonumber(st.burst_round_power_decrease) or 0)
	end
	return p
end

-- The launch speed of a shell of `power`.
function M.lob_speed(info, power, scale)
	scale = scale or 1
	local dmin, dmax = info.throw_distance_min * scale, info.throw_distance_max * scale
	return sqrt(max(0, dmin + power * (dmax - dmin)) * M.GRAVITY)
end

-- Where the shell starts: 1 m up and 1 m out along the flat way h from the muzzle point.
function M.lob_start(muzzle, h)
	return { x = muzzle.x + h.x, y = muzzle.y + h.y, z = muzzle.z + 1 }
end

-- The launch velocity along the flat way h, `angle` above level.
function M.lob_velocity(h, angle, speed)
	local c, s = math.cos(angle), math.sin(angle)
	return { x = h.x * c * speed, y = h.y * c * speed, z = s * speed }
end

-- The flat distance at which a shell from start, `angle` above level at `speed`, comes down through
-- the height z, flying as M.fly flies it with damping k; nil when it never does in MAX_TIME.
function M.lob_reach(start, angle, speed, z, k)
	local x, h = 0, start.z
	local vx, vz = math.cos(angle) * speed, math.sin(angle) * speed
	local decay = math.exp(-(k or 0) * M.STEP)
	local t = 0
	while t < M.MAX_TIME do
		local nx, nh = x + vx * M.STEP, h + vz * M.STEP - M.GRAVITY * M.STEP * M.STEP / 2
		vz = (vz - M.GRAVITY * M.STEP) * decay
		vx = vx * decay
		if h > z and nh <= z then return x + (nx - x) * (h - z) / (h - nh) end
		x, h, t = nx, nh, t + M.STEP
	end
	return nil
end

-- The low angle above level that carries a shell at `speed` from start to target, damped as a shell
-- flies (LOB_DAMPING); past reach, the angle that reaches farthest. Kept between LOB_DOWN and LOB_UP.
function M.lob_angle(start, target, speed)
	local dx, dy = target.x - start.x, target.y - start.y
	local d = max(sqrt(dx * dx + dy * dy), 0.3)
	local k = M.LOB_DAMPING
	local far_angle, far = math.pi / 4, -1
	for a = M.LOB_DOWN, M.LOB_UP, math.rad(2.5) do
		local r = M.lob_reach(start, a, speed, target.z, k)
		if r and r > far then far_angle, far = a, r end
	end
	if far < d then return far_angle end
	-- Below the farthest angle the reach grows with the angle; too low never comes down at the height.
	local lo, hi = M.LOB_DOWN, far_angle
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		local r = M.lob_reach(start, mid, speed, target.z, k)
		if r == nil or r < d then lo = mid else hi = mid end
	end
	return hi
end

-- The blast radius of a shell's settings.
function M.blast(settings)
	local e = type(settings) == "table" and settings.explosive_info
	return type(e) == "table" and tonumber(e.blast_radius) or M.RING
end

-- The angle a shot of this launcher leaves at: the game's (atan of z_direction over a flat way of
-- length 1) for a charged launcher or with no target, else the one that reaches the target, pushed
-- out along h to LOB_CLEAR past the blast radius from the muzzle when closer.
function M.lob_aim(st, settings, muzzle, h, target, scale)
	if st.fire_on_release or not target then return math.atan(tonumber(st.z_direction) or 1) end
	local least = M.blast(settings) + M.LOB_CLEAR
	local along = (target.x - muzzle.x) * h.x + (target.y - muzzle.y) * h.y
	if along < least then
		target = { x = muzzle.x + h.x * least, y = muzzle.y + h.y * least, z = target.z }
	end
	return M.lob_angle(M.lob_start(muzzle, h), target, M.lob_speed(settings.throwable_info, M.lob_power(st, 1), scale))
end

-- The shells of one shot let go now: for each, the start and the launch velocity.
function M.lob_shells(st, settings, muzzle, h, target, scale)
	local info = settings.throwable_info
	local angle = M.lob_aim(st, settings, muzzle, h, target, scale)
	local start = M.lob_start(muzzle, h)
	local n = st.fire_on_release and max(1, floor(tonumber(st.burst_rounds) or 1)) or 1
	local list = {}
	for round = 1, n do
		list[round] = { start = start, v = M.lob_velocity(h, angle, M.lob_speed(info, M.lob_power(st, round), scale)) }
	end
	return list
end

-- Points every `every` metres along the polyline, starting `offset` metres in.
function M.along(points, every, offset)
	local out = {}
	local want = offset % every
	local walked = 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local len = sqrt(dx * dx + dy * dy + dz * dz)
		while len > 0 and want <= walked + len do
			local s = (want - walked) / len
			out[#out + 1] = { x = a.x + dx * s, y = a.y + dy * s, z = a.z + dz * s, dx = dx / len, dy = dy / len, dz = dz / len }
			want = want + every
		end
		walked = walked + len
	end
	return out
end

-- Game parts ----------------------------------------------------------------------------------------

M.held = nil   -- { unit, ctx, frame } of the local Helldiver's throw this frame
M.scroll = 0

-- The throw as it would go now, or nil: the start point, the launch velocity and the throwable info.
-- target: the crosshair point, for an aimed throw (src/aim.lua sets the same velocity on release).
function M.throw_now(unit, ctx, scale, target)
	local U, EA, Q, V3A, LSM = g("Unit"), g("EntityAux"), g("Quaternion"), g("Vector3Aux"), g("LuaSettingsManager")
	local st = type(ctx) == "table" and ctx.state
	if not (st and U.alive(unit)) or st.has_thrown then return nil end
	local inv = EA.state(unit, "inventory")
	local held = inv and inv.held_grenade
	if held == nil or not U.alive(held) or not LSM then return nil end
	local settings = LSM:get_settings_by_unit(held)
	local info = settings and settings.throwable_info
	if not (info and info.throw_distance_min and info.throw_distance_max) then return nil end
	local dir
	if st.last_downed_throw_aim and st.health_state and st.health_state.is_downed then
		local a = V3A.unbox(st.last_downed_throw_aim)
		dir = { x = a.x, y = a.y, z = a.z }
	else
		local f = Q.forward(U.world_rotation(unit, 0))
		dir = { x = f.x, y = f.y, z = 1 }
	end
	local vel = { x = 0, y = 0 }
	if st.mover_state and st.mover_state.velocity then
		local mv = V3A.unbox(st.mover_state.velocity)
		vel = { x = mv.x, y = mv.y }
	end
	local node = U.has_node and U.has_node(unit, "r_hand_attach") and U.node(unit, "r_hand_attach") or 0
	local p = U.world_position(unit, node)
	local start = { x = p.x, y = p.y, z = p.z }
	if target then
		return start, M.aimed(start, target, M.top_speed(info, st.throw_range_multiplier, scale), dir)
	end
	local power = M.power(st.grenade_charge or 0, vel, dir, st.throw_range_multiplier)
	local v = M.launch(info, power, dir, scale)
	if not v then return nil end
	return start, v
end

-- Where a piece of the flight meets the rocks and the ground.
local function ground_hit(pw)
	local PW, V3 = g("PhysicsWorld"), g("Vector3")
	return function(a, b)
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local len = sqrt(dx * dx + dy * dy + dz * dz)
		if len < 1e-6 then return nil end
		local hit, pos = PW.immediate_raycast(pw, V3(a.x, a.y, a.z), V3(dx / len, dy / len, dz / len), len,
			"closest", "types", "statics", "collision_filter", "default")
		if hit and pos then return { x = pos.x, y = pos.y, z = pos.z } end
		return nil
	end
end

-- After a throw the last arc stays where it was, its dashes still, and fades out over FREEZE seconds.
-- A charged launcher's arc (the Rumbler) stays over LOB_FREEZE, about as long as the longest burst
-- flies: on release the game sets the charge back to nothing, so a live arc would shrink to the
-- shortest shot while the shells are still on the way.
M.FREEZE = 1
M.LOB_FREEZE = 2.5
M.frame = 0    -- frames counted by M.start
M.shown = nil  -- { points, land, rings, scroll, frame } of the arc drawn last
M.frozen = nil -- { points, land, rings, scroll, t, span, lob } of a throw or a burst, fading

-- How strong a frozen arc shows `t` seconds after the throw, 1 to 0, fading over `span` seconds.
function M.freeze_alpha(t, span)
	span = span or M.FREEZE
	if t >= span then return 0 end
	return 1 - math.max(0, t) / span
end

-- The throw went: the arc shown last freezes, when it was drawn within the last few frames.
function M.thrown(frame)
	local s = M.shown
	if s and frame - s.frame <= 3 then
		M.frozen = { points = s.points, land = s.land, rings = s.rings, scroll = s.scroll, t = 0, span = s.span, lob = s.lob }
	end
	M.shown = nil
end

-- The first shell of a charged launcher's burst went (src/aim.lua): its arc freezes the same way.
function M.lob_fired()
	if M.shown and M.shown.lob then M.thrown(M.frame) end
end

-- The launcher in this player's hands, when it lobs shells and is held up to fire (aimed, or a charge
-- building): its state, the shell's settings and the weapon unit. Nil while reloading or empty.
function M.lob_held(env)
	local view, api = env.view, env.api
	local avatar = view and view.avatar
	if not avatar or view.vehicle or not (api and api.game and api.game.master) then return nil end
	local inv = g("EntityAux").state(avatar, "inventory")
	local weapon = inv and inv.current_weapon
	local st = weapon and api.game.master(weapon, "launcher")
	if type(st) ~= "table" or st.is_reloading then return nil end
	if not (env.state.aiming or st.charging_shot) then return nil end
	-- A burst on the way, or its arc still fading: no live arc over it.
	if st.burst_timer or (M.frozen and M.frozen.lob) then return nil end
	if not (st.infinite_ammo or (tonumber(st.rounds) or 0) > 0) then return nil end
	local settings = M.lob_settings(st)
	if not settings then return nil end
	return st, settings, weapon
end

function M.draw(hud, env, scale, dt, frame)
	local held = M.held
	local gui = hud.hd_gui
	local view = env.view
	local cm = g("CameraManager")
	if not (gui and view and view.world and cm and cm.viewport) then return end
	local frozen = M.frozen
	if frozen then
		frozen.t = frozen.t + (dt or 0)
		local a = M.freeze_alpha(frozen.t, frozen.span)
		if a <= 0 then M.frozen = nil else M.render(gui, view, cm, frozen.points, frozen.land, frozen.scroll, a, frozen.rings) end
	end
	local pw = g("World").physics_world(view.world)
	if not held then
		local st, settings, weapon = M.lob_held(env)
		if not st then return end
		local muzzle, h = M.aim.lob_way(weapon, st, view, env.state.aim_point)
		if not muzzle then return end
		local shells = M.lob_shells(st, settings, muzzle, h, env.state.aim_point, scale)
		local blast = M.blast(settings)
		local points, rings = nil, {}
		for i, shell in ipairs(shells) do
			local flight, land = M.fly(shell.start, shell.v, ground_hit(pw), M.LOB_DAMPING)
			if i == 1 then points = flight end
			if land then rings[#rings + 1] = { at = land, radius = blast, line = true } end
		end
		M.scroll = (M.scroll + (dt or 0) * M.SCROLL) % M.DASH_EVERY
		M.shown = st.fire_on_release and { points = points, rings = rings, scroll = M.scroll, frame = frame or 0,
			span = M.LOB_FREEZE, lob = true } or nil
		M.render(gui, view, cm, points, nil, M.scroll, 1, rings)
		return
	end
	local start, v = M.throw_now(held.unit, held.ctx, scale, env.state.aim_point)
	if not start then return end
	local points, land = M.fly(start, v, ground_hit(pw))
	M.scroll = (M.scroll + (dt or 0) * M.SCROLL) % M.DASH_EVERY
	M.shown = { points = points, land = land, scroll = M.scroll, frame = frame or 0 }
	M.render(gui, view, cm, points, land, M.scroll, 1)
end

-- Draws a flight's dashes from `scroll` metres in and its landing ring, `fade` (0 to 1) strong.
-- rings: { at, radius } to draw instead of the one ring at `land` (a launcher's blasts).
function M.render(gui, view, cm, points, land, scroll, fade, rings)
	local w, h = cm.viewport:window()
	local cam = frustum.camera_from(view.position, view.forward, math.rad(view.fov or 70))
	local V2, V3, C, G, R2D = g("Vector2"), g("Vector3"), g("Color"), g("Gui"), g("Rotation2D")
	local s = gui.ui_scale or h / 720
	fade = fade or 1
	gui:set_ignore_position_scale(true)
	gui:set_ignore_size_scale(true)
	local colour = C(floor(M.ALPHA * fade + 0.5), 255, 255, 255)
	local dark = C(floor(M.SHADOW_ALPHA * fade + 0.5), 0, 0, 0)
	local sh = max(M.SHADOW * s, 1)
	local function screen(p)
		local sx, depth, sy = frustum.project(cam, p, w, h)
		if depth <= 0.3 then return nil end
		return sx, sy, depth
	end
	-- A dash from screen (x, y) toward (x2, y2), centred on (x, y), `depth` metres away: the shadow,
	-- then the white bar. Dashes shrink with distance, as if lying in the air, from the map's size at
	-- 6 m. A plain bar turned about its middle, as HdGui.rotated_image turns an image
	-- (Gui.bitmap_3d_uv), through Gui.rect_3d as HdGui.rotated_rect does. y grows up the screen here,
	-- so down is minus. most: the longest the dash may be, in pixels.
	local function dash(x, y, x2, y2, depth, exact)
		local k = s * min(1.5, max(0.35, 6 / depth))
		local len, wid = M.DASH * k, M.DASH_WIDTH * k
		if exact then len = exact end
		local a = -(atan2(y2 - y, x2 - x) - M.DASH_ART)
		local function bar(cx, cy, z, c)
			local at = V3(cx - len / 2, cy - wid / 2, 0)
			G.rect_3d(gui.gui, R2D(at, a, at + V2(len / 2, wid / 2)), V3(0, 0, 0), z, V2(len, wid), c)
		end
		bar(x + sh, y - sh, M.LAYER - 1, dark)
		bar(x, y, M.LAYER, colour)
	end
	for _, d in ipairs(M.along(points or {}, M.DASH_EVERY, scroll)) do
		local x, y, depth = screen(d)
		if x then
			local x2, y2 = screen({ x = d.x + d.dx * 0.1, y = d.y + d.dy * 0.1, z = d.z + d.dz * 0.1 })
			if x2 then dash(x, y, x2, y2, depth) end
		end
	end
	rings = rings or (land and { { at = land, radius = M.RING } }) or {}
	local fl = sqrt(cam.forward.x * cam.forward.x + cam.forward.y * cam.forward.y)
	local fx, fy = fl > 1e-6 and cam.forward.x / fl or 0, fl > 1e-6 and cam.forward.y / fl or 1
	for _, ring in ipairs(rings) do
		local at, r = ring.at, ring.radius
		if ring.line then
			-- A blast: a solid circle flat on the ground, made of short straight pieces as thick as the
			-- dashes of the flight, so the line keeps that weight at any size.
			local n = max(24, math.ceil(2 * math.pi * r / M.LINE_PIECE))
			local px, py = screen({ x = at.x + r, y = at.y, z = at.z })
			for i = 1, n do
				local t = 2 * math.pi * i / n
				local x1, y1, depth = screen({ x = at.x + math.cos(t) * r, y = at.y + math.sin(t) * r, z = at.z })
				if px and x1 then
					-- A little longer than the piece, so the joins leave no gap.
					local len = sqrt((x1 - px) ^ 2 + (y1 - py) ^ 2) + M.DASH_WIDTH * s * 0.5
					dash((px + x1) / 2, (py + y1) / 2, x1, y1, depth, len)
				end
				px, py = x1, y1
			end
		end
		-- The ring, flat on the ground: as wide as its radius across the view, as tall as along it.
		local cx, cy = screen(at)
		local rx = screen({ x = at.x + cam.right.x * r, y = at.y + cam.right.y * r, z = at.z })
		local _, ty = screen({ x = at.x + fx * r, y = at.y + fy * r, z = at.z })
		local _, by = screen({ x = at.x - fx * r, y = at.y - fy * r, z = at.z })
		if not ring.line and cx and rx and ty and by then
			local rw = math.abs(rx - cx) * 2
			local rh = math.max(math.abs(ty - by), 2)
			local ring_gui = art.gui()
			if ring_gui then
				art.draw(ring_gui, "eol_ring", cx - rw / 2 + sh, cy - rh / 2 - sh, rw, rh, M.LAYER - 1, floor(M.SHADOW_ALPHA * fade + 0.5), 0, 0, 0)
				art.draw(ring_gui, "eol_ring", cx - rw / 2, cy - rh / 2, rw, rh, M.LAYER, floor(M.RING_ALPHA * fade + 0.5), 255, 255, 255)
			end
		end
	end
	gui:set_ignore_position_scale(false)
	gui:set_ignore_size_scale(false)
end

function M.start(env)
	local on = env.config.get("throw_arc") ~= false
	env.config.on_change("throw_arc", function(v) on = v ~= false end)
	local camera = obsidian.module("src/camera")
	local frame = 0
	-- The Increased throw range part runs this only while the lobby allows it.
	local scaled_frame = -10
	obsidian.on_frame(function() scaled_frame = frame end, env.part("throw_range"))
	obsidian.on_frame(function() frame = frame + 1 M.frame = frame end, env.VIEW)
	for _, class in ipairs(M.THROW_STATES) do
		obsidian.hook(class, "update", function(original, unit, ctx, ...)
			local r = { original(unit, ctx, ...) }
			if camera.input and unit == camera.input.unit then M.held = { unit = unit, ctx = ctx, frame = frame } end
			return unpack(r)
		end, env.VIEW)
	end
	-- The throw of this player's Helldiver: the arc shown freezes and fades.
	obsidian.hook("CharacterComponent", "do_throw", function(original, self, unit, ...)
		if on and camera.input and unit == camera.input.unit then pcall(M.thrown, frame) end
		return original(self, unit, ...)
	end, env.VIEW)
	table.insert(env.on_release, function() M.frozen, M.shown = nil, nil end)
	-- How far throws and lobbed shells fly now: THROW_SCALE while the Increased throw range part runs.
	-- Modules are found here, at start: obsidian.module answers for the mod running at the call.
	local session = obsidian.module("src/session")
	M.aim = obsidian.module("src/aim")
	M.scale_now = function()
		if frame - scaled_frame <= 2 and env.config.get("throw_range") ~= false then return session.THROW_SCALE end
		return 1
	end
	local warned, wait = false, 0
	obsidian.hook("Hud", "draw_plugins", function(original, self, dt, ...)
		local r = { original(self, dt, ...) }
		local held = M.held
		if held and frame - held.frame > 2 then M.held, held = nil, nil end
		if wait > 0 then
			wait = wait - 1
		elseif on and env.state.active and not env.state.watching and not env.state.vehicle then
			local ok, err = pcall(M.draw, self, env, M.scale_now(), type(dt) == "number" and dt or 1 / 60, frame)
			if not ok then
				wait = M.PAUSE
				pcall(self.hd_gui.set_ignore_position_scale, self.hd_gui, false)
				pcall(self.hd_gui.set_ignore_size_scale, self.hd_gui, false)
				if not warned then
					warned = true
					env.log("Eyes of Liberty: throw arc: " .. tostring(err))
				end
			end
		end
		return unpack(r)
	end, env.VIEW)
end

return M
