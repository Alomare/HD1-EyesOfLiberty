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
-- colour, each over a dark bar a little bigger so it reads on snow and sky as on rock; where it lands, a
-- white ball of the mod's own art (src/art.lua, "eol_ball": shaded, dark rim) resting on the ground,
-- sized as a ball of BALL metres would look there, never smaller than BALL_MIN pixels.
local frustum = obsidian.module("src/frustum")
local art = obsidian.module("src/art")

local M = {}

M.GRAVITY = 18        -- m/s^2, PhysicsWorld.set_gravity in state_game
M.STEP = 1 / 30       -- seconds per piece of the flight
M.MAX_TIME = 4        -- seconds of flight at the most
M.DASH = 9            -- design pixels (1280 x 720), the length of a dash at 6 m
M.DASH_WIDTH = 3.2    -- design pixels, how thick a dash is at 6 m
M.OUTLINE = 1         -- design pixels of dark around each dash, at 6 m
M.DASH_EVERY = 0.6    -- metres between two dashes along the flight
M.SCROLL = 1.2        -- metres a second the dashes move along the flight
M.BALL = 0.35         -- metres, radius of the ball where the throw lands
M.BALL_MIN = 7        -- design pixels, the smallest radius the ball is drawn at
M.LAYER = 97
M.ALPHA = 235         -- the dashes, out of 255
M.OUTLINE_ALPHA = 150 -- the dark around them, out of 255
M.BALL_ALPHA = 245    -- the ball, out of 255
-- The dash art lies along screen x at rotation 0; Gui rotations turn clockwise (see src/edge.lua).
M.DASH_ART = 0
M.THROW_STATES = { "CharacterStateThrow", "CharacterStateStratagemsThrow", "CharacterStateDownedThrow",
	"CharacterStateDownedStratagemsThrow" }
M.PAUSE = 300

local sqrt, atan2, min, max = math.sqrt, math.atan2, math.min, math.max

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
-- nothing was hit in MAX_TIME).
function M.fly(p, v, hit)
	local points = { { x = p.x, y = p.y, z = p.z } }
	local x, y, z = p.x, p.y, p.z
	local vz = v.z
	local t = 0
	while t < M.MAX_TIME do
		local nx, ny = x + v.x * M.STEP, y + v.y * M.STEP
		local nz = z + vz * M.STEP - M.GRAVITY * M.STEP * M.STEP / 2
		vz = vz - M.GRAVITY * M.STEP
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

function M.draw(hud, env, scale, dt)
	local held = M.held
	local gui = hud.hd_gui
	local view = env.view
	local cm = g("CameraManager")
	if not (held and gui and view and view.world and cm and cm.viewport) then return end
	local start, v = M.throw_now(held.unit, held.ctx, scale, env.state.aim_point)
	if not start then return end
	local pw = g("World").physics_world(view.world)
	local points, land = M.fly(start, v, ground_hit(pw))
	local w, h = cm.viewport:window()
	local cam = frustum.camera_from(view.position, view.forward, math.rad(view.fov or 70))
	local V2, V3, C, G, R2D = g("Vector2"), g("Vector3"), g("Color"), g("Gui"), g("Rotation2D")
	local s = gui.ui_scale or h / 720
	M.scroll = (M.scroll + (dt or 0) * M.SCROLL) % M.DASH_EVERY
	gui:set_ignore_position_scale(true)
	gui:set_ignore_size_scale(true)
	local colour = C(M.ALPHA, 255, 255, 255)
	local dark = C(M.OUTLINE_ALPHA, 0, 0, 0)
	local function screen(p)
		local sx, depth, sy = frustum.project(cam, p, w, h)
		if depth <= 0.3 then return nil end
		return sx, sy, depth
	end
	for _, d in ipairs(M.along(points, M.DASH_EVERY, M.scroll)) do
		local x, y, depth = screen(d)
		if x then
			local x2, y2 = screen({ x = d.x + d.dx * 0.1, y = d.y + d.dy * 0.1, z = d.z + d.dz * 0.1 })
			if x2 then
				-- Dashes shrink with distance, as if lying in the air, from the map's size at 6 m.
				local k = s * min(1.5, max(0.35, 6 / depth))
				local len, wid, o = M.DASH * k, M.DASH_WIDTH * k, M.OUTLINE * k
				local a = -(atan2(y2 - y, x2 - x) - M.DASH_ART)
				-- A plain bar turned about its middle, as HdGui.rotated_image turns an image
				-- (Gui.bitmap_3d_uv), through Gui.rect_3d as HdGui.rotated_rect does: dark, then white.
				local function bar(l, wd, z, c)
					local at = V3(x - l / 2, y - wd / 2, 0)
					G.rect_3d(gui.gui, R2D(at, a, at + V2(l / 2, wd / 2)), V3(0, 0, 0), z, V2(l, wd), c)
				end
				bar(len + 2 * o, wid + 2 * o, M.LAYER - 1, dark)
				bar(len, wid, M.LAYER, colour)
			end
		end
	end
	if land then
		-- The ball, resting on the ground where the throw first lands.
		local centre = { x = land.x, y = land.y, z = land.z + M.BALL }
		local cx, cy = screen(centre)
		local rx = screen({ x = centre.x + cam.right.x * M.BALL, y = centre.y + cam.right.y * M.BALL, z = centre.z })
		if cx and rx then
			local r = max(math.abs(rx - cx), M.BALL_MIN * s)
			local ball_gui = art.gui()
			if ball_gui then art.draw(ball_gui, "eol_ball", cx - r, cy - r, 2 * r, 2 * r, M.LAYER, M.BALL_ALPHA, 255, 255, 255) end
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
	obsidian.on_frame(function() frame = frame + 1 end, env.VIEW)
	for _, class in ipairs(M.THROW_STATES) do
		obsidian.hook(class, "update", function(original, unit, ctx, ...)
			local r = { original(unit, ctx, ...) }
			if camera.input and unit == camera.input.unit then M.held = { unit = unit, ctx = ctx, frame = frame } end
			return unpack(r)
		end, env.VIEW)
	end
	local warned, wait = false, 0
	obsidian.hook("Hud", "draw_plugins", function(original, self, dt, ...)
		local r = { original(self, dt, ...) }
		local held = M.held
		if held and frame - held.frame > 2 then M.held, held = nil, nil end
		if wait > 0 then
			wait = wait - 1
		elseif on and held and env.state.active and not env.state.watching then
			local scale = 1
			if frame - scaled_frame <= 2 and env.config.get("throw_range") ~= false then
				scale = obsidian.module("src/session").THROW_SCALE
			end
			local ok, err = pcall(M.draw, self, env, scale, type(dt) == "number" and dt or 1 / 60)
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
