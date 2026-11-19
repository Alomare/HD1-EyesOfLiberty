-- Pings: in third person, the ping key marks what the crosshair is on, for LIFE seconds. A player
-- can ping BURST times in a row, then waits COOLDOWN seconds; COOLDOWN without a ping starts a new burst. A marker is a vertical line with a diamond on top, drawn
-- over the level; one out of view sits at the edge of the screen. Aiming near a marker shows what it
-- marks above it and how far it is below it. Each player has one marker at a time: a new ping replaces the last.
--
-- What the crosshair is on decides the marker and its words:
--   enemy                  red, above the enemy and following it      "<enemy>, <metres from the caller> m"
--   objective (found)      yellow, over the objective                 "<objective> here"
--   support weapon, pack   blue line, the stratagem's icon on top     "<stratagem, without its code> here"
--   anything else          white, on the spot                         "Look here"
--
-- Nothing goes through the game's chat, which players without the mod would read with no marker to
-- go with it. Teammates with the mod get the marker through lobby member data (api.lobby.share, about
-- a second late): "<count>|<kind>|<x>|<y>|<z>|<icon>|<words>". Each machine with the mod plays the
-- chat's sound (TextChat.play_chat_sound, "ui_radio_chat") as a ping comes up, its own or a teammate's;
-- players without the mod hear and see nothing.
local frustum = obsidian.module("src/frustum")
local edge = obsidian.module("src/edge")
local compass = obsidian.module("src/compass")

local M = {}

M.LIFE = 7              -- seconds a marker shows
M.FADE = 1              -- its last second fades out
M.BURST = 3             -- pings in a row before the cooldown
M.COOLDOWN = 2.5        -- seconds of wait after a burst
M.GROW = 0.3            -- seconds for the line to rise
M.POP = 0.25            -- seconds for the diamond to settle
M.LINE = 2.5            -- metres of line over the spot
M.ABOVE_ENEMY = 2.2     -- metres over an enemy's root for its diamond, when its box can't be read
M.OVER_BOX = 0.15       -- metres over the top of an enemy's bounding box for its diamond
M.ENEMY_REACH = 4       -- metres from the crosshair point an enemy counts as aimed at
M.PICKUP_REACH = 2.5    -- the same for a weapon or pack on the ground
M.OBJECTIVE_REACH = 12  -- the same, over the ground, for an objective
M.DIAMOND = 10.4        -- design pixels from the middle of the diamond to a corner
M.ICON = 30             -- design pixels, a stratagem icon
M.HOVER = 70            -- design pixels from the crosshair that bring up the words
M.TEXT = 20             -- design pixels, the words' size
M.ENEMY_TEXT = { 255, 178, 170 } -- an enemy's name: light red
M.PULSE_LIGHT = 0.2     -- the dash up the line: the marker's colour this much toward white
M.INSET = 30            -- design pixels from the screen edge for a marker out of view
M.POLL = 0.25           -- seconds between two looks at what teammates share
M.LAYER = 475
M.SHARE = "ping"
M.COLORS = {
	ground = { 255, 255, 255 },
	enemy = { 235, 45, 35 },
	objective = { 255, 196, 51 },
	support = { 80, 165, 255 },
}

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min

-- Pure parts ----------------------------------------------------------------------------------------

-- A stratagem name without its code: "MG-94 Machine Gun" is "Machine Gun". Words with a digit at the
-- start of the name go, as long as a word stays.
function M.trim(name)
	if type(name) ~= "string" then return "" end
	local words = {}
	for w in name:gmatch("%S+") do words[#words + 1] = w end
	while #words > 1 and words[1]:find("%d") do table.remove(words, 1) end
	return table.concat(words, " ")
end

-- A name in capitals as the game's enemy list keeps it, as a word: "BILE SPEWER" is "Bile Spewer".
function M.title(name)
	if type(name) ~= "string" then return "" end
	return (name:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- The words of a ping.
function M.message(kind, name, metres)
	if kind == "enemy" then return string.format("%s, %d m", name or "Enemy", floor((metres or 0) + 0.5)) end
	if kind == "objective" or kind == "support" then return (name or "Objective") .. " here" end
	return "Look here"
end

local function clean(s) return (tostring(s or ""):gsub("|", "/")) end

function M.encode(count, kind, p, icon, words)
	return string.format("%d|%s|%.1f|%.1f|%.1f|%s|%s", count, kind, p.x, p.y, p.z, clean(icon), clean(words)):sub(1, 200)
end

function M.decode(s)
	if type(s) ~= "string" then return nil end
	local count, kind, x, y, z, icon, words = s:match("^(%d+)|(%a+)|([-%d.]+)|([-%d.]+)|([-%d.]+)|([^|]*)|(.*)$")
	if not count or not M.COLORS[kind] then return nil end
	return { count = tonumber(count), kind = kind, pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) },
		icon = icon ~= "" and icon or nil, words = words }
