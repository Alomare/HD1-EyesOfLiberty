-- The over-the-shoulder camera, on foot, in vehicles and on the ship.
--
-- The game's CameraManager.update runs as usual and keeps the top-down pose (src/frustum.lua answers
-- the game's rules from it). After it, this module puts the drawn camera at the shoulder: the same
-- engine calls the game's update ends with (Camera.set_local_position and set_local_rotation, the field of
-- view, World.update_unit, the grass observer and the sound listener).
--
-- While the shoulder camera draws, the game's update still works out the top-down pose but never hands
-- it to the engine: Camera.set_local_position and set_local_rotation do nothing while it runs, so each
-- frame places the drawn camera once. With both poses written every frame, the first run in the game
-- (2026-11-11) flickered between the top-down and the shoulder view. The free camera of Obsidian API
-- and Third Person Camera both write one pose a frame.
--
-- Movement follows the view: the game turns the movement keys and the left stick by
-- CameraManager.follow_spin, the top-down camera's. CameraManager.follow_spin itself stays as the game
-- has it, because Obsidian API's bots (and the game's leash) turn their own movement by it in the same
-- update; only the local player's movement commands are turned on by the difference to the view's yaw.
local rig = obsidian.module("src/rig")
local scoped = obsidian.module("src/scoped")
local frustum = obsidian.module("src/frustum")
local pod = obsidian.module("src/pod")
local shake = obsidian.module("src/shake")
local deathcam = obsidian.module("src/deathcam")
local kick = obsidian.module("src/kick")
local cursor = obsidian.module("src/cursor")

local M = {}

local function g(name) return rawget(_G, name) end

