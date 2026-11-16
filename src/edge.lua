-- Edge markers: in third person, stratagem beacons and objectives out of view show at the edge of the
-- screen, on the side to turn to. Allies out of view have the game's own marker (the name card's
-- "icon_outofscreen_player_01", Hud.draw_player_name_in_world), which src/frustum.lua points the right
-- way for allies behind the camera and reddens for a downed ally.
--
-- Nothing here is drawn in a look of its own. Each marker is the icon the game's map draws for the thing,
-- in the map's colours, on the HUD gui (Hud.hd_gui) the game draws the "!" over the crew with:
--   stratagem beacon the stratagem's own icon (LoadoutSettings.stratagems[id].icon), at the size of the
--                    countdown list (HudSettings.settings.stratagem_countdown_list.stratagem_icon.size),
--                    while it counts down
--   objective        the objective's map icon in the map's colours (Hud.init objective_colors): white
--                    while pending, the search yellow while hidden, at the middle of the search zone
-- Beacons and objectives carry "icon_arrow_01", the HUD's scroll arrow, on the side toward the edge.
-- Only what is out of view gets a marker: on screen the game shows its own.
local frustum = obsidian.module("src/frustum")

local M = {}

M.INSET = 22          -- design pixels (1280 x 720) between a marker and the screen edge
M.INSET_BOTTOM = 96   -- at the bottom, above the player panels of the HUD
M.OBJECTIVE = 32      -- objective icon, design pixels (Hud.draw_map)
M.BEACON = 32         -- fallback when the HUD settings have no countdown icon size
M.ARROW = 16          -- icon_arrow_01, design pixels (menu_screen_base: 16 for small arrows)
M.ARROW_GAP = 2       -- design pixels between an icon and its arrow
M.LAYER = 98          -- under the "!" (99) and the busy box (99, 100)
-- Rotations, radians, of the art at rotation 0, as the direction it points on screen (x right, y up).
-- icon_arrow_01 points left at 0 (menu_screen_base draws the left arrow at 0 and the right one at pi).
-- Seen in game (2026-11-16).
M.ARROW_ART = math.pi
-- Gui rotations turn clockwise on screen (seen in game: the player arrow at +90 degrees points right).
M.CLOCKWISE = true
M.PAUSE = 300         -- frames without markers after an error

local sqrt, atan2, pi, min = math.sqrt, math.atan2, math.pi, math.min

local function g(name) return rawget(_G, name) end

-- Pure parts ----------------------------------------------------------------------------------------

-- Where a point of the level shows for a camera (frustum.camera_from: position, forward, right, up,
-- fov radians) on a w by h screen. Answers on, x, y, dx, dy: on is true when the point is in front and
-- inside the screen less `inset` pixels; dx, dy is the way from the middle of the screen toward it, as
-- it would be if it were in front, so a point behind and to the right points right. A point straight
-- behind points down.
function M.locate(cam, p, w, h, inset)
	local d = { x = p.x - cam.position.x, y = p.y - cam.position.y, z = p.z - cam.position.z }
	local z = d.x * cam.forward.x + d.y * cam.forward.y + d.z * cam.forward.z
	local r = d.x * cam.right.x + d.y * cam.right.y + d.z * cam.right.z
	local u = d.x * cam.up.x + d.y * cam.up.y + d.z * cam.up.z
	local ty = math.tan(cam.fov / 2)
	local tx = ty * w / h
	local dx, dy = r / tx * w / 2, u / ty * h / 2
	if z > 1e-3 then
		local x, y = w / 2 + dx / z, h / 2 + dy / z
		if x >= inset and x <= w - inset and y >= inset and y <= h - inset then return true, x, y, dx, dy end
	end
	if dx * dx + dy * dy < 1e-6 then dx, dy = 0, -1 end
	return false, nil, nil, dx, dy
end

-- The point on the edge of the screen, `inset` pixels in (`bottom` at the bottom), along (dx, dy) from
-- the middle.
function M.edge(dx, dy, w, h, inset, bottom)
	local hw = w / 2 - inset
	local hh = dy < 0 and h / 2 - (bottom or inset) or h / 2 - inset
	local t = math.huge
	if math.abs(dx) > 1e-9 then t = min(t, hw / math.abs(dx)) end
	if math.abs(dy) > 1e-9 then t = min(t, hh / math.abs(dy)) end
	return w / 2 + dx * t, h / 2 + dy * t
end

-- The gui rotation that turns art pointing at `art` (radians, x right, y up) to point at `toward`.
function M.turn(art, toward)
	local a = toward - art
	if M.CLOCKWISE then a = -a end
	a = (a + pi) % (2 * pi) - pi
	return a
end

-- Game parts ----------------------------------------------------------------------------------------

local function colour(box, fallback)
	local QA = g("QuaternionAux")
	if type(box) == "table" and QA then
		local ok, c = pcall(QA.unbox, box)
		if ok and c then return c end
	end
	return fallback
end

local function size_of(setting, fallback)
	local V2A = g("Vector2Aux")
	if type(setting) == "table" and V2A then
		local ok, s = pcall(V2A.unbox, setting)
		if ok and s then return s.x, s.y end
	end
	return fallback, fallback
