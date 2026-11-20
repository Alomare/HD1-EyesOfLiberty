-- Alarm: while an alarm is up, the game puts a red overlay on the camera (the camera particle
-- "effects/camera_alarm", from the flow callback camera_particles_start, on every machine). The
-- particle is sized for the top-down view, and widened for the shoulder view (src/camera.lua) it
-- still came out shrunk now and then. So in third person the game's overlay is kept out of sight
-- (linked at a scale of nothing, put back as it was in the top-down view) and this one shows instead:
--   - the screen edges throb red ("eol_hurt" of the mod's art), a sharp beat and a slow fall, as a siren;
--   - broad red hazard stripes run up each side of the screen, strongest at the edge and fading out
--     toward the middle: at full strength as the alarm sounds, down to REST of it over SETTLE seconds.
-- It fades in over FADE_IN seconds when the alarm starts and out over FADE_OUT when it ends. The compass
-- (src/compass.lua) turns dark red for as long as M.level is up.
-- The overlay is the Alarm effect option; off, the game's own overlay shows as before.
local art = obsidian.module("src/art")

local M = {}

M.COLOR = { 205, 18, 12 }     -- the throb at the edges
M.STRIPE = { 200, 18, 12 }    -- the hazard stripes
M.STRIPE_ALPHA = 200          -- out of 255, a stripe at the screen edge at full strength
M.BEAT = 1.1                  -- seconds from one beat to the next
M.ATTACK = 0.12               -- share of a beat taken by the rise
M.EDGE_LOW, M.EDGE_HIGH = 70, 200 -- alpha of the edges between beats and at a beat, out of 255
M.BAND = 150                  -- design pixels, how far in from the edge the stripes reach
M.SLICES = 10                 -- steps of the fade from the edge to the inside of a band
M.PERIOD = 80                 -- design pixels from one stripe to the next
M.WIDTH = 36                  -- design pixels, a stripe
M.SCROLL = 40                 -- design pixels a second the stripes move
M.REST, M.SETTLE = 0.2, 5     -- the stripes settle to REST of full strength over SETTLE seconds
M.FADE_IN, M.FADE_OUT = 0.1, 0.8
M.EDGE_LAYER = 57             -- the art gui, under the hurt flash (60)
M.LAYER = 450                 -- the bands, on the canvas under the compass (465)
M.H = 1080

M.level = 0                   -- 0 to 1: how far the effect has faded in
M.clock = 0
M.since = 0                   -- seconds since the alarm sounded
M.was_up = false

-- Whether a camera particle's effect is the alarm.
function M.is_alarm(effect)
	return type(effect) == "string" and effect:find("alarm", 1, true) ~= nil
end

-- Whether a camera particle of the alarm is up: src/camera.lua marks them in camera.particles, and the
-- game's CameraManager keeps the live ones in camera_particles (dropping one that stopped playing).
function M.up(particles, live)
	for name, info in pairs(particles or {}) do
		if info.alarm and (live == nil or live[name] ~= nil) then return true end
	end
	return false
end

-- The beat at `t` seconds, 0 to 1: a quick rise, then a slow fall.
function M.beat(t)
	local f = (t % M.BEAT) / M.BEAT
	if f < M.ATTACK then return f / M.ATTACK end
	local d = 1 - (f - M.ATTACK) / (1 - M.ATTACK)
	return d * d
end

-- The level eased toward on (1) or off (0) by dt.
function M.ease(level, on, dt)
	if on then return math.min(1, level + dt / M.FADE_IN) end
	return math.max(0, level - dt / M.FADE_OUT)
end

-- How strong the stripes show `since` seconds after the alarm sounded: 1, down to REST over SETTLE.
function M.stripe_strength(since)
	local t = math.max(0, math.min(1, (since or 0) / M.SETTLE))
	return 1 - (1 - M.REST) * t
end

-- The share of the stripe alpha in slice i of n, counted from the screen edge: from nearly 1 at the edge
-- down to nearly 0 at the inside of the band.
function M.slice_alpha(i, n)
	return 1 - (i - 0.5) / n
end

-- Clips a convex polygon { x1, y1, ... } to the box x0..x1, y0..y1 (Sutherland-Hodgman).
function M.clip(pts, x0, y0, x1, y1)
	local function pass(input, inside, cross)
		local out = {}
		local n = #input / 2
		if n == 0 then return out end
		local px, py = input[n * 2 - 1], input[n * 2]
		local pin = inside(px, py)
		for i = 1, n do
			local x, y = input[i * 2 - 1], input[i * 2]
			local cin = inside(x, y)
			if cin then
				if not pin then local ix, iy = cross(px, py, x, y) out[#out + 1] = ix out[#out + 1] = iy end
				out[#out + 1] = x out[#out + 1] = y
			elseif pin then
				local ix, iy = cross(px, py, x, y) out[#out + 1] = ix out[#out + 1] = iy
			end
			px, py, pin = x, y, cin
		end
		return out
	end
	local function at_x(e) return function(ax, ay, bx, by) local t = (e - ax) / (bx - ax) return e, ay + (by - ay) * t end end
	local function at_y(e) return function(ax, ay, bx, by) local t = (e - ay) / (by - ay) return ax + (bx - ax) * t, e end end
	local p = pass(pts, function(x) return x >= x0 end, at_x(x0))
	p = pass(p, function(x) return x <= x1 end, at_x(x1))
	p = pass(p, function(_, y) return y >= y0 end, at_y(y0))
	p = pass(p, function(_, y) return y <= y1 end, at_y(y1))
	return p
end

-- The stripes over the box (x, y, w, h), slanted 45 degrees, `period` apart and `width` wide, moved
-- along by `offset`: convex polygons { x1, y1, ... } clipped to the box.
function M.stripes(x, y, w, h, period, width, offset)
	local out = {}
	local start = (offset % period) - period - h
	for s = start, w + period, period do
		local poly = { x + s, y, x + s + width, y, x + s + width + h, y + h, x + s + h, y + h }
		local c = M.clip(poly, x, y, x + w, y + h)
		if #c >= 6 then out[#out + 1] = c end
	end
	return out
end

function M.start(env)
	local camera = obsidian.module("src/camera")
	local config = env.config
	local on = config.get("alarm_effect") ~= false
	camera.hide_alarm = on
	if config.on_change then
		config.on_change("alarm_effect", function(v)
			on = v ~= false
			camera.hide_alarm = on
		end)
	end
	local ui = obsidian.ui
	local kit = type(ui) == "table" and type(ui.canvas) == "function" and ui.canvas("eyesofliberty_alarm", { layer = M.LAYER }) or nil

	local function shown(api)
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return false end
		local compass = obsidian.module("src/compass")
		return compass.shown(api)
	end

	local function draw(api, dt)
		local cm = rawget(_G, "CameraManager")
		if not (cm and cm.viewport) then return end
		local w, h, x0, y0 = cm.viewport:window()
		if not (w and h and w > 0 and h > 0) then return end
		x0, y0 = x0 or 0, y0 or 0
		local s = h / M.H
		local beat = M.beat(M.clock)
		local level = M.level
		-- The edges throb.
		local gui = art.gui()
		if gui then
			local a = (M.EDGE_LOW + (M.EDGE_HIGH - M.EDGE_LOW) * beat) * level
			local c = M.COLOR
			art.draw(gui, "eol_hurt", x0, y0, w, h, M.EDGE_LAYER, math.floor(a + 0.5), c[1], c[2], c[3])
		end
		if not kit then return end
		-- Red stripes up each side, moving up, cut into slices that fade from the edge inward.
		local band = M.BAND * s
		local strength = M.STRIPE_ALPHA * M.stripe_strength(M.since) * level
		if strength < 1 then return end
		local offset = M.clock * M.SCROLL * s
		local n, piece = M.SLICES, band / M.SLICES
		local color = { M.STRIPE[1], M.STRIPE[2], M.STRIPE[3], 0 }
		kit:layer(M.LAYER)
		for side = 0, 1 do
			local bx = side == 0 and x0 or x0 + w - band
			local list = M.stripes(bx, y0, band, h, M.PERIOD * s, M.WIDTH * s, side == 0 and offset or -offset)
			for i = 1, n do
				color[4] = math.floor(strength * M.slice_alpha(i, n) + 0.5)
				if color[4] > 0 then
					local sx0 = side == 0 and bx + (i - 1) * piece or bx + band - i * piece
					for _, poly in ipairs(list) do
						local c = M.clip(poly, sx0, y0, sx0 + piece, y0 + h)
						if #c >= 6 then kit:poly(c, color) end
					end
				end
			end
		end
	end

	local warned = false
	obsidian.on_frame(function()
		local dt = rawget(_G, "ENGINE_DT")
		dt = type(dt) == "number" and dt > 0 and math.min(dt, 0.1) or 1 / 60
		local active = on and env.state.active and not env.state.watching
		local cm = rawget(_G, "CameraManager")
		local live = type(cm) == "table" and type(cm.camera_particles) == "table" and cm.camera_particles or nil
		local up = active and M.up(camera.particles, live)
		if up and not M.was_up then M.since = 0 end
		M.was_up = up and true or false
		M.level = M.ease(M.level, up, dt)
		if M.level <= 0 then M.clock = 0 return end
		M.clock = M.clock + dt
		M.since = M.since + dt
		local api = env.api
		if not active or not shown(api) then return end
		local ok, err = pcall(draw, api, dt)
		if not ok and not warned then
			warned = true
			env.log("Eyes of Liberty: alarm effect: " .. tostring(err))
		end
	end, env.VIEW)
	table.insert(env.on_release, function() M.level, M.clock, M.since, M.was_up = 0, 0, 0, false end)
end

return M
