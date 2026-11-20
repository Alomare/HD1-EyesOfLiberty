-- The ammo bar: Better HUD's ammo circle (src/ammo_look.lua) as a sixth of a circle around the
-- crosshair, in third person on foot. Same colours, warnings, shakes, laser heat, arc charge, empty
-- flash and reload button; shows from a shot, fades out 8 seconds after the last shot. A weapon of 50
-- rounds or fewer has a faint line between rounds. While the weapon reloads, the bar fills in Better
-- HUD's reload grey as the reload goes; a finished reload swells the band by GROW and fades it out over
-- DONE seconds, as Better HUD's reload ring does, and the bar stays hidden until the next shot.
--
-- Options: ammo_bar (on), ammo_bar_position ("oppose": on the side away from the Helldiver, "same": on
-- the Helldiver's side, "top", "bottom"), ammo_bar_curved (on; off draws a straight bar of the same
-- length), ammo_bar_scale (0.5 to 2). While it shows, Better HUD's ammo circle steps aside (main.lua
-- export ammo_bar, read by Better HUD).
--
-- Sizes: the band is Better HUD's ring band at its shoulder view size (3.5 design units wide with a
-- 1.5 unit border, times 1.5, times the HUD scale); the bar sits RADIUS of the screen height from the
-- crosshair, past the enemy indicators (0.11) and inside the hit bars (0.15). Scale multiplies both.
local look = obsidian.module("src/ammo_look")

local M = {}

local function g(name) return rawget(_G, name) end

M.RADIUS = 0.135      -- of the screen height, from the crosshair to the middle of the band
M.WIDTH, M.EDGE = 4.2, 1.5 -- design units: the band (Better HUD's 3.5, a fifth thicker), and the dark
                           -- border around it, past the ends too
M.SIZE = 1.5          -- Better HUD's ring size in the shoulder view
M.SPAN = math.pi / 3  -- a sixth of a circle: two thirds of a quarter
M.PIECES = 24         -- pieces a curved bar is drawn in
M.ROUNDS = 50         -- magazines up to this many rounds show a line between rounds
M.LINE = { 0, 0, 0, 110 } -- those lines: faded
M.LINE_WIDTH = 0.5    -- design units
M.BUTTON_GAP = 4      -- design units between the band and the reload button
M.TRACK, M.BORDER = { 30, 30, 30, 85 }, { 0, 0, 0, 100 }
M.SHADOW = 0.2
M.OPACITY = 0.9       -- the whole bar at most this opaque
M.KINDS = { "firearm", "flameweapon", "launcher", "beamweapon", "arcweapon" }
local NEAR_END = 0.85 -- a reload that stops past this far counts as finished, not cancelled
M.FILL = { 212, 212, 212, 255 } -- the reload fill, Better HUD's
M.LASER = { 255, 232, 70, 255 } -- a laser's heat: brighter than the yellow of rounds
M.DONE = 0.1          -- seconds a finished reload takes to swell and fade out
M.GROW = 0.45         -- how much thicker the band ends, of its width

-- How thick and how visible the band of a finished reload is `t` seconds after it finished, or nil once
-- gone.
function M.finish(t)
	if t >= M.DONE then return nil end
	local f = t / M.DONE
	return 1 + M.GROW * f, 1 - f
end

-- The bar's shape: a function (t, r) giving the screen point t of the way along the bar (0 where the
-- fill starts) at r pixels from the crosshair (cx, cy). position: "oppose", "same", "top", "bottom";
-- side: the camera's shoulder, 1 right, -1 left, between the two during a swap; R: pixels from the
-- crosshair to the middle of the band. Side bars fill upward, top and bottom bars left to right.
function M.shape(position, side, curved, cx, cy, R)
	local s = side or 1
	if position == "same" then s = -s end
	local length = 2 * R * math.sin(M.SPAN / 2)
	if position == "top" or position == "bottom" then
		local up = position == "top" and 1 or -1
		if curved then
			local from = position == "top" and -M.SPAN / 2 or math.pi + M.SPAN / 2
			local dir = position == "top" and 1 or -1
			return function(t, r)
				local a = from + dir * M.SPAN * t
				return cx + math.sin(a) * r, cy + math.cos(a) * r
			end
		end
		return function(t, r) return cx - length / 2 + length * t, cy + up * r end
	end
	-- The side the Helldiver isn't on: right of the crosshair with the camera over the right shoulder.
	if curved then
		return function(t, r)
			local a = math.pi / 2 + M.SPAN / 2 - M.SPAN * t
			return cx + s * math.sin(a) * r, cy + math.cos(a) * r
		end
	end
	return function(t, r) return cx + s * r, cy - length / 2 + length * t end