end

-- The things to mark this frame: calls fn(kind, position, icon, width, height, colour).
function M.gather(hud, api, fn)
	local U, EA, C = g("Unit"), g("EntityAux"), g("Color")
	local me = api.game.my_unit and api.game.my_unit()
	-- Stratagem beacons counting down.
	local em = hud.entity_manager
	local LS = g("LoadoutSettings")
	if em and em.get_slave_entities and LS and LS.stratagems then
		local HS = g("HudSettings")
		local list = HS and HS.settings and HS.settings.stratagem_countdown_list
		local bw, bh = size_of(list and list.stratagem_icon and list.stratagem_icon.size, M.BEACON)
		for unit, ext in pairs(em:get_slave_entities("stratagem")) do
			local st = type(ext) == "table" and ext.state
			if st and (st.stratagem_id or 0) > 0 and st.has_been_enabled and not st.is_done and not st.abort
				and U.alive(unit) then
				local info = LS.stratagems[st.stratagem_id]
				if info and info.icon then
					local p = U.world_position(unit, 0)
					fn("thing", { x = p.x, y = p.y, z = p.z + 0.5 }, info.icon, bw, bh, C(255, 255, 255, 255))
				end
			end
		end
	end
	-- Objectives not done yet.
	local mm = hud.mission_manager
	local V3A = g("Vector3Aux")
	if mm and mm.get_objectives and V3A then
		local colours = {
			pending = colour({ x = 255, y = 255, z = 255, w = 255 }, C(255, 255, 255, 255)),
			search = C(255, 234, 193, 0),
		}
		for _, o in ipairs(mm:get_objectives() or {}) do
			if type(o) == "table" and o.icon and o.state ~= "complete" and o.state ~= "failed"
				and type(o.position) == "table" then
				local hidden = type(o.objective_hidden_data) == "table" and o.objective_hidden_data
				local offset = hidden and hidden.offset and V3A.unbox(hidden.offset)
				local c = hidden and colours.search or colours.pending
				for _, box in ipairs(o.position) do
					local p = V3A.unbox(box)
					if offset then p = p + offset end
					fn("thing", { x = p.x, y = p.y, z = p.z + 1 }, o.icon, M.OBJECTIVE, M.OBJECTIVE, c)
				end
			end
		end
	end
end

-- Draws the markers on the HUD gui for the shoulder camera's pose.
function M.draw(hud, env)
	local gui = hud.hd_gui
	local view = env.view
	local cm = g("CameraManager")
	if not (gui and view and view.position and view.forward and cm and cm.viewport) then return end
	local w, h = cm.viewport:window()
	if not (w and h and w > 0 and h > 0) then return end
	local V2, V3 = g("Vector2"), g("Vector3")
	local cam = frustum.camera_from(view.position, view.forward, math.rad(view.fov or 70))
	local scale = gui.ui_scale or h / 720
	gui:set_ignore_position_scale(true)
	gui:set_ignore_size_scale(false)
	local inset = M.INSET * scale
	local arrow = M.ARROW * scale
	M.gather(hud, env.api, function(kind, p, icon, iw, ih, c)
		local big = (iw > ih and iw or ih) * scale
		local room = big / 2 + arrow + M.ARROW_GAP * scale
		local on, _, _, dx, dy = M.locate(cam, p, w, h, 0)
		if on then return end
		local x, y = M.edge(dx, dy, w, h, inset + room, M.INSET_BOTTOM * scale + room)
		local toward = atan2(dy, dx)
		gui:image(icon, V3(x - iw * scale / 2, y - ih * scale / 2, M.LAYER), V2(iw, ih), c)
		local len = sqrt(dx * dx + dy * dy)
		local ux, uy = dx / len, dy / len
		local reach = big / 2 + M.ARROW_GAP * scale + arrow / 2
		local ax, ay = x + ux * reach, y + uy * reach
		gui:rotated_image("icon_arrow_01", V3(ax - arrow / 2, ay - arrow / 2, M.LAYER), V2(M.ARROW, M.ARROW),
			M.turn(M.ARROW_ART, toward), c)
	end)
	gui:set_ignore_position_scale(false)
	gui:set_ignore_size_scale(false)
end

function M.start(env)
	local on = env.config.get("edge_markers") ~= false
	env.config.on_change("edge_markers", function(v) on = v ~= false end)
	local warned, wait = false, 0
	obsidian.hook("Hud", "draw_plugins", function(original, self, ...)
		local r = { original(self, ...) }
		if on and env.state.active and not env.state.watching and wait == 0 then
			local api = env.api
			if api and api.game and api.game.in_mission and api.game.in_mission() then
				local ok, err = pcall(M.draw, self, env)
				if not ok then
					wait = M.PAUSE
					pcall(self.hd_gui.set_ignore_position_scale, self.hd_gui, false)
					if not warned then
						warned = true
						env.log("Eyes of Liberty: edge markers: " .. tostring(err))
					end
				end
			end
		elseif wait > 0 then
			wait = wait - 1
		end
		return unpack(r)
	end, env.VIEW)
end

return M