end

-- How strong a marker shows at `age`: full, then fading over its last FADE seconds.
function M.alpha(age)
	if age < 0 or age >= M.LIFE then return 0 end
	if age > M.LIFE - M.FADE then return (M.LIFE - age) / M.FADE end
	return 1
end

-- Whether a ping may go out at `now`, for the burst state `b` ({ count, last, until }), which it
-- updates: BURST pings in a row, then COOLDOWN seconds of wait.
function M.allow(b, now)
	if b.wait and now < b.wait then return false end
	if not b.last or now - b.last >= M.COOLDOWN then b.count = 0 end
	b.count, b.last = (b.count or 0) + 1, now
	if b.count >= M.BURST then b.count, b.wait = 0, now + M.COOLDOWN end
	return true
end

-- How far up the line has risen at `age`, 0 to 1, easing out.
function M.rise(age)
	local t = min(1, max(0, age / M.GROW))
	return 1 - (1 - t) * (1 - t)
end

-- The diamond's size at `age`: popping from POP_SIZE times down to 1.
function M.pop(age)
	local t = min(1, max(0, age / M.POP))
	return 1 + 0.6 * (1 - t) * (1 - t)
end

-- The nearest of `list` (each { x, y, z } under `at`, or the item itself) to p within `reach`, over the
-- ground when `flat`.
function M.nearest(list, p, reach, at, flat)
	local best, best_d = nil, reach
	for _, item in ipairs(list or {}) do
		local q = at and item[at] or item
		if q then
			local dx, dy, dz = q.x - p.x, q.y - p.y, flat and 0 or (q.z - p.z)
			local d = sqrt(dx * dx + dy * dy + dz * dz)
			if d <= best_d then best, best_d = item, d end
		end
	end
	return best, best and best_d or nil
end

-- The name over a marker: what was pinged, from its own name or from its words. Nothing for the
-- ground.
function M.label(kind, name, words)
	if kind == "ground" then return nil end
	if name and name ~= "" then return name end
	if type(words) ~= "string" then return nil end
	if kind == "enemy" then return words:match("^(.-), %d+ m$") end
	return words:match("^(.-) here$") or words
end

-- A colour this share of the way toward white.
function M.lighter(c, share)
	return { c[1] + (255 - c[1]) * share, c[2] + (255 - c[2]) * share, c[3] + (255 - c[3]) * share }
end

-- The game -----------------------------------------------------------------------------------------

local function g(name) return rawget(_G, name) end

local function v3(p) return g("Vector3")(p.x, p.y, p.z) end

-- How far over its root an enemy's diamond sits: just over the top of its bounding box, read once.
local tops = setmetatable({}, { __mode = "k" })
local function top_of(unit)
	local z = tops[unit]
	if z then return z end
	local U = g("Unit")
	local ok, pose, extents = pcall(U.box, unit)
	if ok and pose and extents then
		local okt, at = pcall(g("Matrix4x4").translation, pose)
		local root = U.world_position(unit, 0)
		if okt and at then z = at.z + extents.z - root.z + M.OVER_BOX end
	end
	if type(z) ~= "number" or z ~= z or z < 0.3 then z = M.ABOVE_ENEMY end
	tops[unit] = z
	return z
end
local function plain(v) return { x = v.x, y = v.y, z = v.z } end

local function is_enemy(unit)
	local EA = g("EntityAux")
	local ok, yes = pcall(function()
		if not EA.has_component(unit, "enemy") then return false end
		local health = EA.state(unit, "health")
		return not (health and health.is_dead)
	end)
	return ok and yes
end