-- What stops the view, by reason, for tests and the log. Each is a function of (cm).
M.enabled = true      -- false in the top-down mode
-- The camera mode: "default" (the game's top-down camera) or "third". The toggle key switches them;
-- the mode set with the key is kept until the Camera mode option changes.
M.MODES = { "default", "third" }
M.MODE_TEXT = { default = "Top-down camera", third = "Third person" }
M.mode = "third"
M.dt = 0.016
M.view = { yaw = nil, pitch = 0, side = 1 }
-- The vehicle the camera follows and where it sits there: side -1 left, 0 middle, 1 right. The place
-- picked with the swap key is kept for each vehicle kind until the game closes.
M.ride = { target = nil, kind = nil, side = 0 }
M.vehicle_sides = {}
-- The Hellpod ride under way (src/pod.lua), with the avatar it is for.
M.drop = nil
-- How much of the game's own shake reaches the shoulder view: the game sizes them for a camera 20 m
-- and more away.
M.GAME_SHAKE = 0.5
-- The shake of the pod landing: metres, a second, seconds.
M.LAND_SHAKE = { 0.35, 9, 0.8 }

-- The pod lands now: the landing shake, once.
function M.pod_landed()
	if M.drop and pod.land(M.drop) then shake.add(M.LAND_SHAKE[1], M.LAND_SHAKE[2], M.LAND_SHAKE[3]) end
end
M.TAP = 0.35          -- seconds: a right stick click shorter than this swaps the shoulder
M.stick_held = nil    -- seconds the right stick has been held down, nil when up
M.input = nil         -- the local player's input this frame (from InputComponent.update_masters)
M.frame = 0
M.warned = {}
M.dropped = 0         -- lines logged when the view went back to top-down, at most 20 a launch
M.last_why = nil      -- why the view stayed top-down last frame, nil while the shoulder camera ran
M.SHARED_TEXT = "Third person is off: players on one computer share the screen, so the top-down camera stays. It comes back when one player is left."
M.BACK_TEXT = "One player on this computer: third person is back."

local smooth = { pivot = nil, length = nil, aim = 0, target = nil, side = nil, dive = 0, down = 0, sprint = 0 }
local saved_near = nil

-- The local player's master of InputComponent: the avatar, the context of that master, and whether another local
-- player (a second pad) shares the screen.
function M.local_master(masters, api)
	if type(masters) ~= "table" then return nil end
	local main = api and api.game and api.game.my_unit and api.game.my_unit() or nil
	local kbm = rawget(_G, "KEYBOARD_MOUSE_PAD_NUMBER")
	local settings = g("GameSettings")
	local main_pad = settings and settings.get_main_pad_number and settings.get_main_pad_number()
	local found, ctx, others = nil, nil, {}
	for unit, c in pairs(masters) do
		local st = type(c) == "table" and c.state
		if st and st.pad_number ~= nil then
			local mine = unit == main or (not main and (st.pad_number == main_pad or st.pad_number == kbm))
			if mine and not found then found, ctx = unit, c else others[#others + 1] = unit end
		end
	end
	-- Obsidian API's bots drive input masters of this machine too, with pads of their own: they don't
	-- share the screen the way a second player does.
	if #others > 0 then
		local bots = api and api.bots and api.bots.all
		local ok, list = pcall(function() return bots and bots() or {} end)
		local bot = {}
		for _, b in ipairs(ok and list or {}) do
			local got, u = pcall(b.unit, b)
			if got and u then bot[u] = true end
		end
		local people = 0
		for _, u in ipairs(others) do if not bot[u] then people = people + 1 end end
		return found, ctx, people > 0
	end
	return found, ctx, false
end

-- Reads what the local player asks of the view this frame, from the input the game is about to use.
-- While a Hellpod ride is under way and the game reads no input for its Helldiver, a still snapshot for
-- that Helldiver stands in: nothing pressed, no look.
function M.riding_input()
	local drop = M.drop
	if not (drop and drop.avatar) then return end
	local input = M.input
	if input and input.unit == drop.avatar and M.frame - input.frame <= 30 then return end
	local U = g("Unit")
	local ok, alive = pcall(U.alive, drop.avatar)
	if not (ok and alive) then return end
	M.input = { frame = M.frame, unit = drop.avatar, kbm = input and input.kbm, look = false, fire = false,
		throw = false, aiming = false, stick = nil, shared = false, dt = input and input.dt, riding = true }
end

-- Whether a Helldiver entering the drop cutscene is this player's. The game enters it as it makes the
-- body (CharacterComponent's master setup), before Obsidian API knows the new unit as this player's:
-- a body of this machine counts when it's the known avatar, or when this player has no living one (a
-- dead body left on the ground doesn't count as living). pad: the pad of the body's input master
-- (the context's input_state), when known: an Obsidian API bot's body has a pad of its own, neither
-- the main pad nor the keyboard's, and is never this player's (before, a bot dropping first took the
-- Hellpod camera). own_pads: { [pad] = true } for this player's.
function M.drop_is_mine(unit, mine, current, pad, own_pads)
	if unit == nil then return false end
	if mine ~= nil and unit == mine then return true end
	if pad ~= nil and own_pads and not own_pads[pad] then return false end
	for _, u in ipairs({ mine, current }) do
		if u ~= nil and deathcam.living(u) then return false end
	end
	return true
end

-- Whether Windows has the game's window in front. A game started while another window was in front
-- can answer true to Window.has_focus until it is switched to and away twice, and the view would hold
-- the mouse in the middle of the screen over the other window. Asked of Windows itself through LuaJIT's
-- FFI (GetForegroundWindow, its process against this one); true when FFI can't tell.
local foreground_fn = nil
function M.os_foreground()
	if foreground_fn == nil then
		foreground_fn = false
		pcall(function()
			local ok, ffi = pcall(require, "ffi")
			if not (ok and type(ffi) == "table") then
				local loaded = package and package.loaded
				ffi = type(loaded) == "table" and loaded.ffi or nil
			end
			if type(ffi) ~= "table" or ffi.os ~= "Windows" then return end
			pcall(ffi.cdef, [[
				void *GetForegroundWindow(void);
				unsigned long GetWindowThreadProcessId(void *window, unsigned long *pid);
				unsigned long GetCurrentProcessId(void);
			]])
			local user32 = ffi.load("user32")
			local kernel32 = ffi.load("kernel32")
			local mine = kernel32.GetCurrentProcessId()
			local pid = ffi.new("unsigned long[1]")
			foreground_fn = function()
				local w = user32.GetForegroundWindow()
				if w == nil then return false end
				pid[0] = 0
				user32.GetWindowThreadProcessId(w, pid)
				return pid[0] == mine
			end
		end)
	end
	if not foreground_fn then return true end
	local ok, front = pcall(foreground_fn)
	return not ok or front
end

function M.has_focus()
	local window = g("Window")
	if window and window.has_focus and not window.has_focus() then return false end
	return M.os_foreground()
end

-- Answers the snapshot kept in M.input.
function M.read_input(self, unit, ctx, shared, dt)
	local st = ctx.state
	local data = st.input_data
	local kbm = st.pad_number == rawget(_G, "KEYBOARD_MOUSE_PAD_NUMBER")
	local hud = nil
	if self and (self.current_state == "game" or self.current_state == "tutorial") then
		local cc = g("CharacterComponent")
		if cc and cc.get_hud_state then
			local ok, h = pcall(cc.get_hud_state, unit)
			if ok then hud = h end
		end
	end
	-- The window focus matters to the mouse only, which the view holds in the middle of the screen. The
	-- game reads a pad whatever window is in front, and so does the view: split-screen tools such as
	-- Nucleus Co-op run one game window per player, and only one of them is ever in front.
	local focused = not kbm or M.has_focus()
	local active = type(data) == "table" and data.is_active and st.has_focus
	local look = active and focused and not st.character_input_disabled and hud ~= "map" and not st.show_menu_cursor
		and not st.mouse_aim_disabled and true or false
	local fire = active and type(data.fire_button) == "number" and data.fire_button >= 0.5 or false
	local throw = active and type(data.throw) == "number" and data.throw > 0.1 or false
	local aiming = active and kbm and data.aiming_pressed and true or false
	-- A pad aims with the left trigger, as in other third person games. The game's pad layout throws
	-- with it (controller_settings.lua: left_trigger is "throw"), so while it aims, the reload button
	-- throws instead (M.pad_buttons). left_trigger and reload_button are the held values the game's pad
	-- interface answers each frame.
	local pad_aim, pad_throw = nil, nil
	if active and not kbm then
		local lt = type(data.left_trigger) == "number" and data.left_trigger or 0
		if lt > 0.1 then
			aiming = true
			pad_aim = true
			pad_throw = type(data.reload_button) == "number" and data.reload_button or 0
			throw = pad_throw > 0.1
		end
	end
	-- A tap of the right stick swaps the shoulder. The game's pad layout reads that button as
	-- push_to_talk, held (controller_settings.lua), and its press only on a Vita, so a short tap is
	-- free: the swap comes when the button lets go within M.TAP seconds, and talking doesn't swap.
	local swap = false
	if active and not kbm then
		local held = type(data.push_to_talk) == "number" and data.push_to_talk > 0.5 or data.push_to_talk == true
		if held then
			M.stick_held = (M.stick_held or 0) + (dt or 0)
		else
			swap = look and M.stick_held ~= nil and M.stick_held <= M.TAP or false
			M.stick_held = nil
		end
	end
	local stick = nil
	if active and not kbm and data.aim then
		local ok, x, y = pcall(function() return data.aim.x, data.aim.y end)
		if ok then stick = { x = x or 0, y = y or 0 } end
	end
	M.input = { frame = M.frame, unit = unit, ctx = ctx, kbm = kbm, look = look, fire = fire, throw = throw,
		aiming = aiming, stick = look and stick or nil, shared = shared, dt = dt, pad_aim = pad_aim, pad_throw = pad_throw,
		swap = swap, confused = M.confused(st), map = hud == "map" }
	return M.input
end

-- Whether the controls are turned around: an Illuminate confusion (StatusSettings confuse,
-- invert_move_confuse, switch_move_aim_confuse) queues "change_controls" on the input, which keeps an
-- input_filter whose invert list flips move and aim, or whose switch swaps them, until "reset_controls".
-- The game flips its own output only; the camera turns the other way too.
function M.confused(st)
	local f = type(st) == "table" and st.input_filter
	if type(f) ~= "table" then return false end
	return (type(f.invert) == "table" and next(f.invert) ~= nil) or (type(f.switch) == "table" and next(f.switch) ~= nil) or false
end

-- While a pad aims with the left trigger (M.read_input), the character input the game queues throws
-- with the reload button and doesn't reload; the left trigger's own throw is dropped.
function M.pad_buttons(data, input)
	if type(data) ~= "table" or not (input and input.pad_aim and input.look) then return false end
	local amount = input.pad_throw or 0
	data.throw = amount > 0.1
	data.throw_amount = amount
	data.reload = false
	return true
end

-- The swap key, or a click of the right stick: the other shoulder on foot, in a vehicle the next of
-- left, middle and right.
function M.swap_shoulder(state)
	if state.vehicle then
		if not M.ride.kind then return end
		M.ride.side = rig.next_vehicle_side(M.ride.side)
		M.vehicle_sides[M.ride.kind] = M.ride.side
		return
	end
	M.view.side = -M.view.side
end

-- Why the view stays top-down now, or nil when the shoulder camera can steer it.
function M.blocked(env, cm)
	if env.off then return "old" end
	if not M.enabled then return "off" end
	if rawget(_G, "HD2CAM_OVERLAY") then return "tpc" end
	local api = env.api
	local cam = api and api.world and api.world.camera
	if cam and cam.taken then
		local ok, taken = pcall(cam.taken)
		if ok and taken then return "taken" end
	end
	if type(cm) ~= "table" or not cm.viewport then return "no_camera" end
	if cm.state ~= "follow" and cm.state ~= "follow_menu" then return "state" end
	-- In the drop cutscene the game reads no input for the new Helldiver: the ride goes on without it.
	M.riding_input()
	local input = M.input
	if not input or M.frame - input.frame > 30 then return "no_input" end
	if input.shared then return "shared" end
	local units = g("Unit")
	if not (input.unit and units and units.alive(input.unit)) then return "no_avatar" end
	return nil
end

-- The unit the camera follows and the vehicle kind, nil on foot.
function M.target(env, avatar)
	local EA = g("EntityAux")
	local ok, cs = pcall(EA.state, avatar, "character")
	local seat = ok and type(cs) == "table" and cs.current_seat_unit or nil
	if seat and g("Unit").alive(seat) then
		local kind = nil
		local vehicles = env.api and env.api.vehicles
		if vehicles and vehicles.kind then
			local got, k = pcall(vehicles.kind, seat)
			if got then kind = k end
		end
		return seat, kind or "turret"
	end
	return avatar, nil
end

-- Where the Helldiver is drawn this frame. The camera runs in the game's update, after the mover has
-- moved (MoverComponent.update_masters, Mover.move), but the engine moves the unit's root to the mover
-- only in the scene update that follows: Unit.world_position answered the frame before, so the camera
-- trailed the Helldiver by one frame of movement, more on a long frame, and the Helldiver seemed to
-- shake when frame times jumped (probe 2026-11-20: root and Hud.update equal, the mover one frame
-- ahead, the next frame's root equal to it, and after the scene update the root equals the mover).
-- The mover's own position, when the unit has one; the root otherwise.
function M.body_position(unit)
	local U, Mv = g("Unit"), g("Mover")
	if Mv and Mv.position and U.mover then
		local ok, p = pcall(function()
			local m = U.mover(unit)
			return m and Mv.position(m)
		end)
		if ok and p then return p end
	end
	return U.world_position(unit, 0)
end

-- Whether the Helldiver is in a dive: the dive sets is_dodging in the health state until the body lands.
function M.diving(avatar)
	local EA = g("EntityAux")
	local ok, hs = pcall(EA.state, avatar, "health")
	return ok and type(hs) == "table" and hs.is_dodging == true
end

-- Whether the Helldiver holds the support weapon (the inventory's support_weapon is the one in hand).
function M.holding_support(avatar)
	local EA = g("EntityAux")
	local inv = nil
	for _, get in ipairs({ EA.state_master, EA.state }) do
		if not inv and type(get) == "function" then
			local ok, s = pcall(get, avatar, "inventory")
			if ok and type(s) == "table" then inv = s end
		end
	end
	return inv ~= nil and inv.support_weapon ~= nil and inv.support_weapon == inv.current_weapon
end

-- Whether the Helldiver is down and crawling.
function M.downed(avatar)
	local EA = g("EntityAux")
	local ok, hs = pcall(EA.state, avatar, "health")
	return ok and type(hs) == "table" and hs.is_downed == true
end

-- Whether the Helldiver sprints (CharacterStateSprint, or the sprint substate).
function M.sprinting(avatar)
	local EA = g("EntityAux")
	local ok, cs = pcall(EA.state_master, avatar, "character")
	if not ok or type(cs) ~= "table" then return false end
	local sprint, sub_sprint = g("CharacterStateSprint"), g("CharacterSubstateSprint")
	return (sprint ~= nil and cs.current_state == sprint) or (sub_sprint ~= nil and cs.current_substate == sub_sprint)
end

-- How far a jump pack lifts the Helldiver now, in metres, or 0. The jump moves the root along the
-- ground from start to target (CharacterStateJump.update, jump_state 4) and the height comes only from
-- the animation "jumppack_jump", so the hips show it: their height over the root, less the height
-- they have standing (rest, measured while not jumping; nil until then).
M.JUMP_STATES = { [4] = true, [5] = true }
function M.jump_lift(avatar, root_z, rest)
	local EA, U = g("EntityAux"), g("Unit")
	local ok, cs = pcall(EA.state_master, avatar, "character")
	local jump = g("CharacterStateJump")
	local jumping = ok and type(cs) == "table" and jump ~= nil and cs.current_state == jump and M.JUMP_STATES[cs.jump_state]
	local hips = nil
	if U.has_node and U.has_node(avatar, "hips") then hips = U.world_position(avatar, U.node(avatar, "hips")).z - root_z end
	if not jumping then return 0, hips end
	if not (hips and rest) then return 0, nil end
	return math.max(0, hips - rest), nil
end

-- Whether the Helldiver is still in the drop cutscene: the Hellpod holds the aim until they climb out.
function M.in_pod(avatar)
	local EA = g("EntityAux")
	local ok, cs = pcall(EA.state_master, avatar, "character")
	local cut = g("CharacterStateCutscene")
	return ok and type(cs) == "table" and cut ~= nil and cs.current_state == cut
end

-- The next camera mode after `mode`.
function M.next_mode(mode)
	for i, m in ipairs(M.MODES) do
		if m == mode then return M.MODES[i % #M.MODES + 1] end
	end
	return "third"
end

function M.set_mode(env, mode)
	M.mode = mode
	M.enabled = mode ~= "default"
end

-- Whether the map is open (Obsidian API), false when the API can't tell.
function M.map_open(env)
	local map = env.api and env.api.map
	if not (map and map.is_open) then return false end
	local ok, open = pcall(map.is_open)
	return ok and open and true or false
end

-- The fire and throw a vehicle reads from its driver's input (VehicleComponent takes the input
-- component's output_table as input_data), cleared: a click that places a map marker doesn't fire
-- the vehicle's guns.
function M.hold_fire(st)
	local out = type(st) == "table" and st.output_table
	if type(out) ~= "table" then return end
	out.fire_amount, out.fire, out.fire_auto = 0, false, false
	out.throw_amount, out.throw = 0, false
end

-- The hidden Windows cursor is held at the middle of the window (src/cursor.lua) while the mouse turns
-- the view in a mission, so a click never lands outside a windowed game. The game's aiming cursor
-- stays hidden: Windows draws it where the mouse is, and the engine lets go of the hold every frame
-- (probe 2026-11-25: the clip is the whole window again before each camera update, also with the
-- game's own clip off), so at a low frame rate it slid with the mouse and jumped back each frame. The
-- crosshair is drawn in the frame instead (src/crosshair.lua), with the game's images and steps.
-- M.held is decided after each frame's pose.
M.held = false

function M.hold_wanted(env, cm)
	local state, input = env.state, M.input
	if not (state.active and not M.watching and not M.hanging) then return false end
	if not (input and input.kbm and input.look and not input.riding and M.frame - input.frame <= 4) then return false end
	if type(cm) ~= "table" or cm.state ~= "follow" then return false end
	return cursor.available()
end

-- The cursors of the game's aim, which the shoulder view keeps out of the window.
M.GAME_CURSORS = { ["hud/cursors/game"] = true, ["hud/cursors/game_inactive"] = true }

-- Stops a step from the aiming cursor to the idle one and hides a game cursor still up.
function M.hide_game_cursor(cursors)
	if cursors.next_cursor ~= nil and M.GAME_CURSORS[cursors.next_cursor] then
		cursors.current_cursor = cursors.next_cursor
		cursors.next_cursor, cursors.cursor_transition_timer, cursors.cursor_transition_index = nil, nil, nil
	end
	if cursors.shown and M.GAME_CURSORS[cursors.current_cursor] and cursors.set_show_cursor then
		cursors:set_show_cursor(false)
	end
end

-- The shortest free length along a line, from three rays: the line and two beside it, so the camera
-- doesn't slip through a gap narrower than the picture. Only static geometry stops it.
function M.clear_length(pw, from, dir, length)
	local PW, V3 = g("PhysicsWorld"), g("Vector3")
	local side = rig.normalize({ x = dir.y, y = -dir.x, z = 0 }) or { x = 1, y = 0, z = 0 }
	local best = nil
	for _, s in ipairs({ 0, 0.2, -0.2 }) do
		local start = rig.add(from, side, s)
		local hit, _, distance = PW.immediate_raycast(pw, V3(start.x, start.y, start.z), V3(dir.x, dir.y, dir.z),
			length + rig.MARGIN, "closest", "types", "statics", "collision_filter", "default")
		if hit and type(distance) == "number" and (not best or distance < best) then best = distance end
	end
	return best
end

local function world_of(cm)
	local proxy = cm.viewport:get_world_proxy()
	return proxy:get_world(), proxy
end

-- Screen effects on the camera: the red of an alarm and the like (CameraManager.add_camera_particle,
-- from the flow callback camera_particles_start). The game links each to the camera unit once, sized
-- for its own top-down field of view; under the wider shoulder view it covers only the middle of the
-- screen. While the shoulder view draws, each is linked again, widened by how much wider the view is.
-- name -> { aspect = the game's own x stretch, scale = the scale it was linked at }
M.particles = {}
-- How far past the edges of the screen the widened ones reach. 1 draws them as the game draws them in
-- the top-down view (an alarm's red frame sits just inside the edges there too); 1.5 put the alarm's
-- frame past the edges or, pulled in, nearer than the near clip, so it didn't show (probe 2026-11-18).
M.PARTICLE_MARGIN = 1

function M.particle_scale(view_fov, game_fov)
	if type(view_fov) ~= "number" or type(game_fov) ~= "number" or game_fov <= 0 then return 1 end
	return math.tan(view_fov / 2) / math.tan(game_fov / 2)
end

-- How the link widens them: "pull" brings the effect nearer the camera by the scale (y is the camera's
-- forward), which grows the places and the sprites of the particles alike, as the view would see a
-- larger effect; "spread" stretches the places across the view only, which leaves each sprite as big
-- as it was. The alarm sits a few centimetres in front of the camera, so a pull past PULL_MAX takes it
-- nearer than the near clip (0.05 m): the widening past that is spread.
M.PARTICLE_FIT = "pull"
M.PULL_MAX = 1.3

-- The x, y and z scale of the link for a widening of `scale`.
function M.particle_axes(aspect, scale, fit)
	if (fit or M.PARTICLE_FIT) == "spread" then return aspect * scale, 1, scale end
	local pull = math.min(scale, M.PULL_MAX)
	local rest = scale / pull
	return aspect * rest, 1 / pull, rest
end

local function relink(cm, name, info, scale)
	local W, M4 = g("World"), g("Matrix4x4")
	local id = cm.camera_particles and cm.camera_particles[name]
	if not id then
		M.particles[name] = nil
		return
	end
	local world = world_of(cm)
	local m = M4.identity()
	local sx, sy, sz
	if scale == 0 then sx, sy, sz = 1e-4, 1e-4, 1e-4 else sx, sy, sz = M.particle_axes(info.aspect, scale) end
	M4.set_element(m, 1, 1, sx)
	M4.set_element(m, 2, 2, sy)
	M4.set_element(m, 3, 3, sz)
	W.link_particles(world, id, cm.viewport.camera_unit, 0, m, "destroy")
	info.scale = scale
end

-- Each frame of the shoulder view: view_fov in radians. scale 1 puts them back as the game had them.
-- With M.hide_alarm (the Alarm effect option, src/alarm.lua), the game's alarm overlay is linked at a
-- scale of nothing while the shoulder view draws, as the mod draws its own; the top-down view (view_fov
-- nil) puts it back.
M.hide_alarm = false
function M.fit_particles(cm, view_fov)
	local wide = view_fov and M.particle_scale(view_fov, cm.fov) * M.PARTICLE_MARGIN or 1
	for name, info in pairs(M.particles) do
		local scale = (view_fov and info.alarm and M.hide_alarm) and 0 or wide
		if math.abs((info.scale or 1) - scale) > 0.005 then
			local ok = pcall(relink, cm, name, info, scale)
			if not ok then M.particles[name] = nil end
		end
	end
end

-- Gives the drawn camera back to the game's pose.
function M.release(env, cm)
	local state = env.state
	if not state.active then return end
	state.active, state.vehicle, state.aiming, state.firing, state.crosshair = false, false, false, false, nil
	state.watching, M.watching = false, false
	env.view = nil
	smooth.pivot, smooth.length, smooth.aim, smooth.target, smooth.side, smooth.dive = nil, nil, 0, nil, nil, 0
	smooth.down, smooth.sprint, smooth.speed, smooth.last_p = 0, 0, nil, nil
	state.sprint_fade = 1
	state.dropping = false
	shake.clear()
	M.view.yaw = nil
	M.ride.target, M.ride.kind = nil, nil
	if type(cm) == "table" and cm.viewport then
		pcall(function()
			local C = g("Camera")
			local cam = cm.viewport:get_camera()
			-- The game sets the field of view only when cm.fov changes, so it goes back by hand.
			if cm.fov then C.set_vertical_fov(cam, cm.fov) end
			cm.prev_fov = cm.fov
			if saved_near then C.set_near_range(cam, saved_near) end
		end)
	end
	saved_near = nil
	if type(cm) == "table" and cm.viewport then pcall(M.fit_particles, cm, nil) end
	local cursors = g("CursorManager")
	if type(cursors) == "table" then
		local ok, was = pcall(M.give_cursor_back, cursors)
		if ok and was and M.cursor_logs < 10 then
			M.cursor_logs = M.cursor_logs + 1
			env.log("Eyes of Liberty: game cursor given back (" .. was .. ")")
		end
	end
	if M.held then
		M.held = false
		cursor.hold(false)
	end
	for _, fn in ipairs(env.on_release) do pcall(fn, cm) end
end

M.cursor_logs = 0

-- The game's cursor as the top-down view expects it after the shoulder view: no step between two
-- cursors left half done, and hidden through CursorManager itself, so the game's next
-- set_cursor/set_show_cursor (input_component.lua, idle and aiming) draws it again. Answers what was
-- there, for the log.
function M.give_cursor_back(cursors)
	local was = tostring(cursors.current_cursor) .. ", next " .. tostring(cursors.next_cursor) .. ", shown " .. tostring(cursors.shown)
	if cursors.next_cursor ~= nil then
		cursors.current_cursor = cursors.next_cursor
		cursors.next_cursor, cursors.cursor_transition_timer, cursors.cursor_transition_index = nil, nil, nil
	end
	if cursors.set_show_cursor then
		cursors.shown = true
		cursors:set_show_cursor(false)
	end
	return was
end

local function quiet() end

-- The game's camera update with the two calls that place the drawn camera left out.
function M.quiet_update(original, self, dt, ...)
	local C = g("Camera")
	if type(C) ~= "table" then return original(self, dt, ...) end
	return scoped.swap(C, "set_local_position", quiet, scoped.swap, C, "set_local_rotation", quiet, original, self, dt, ...)
end

-- The top-down pose on the drawn camera, for a frame where the game's update was kept quiet and the
-- shoulder camera then stopped.
function M.game_pose(cm)
	local C, V3A, QA = g("Camera"), g("Vector3Aux"), g("QuaternionAux")
	local cam, cam_unit = cm.viewport:get_camera(), cm.viewport.camera_unit
	C.set_local_position(cam, cam_unit, V3A.unbox(cm.position))
	C.set_local_rotation(cam, cam_unit, QA.unbox(cm.rotation))
	local world, proxy = world_of(cm)
	if cm.viewport:is_active() and proxy:is_active() then g("World").update_unit(world, cam_unit) end
end

-- The reasons to stay top-down that a death explains: the dead Helldiver reads no input, or is gone.
M.DEATH_WHY = { no_input = true, no_avatar = true }
M.RIDE_PITCH = -20    -- degrees: the extraction ride looks at least this far down when it starts
M.watching = false

-- Whether the mouse may turn the death cam: the window has focus and no menu cursor is up (the game's
-- aiming cursors don't count; the shoulder view hides them).
function M.watch_look()
	local input = M.input
	if input and M.frame - input.frame <= 4 and input.unit then
		local U = g("Unit")
		local ok, alive = pcall(U.alive, input.unit)
		if ok and alive and not input.look then return false end
	end
	if not M.has_focus() then return false end
	local cursors = g("CursorManager")
	if type(cursors) == "table" and cursors.is_shown then
		local ok, shown = pcall(cursors.is_shown, cursors)
		if ok and shown and not M.GAME_CURSORS[cursors.current_cursor] then return false end
	end
	return true
end

-- The clicks that browse the allies this frame: 1 for the right button, -1 for the left.
function M.watch_clicks()
	local mouse = g("Mouse")
	if not (mouse and mouse.pressed and mouse.button_index) then return 0 end
	local ok, step = pcall(function()
		local n = 0
		if mouse.pressed(mouse.button_index("right")) then n = n + 1 end
		if mouse.pressed(mouse.button_index("left")) then n = n - 1 end
		return n
	end)
	return ok and step or 0
end

-- The watch for this frame, and whether the mouse may turn it.
function M.watch_step(env, cm, dt)
	local look = M.watch_look()
	local world = world_of(cm)
	return deathcam.update(env.api, world, dt, look and M.watch_clicks() or 0), look
end

-- One frame of the death cam: the view turns about the body, or the ally watched, from farther back.
-- Answers false when there is nothing to look at.
function M.watch_frame(env, cm, dt, w, look)
	local state, config = env.state, env.config
	local U = g("Unit")
	M.last_why = nil
	dt = math.min(math.max(dt or 0.016, 0), 0.1)
	M.dt = dt
	local target, kind = nil, nil
	if w.ally then target, kind = M.target(env, w.ally) end
	local want
	if target then
		local p = U.world_position(target, 0)
		want = { x = p.x, y = p.y, z = p.z + rig.height(kind, 0, 0, 0) + (tonumber(config.get("camera_height")) or 0) }
	elseif w.at then
		want = { x = w.at.x, y = w.at.y, z = w.at.z }
	else
		return false
	end
	local view = M.view
	if w.ride and not w.turned then
		-- The ride starts looking down on the shuttle from a little higher than the shoulder view.
		w.turned = true
		view.pitch = math.min(view.pitch or rig.START_PITCH, M.RIDE_PITCH)
	end
	if view.yaw == nil then
		local f = deathcam.point(w.body) and g("Quaternion").forward(U.world_rotation(w.body, 0))
		view.yaw, view.pitch = f and rig.yaw_of(f) or 0, rig.START_PITCH
	end
	local input = M.input
	local stick = input and M.frame - input.frame <= 4 and input.stick or nil
	if look then
		rig.look(view, M.mouse_delta(true), stick, { speed = config.get("look_speed") or 1, invert = config.get("invert_y"), zoom = 1, dt = dt })
	else
		M.mouse_delta(false)
	end
	local followed = target or w.body
	if smooth.target ~= followed then smooth.target, smooth.length = followed, nil end
	M.ride.target, M.ride.kind = nil, nil
	state.aiming, state.firing, state.crosshair, state.sprint_fade = false, false, nil, 1
	smooth.aim, smooth.dive, smooth.down, smooth.sprint = 0, 0, 0, 0
	shake.sprint.level = 0
	smooth.pivot = rig.follow_pivot(smooth.pivot, want, dt)
	local distance
	if kind then distance = config.get("vehicle_distance") or 7
	elseif w.ride then distance = deathcam.RIDE_DISTANCE
	else distance = (config.get("foot_distance") or 3) + (target and 0 or deathcam.BACK) end
	local fov, side
	distance, fov, side = rig.lens({ distance = distance, side = 0, vehicle = kind,
		fov = kind and (config.get("vehicle_fov") or 70) or (config.get("foot_fov") or 70) })
	local world, proxy = world_of(cm)
	local _, dir, full = rig.place(smooth.pivot, view.yaw, view.pitch, distance, side)
	-- The ride's pivot sits inside the shuttle, whose own collision would pull the camera in: the ride
	-- camera stays at full distance, outside it.
	local hit = nil
	if not w.ride then hit = M.clear_length(g("World").physics_world(world), smooth.pivot, dir, full) end
	smooth.length = rig.follow_length(smooth.length, rig.pull_in(full, hit), dt)
	local position = rig.add(smooth.pivot, dir, smooth.length)
	local sx, sy = shake.offset(dt, shake.factor(config.get("camera_shake")))
	if sx ~= 0 or sy ~= 0 then
		local r, u = rig.right(view.yaw), rig.up(view.yaw, view.pitch)
		position = { x = position.x + r.x * sx + u.x * sy, y = position.y + r.y * sx + u.y * sy, z = position.z + u.z * sy }
	end
	state.dropping = false
	-- On this player's own body, before the camera moves to an ally, pings still go out (src/ping.lua).
	local own = not (w.ally or w.ride or w.last_ally)
	return M.apply(env, cm, dt, { position = position, pitch = view.pitch, fov = fov, avatar = nil, target = followed,
		kind = kind, world = world, proxy = proxy, ground = want.z, watching = true, own_body = own })
end

-- The pads of this player: the main pad and the keyboard's.
function M.own_pads()
	local out = {}
	local kbm = rawget(_G, "KEYBOARD_MOUSE_PAD_NUMBER")
	if kbm ~= nil then out[kbm] = true end
	local settings = g("GameSettings")
	local ok, main = pcall(function() return settings.get_main_pad_number() end)
	if ok and main ~= nil then out[main] = true end
	return out
end

-- The camera hanging in the sky over the squad's first pod, before this player's own drops in
-- (src/pod.lua hang). Gives up after HANG_MAX seconds, or in another world.
M.hang = nil
M.hanging = false
M.HANG_MAX = 20

-- One frame of the hanging camera. Answers false when there is none.
function M.hang_frame(env, cm, dt)
	local h = M.hang
	if not h then return false end
	local world, proxy = world_of(cm)
	h.world = h.world or world
	h.t = h.t + math.max(0, dt or 0)
	if h.world ~= world or h.t > M.HANG_MAX or env.config.get("hellpod_camera") == false then
		M.hang = nil
		return false
	end
	local view = M.view
	if view.yaw == nil then view.yaw, view.pitch = 0, rig.START_PITCH end
	M.mouse_delta(false)
	local position, pitch = pod.hang_pose(h, view.yaw)
	h.at = position
	smooth.pivot = { x = h.anchor.x, y = h.anchor.y, z = h.anchor.z }
	smooth.target, smooth.length = nil, nil
	local state = env.state
	state.aiming, state.firing, state.crosshair, state.sprint_fade = false, false, nil, 1
	state.dropping = true
	M.last_why = nil
	M.hanging = true
	local fov = env.config.get("foot_fov") or 70
	return M.apply(env, cm, dt, { position = position, pitch = pitch, fov = fov, avatar = nil, target = nil,
		kind = nil, world = world, proxy = proxy, ground = h.anchor.z, watching = true })
end

-- One frame of the shoulder camera, after the game's own update.
function M.drive(env, cm, dt)
	local state, config = env.state, env.config
	M.hanging = false
	local why = M.blocked(env, cm)
	-- This player's Helldiver is dead: the death cam (src/deathcam.lua) watches the body, then allies.
	-- It stays in the client part: with the game's shared top-down screen, a dead player sees the whole
	-- squad anyway, so watching an ally shows nothing the game doesn't.
	deathcam.dead_on = config.get("death_cam") ~= false
	deathcam.ride_on = config.get("extraction_camera") ~= false
	if not (deathcam.dead_on or deathcam.ride_on) then
		deathcam.reset()
	elseif why == nil or M.DEATH_WHY[why] then
		local ok, w, look = pcall(M.watch_step, env, cm, dt)
		if not ok and not M.warned.watch then
			M.warned.watch = true
			env.log("Eyes of Liberty: death cam: " .. tostring(w))
		end
		if ok and w then
			local drew, err = pcall(M.watch_frame, env, cm, dt, w, look)
			if drew and err then return true end
			if not drew and not M.warned.watch_frame then
				M.warned.watch_frame = true
				env.log("Eyes of Liberty: death cam: " .. tostring(err))
			end
		end
	end
	-- Before this player's pod, the camera hangs over the squad's first one.
	if why and M.DEATH_WHY[why] and M.hang and not deathcam.watch then
		local ok, drew = pcall(M.hang_frame, env, cm, dt)
		if ok and drew then return true end
		if not ok and not M.warned.hang then
			M.warned.hang = true
			env.log("Eyes of Liberty: hellpod wait: " .. tostring(drew))
		end
	end
	if why then
		if state.active and M.dropped < 20 then
			M.dropped = M.dropped + 1
			env.log("Eyes of Liberty: top-down view (" .. why .. ")")
		end
		if why == "tpc" and not M.warned.tpc then
			M.warned.tpc = true
			obsidian.toast("Eyes of Liberty stays off: Third Person Camera is installed.", 8)
			env.log("Third Person Camera found (HD2CAM_OVERLAY); staying off")
		elseif why == "shared" and M.last_why ~= "shared" then
			-- Players on one computer share one screen, which only the top-down camera can show.
			obsidian.toast(M.SHARED_TEXT, 8)
			env.log("Eyes of Liberty: off while players share this computer")
		end
		M.last_why = why
		M.release(env, cm)
		return false
	end
	if M.last_why == "shared" then obsidian.toast(M.BACK_TEXT, 4) end
	M.last_why = nil
	local input = M.input
	local avatar = input.unit
	local U, Q, V3 = g("Unit"), g("Quaternion"), g("Vector3")
	local target, kind = M.target(env, avatar)
	local view = M.view
	if view.yaw == nil or smooth.target ~= target then
		-- A new view looks the way the Helldiver or the vehicle faces.
		local f = Q.forward(U.world_rotation(target, 0))
		if view.yaw == nil then view.yaw, view.pitch = rig.yaw_of(f), rig.START_PITCH end
		smooth.target = target
		smooth.length = nil
	end
	dt = math.min(math.max(dt or 0.016, 0), 0.1)
	M.dt = dt

	-- Look.
	local aim_t = smooth.aim
	local zoom = 1 + (rig.AIM_FOV - 1) * aim_t
	-- The Hellpod holds the aim until the Helldiver climbs out.
	local locked = M.drop ~= nil and M.drop.avatar == avatar and M.in_pod(avatar)
	if input.look and not locked and M.frame - input.frame <= 4 then
		rig.look(view, M.mouse_delta(true), input.stick, { speed = config.get("look_speed") or 1, invert = config.get("invert_y"),
			zoom = zoom, dt = dt, confused = input.confused })
	else
		M.mouse_delta(false) -- drop what moved while the view didn't take it
	end
	smooth.aim = rig.ease(smooth.aim, (input.aiming and not kind) and 1 or 0, 12, dt)
	smooth.support = rig.ease(smooth.support or 0, (not kind and M.holding_support(avatar)) and 1 or 0, 12, dt)
	state.aiming = input.aiming and not kind and true or false
	-- Fire or a throw held: the game shows the aiming cursor for these too.
	state.firing = (input.fire or input.throw) and true or false
	-- The shoulder swap and the dive close-up ease in, so neither jumps.
	-- In a vehicle the camera sits left, in the middle or right (M.ride), on foot over a shoulder.
	if kind then
		if M.ride.target ~= target then
			M.ride.target, M.ride.kind = target, kind
			M.ride.side = M.vehicle_sides[kind] or rig.vehicle_side(kind, view.side)
		end
	else
		M.ride.target, M.ride.kind = nil, nil
	end
	local wanted_side = kind and M.ride.side or view.side
	smooth.side = smooth.side and rig.ease(smooth.side, wanted_side, rig.SWAP_RATE, dt) or wanted_side
	M.side_now = smooth.side -- the shoulder, easing from -1 to 1 during a swap (src/ammobar.lua)
	local diving = not kind and config.get("dive_camera") ~= false and M.diving(avatar)
	smooth.dive = rig.ease(smooth.dive, diving and 1 or 0, diving and rig.DIVE_IN or rig.DIVE_OUT, dt)
	-- Down and crawling: the camera comes low, near the ground, and backs away.
	local down = not kind and config.get("downed_camera") ~= false and M.downed(avatar)
	smooth.down = rig.ease(smooth.down, down and 1 or 0, rig.DOWN_RATE, dt)
	-- Sprinting: the crosshair fades out and the camera moves a little (src/shake.lua).
	local sprinting = not kind and M.sprinting(avatar)
	smooth.sprint = rig.ease(smooth.sprint, sprinting and 1 or 0, rig.SPRINT_RATE, dt)
	state.sprint_fade = 1 - smooth.sprint
	shake.sprint.level = smooth.sprint

	local p = kind and U.world_position(target, 0) or M.body_position(target)
	-- How fast the Helldiver moves over the ground, eased, for the pace of the sprint sway.
	local last = smooth.last_p
	if last and dt > 0 then
		local dx, dy = p.x - last.x, p.y - last.y
		local speed = math.sqrt(dx * dx + dy * dy) / dt
		if speed < 30 then smooth.speed = rig.ease(smooth.speed or speed, speed, 8, dt) end
	end
	smooth.last_p = { x = p.x, y = p.y }
	shake.sprint.pace = shake.pace_of(smooth.speed)
	local world, proxy = world_of(cm)
	local position, fov
	-- Pivot and lens. The ship has a distance of its own: the bridge is small.
	local lift = tonumber(config.get("camera_height")) or 0
	-- A jump pack's flight lifts the camera with the Helldiver.
	local jumped = 0
	if not kind then
		local ok, up, standing = pcall(M.jump_lift, avatar, U.world_position(avatar, 0).z, smooth.hips_rest) -- hips and root of the same frame
		if ok then
			jumped = up
			if standing and smooth.dive < 0.01 and smooth.down < 0.01 then
				smooth.hips_rest = smooth.hips_rest and rig.ease(smooth.hips_rest, standing, 4, dt) or standing
			end
		end
	end
	local want = { x = p.x, y = p.y, z = p.z + rig.height(kind, smooth.side, smooth.dive, smooth.down) + lift + jumped }
	smooth.pivot = rig.follow_pivot(smooth.pivot, want, dt)
	local distance
	if kind then distance = config.get("vehicle_distance") or 7
	elseif cm.state == "follow_menu" then distance = config.get("ship_distance") or 2
	else
		distance = config.get("foot_distance") or 3
		-- Scroll camera distance: the wheel sets the distance on foot, eased toward it.
		if config.get("scroll_distance") == true then
			local wheel = (input.look and input.kbm) and M.wheel() or 0
			M.zoom.want = M.zoom_step(M.zoom.want or distance, wheel)
			M.zoom.now = M.zoom.now and rig.ease(M.zoom.now, M.zoom.want, M.ZOOM_RATE, dt) or M.zoom.want
			distance = M.zoom.now
		end
	end
	local side
	distance, fov, side = rig.lens({
		distance = distance,
		fov = kind and (config.get("vehicle_fov") or 70) or (config.get("foot_fov") or 70),
		side = smooth.side, aim = smooth.aim, dive = smooth.dive, down = smooth.down, vehicle = kind,
		shoulder = config.get("side_distance"), support = smooth.support })
	local _, dir, full = rig.place(smooth.pivot, view.yaw, view.pitch, distance, side)

	-- Walls and rocks pull the camera in.
	local hit = M.clear_length(g("World").physics_world(world), smooth.pivot, dir, full)
	smooth.length = rig.follow_length(smooth.length, rig.pull_in(full, hit), dt)
	position = rig.add(smooth.pivot, dir, smooth.length)

	-- The Hellpod ride: the pod pose, then the glide into the shoulder pose.
	local pitch = view.pitch
	local drop = M.drop
	if drop then
		local was = drop.landed
		local going = drop.avatar == avatar and not kind and pod.step(drop, dt)
		if going and not was and drop.landed then shake.add(M.LAND_SHAKE[1], M.LAND_SHAKE[2], M.LAND_SHAKE[3]) end
		if not going then M.drop, drop = nil, nil end
	end
	state.dropping = false
	if drop then
		local w = pod.blend(drop)
		local pod_at, pod_pitch = pod.pose(drop, view.yaw)
		position, pitch = pod.mix(pod_at, pod_pitch, position, view.pitch, w)
		-- From where the camera hung over the squad's first pod, over to this one.
		if drop.from then
			local k = pod.snap(drop)
			if k >= 1 then drop.from = nil
			else position = pod.mix(drop.from, pitch, position, pitch, k) end
		end
		state.dropping = w < 1
	end

	-- Shake: the game's, and the mod's own.
	local factor = shake.factor(config.get("camera_shake"))
	shake.game.x, shake.game.y = (shake.game.x or 0) * M.GAME_SHAKE, (shake.game.y or 0) * M.GAME_SHAKE
	local sx, sy = shake.offset(dt, factor)
	if sx ~= 0 or sy ~= 0 then
		local r, u = rig.right(view.yaw), rig.up(view.yaw, pitch)
		position = { x = position.x + r.x * sx + u.x * sy, y = position.y + r.y * sx + u.y * sy, z = position.z + u.z * sy }
	end

	return M.apply(env, cm, dt, { position = position, pitch = pitch, fov = fov, avatar = avatar, target = target,
		kind = kind, world = world, proxy = proxy, ground = p.z })
end

-- Puts the drawn camera at pose.position, turned to the view's yaw and pose.pitch, and tells the other
-- modules (env.on_pose). pose: position, pitch, fov (degrees), avatar, target, kind, world, proxy,
-- ground (the height the grass gathers about), watching (the death cam).
function M.apply(env, cm, dt, pose)
	local state, view = env.state, M.view
	local Q, V3, C = g("Quaternion"), g("Vector3"), g("Camera")
	local position, pitch, fov, world, proxy = pose.position, pose.pitch, pose.fov, pose.world, pose.proxy
	-- An explosion's kick (src/kick.lua): a roll about the view, a tip up and a lift, scaled by the
	-- Camera shake option. The tip and lift reach the aim too, so the crosshair stays where shots go.
	local roll = 0
	if not pose.watching then
		local kr, kp, kl = kick.step(dt, shake.factor(env.config.get("camera_shake")))
		roll, pitch = kr, pitch + kp
		position = { x = position.x, y = position.y, z = position.z + kl }
	else
		kick.clear()
	end
	-- Apply.
	local cam, cam_unit = cm.viewport:get_camera(), cm.viewport.camera_unit
	local rotation = Q.multiply(Q(V3(0, 0, 1), math.rad(view.yaw)), Q(V3(1, 0, 0), math.rad(pitch)))
	if roll ~= 0 then rotation = Q.multiply(rotation, Q(V3(0, 1, 0), math.rad(roll))) end
	C.set_local_position(cam, cam_unit, V3(position.x, position.y, position.z))
	C.set_local_rotation(cam, cam_unit, rotation)
	C.set_vertical_fov(cam, math.rad(fov))
	pcall(M.fit_particles, cm, math.rad(fov))
	if saved_near == nil then
		local ok, near = pcall(C.near_range, cam)
		saved_near = ok and near or 0.1
		pcall(C.set_near_range, cam, 0.05)
	end
	if cm.viewport:is_active() and proxy:is_active() then g("World").update_unit(world, cam_unit) end
	local forward = rig.forward(view.yaw, pitch)
	-- Grass and scattered detail gather around what the view looks at.
	local scatter = g("ScatterSystem")
	if scatter and cm.scatter_system and cm.observer_id then
		local f = rig.flat_forward(view.yaw)
		pcall(scatter.move_observer, cm.scatter_system, cm.observer_id, V3(smooth.pivot.x + f.x * 20, smooth.pivot.y + f.y * 20, pose.ground + 10))
	end
	local tw, M4 = g("TimpaniWorld"), g("Matrix4x4")
	if tw and M4 and cm.timpani_world then
		pcall(tw.set_listener, cm.timpani_world, 0, M4.from_quaternion_position(rotation, V3(position.x, position.y, position.z)))
	end

	env.view = { position = position, forward = forward, yaw = view.yaw, pitch = pitch, fov = fov, pivot = smooth.pivot,
		avatar = pose.avatar, target = pose.target, vehicle = pose.kind, world = world, camera = cam, watching = pose.watching,
		own_body = pose.own_body }
	state.active = true
	state.vehicle = pose.kind ~= nil and not pose.watching
	state.watching = pose.watching and true or false
	M.watching = state.watching
	for _, fn in ipairs(env.on_pose) do
		local ok, err = pcall(fn, env.view, cm, dt)
		if not ok and not M.warned[fn] then
			M.warned[fn] = true
			env.log("Eyes of Liberty: " .. tostring(err))
		end
	end
	return true
end

-- Scroll camera distance. M.zoom: want, the distance the wheel asks for; now, the eased one. Both
-- start from the On-foot camera distance option and go back to it when that option changes.
M.ZOOM_STEP = 0.5     -- metres a wheel notch moves the camera
M.ZOOM_MIN, M.ZOOM_MAX = 1, 10
M.ZOOM_RATE = 14      -- ease rate toward the wanted distance: fast, without a jump
M.zoom = { want = nil, now = nil }

-- The distance after `wheel` notches (up, positive, brings the camera closer), within ZOOM_MIN and
-- ZOOM_MAX. Wheels that report 120 a notch count as one.
function M.zoom_step(current, wheel)
	if type(wheel) ~= "number" or wheel == 0 then return current end
	local notches = math.abs(wheel) >= 60 and wheel / 120 or wheel
	return math.max(M.ZOOM_MIN, math.min(M.ZOOM_MAX, current - notches * M.ZOOM_STEP))
end

-- The mouse wheel this frame, up positive, or 0.
local wheel_id = nil
function M.wheel()
	local mouse = g("Mouse")
	if not mouse then return 0 end
	local ok, y = pcall(function()
		wheel_id = wheel_id or mouse.axis_index("wheel")
		return mouse.axis(wheel_id).y
	end)
	return ok and type(y) == "number" and y or 0
end

-- Mouse movement since the last frame: { x right, y down the screen } in counts. The cursor is kept near
-- the middle of the window, so it never reaches the edge of a windowed game.
local mouse_ids, last_cursor, skip_cursor = nil, nil, false
function M.mouse_delta(recenter)
	local mouse = g("Mouse")
	if not mouse then return nil end
	local ok, out = pcall(function()
		if not mouse_ids then
			local found, delta = pcall(mouse.axis_index, "mouse")
			mouse_ids = { delta = found and delta or nil, cursor = mouse.axis_index("cursor") }
		end
		local cursor = mouse.axis(mouse_ids.cursor)
		local d = nil
		if mouse_ids.delta then
			local v = mouse.axis(mouse_ids.delta)
			d = { x = v.x, y = v.y }
		elseif last_cursor and not skip_cursor then
			-- The cursor's y grows up the screen.
			d = { x = cursor.x - last_cursor.x, y = -(cursor.y - last_cursor.y) }
		end
		skip_cursor = false
		last_cursor = { x = cursor.x, y = cursor.y }
		local w, h = g("Application").resolution()
		if recenter and M.has_focus() and (math.abs(cursor.x - w / 2) > w * 0.1 or math.abs(cursor.y - h / 2) > h * 0.1) then
			local cursors = g("CursorManager")
			if cursors and cursors.set_cursor_position then
				cursors:set_cursor_position(g("Vector3")(math.floor(w / 2), math.floor(h / 2), 0))
				skip_cursor, last_cursor = true, nil
			end
		end
		return d
	end)
	return ok and out or nil
end

function M.start(env)
	local state = env.state
	env.on_pose = env.on_pose or {}
	env.on_release = env.on_release or {}
	env.frame = function() return M.frame end
	env.camera = M
	-- The mode the key left, while the Camera mode option is still the one it was then.
	local option = env.config.get("camera_mode") or "third"
	local kept = obsidian.storage.get("camera_mode", nil)
	local kept_option = obsidian.storage.get("camera_mode_option", nil)
	local mode = option
	if kept_option == option and (kept == "default" or kept == "third") then mode = kept end
	M.set_mode(env, mode)
	M.view.side = env.config.get("shoulder") == "left" and -1 or 1
	env.config.on_change("shoulder", function(v) M.view.side = v == "left" and -1 or 1 end)
	env.config.on_change("foot_distance", function() M.zoom.want, M.zoom.now = nil, nil end)
	-- Camera mode changed in the pause menu: that mode now, as if the key had picked it.
	env.config.on_change("camera_mode", function(v)
		if v ~= "default" and v ~= "third" then return end
		M.set_mode(env, v)
		obsidian.storage.set("camera_mode", v)
		obsidian.storage.set("camera_mode_option", v)
	end)

	frustum.install(env)

	-- The screen effects the game puts on the camera, to widen with the view (M.fit_particles).
	obsidian.hook("CameraManager", "add_camera_particle", function(original, self, name, effect, stretch, ...)
		local had = type(self) == "table" and type(self.camera_particles) == "table" and self.camera_particles[name]
		local r = scoped.pack(original(self, name, effect, stretch, ...))
		if not had and type(self) == "table" and type(self.camera_particles) == "table" and self.camera_particles[name] then
			local aspect = 1
			if stretch then
				local ok, w, h = pcall(function() return self.viewport:window() end)
				if ok and type(w) == "number" and type(h) == "number" and h > 0 then aspect = (w / h) / 1.777778 end
			end
			M.particles[name] = { aspect = aspect, scale = 1, alarm = type(effect) == "string" and effect:find("alarm", 1, true) ~= nil }
		end
		return unpack(r, 1, r.n)
	end, env.VIEW)
	-- The extraction ride: the shuttle this player's Helldiver boards (src/deathcam.lua).
	obsidian.hook("StateGame", "on_avatar_extract", function(original, self, avatar, shuttle, ...)
		local cm = g("CameraManager")
		if type(cm) == "table" and cm.viewport then
			pcall(function() deathcam.board(avatar, shuttle, (world_of(cm))) end)
		end
		return original(self, avatar, shuttle, ...)
	end, env.VIEW)
	obsidian.hook("CameraManager", "remove_camera_particle", function(original, self, name, ...)
		M.particles[name] = nil
		return original(self, name, ...)
	end, env.VIEW)

	-- The input this frame is kept for the camera, and the cursor stays hidden.
	local inside = false
	local function enter() inside = true end
	local function leave() inside = false end
	obsidian.hook("InputComponent", "update_masters", function(original, self, masters, dt, ...)
		local unit, ctx, shared = M.local_master(masters, env.api)
		if unit then
			M.read_input(self, unit, ctx, shared, dt)
			if M.input.swap and state.active then M.swap_shoulder(state) end
		end
		if not (state.active and M.view.yaw) then return original(self, masters, dt, ...) end
		if M.input and M.input.look then
			local st = ctx and ctx.state
			-- The software cursor the game eases back to the Helldiver after aiming stays away.
			if st then st.software_cursor_position, st.software_cursor_start_distance = nil, nil end
			local cursors = g("CursorManager")
			if cursors and cursors.is_shown and cursors:is_shown() then cursors:set_show_cursor(false) end
		end
		local r = scoped.pack(scoped.around(enter, leave, original, self, masters, dt, ...))
		if state.vehicle and ctx and M.map_open(env) then M.hold_fire(ctx.state) end
		return unpack(r, 1, r.n)
	end, env.VIEW)

	-- W moves where the camera looks: the local player's movement, which the game turned by the top-down
	-- spin, turns on by the difference to the view's yaw (the mover's set_movement, and the movement
	-- in the character's input, which the Helldiver faces while not aiming). Not while the map is open:
	-- the map pans by that same movement, turned back by the top-down spin only (Hud.handle_map_input),
	-- so a turned one panned the map the way the view faced instead of up the screen.
	obsidian.hook("InputComponent", "queue_command_master", function(original, self, unit, component, command, data, ...)
		local cm = g("CameraManager")
		if inside and state.active and M.view.yaw and M.input and unit == M.input.unit and not M.input.map
			and type(cm) == "table" and type(cm.follow_spin) == "number" and not M.map_open(env) then
			local turn = rig.spin_of(M.view.yaw) - cm.follow_spin
			if component == "mover" and command == "set_movement" then
				rig.turn_flat(data, turn)
			elseif component == "character" and command == "input" and type(data) == "table" then
				rig.turn_flat(data.movement, turn)
			end
		end
		return original(self, unit, component, command, data, ...)
	end, env.VIEW)

	-- A tank's tracks and a vehicle's turn read the driver's movement back through follow_spin: with this
	-- player's vehicle the only one this machine drives, the view's yaw stands there for that update.
	obsidian.hook("VehicleComponent", "update_masters", function(original, self, masters, ...)
		local cm = g("CameraManager")
		local view = env.view
		if not (state.active and state.vehicle and view and type(cm) == "table" and M.view.yaw and type(masters) == "table"
			and masters[view.target] and next(masters, next(masters)) == nil) then
			return original(self, masters, ...)
		end
		return scoped.swap(cm, "follow_spin", rig.spin_of(M.view.yaw), original, self, masters, ...)
	end, env.VIEW)

	-- While the game reads input under the shoulder camera, the aiming cursor stays hidden and in place.
	obsidian.hook("CursorManager", "set_show_cursor", function(original, self, on, ...)
		if inside and on and state.active and M.input and M.input.look then return original(self, false, ...) end
		return original(self, on, ...)
	end, env.VIEW)
	obsidian.hook("CursorManager", "set_cursor_position", function(original, self, ...)
		if inside and state.active and M.input and M.input.look then return end
		return original(self, ...)
	end, env.VIEW)
	-- set_cursor hands the game cursor to the window and counts it as shown, and the steps from the
	-- aiming cursor to the idle one go on in CursorManager.update even while the cursor is hidden: either
	-- way the hardware cursor came back at the mouse, which the view keeps near the middle. The game
	-- cursors stay out while the shoulder camera takes the mouse; src/crosshair.lua draws the crosshair.
	obsidian.hook("CursorManager", "set_cursor", function(original, self, path, ...)
		if inside and state.active and M.input and M.input.look and M.GAME_CURSORS[path] then return end
		return original(self, path, ...)
	end, env.VIEW)
	obsidian.hook("CursorManager", "update", function(original, self, ...)
		if state.active and (M.watching or (M.input and M.input.look)) and type(self) == "table" then
			pcall(M.hide_game_cursor, self)
		end
		return original(self, ...)
	end, env.VIEW)

	-- On the ship the game draws the HUD before the camera update (StateMenu.update), so the marks over
	-- the crew and the terminals were placed for the view of the frame before. While the shoulder view
	-- is on there, the HUD of the frame is drawn right after the camera update instead.
	local hud_late, hud_flushing = nil, false
	obsidian.hook("Hud", "update", function(original, self, ...)
		local cm = g("CameraManager")
		if not hud_flushing and state.active and type(cm) == "table" and cm.state == "follow_menu" then
			hud_late = { self = self, args = scoped.pack(...) }
			return
		end
		return original(self, ...)
	end, env.VIEW)
	M.flush_hud = function()
		local late = hud_late
		if not late then return end
		hud_late = nil
		hud_flushing = true
		local ok, err = pcall(function() late.self:update(unpack(late.args, 1, late.args.n)) end)
		hud_flushing = false
		if not ok and not M.warned.hud then
			M.warned.hud = true
			env.log("Eyes of Liberty: ship HUD: " .. tostring(err))
		end
	end

	-- A Helldiver dropping in: the game's drop cutscene of this player's avatar starts the Hellpod ride.
	obsidian.hook("CharacterStateCutscene", "on_enter", function(original, unit, context, previous, params, ...)
		local r = scoped.pack(original(unit, context, previous, params, ...))
		pcall(function()
			if type(params) ~= "table" or params.animation ~= "intro_land" then return end
			if env.config.get("hellpod_camera") == false then return end
			local api = env.api
			local mine = api and api.game and api.game.my_unit and api.game.my_unit()
			local st = type(context) == "table" and context.state
			local input_state = type(st) == "table" and st.input_state
			local pad = type(input_state) == "table" and input_state.pad_number or nil
			local current = M.input and not M.input.riding and M.input.unit or nil
			local p = g("Unit").world_position(unit, 0)
			if not M.drop_is_mine(unit, mine, current, pad, M.own_pads()) then
				-- Another Helldiver of this machine drops first while this player has none: the camera
				-- waits in the sky over that pod.
				if not M.hang and not M.drop and not deathcam.watch and not deathcam.living(mine) and not deathcam.living(current) then
					M.hang = pod.hang({ x = p.x, y = p.y, z = p.z })
				end
				return
			end
			M.drop = pod.new({ x = p.x, y = p.y, z = p.z })
			M.drop.avatar = unit
			if M.hang and M.hang.at then M.drop.from = M.hang.at end
			M.hang = nil
		end)
		return unpack(r, 1, r.n)
	end, env.VIEW)

	-- The pod's landing is the game's hellpod shake near the Helldiver.
	obsidian.hook("CameraManager", "add_shake", function(original, self, template, epicenter, ...)
		pcall(function()
			local drop = M.drop
			local settings = g("CameraShakeSettings")
			if not (drop and not drop.landed and settings and template == settings.hellpod) then return end
			if epicenter then
				local e = g("Vector3Aux").unbox(epicenter)
				local a = drop.anchor
				if (e.x - a.x) ^ 2 + (e.y - a.y) ^ 2 > pod.NEAR * pod.NEAR then return end
			end
			M.pod_landed()
		end)
		return original(self, template, epicenter, ...)
	end, env.VIEW)

	-- The offset of the game's shakes this frame (zero when it has none), for the shoulder view.
	obsidian.hook("CameraShaker", "update", function(original, self, ...)
		local r = original(self, ...)
		local cm = g("CameraManager")
		if type(cm) == "table" and self == cm.camera_shaker and type(r) == "table" then
			shake.game.x, shake.game.y = tonumber(r.x) or 0, tonumber(r.y) or 0
		end
		return r
	end, env.VIEW)

	obsidian.hook("CameraManager", "update", function(original, self, dt, ...)
		shake.game.x, shake.game.y = 0, 0
		-- The shoulder camera of the last frame goes on unless something stops it in this one.
		local asked, why = pcall(M.blocked, env, self)
		local still = state.active and asked and (why == nil or ((M.watching or M.hanging) and M.DEATH_WHY[why] ~= nil))
		local r
		if still then
			r = scoped.pack(M.quiet_update(original, self, dt, ...))
		else
			r = scoped.pack(original(self, dt, ...))
		end
		M.frame = M.frame + 1
		local ok, drove = pcall(M.drive, env, self, dt)
		if not ok then
			if not M.warned.drive then
				M.warned.drive = true
				env.log("Eyes of Liberty: camera stopped: " .. tostring(drove))
			end
			pcall(M.release, env, self)
		end
		if still and not (ok and drove) then pcall(M.game_pose, self) end
		local got, want = pcall(M.hold_wanted, env, self)
		M.held = cursor.hold(got and want or false) and true or false
		if M.flush_hud then M.flush_hud() end
		return unpack(r, 1, r.n)
	end, env.VIEW)

	obsidian.keybind("toggle_view", function()
		M.set_mode(env, M.next_mode(M.mode))
		obsidian.storage.set("camera_mode", M.mode)
		obsidian.storage.set("camera_mode_option", env.config.get("camera_mode") or "third")
		obsidian.toast(M.MODE_TEXT[M.mode], 2)
	end, env.KEY_VIEW)

	obsidian.keybind("swap_shoulder", function()
		if state.active then M.swap_shoulder(state) end
	end, env.KEY_VIEW)
end

return M
