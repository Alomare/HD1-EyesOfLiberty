-- Compass: in third person, a strip at the top of the screen in the look of Helldivers Arcade's level
-- bar (the HUD's basicbox_01 panel, 560 design pixels wide), thinner. It scrolls with the camera's
-- heading: the letters N, E, S and W on the cardinal points and a faint short line every TICK degrees,
-- a longer, brighter one on the 45s. A white arrow marks the middle, and the heading in degrees shows
-- under the strip in the game's body font. Objectives found on the map show at their bearing from the Helldiver, at any distance, with
-- their map icon; one still hidden in a search zone doesn't show. Bearings run clockwise from north
-- (+y), east being +x, as on the game's map.
--
-- The panel and the map icons are drawn on the HUD's own gui (Hud.hd_gui, in Hud.draw_plugins), as
-- the game's map and the edge markers draw them: the canvas can't draw map icons, and a panel drawn by
-- the canvas covered them (the canvas draws over the HUD's gui). The icons are white, as on the
-- minimap, and may stand out past the panel.
local radar = obsidian.module("src/radar")

local M = {}

M.W, M.H = 1920, 1080   -- design space, scaled and centred in the window
M.BOX = { w = 560, h = 30, top = 22, inset = 6 }
M.SPAN = 120            -- degrees across the strip
M.TICK = 5              -- degrees between ticks
M.ICON = 31             -- objective icon, design pixels
M.TICK_SHORT = 6        -- design pixels, a line
M.TICK_LONG = 11        -- on the 45s
M.ICON_LAYER = 470      -- the map icons on the HUD's gui, over the panel (PANEL_LAYER)
M.PANEL_LAYER = 466
M.ARROW = 12.25         -- design pixels, half the arrow's width
M.HEADING_SIZE = 22     -- design pixels
M.TICK_COLOR = "#ffffff58"
M.LONG_COLOR = "#ffffffb0"
M.LAYER = 465           -- under the hurt indicator (470)
M.TINT = "#ffffffcc"    -- the box, as the Arcade bar
M.FRAME = "#5d5c56"
M.GOLD = "#ffc433"
M.WHITE = "#ffffffff"
M.OUTLINE = "#000000ff"
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

-- The marks inside the span for a heading: { bearing, kind, label } with kind "letter", "long" (the
-- 45s between the letters) or "tick".
function M.marks(heading)
	local out = {}
	local first = floor((heading - M.SPAN / 2) / M.TICK) * M.TICK
	for b = first, heading + M.SPAN / 2 + M.TICK, M.TICK do
		local d = b % 360
		if math.abs(M.gap(heading, d)) <= M.SPAN / 2 then
			if M.LETTERS[d] then out[#out + 1] = { d, "letter", M.LETTERS[d] }
			elseif d % 45 == 0 then out[#out + 1] = { d, "long" }
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

-- The heading as shown under the strip: whole degrees, 0 to 359. No degree sign: the game's body font
-- has none.
function M.heading_text(heading)
	return tostring(floor(heading + 0.5) % 360)
end

-- The game -----------------------------------------------------------------------------------------

-- What to draw this frame on the HUD's gui, in window pixels: the panel ({ x, y, w, h, s }) and the
-- map icons ({ icon, x, y, size, alpha } each).
M.icons = nil
M.panel = nil

-- Draws M.panel and M.icons on the HUD's gui, at window pixels.
function M.draw_icons(hud)
	local list, gui, panel = M.icons, hud and hud.hd_gui, M.panel
	if not (gui and (panel or (list and #list > 0))) then return end
	local V2, V3, C = rawget(_G, "Vector2"), rawget(_G, "Vector3"), rawget(_G, "Color")
	gui:set_ignore_position_scale(true)
	gui:set_ignore_size_scale(true)
	local ok, err = pcall(function()
		if panel then
			local x, y, w, h, f = panel.x, panel.y, panel.w, panel.h, 2 * panel.s
			gui:image("basicbox_01", V3(x, y, M.PANEL_LAYER), V2(w, h), C(204, 255, 255, 255),
				V2(M.BOX_UV[1], M.BOX_UV[2]), V2(M.BOX_UV[3], M.BOX_UV[4]))
			local frame = C(255, 93, 92, 86)
			gui:rect(V3(x, y, M.PANEL_LAYER + 1), V2(w, f), frame)
			gui:rect(V3(x, y + h - f, M.PANEL_LAYER + 1), V2(w, f), frame)
			gui:rect(V3(x, y, M.PANEL_LAYER + 1), V2(f, h), frame)
			gui:rect(V3(x + w - f, y, M.PANEL_LAYER + 1), V2(f, h), frame)
		end
		for _, i in ipairs(list or {}) do
			gui:image(i.icon, V3(i.x - i.size / 2, i.y - i.size / 2, M.ICON_LAYER), V2(i.size, i.size), C(i.alpha, 255, 255, 255))
		end
	end)
	gui:set_ignore_position_scale(false)
	gui:set_ignore_size_scale(false)
	if not ok then error(err, 0) end
end

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

	local function text(str, x, y, size, color)
		local d = math.max(1, floor(size / 14))
		kit:text(str, x + d, y - d, { font = "body_large", size = size, align = "center", color = "#000000c0" })
		kit:text(str, x, y, { font = "body_large", size = size, align = "center", color = color })
	end

	local tri = { 0, 0, 0, 0, 0, 0 }

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
		M.panel = { x = x, y = y, w = bw, h = bh, s = s }
		local tx, tw = x + B.inset * s, bw - 2 * B.inset * s
		local mid, cy = tx + tw / 2, y + bh / 2
		local heading = M.bearing(view.forward.x, view.forward.y)

		kit:layer(M.LAYER + 2)
		kit:clip(tx, y, tw, bh, function()
			for _, m in ipairs(M.marks(heading)) do
				local px = mid + M.place(heading, m[1], tw)
				if m[2] == "letter" then
					text(m[3], px, cy - 7 * s, 20 * s, M.GOLD)
				else
					local long = m[2] == "long"
					local len = (long and M.TICK_LONG or M.TICK_SHORT) * s
					kit:rect(px - s, cy - len / 2, 2 * s, len, long and M.LONG_COLOR or M.TICK_COLOR)
				end
			end
		end)

		-- Objectives: inside the span at their bearing, past it held at the end, fainter. Drawn by the HUD.
		local me = api.game.my_unit and api.game.my_unit()
		local st = api.game.state and api.game.state()
		local mm = type(st) == "table" and st.mission_manager
		local V3A = g("Vector3Aux")
		local icons = {}
		if me and mm and mm.get_objectives and V3A then
			local p = g("Unit").world_position(me, 0)
			local size = M.ICON * s
			for _, o in ipairs(M.objectives(mm:get_objectives(), V3A.unbox)) do
				local off, inside = M.place(heading, M.bearing(o.x - p.x, o.y - p.y), tw)
				local half = tw / 2 - size / 2
				if off > half then off = half elseif off < -half then off = -half end
				icons[#icons + 1] = { icon = o.icon, x = mid + off, y = cy, size = size, alpha = inside and 255 or 130 }
			end
		end
		M.icons = icons

		-- The middle: a white arrow pointing down into the strip, with a thin soft outline.
		kit:layer(M.LAYER + 4)
		-- Equal sides: as tall as sqrt(3) / 2 of its width.
		local n = M.ARROW * s
		local tip = y + bh - 2 * s
		local base = tip + n * math.sqrt(3)
		tri[1], tri[2], tri[3], tri[4], tri[5], tri[6] = mid - n, base, mid + n, base, mid, tip
		kit:poly(tri, M.WHITE)
		kit:outline(tri, M.OUTLINE, 1.5 * s)
		-- The heading under the strip.
		local hs = M.HEADING_SIZE * s
		local d = math.max(1, floor(hs / 20))
		kit:text(M.heading_text(heading), mid + d, y - 6 * s - hs * 0.8 - d, { font = "body", size = hs, align = "center", color = "#000000c0" })
		kit:text(M.heading_text(heading), mid, y - 6 * s - hs * 0.8, { font = "body", size = hs, align = "center", color = M.WHITE })
	end

	obsidian.hook("Hud", "draw_plugins", function(original, self, ...)
		local r = { original(self, ...) }
		if M.icons then pcall(M.draw_icons, self) end
		return unpack(r)
	end, env.VIEW)

	local warned, wait = false, 0
	obsidian.on_frame(function()
		M.icons, M.panel = nil, nil
		if wait > 0 then wait = wait - 1 return end
		if not on or not env.state.active then return end
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return end
		if not M.shown(api) then return end
		local ok, err = pcall(draw, api)
		if not ok then
			M.icons, M.panel = nil, nil
			wait = 300
			if not warned then
				warned = true
				env.log("Eyes of Liberty: compass: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