-- The enemy's name in the game's language.
local function enemy_name(api, unit)
	local ok, info = pcall(api.enemies.info, unit)
	if not ok or type(info) ~= "table" then return "Enemy" end
	local entry = info.key and api.catalog and api.catalog.enemy and api.catalog.enemy(info.key)
	if entry and entry.loc and api.catalog.text then
		local got, text = pcall(api.catalog.text, entry.loc)
		if got and type(text) == "string" and text ~= "" and text ~= entry.loc then return M.title(text) end
	end
	return M.title(info.name or "Enemy")
end

local function text_of(api, key)
	if api.catalog and api.catalog.text then
		local ok, t = pcall(api.catalog.text, key)
		if ok and type(t) == "string" and t ~= "" then return t end
	end
	return key
end

-- What the crosshair is on: { kind, pos, unit, icon, name }.
function M.target(env)
	local api, state = env.api, env.state
	local point = state.aim_point
	if not point then return nil end
	local unit = state.aim_unit
	if unit and is_enemy(unit) then
		return { kind = "enemy", unit = unit, pos = plain(g("Unit").world_position(unit, 0)), name = enemy_name(api, unit) }
	end
	local ok, near = pcall(api.enemies.near, M.ENEMY_REACH, v3(point))
	if ok and type(near) == "table" and near[1] then
		local u = near[1]
		return { kind = "enemy", unit = u, pos = plain(g("Unit").world_position(u, 0)), name = enemy_name(api, u) }
	end
	if api.world and api.world.pickups then
		local got, list = pcall(api.world.pickups, point, M.PICKUP_REACH, { "weapon_pickup", "backpack_pickup" })
		local pick = got and type(list) == "table" and list[1]
		if pick then
			local strat = pick.stratagem
			local entry = nil
			if strat and api.catalog and api.catalog.stratagem then entry = api.catalog.stratagem(strat) end
			if not entry and api.catalog and api.catalog.stratagem_of then entry = api.catalog.stratagem_of(pick.weapon or pick.backpack) end
			local LS = g("LoadoutSettings")
			if not entry and strat and LS then
				for _, s in ipairs(LS.stratagems or {}) do if s.name == strat then entry = s end end
			end
			if entry then
				return { kind = "support", pos = pick.position, unit = pick.unit, icon = entry.icon, name = M.trim(text_of(api, entry.name)) }
			end
		end
	end
	local st = api.game.state and api.game.state()
	local mm = type(st) == "table" and st.mission_manager
	local V3A = g("Vector3Aux")
	if mm and mm.get_objectives and V3A then
		local found = {}
		for _, o in ipairs(mm:get_objectives() or {}) do
			if type(o) == "table" and o.objective_hidden_data == nil and o.state == "pending" and type(o.position) == "table" then
				for _, box in ipairs(o.position) do
					local got, p = pcall(V3A.unbox, box)
					if got and p then found[#found + 1] = { x = p.x, y = p.y, z = p.z, name = o.name } end
				end
			end
		end
		local o = M.nearest(found, point, M.OBJECTIVE_REACH, nil, true)
		if o then return { kind = "objective", pos = { x = o.x, y = o.y, z = o.z }, name = text_of(api, o.name) } end
	end
	return { kind = "ground", pos = { x = point.x, y = point.y, z = point.z } }
end

-- The chat's sound, on this machine only, through the game's own call. Answers whether it played.
function M.sound(api)
	local st = api.game.state and api.game.state()
	local chat = type(st) == "table" and st.text_chat
	if type(chat) ~= "table" or type(chat.play_chat_sound) ~= "function" then return false end
	return (pcall(chat.play_chat_sound, chat))
end

function M.start(env)
	local ui = obsidian.ui
	if type(ui) ~= "table" or type(ui.canvas) ~= "function" then return end
	local kit = ui.canvas("eyesofliberty_pings", { layer = M.LAYER })
	if not kit then return end
	local on = env.config.get("pings") ~= false
	if env.config.on_change then env.config.on_change("pings", function(v) on = v ~= false end) end

	local markers = {}      -- by peer ("me" for this machine): { kind, pos, unit, icon, words, age }
	local seen = {}         -- peer -> the last count read
	local primed = false    -- the first look of a mission only notes what was already there
	local count, burst = 0, {}
	local poll = 0
	local clock = os and os.clock or function() return 0 end

	local function in_mission(api)
		return api and api.game and api.game.in_mission and api.game.in_mission()
	end

	obsidian.keybind("ping", function()
		if not on or not env.state.active or env.state.watching then return end
		local api = env.api
		if not in_mission(api) then return end
		local now = clock()
		local ok, t = pcall(M.target, env)
		if not ok then
			env.log("Eyes of Liberty: ping: " .. tostring(t))
			return
		end
		if not t or not M.allow(burst, now) then return end
		local metres = nil
		if t.kind == "enemy" then
			local me = api.game.my_unit()
			if me then
				local p = g("Unit").world_position(me, 0)
				local dx, dy, dz = t.pos.x - p.x, t.pos.y - p.y, t.pos.z - p.z
				metres = sqrt(dx * dx + dy * dy + dz * dz)
			end
		end
		local words = M.message(t.kind, t.name, metres)
		markers.me = { kind = t.kind, pos = t.pos, unit = t.kind == "enemy" and t.unit or nil, icon = t.icon, words = words,
			name = t.name, age = 0 }
		count = count + 1
		M.sound(api)
		if api.lobby and api.lobby.share then pcall(api.lobby.share, M.SHARE, M.encode(count, t.kind, t.pos, t.icon, words)) end
	end, env.KEY_VIEW or env.VIEW)

	-- Teammates' pings, from what they share.
	local function listen(api)
		if not (api.lobby and api.lobby.shared) then return end
		local ok, all = pcall(api.lobby.shared, M.SHARE)
		if not ok or type(all) ~= "table" then return end
		for peer, s in pairs(all) do
			local p = M.decode(s)
			if p and not primed then
				seen[peer] = p.count -- shared before this mission: old
			elseif p and p.count ~= seen[peer] then
				seen[peer] = p.count
				local m = { kind = p.kind, pos = p.pos, icon = p.icon, words = p.words, age = 0, name = M.label(p.kind, nil, p.words) }
				if p.kind == "enemy" then
					local got, near = pcall(api.enemies.near, 3, v3(p.pos))
					m.unit = got and type(near) == "table" and near[1] or nil
				end
				markers[peer] = m
				M.sound(api)
			end
		end
		primed = true
	end

	local line = { 0, 0, 0, 0, 0, 0, 0, 0 }
	local diamond = { 0, 0, 0, 0, 0, 0, 0, 0 }

	local function rgba(c, a) return { c[1], c[2], c[3], floor(255 * a + 0.5) } end

	local function quad(x1, y1, x2, y2, half, color)
		local dx, dy = x2 - x1, y2 - y1
		local len = sqrt(dx * dx + dy * dy)
		if len < 0.5 then return end
		local px, py = -dy / len * half, dx / len * half
		line[1], line[2], line[3], line[4] = x1 + px, y1 + py, x2 + px, y2 + py
		line[5], line[6], line[7], line[8] = x2 - px, y2 - py, x1 - px, y1 - py
		kit:poly(line, color)
	end

	local function draw_diamond(x, y, r, c, a)
		diamond[1], diamond[2], diamond[3], diamond[4] = x, y + r, x + r, y
		diamond[5], diamond[6], diamond[7], diamond[8] = x, y - r, x - r, y
		kit:poly(diamond, rgba(c, a))
		kit:outline(diamond, { 0, 0, 0, floor(200 * a) }, max(1, r * 0.18))
	end

	local function draw(api, dt)
		local view = env.view
		local cm = g("CameraManager")
		if not (view and view.position and view.forward and cm and cm.viewport) then return end
		local w, h, x0, y0 = cm.viewport:window()
		if not (w and h and w > 0 and h > 0) then return end
		x0, y0 = x0 or 0, y0 or 0
		local s = min(w / compass.W, h / compass.H)
		local cam = frustum.camera_from(view.position, view.forward, math.rad(view.fov or 70))
		local cross = env.state.crosshair
		local me = api.game.my_unit()
		local mine = me and plain(g("Unit").world_position(me, 0))
		kit:layer(M.LAYER)
		for peer, m in pairs(markers) do
			m.age = m.age + dt
			local a = M.alpha(m.age)
			if a <= 0 then
				markers[peer] = nil
			else
				local U = g("Unit")
				if m.unit then
					local okp, p = pcall(function() return U.alive(m.unit) and is_enemy(m.unit) and U.world_position(m.unit, 0) end)
					if okp and p then m.pos = plain(p) else m.unit = nil end
				end
				local c = M.COLORS[m.kind] or M.COLORS.ground
				if m.unit then m.lift = top_of(m.unit) end
				local lift = m.kind == "enemy" and (m.lift or M.ABOVE_ENEMY) or M.LINE
				local base = m.pos
				local top = { x = m.pos.x, y = m.pos.y, z = m.pos.z + lift * M.rise(m.age) }
				local inset = M.INSET * s
				local on_top, tx, ty, dx, dy = edge.locate(cam, top, w, h, inset)
				local r = M.DIAMOND * s * M.pop(m.age)
				if on_top then
					local bx, depth, by = frustum.project(cam, base, w, h)
					local t = (m.age % 1)
					local pulse = M.lighter(c, M.PULSE_LIGHT)
					if depth > 0.1 then
						quad(x0 + bx, y0 + by, x0 + tx, y0 + ty, 1.5 * s, rgba(c, 0.85 * a))
						-- A dash, a little lighter than the line and thicker, running up it once a second.
						local px, py = bx + (tx - bx) * t, by + (ty - by) * t
						local qx, qy = bx + (tx - bx) * min(1, t + 0.15), by + (ty - by) * min(1, t + 0.15)
						quad(x0 + px, y0 + py, x0 + qx, y0 + qy, 2.5 * s, rgba(pulse, a))
					end
				else
					tx, ty = edge.edge(dx, dy, w, h, inset, inset)
				end
				local cx, cy = x0 + tx, y0 + ty
				if m.kind == "support" and m.icon then
					local size = M.ICON * s * M.pop(m.age)
					if not kit:icon(m.icon, cx - size / 2, cy - size / 2, size, size, { 255, 255, 255, floor(255 * a) }) then
						draw_diamond(cx, cy, r, c, a)
					end
				else
					draw_diamond(cx, cy, r, c, a)
				end
				-- While the crosshair is near the marker: the name above it on a see-through black box (light
				-- red for an enemy), the distance from this player below it.
				if cross and on_top then
					local hx, hy = cx - cross.x, cy - cross.y
					if hx * hx + hy * hy <= (M.HOVER * s) ^ 2 then
						local size = M.TEXT * s
						local d = max(1, floor(size / 14))
						local half = (m.kind == "support" and m.icon) and M.ICON * s / 2 or r
						local name = M.label(m.kind, m.name, m.words)
						if name then
							local opts = { font = "body_large", size = size, align = "center",
								color = rgba(m.kind == "enemy" and M.ENEMY_TEXT or { 255, 255, 255 }, a) }
							local tw = size * 0.55 * #name
							if kit.measure then
								local okm, mw = pcall(kit.measure, kit, name, opts)
								if okm and type(mw) == "number" then tw = mw end
							end
							local pad = 6 * s
							local y = cy + half + 8 * s
							kit:rect(cx - tw / 2 - pad, y - pad * 0.6, tw + 2 * pad, size + pad * 0.8, { 0, 0, 0, floor(150 * a) })
							kit:text(name, cx, y + size * 0.15, opts)
						end
						if mine then
							local ex, ey, ez = m.pos.x - mine.x, m.pos.y - mine.y, m.pos.z - mine.z
							local dist = string.format("%d m", floor(sqrt(ex * ex + ey * ey + ez * ez) + 0.5))
							local y = cy - half - 6 * s - size
							kit:text(dist, cx + d, y - d, { font = "body_large", size = size, align = "center", color = { 0, 0, 0, floor(190 * a) } })
							kit:text(dist, cx, y, { font = "body_large", size = size, align = "center", color = { 255, 255, 255, floor(255 * a) } })
						end
					end
				end
			end
		end
	end

	local warned, wait = false, 0
	obsidian.on_frame(function()
		local api = env.api
		if not in_mission(api) then
			markers, seen, primed = {}, {}, false
			return
		end
		local dt = g("ENGINE_DT")
		dt = type(dt) == "number" and dt > 0 and min(dt, 0.1) or 1 / 60
		poll = poll - dt
		if on and poll <= 0 then
			poll = M.POLL
			pcall(listen, api)
		end
		if wait > 0 then wait = wait - 1 return end
		if not on or not env.state.active or not compass.shown(api) then
			for _, m in pairs(markers) do m.age = m.age + dt end
			return
		end
		local ok, err = pcall(draw, api, dt)
		if not ok then
			wait = 300
			if not warned then
				warned = true
				env.log("Eyes of Liberty: pings: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
