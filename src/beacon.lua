-- Beacon icon: in third person, with the crosshair on the light beam of a stratagem beacon, the
-- stratagem's icon shows on the beam at the height of the crosshair, held within the beam: it follows
-- the aim up and down and stays on the beam's line.
--
-- The beacons are the ones the edge markers mark (src/edge.lua gather: counting down, beam up), with the
-- same icon at SIZE of theirs, on the HUD gui (Hud.hd_gui). The beam is taken as BEAM metres straight
-- up from the beacon. Of the beams the crosshair is within NEAR design pixels of, the nearest shows,
-- whole within CORE pixels and fading out past it (M.opacity).
local frustum = obsidian.module("src/frustum")
local edge = obsidian.module("src/edge")

local M = {}

local function g(name) return rawget(_G, name) end

M.BEAM = 25           -- metres of beam above the beacon
M.NEAR = 40           -- design pixels (1280 x 720) from the beam that count as on it
M.CORE = 12           -- design pixels from the beam within which the icon is whole; past it the
                      -- icon fades out toward NEAR (the user: one fully opaque range was too wide)
M.SIZE = 0.7          -- of the countdown list's icon size (the user: 30 percent smaller)
M.FADE = 12           -- how fast the icon follows its opacity

-- How strong the icon shows with the crosshair `off` design pixels from the beam: 1 within CORE,
-- down to 0 at NEAR.
function M.opacity(off)
	if off <= M.CORE then return 1 end
	if off >= M.NEAR then return 0 end
	return 1 - (off - M.CORE) / (M.NEAR - M.CORE)
end
M.LAYER = 98
M.PAUSE = 300         -- frames without the icon after an error

-- The point of a beam seen on screen from (bx, by) at the beacon to (tx, ty) at the top that is at the
-- crosshair's height (cy), held within the two ends; and how far the crosshair (cx, cy) is from it.
-- A straight line stays straight on screen, so the beam's points lie on that segment.
function M.on_beam(bx, by, tx, ty, cx, cy)
	local dy = ty - by
	local t = math.abs(dy) > 1e-6 and (cy - by) / dy or 0
	t = math.max(0, math.min(1, t))
	local x, y = bx + (tx - bx) * t, by + dy * t
	return x, y, math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2), t
end

-- The highest part of the beam in front of the camera: from `top` metres down, halving, until the top
-- stands in front (depth over 0.3 m). Answers its screen x, y, or nil when even the base is behind.
local function top_in_view(cam, p, top, w, h)
	local m = top
	while m > 0.5 do
		local sx, depth, sy = frustum.project(cam, { x = p.x, y = p.y, z = p.z + m }, w, h)
		if depth > 0.3 then return sx, sy end
		m = m / 2
	end
	return nil
end

M.shown = nil -- { unit, alpha, icon, x, y } of the icon drawn

-- Picks the beam the crosshair is on and draws its icon.
function M.draw(hud, env, dt)
	local gui = hud.hd_gui
	local view, state = env.view, env.state
	local cm = g("CameraManager")
	if not (gui and view and view.position and view.forward and cm and cm.viewport) then return end
	local c = state.crosshair
	local w, h = cm.viewport:window()
	if not (w and h and w > 0 and h > 0) then return end
	local cam = frustum.camera_from(view.position, view.forward, math.rad(view.fov or 70))
	local scale = gui.ui_scale or h / 720
	local best = nil
	if c and state.armed ~= false then
		edge.gather(hud, env.api, function(kind, p, icon, iw, ih)
			if kind ~= "thing" then return end
			local bx, depth, by = frustum.project(cam, p, w, h)
			if depth <= 0.3 then return end
			local tx, ty = top_in_view(cam, p, M.BEAM, w, h)
			if not tx then return end
			local x, y, off = M.on_beam(bx, by, tx, ty, c.x, c.y)
			if off <= M.NEAR * scale and (not best or off < best.off) then
				best = { off = off, x = x, y = y, icon = icon, iw = iw, ih = ih, key = icon .. string.format("%.0f %.0f", p.x, p.y) }
			end
		end)
	end
	local s = M.shown
	if best then
		if not s or s.key ~= best.key then s = { key = best.key, alpha = 0 } end
		s.icon, s.x, s.y = best.icon, best.x, best.y
		s.iw, s.ih = best.iw * M.SIZE, best.ih * M.SIZE
		local want = M.opacity(best.off / scale)
		local step = (dt or 0.016) * M.FADE
		s.alpha = s.alpha < want and math.min(want, s.alpha + step) or math.max(want, s.alpha - step)
		if s.alpha <= 0 and want <= 0 then s = nil end
	elseif s then
		s.alpha = s.alpha - (dt or 0.016) * M.FADE
		if s.alpha <= 0 then s = nil end
	end
	M.shown = s
	if not s or s.alpha <= 0 then return end
	local V2, V3, C = g("Vector2"), g("Vector3"), g("Color")
	gui:set_ignore_position_scale(true)
	gui:set_ignore_size_scale(false)
	gui:image(s.icon, V3(s.x - s.iw * scale / 2, s.y - s.ih * scale / 2, M.LAYER), V2(s.iw, s.ih),
		C(math.floor(255 * s.alpha + 0.5), 255, 255, 255))
	gui:set_ignore_position_scale(false)
end

function M.start(env)
	local on = env.config.get("beacon_icon") ~= false
	env.config.on_change("beacon_icon", function(v) on = v ~= false end)
	local warned, wait = false, 0
	obsidian.hook("Hud", "draw_plugins", function(original, self, dt, ...)
		local r = { original(self, dt, ...) }
		if wait > 0 then
			wait = wait - 1
		elseif on and env.state.active and not env.state.watching then
			local api = env.api
			if api and api.game and api.game.in_mission and api.game.in_mission() then
				local ok, err = pcall(M.draw, self, env, type(dt) == "number" and dt or 1 / 60)
				if not ok then
					wait = M.PAUSE
					M.shown = nil
					pcall(self.hd_gui.set_ignore_position_scale, self.hd_gui, false)
					if not warned then
						warned = true
						env.log("Eyes of Liberty: beacon icon: " .. tostring(err))
					end
				end
			end
		else
			M.shown = nil
		end
		return unpack(r)
	end, env.VIEW)
end

return M
