-- Compass: in third person, a strip at the top of the screen in the look of Helldivers Arcade's level
-- bar (the HUD's basicbox_01 panel, 560 by 48 design pixels, with a dark trough inside). It scrolls
-- with the camera's heading: the letters N, E, S and W on the cardinal points, the bearing in degrees
-- on the four points between, and a tick every TICK degrees. Objectives found on the map show at their
-- bearing from the Helldiver, at any distance, with their map icon; one still hidden in a search zone
-- doesn't show. Bearings run clockwise from north (+y), east being +x, as on the game's map.
local radar = obsidian.module("src/radar")

local M = {}

M.W, M.H = 1920, 1080   -- design space, scaled and centred in the window
M.BOX = { w = 560, h = 48, top = 18, trough = 26, inset = 14 }
M.SPAN = 120            -- degrees across the trough
M.TICK = 15             -- degrees between ticks
M.ICON = 24             -- objective icon, design pixels
M.LAYER = 465           -- under the hurt indicator (470)
M.TINT = "#ffffffcc"    -- the box, as the Arcade bar
M.TROUGH = "#000000b0"
M.FRAME = "#5d5c56"
M.GOLD = "#ffc433"
M.TEXT = "#d4d2cb"
M.LETTERS = { [0] = "N", [90] = "E", [180] = "S", [270] = "W" }
M.BOX_UV = { 0.25, 0.01, 0.75, 0.99 }

local atan2, deg, floor = math.atan2, math.deg, math.floor

-- Pure parts ----------------------------------------------------------------------------------------

-- The bearing of a direction over the ground, degrees from 0 to 360 clockwise from north.
function M.bearing(dx, dy)
	return deg(atan2(dx, dy)) % 360
end

-- The signed gap from bearing a to bearing b, -180 to 180: positive is clockwise (to the right).
function M.gap(a, b)
	return (b - a + 180) % 360 - 180
end

-- Where a bearing sits across a trough `width` wide for a heading: pixels from the trough's middle,
-- and whether it's inside the span.
function M.place(heading, bearing, width)
	local g = M.gap(heading, bearing)
	return g / M.SPAN * width, math.abs(g) <= M.SPAN / 2
end

-- The marks inside the span for a heading: { bearing, kind, label } with kind "letter", "number" or
-- "tick". Numbers on the 45s between the letters, ticks on the rest.
function M.marks(heading)
	local out = {}
	local first = floor((heading - M.SPAN / 2) / M.TICK) * M.TICK
	for b = first, heading + M.SPAN / 2 + M.TICK, M.TICK do
		local d = b % 360
		if math.abs(M.gap(heading, d)) <= M.SPAN / 2 then
			if M.LETTERS[d] then out[#out + 1] = { d, "letter", M.LETTERS[d] }
			elseif d % 45 == 0 then out[#out + 1] = { d, "number", tostring(d) }
			else out[#out + 1] = { d, "tick" } end
		end
	end
	return out
end

-- The objectives to show from a MissionManager's list: found (no objective_hidden_data) and not done,
-- each place once ({ x, y, icon }). unbox turns a stored position into a vector.
function M.objectives(list, unbox)
	local out = {}
	for _, o in ipairs(list or {}) do
		if type(o) == "table" and o.icon and o.objective_hidden_data == nil and o.state ~= "complete"
			and o.state ~= "failed" and type(o.position) == "table" then
			for _, box in ipairs(o.position) do
				local ok, p = pcall(unbox, box)
				if ok and p then out[#out + 1] = { x = p.x, y = p.y, icon = o.icon } end
			end
		end
	end
	return out
end

-- The game -----------------------------------------------------------------------------------------

local function g(name) return rawget(_G, name) end

-- Whether the HUD shows: not paused, no menu over it, the map shut, no photo being taken. The pings
-- (src/ping.lua) ask the same.
function M.shown(api)
	local ui = obsidian.ui
	if radar.paused and radar.paused(api) then return false end
	if type(ui) == "table" and ui.current then
		local ok, cur = pcall(ui.current)
		if ok and type(cur) == "table" and cur.screen ~= "hud" then return false end
	end
	if api.map and api.map.is_open then
		local ok, open = pcall(api.map.is_open)
		if ok and open then return false end
	end
	if api.capture and api.capture.busy then
		local ok, busy = pcall(api.capture.busy)
		if ok and busy then return false end
	end
	return true
end

function M.start(env)
	local ui = obsidian.ui
	if type(ui) ~= "table" or type(ui.canvas) ~= "function" then return end
	local kit = ui.canvas("eyesofliberty_compass", { layer = M.LAYER })
	if not kit then return end
	local on = env.config.get("compass") ~= false
	if env.config.on_change then env.config.on_change("compass", function(v) on = v ~= false end) end

	local function text(s, x, y, size, color)
		local d = math.max(1, floor(size / 14))
		kit:text(s, x + d, y - d, { font = "body_large", size = size, align = "center", color = "#000000c0" })
		kit:text(s, x, y, { font = "body_large", size = size, align = "center", color = color })
	end

	local tri = { 0, 0, 0, 0, 0, 0 }
	local diamond = { 0, 0, 0, 0, 0, 0, 0, 0 }

	local function draw(api)
		local view = env.view
		local cm = g("CameraManager")
		if not (view and view.forward and cm and cm.viewport) then return end
		local w, h = cm.viewport:window()
		if not (w and h and w > 0 and h > 0) then return end
		local s = math.min(w / M.W, h / M.H)
		local ox, oy = (w - M.W * s) / 2, (h - M.H * s) / 2
		local B = M.BOX
		local bw, bh = B.w * s, B.h * s
		local x, y = ox + (M.W - B.w) / 2 * s, oy + (M.H - B.top - B.h) * s
		kit:layer(M.LAYER)
		if not kit:icon("basicbox_01", x, y, bw, bh, M.TINT, M.BOX_UV) then
			kit:rect(x, y, bw, bh, "#1e1e1c")
			kit:rect(x, y + bh * 0.45, bw, bh * 0.55, "#2b2b28")
		end
		kit:layer(M.LAYER + 1)
		local f = 2 * s
		kit:rect(x, y, bw, f, M.FRAME)
		kit:rect(x, y + bh - f, bw, f, M.FRAME)
		kit:rect(x, y, f, bh, M.FRAME)
		kit:rect(x + bw - f, y, f, bh, M.FRAME)
		local tx, tw, th = x + B.inset * s, bw - 2 * B.inset * s, B.trough * s
		local ty = y + (bh - th) / 2
		kit:rect(tx, ty, tw, th, M.TROUGH)
		local mid = tx + tw / 2
		local heading = M.bearing(view.forward.x, view.forward.y)

		kit:layer(M.LAYER + 2)
		kit:clip(tx, ty, tw, th, function()
			for _, m in ipairs(M.marks(heading)) do
				local px = mid + M.place(heading, m[1], tw)
				if m[2] == "letter" then
					text(m[3], px, ty + 6 * s, 22 * s, M.GOLD)
				elseif m[2] == "number" then
					text(m[3], px, ty + 7 * s, 17 * s, M.TEXT)
				else
					kit:rect(px - s, ty + 2 * s, 2 * s, 6 * s, "#ffffff80")
					kit:rect(px - s, ty + th - 8 * s, 2 * s, 6 * s, "#ffffff80")
				end
			end
		end)

		-- Objectives, over the marks: inside the span at their bearing, past it held at the end, fainter.
		local me = api.game.my_unit and api.game.my_unit()
		local st = api.game.state and api.game.state()
		local mm = type(st) == "table" and st.mission_manager
		local V3A = g("Vector3Aux")
		if me and mm and mm.get_objectives and V3A then
			local p = g("Unit").world_position(me, 0)
			local size = M.ICON * s
			kit:layer(M.LAYER + 3)
			for _, o in ipairs(M.objectives(mm:get_objectives(), V3A.unbox)) do
				local off, inside = M.place(heading, M.bearing(o.x - p.x, o.y - p.y), tw)
				local half = tw / 2 - size / 2
				if off > half then off = half elseif off < -half then off = -half end
				local cx, cy = mid + off, ty + th / 2
				local color = inside and "#ffffffff" or "#ffffff80"
				if not kit:icon(o.icon, cx - size / 2, cy - size / 2, size, size, color) then
					local r = size * 0.35
					diamond[1], diamond[2], diamond[3], diamond[4] = cx, cy + r, cx + r, cy
					diamond[5], diamond[6], diamond[7], diamond[8] = cx, cy - r, cx - r, cy
					kit:poly(diamond, color)
				end
			end
		end

		-- The heading: a gold notch over the middle of the box.
		local n = 7 * s
		tri[1], tri[2], tri[3], tri[4], tri[5], tri[6] = mid - n, y + bh + n, mid + n, y + bh + n, mid, y + bh - s
		kit:poly(tri, M.GOLD)
	end

	local warned, wait = false, 0
	obsidian.on_frame(function()
		if wait > 0 then wait = wait - 1 return end
		if not on or not env.state.active then return end
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return end
		if not M.shown(api) then return end
		local ok, err = pcall(draw, api)
		if not ok then
			wait = 300
			if not warned then
				warned = true
				env.log("Eyes of Liberty: compass: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