end

-- Where the lines between rounds go along the bar, for a magazine of `size`: none above ROUNDS.
function M.dividers(size)
	local out = {}
	if type(size) ~= "number" or size < 2 or size > M.ROUNDS then return out end
	for k = 1, size - 1 do out[#out + 1] = k / size end
	return out
end

-- The light's shade at the screen angle of (x, y) from the crosshair: Better HUD's shadow, darkest at
-- the bottom left.
local function shaded(color, x, y, cx, cy)
	local a = math.atan2(x - cx, y - cy)
	local k = 1 - M.SHADOW * (1 - (math.sin(a) + math.cos(a)) / math.sqrt(2)) / 2
	return { math.floor(color[1] * k + 0.5), math.floor(color[2] * k + 0.5), math.floor(color[3] * k + 0.5), color[4] }
end

-- How far the reload has come, 0 to 1, or nil when not reloading (Better HUD src/reload.lua).
function M.progress(state)
	local left, total = state.reload_time, state.reload_duration
	if type(left) ~= "number" or type(total) ~= "number" or left < 0 or total <= 0 then return nil end
	if state.is_reloading == false then return nil end
	return math.max(0, math.min(1, 1 - left / total))
end

-- Pixels a HUD design unit: the resolution's scale times the UI scale setting (Better HUD M.scale).
local function hud_scale(gui, w, h)
	local res = gui and gui.ui_scale_resolution or math.min(w / 1280, h / 720)
	local user = gui and gui.ui_scale_user
	if not user then
		local save = g("SaveManager")
		local ok, v = pcall(function() return save:get("ui_scale") end)
		user = ok and tonumber(v) or nil
	end
	return res * (user or 1)
end

-- Whether the bar is meant to show now (option on, third person on foot): Better HUD's circle steps
-- aside while this is true.
function M.wanted(env)
	local state = env.state
	return env.config.get("ammo_bar") ~= false and state.active and not state.vehicle and not state.watching or false
end

function M.start(env)
	local state, api = env.state, env.api
	local ui = obsidian.ui
	if type(ui) ~= "table" or type(ui.canvas) ~= "function" then return end
	local kit = ui.canvas("eyesofliberty_ammo", { layer = 420 })
	if not kit then return end
	local quad = { 0, 0, 0, 0, 0, 0, 0, 0 }
	local t = {}           -- the circle's tracking (src/ammo_look.lua)
	local last, clock, done_at = nil, 0, nil
	local failed = false

	local function piece(f, t0, t1, r1, r2, color, cx, cy, shade)
		local ax, ay = f(t0, r1)
		local bx, by = f(t0, r2)
		local qx, qy = f(t1, r2)
		local px, py = f(t1, r1)
		quad[1], quad[2], quad[3], quad[4], quad[5], quad[6], quad[7], quad[8] = ax, ay, bx, by, qx, qy, px, py
		if shade then color = shaded(color, (ax + qx) / 2, (ay + qy) / 2, cx, cy) end
		kit:poly(quad, color)
	end

	local function band(f, from, to, r1, r2, color, cx, cy, shade, curved)
		local n = curved and math.max(1, math.ceil(M.PIECES * (to - from))) or 1
		for i = 0, n - 1 do
			piece(f, from + (to - from) * i / n, from + (to - from) * (i + 1) / n, r1, r2, color, cx, cy, shade)
		end
	end

	local function frame(dt)
		local view = env.view
		local avatar = view and view.avatar
		if not (M.wanted(env) and avatar) then return end
		local inv = g("EntityAux").state(avatar, "inventory")
		local weapon = inv and inv.current_weapon
		local st, kind = nil, nil
		if weapon then
			for _, k in ipairs(M.KINDS) do
				st = api.game.master(weapon, k)
				if st then kind = k break end
			end
		end
		local p = st and M.progress(st)
		local reloading = p ~= nil
		if p then done_at = nil
		elseif last and last >= NEAR_END then
			done_at = clock
			look.reloaded(t)
		end
		last = p
		-- The reload: its progress, or a finished one swelling and fading.
		local rp, grow, ralpha = p, 1, 1
		if not rp and done_at then
			grow, ralpha = M.finish(clock - done_at)
			if grow then rp = 1 else grow, ralpha, done_at = 1, 1, nil end
		end
		local share, rounds, empty, size, ready = look.reading(st)
		if share then look.track(t, weapon, share, clock, reloading) end
		look.react(t, kind, share, rounds, empty, ready, clock, dt)
		local alpha = (share and not reloading) and look.alpha(t.shot, clock) or 0
		local discharge = not reloading and kind == "arcweapon" and look.discharge_alpha(t, clock)
		if alpha <= 0 and not discharge and not rp then return end
		local game = api.game.state and api.game.state()
		local hud = game and game.hud
		if hud and (hud.hidden or hud.enabled == false) then return end
		if api.map and api.map.is_open and api.map.is_open() then return end
		if api.effects and api.effects.is_on and api.effects.is_on("photo_mode") then return end
		local cross = state.crosshair
		if not cross then return end
		local w, h = g("Application").resolution()
		local user = math.max(0.5, math.min(2, tonumber(env.config.get("ammo_bar_scale")) or 1))
		local ring = hud_scale(hud and hud.hd_gui, w, h) * M.SIZE * user
		local R = M.RADIUS * h * user
		local dx, dy = look.shake_offset(t, clock)
		local cx, cy = cross.x + dx * ring, cross.y + dy * ring
		local curved = env.config.get("ammo_bar_curved") ~= false
		local camera = env.camera
		local f = M.shape(env.config.get("ammo_bar_position") or "oppose", camera and camera.side_now or 1, curved, cx, cy, R)
		local half, e = M.WIDTH * ring / 2 * grow, M.EDGE * ring
		local r1, r2 = R - half, R + half
		local fill, ccw, color, track = 1, false, look.WHITE, nil
		if rp then
			kit:opacity(ralpha * M.OPACITY)
			fill, color = rp, M.FILL
		elseif discharge then
			kit:opacity(discharge * M.OPACITY)
		else
			kit:opacity(alpha * M.OPACITY)
			fill, ccw, color = look.look(kind, share, rounds, empty, size, ready)
			if kind == "beamweapon" then
				-- A laser's heat fills the bar from its start, like a magazine, in a brighter yellow
				-- (the circle's counter-clockwise fill read upside down on a bar).
				ccw = false
				if empty then track = look.burn_track(t, clock) else color = look.heat_color(1 - share, t.phase, M.LASER) end
			elseif empty then
				track = look.flash(clock)
			end
		end
		-- The border reaches e past both ends, so the tips aren't bare.
		local over = e / (curved and R * M.SPAN or 2 * R * math.sin(M.SPAN / 2))
		kit:layer(419)
		band(f, -over, 1 + over, r1 - e, r2 + e, M.BORDER, cx, cy, false, curved)
		kit:layer(420)
		band(f, 0, 1, r1, r2, track or M.TRACK, cx, cy, false, curved)
		if fill > 0 then
			kit:layer(421)
			if ccw then band(f, 1 - fill, 1, r1, r2, color, cx, cy, true, curved)
			else band(f, 0, fill, r1, r2, color, cx, cy, true, curved) end
		end
		if rounds and not discharge and not rp then
			kit:layer(422)
			local lw = M.LINE_WIDTH * ring / R / M.SPAN -- the line's width as a share of the bar
			if not curved then lw = M.LINE_WIDTH * ring / (2 * R * math.sin(M.SPAN / 2)) end
			for _, at in ipairs(M.dividers(size)) do piece(f, at - lw / 2, at + lw / 2, r1, r2, M.LINE, cx, cy, false) end
		end
		if empty and (rounds or kind == "beamweapon") and not discharge and not rp then
			kit:layer(424)
			local room = 2 * (11 - M.WIDTH) * ring * 0.9
			local bx, by = f(0.5, r2 + e + M.BUTTON_GAP * ring + room / 2)
			look.draw_button(kit, look.reload_button(nil), bx, by, room)
		end
		kit:opacity(1)
	end

	obsidian.on_frame(function()
		if failed then return end
		local dt = rawget(_G, "ENGINE_DT") or 0.016
		clock = clock + dt
		local ok, err = pcall(frame, dt)
		if not ok then
			failed = true
			env.log("Eyes of Liberty: ammo bar stopped: " .. tostring(err))
		end
	end, env.VIEW)
end

return M
