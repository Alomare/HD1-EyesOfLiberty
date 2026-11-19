-- The blocked shot mark. Shots start at the Helldiver, not at the camera (src/aim.lua), so over the
-- shoulder the crosshair can sit on a target while a rock or a wall in front of the weapon takes the
-- shot. When the way from the shot's start to the crosshair point meets something more than GAP metres
-- short of that point, a small plain red X marks where the shot would land. On foot only, while the
-- crosshair shows (src/crosshair.lua; drawn under another mod's crosshair too).
local rig = obsidian.module("src/rig")
local frustum = obsidian.module("src/frustum")
local crosshair = obsidian.module("src/crosshair")

local M = {}

local function g(name) return rawget(_G, name) end

M.GAP = 0.75          -- metres short of the crosshair point a hit must be to count as blocked
M.ORIGIN = { x = 0, y = 0, z = 1.5 } -- where shots start over the root until a weapon reports it
M.SIZE = 7            -- pixels at 1080 lines from the middle of the X to a tip
M.WIDTH = 2.2         -- pixels at 1080 lines, the stroke
M.COLOR = { 230, 40, 28 } -- the red of the game's warnings
M.LAYER = 505         -- over the crosshair (500)

-- Whether a unit belongs to this player (the body, or gear the Helldiver carries).
local function own(unit, view)
	if unit == nil then return false end
	if unit == view.avatar or unit == view.target then return true end
	local EA = g("EntityAux")
	local ok, wielder = pcall(function()
		if EA.has_component(unit, "equipment") then return EA.state(unit, "equipment").wielder end
		return nil
	end)
	return ok and wielder ~= nil and wielder == view.avatar
end

-- The point where a shot from `origin` to `point` is stopped, given the hits along that way as
-- { distance, unit, position } (own ones already left out), or nil when nothing stops it more than
-- GAP metres short.
function M.stop(origin, point, hits)
	local length = rig.length(rig.sub(point, origin))
	if length < 1.5 then return nil end
	local best, best_d = nil, length - M.GAP
	for _, h in ipairs(hits or {}) do
		if type(h.distance) == "number" and h.distance > 0.05 and h.distance < best_d then
			best, best_d = h.position, h.distance
		end
	end
	return best
end

-- The X's two strokes, centred on (x, y), for a screen h pixels tall: { x1, y1, x2, y2 } each.
function M.strokes(x, y, h)
	local s = M.SIZE * h / 1080
	return { { x - s, y - s, x + s, y + s }, { x - s, y + s, x + s, y - s } }
end

-- The hits along the way from `origin` to `point`, for M.stop.
local function cast(view, origin, point)
	local PW, V3, W, Actor = g("PhysicsWorld"), g("Vector3"), g("World"), g("Actor")
	local d = rig.sub(point, origin)
	local length = rig.length(d)
	if length < 1.5 then return {} end
	local n = rig.normalize(d)
	local hits = PW.immediate_raycast(W.physics_world(view.world), V3(origin.x, origin.y, origin.z), V3(n.x, n.y, n.z),
		length, "all", "collision_filter", "damage_ray")
	local out = {}
	if type(hits) == "table" then
		for _, h in ipairs(hits) do
			local pos, distance, actor = h[1], h[2], h[4]
			local unit = actor and Actor and Actor.unit(actor)
			if pos and not own(unit, view) then
				out[#out + 1] = { distance = distance, position = { x = pos.x, y = pos.y, z = pos.z } }
			end
		end
	end
	return out
end

function M.start(env)
	local state = env.state
	local aim = obsidian.module("src/aim")
	state.blocked = nil
	table.insert(env.on_pose, function(view)
		state.blocked = nil
		if view.watching or view.vehicle or env.config.get("blocked_shot") == false then return end
		local point = state.aim_point
		if not point or not view.avatar then return end
		local p = g("Unit").world_position(view.avatar, 0)
		local o = aim.shot_offset or M.ORIGIN
		local origin = { x = p.x + o.x, y = p.y + o.y, z = p.z + o.z }
		state.blocked = M.stop(origin, point, cast(view, origin, point))
	end)
	table.insert(env.on_release, function() state.blocked = nil end)

	local ui = obsidian.ui
	if type(ui) ~= "table" or type(ui.canvas) ~= "function" then return end
	local kit = ui.canvas("eyesofliberty_blocked", { layer = M.LAYER })
	if not kit then return end
	local quad = { 0, 0, 0, 0, 0, 0, 0, 0 }
	local failed = false
	obsidian.on_frame(function()
		if failed then return end
		local ok, err = pcall(function()
			local at, view = state.blocked, env.view
			if not (at and view and state.active and not state.vehicle) then return end
			-- The X shows with the crosshair, whoever draws it.
			local claimed = state.claimed_by
			state.claimed_by = nil
			local shown = crosshair.visible(env, crosshair.always_on())
			state.claimed_by = claimed
			if not shown then return end
			local cm = g("CameraManager")
			local w, h, x0, y0 = cm.viewport:window()
			if not (w and h and w > 0 and h > 0) then return end
			local cam = frustum.camera_from(view.position, view.forward, math.rad(view.fov or 70))
			local x, depth, y = frustum.project(cam, at, w, h)
			if not (x and depth and depth > 0.1) then return end
			x, y = (x0 or 0) + x, (y0 or 0) + y
			local half = M.WIDTH * h / 1080 / 2
			local a = math.floor(255 * math.max(0, math.min(1, state.sprint_fade or 1)) + 0.5)
			local color = { M.COLOR[1], M.COLOR[2], M.COLOR[3], a }
			kit:layer(M.LAYER)
			for _, s in ipairs(M.strokes(x, y, h)) do
				local dx, dy = s[3] - s[1], s[4] - s[2]
				local len = math.sqrt(dx * dx + dy * dy)
				local px, py = -dy / len * half, dx / len * half
				quad[1], quad[2], quad[3], quad[4] = s[1] + px, s[2] + py, s[3] + px, s[4] + py
				quad[5], quad[6], quad[7], quad[8] = s[3] - px, s[4] - py, s[1] - px, s[2] - py
				kit:poly(quad, color)
			end
		end)
		if not ok then
			failed = true
			env.log("Eyes of Liberty: blocked shot mark stopped: " .. tostring(err))
		end
	end, env.VIEW)
end

return M
