-- The Helldiver's body under the shoulder camera.
--
-- Jump pack: a Helldiver's body is drawn by part units (body, helmet, cape, heavy armor, boots) skinned
-- bone by bone onto the character (CustomizationComponent, UnitAux.skin_item) and linked to its root.
-- The engine culls each part by its box, which sits around the part's root: on the ground, since the
-- character's root stays there while the jump pack's flight lifts the bones (probe 2026-11-19: hips 5 m
-- up, every part's box still at 0.87 m). Looking up at the flight, the box leaves the view and the body
-- vanishes, while the backpack and weapons, linked to bones, stay. Each part's root is raised by how
-- far the hips are over their usual height (LIFT_FROM); the skinning places the mesh from the bones,
-- so only the box moves (probe: the body drew in place, the box followed). Every Helldiver in the
-- level, while third person is on.
--
-- Close camera: when the camera presses within NEAR metres of the Helldiver (a wall behind, a tight
-- corner), the body, gear and weapons are hidden until it is FAR again. The Helldiver's materials have
-- no opacity to fade, so the parts' meshes are switched off, and switched back to what they were.
--
-- Stowed support weapon: with the option on, the support weapon (the inventory's support_weapon) is
-- hidden while another weapon is in hand. Stowed on the back it sits between the camera and the view
-- (the Dum-Dum's tube). This player's Helldiver on foot, on this screen only; the meshes go back as
-- they were when it is wielded, the option goes off or third person ends.
local M = {}

local function g(name) return rawget(_G, name) end

M.PARTS = { "body_unit", "helmet_unit", "cape_unit", "heavy_armor_unit", "all_terrain_boots_unit" }
M.LIFT_FROM = 1.2     -- metres of hips over the root that count as standing; above that the parts rise
M.NEAR, M.FAR = 0.55, 0.7 -- metres from the camera to the body's middle line: hide, show again
M.BODY = { 0.25, 1.65 } -- metres over the root: the bottom and top of the body's middle line

-- How far to raise the parts for hips `hips` metres over the root.
function M.lift_for(hips)
	if type(hips) ~= "number" then return 0 end
	return math.max(0, hips - M.LIFT_FROM)
end

-- The distance from point c to the upright segment over `root` from BODY[1] to BODY[2].
function M.distance_to_body(c, root)
	local z = math.max(root.z + M.BODY[1], math.min(root.z + M.BODY[2], c.z))
	local dx, dy, dz = c.x - root.x, c.y - root.y, c.z - z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Whether the body should be hidden now, from the distance and whether it is hidden already.
function M.hide_now(distance, hidden)
	if type(distance) ~= "number" then return false end
	if hidden then return distance < M.FAR end
	return distance < M.NEAR
end

-- The part units of an avatar, from its customization slave.
local function parts_of(api, avatar)
	local slaves = api.game.slaves and api.game.slaves("customization")
	local c = slaves and slaves[avatar]
	local s = c and c.state
	local list = {}
	if type(s) ~= "table" then return list end
	local U = g("Unit")
	for _, k in ipairs(M.PARTS) do
		local u = s[k]
		if u and U.alive(u) then list[#list + 1] = u end
	end
	return list
end

-- Jump pack lifts --------------------------------------------------------------------------------------

local lifted = {} -- part unit: the height it was raised by

local function set_lift(U, V3, unit, up)
	if (lifted[unit] or 0) == up then return end
	local lp = U.local_position(unit, 0)
	U.set_local_position(unit, 0, V3(lp.x, lp.y, up))
	lifted[unit] = up > 0 and up or nil
end

local function lift_all(api)
	local U, V3 = g("Unit"), g("Vector3")
	local seen = {}
	for _, p in ipairs(api.game.all_avatars() or {}) do
		local avatar = p.unit
		if avatar and U.alive(avatar) and U.has_node(avatar, "hips") then
			local root = U.world_position(avatar, 0)
			local up = M.lift_for(U.world_position(avatar, U.node(avatar, "hips")).z - root.z)
			for _, part in ipairs(parts_of(api, avatar)) do
				seen[part] = true
				set_lift(U, V3, part, up)
			end
		end
	end
	for part in pairs(lifted) do
		if not seen[part] then lifted[part] = nil end
	end
end

local function drop_all()
	local U, V3 = g("Unit"), g("Vector3")
	for part in pairs(lifted) do
		pcall(function() if U.alive(part) then set_lift(U, V3, part, 0) end end)
	end
	lifted = {}
end

-- Close camera ---------------------------------------------------------------------------------------

local hidden = nil -- { [unit] = { mesh index = was visible } } while hidden

-- Every unit drawn for the Helldiver: its parts and what is linked under it (weapons, backpack).
local function drawn_units(api, avatar)
	local U = g("Unit")
	local list, seen = {}, { [avatar] = true }
	local function add(u)
		if u and not seen[u] and U.alive(u) then
			seen[u] = true
			list[#list + 1] = u
			local kids = {}
			pcall(U.children, u, kids)
			for _, k in ipairs(kids) do add(k) end
		end
	end
	for _, part in ipairs(parts_of(api, avatar)) do add(part) end
	local kids = {}
	pcall(U.children, avatar, kids)
	for _, k in ipairs(kids) do add(k) end
	return list
end

-- Hides what isn't hidden yet: called each frame while hidden, so a weapon switched in hides too.
local function hide(api, avatar)
	local U = g("Unit")
	hidden = hidden or { avatar = avatar, units = {} }
	for _, u in ipairs(drawn_units(api, avatar)) do
		if not hidden.units[u] then
			local was = {}
			for i = 0, U.num_meshes(u) - 1 do
				was[i] = U.mesh_visibility(u, i)
				if was[i] then U.set_mesh_visibility(u, i, false) end
			end
			hidden.units[u] = was
		end
	end
end

local function show()
	if not hidden then return end
	local U = g("Unit")
	for u, was in pairs(hidden.units) do
		pcall(function()
			if U.alive(u) then
				for i, on in pairs(was) do if on then U.set_mesh_visibility(u, i, true) end end
			end
		end)
	end
	hidden = nil
end

-- Stowed support weapon ------------------------------------------------------------------------------

local stowed = nil -- { unit, was = { mesh index = was visible } } while hidden

-- The support weapon of an avatar while it is stowed (in the inventory, alive, not the weapon in hand).
function M.stowed_support(avatar)
	local EA, U = g("EntityAux"), g("Unit")
	local inv = nil
	for _, get in ipairs({ EA.state_master, EA.state }) do
		if not inv and type(get) == "function" then
			local ok, s = pcall(get, avatar, "inventory")
			if ok and type(s) == "table" then inv = s end
		end
	end
	if not inv then return nil end
	local support = inv.support_weapon
	if support == nil or support == inv.current_weapon or not U.alive(support) then return nil end
	return support
end

local function unstow()
	if not stowed then return end
	local U, s = g("Unit"), stowed
	stowed = nil
	-- Hidden by the close camera meanwhile: it shows the meshes again when the camera moves off.
	if hidden and hidden.units[s.unit] then
		hidden.units[s.unit] = s.was
		return
	end
	pcall(function()
		if U.alive(s.unit) then
			for i, on in pairs(s.was) do if on then U.set_mesh_visibility(s.unit, i, true) end end
		end
	end)
end

local function stow(unit)
	if stowed and stowed.unit == unit then return end
	unstow()
	local U = g("Unit")
	-- Already hidden by the close camera: the stow takes its record over.
	if hidden and hidden.units[unit] then
		stowed = { unit = unit, was = hidden.units[unit] }
		hidden.units[unit] = {}
		return
	end
	local was = {}
	for i = 0, U.num_meshes(unit) - 1 do
		was[i] = U.mesh_visibility(unit, i)
		if was[i] then U.set_mesh_visibility(unit, i, false) end
	end
	stowed = { unit = unit, was = was }
end

function M.start(env)
	local state = env.state
	local config = env.config
	local hide_stowed = not config or config.get("hide_stowed_support") ~= false
	if config then config.on_change("hide_stowed_support", function(v) hide_stowed = v ~= false end) end
	table.insert(env.on_pose, function(view)
		local target = nil
		if hide_stowed and view.avatar and not view.vehicle and not view.watching then
			local ok, t = pcall(M.stowed_support, view.avatar)
			target = ok and t or nil
		end
		if target then pcall(stow, target) elseif stowed then unstow() end
		local api = env.api
		lift_all(api)
		local avatar = view.avatar
		local want = false
		if avatar and not view.vehicle and not view.watching and not state.dropping then
			local root = g("Unit").world_position(avatar, 0)
			local up = 0
			for _, part in ipairs(parts_of(api, avatar)) do up = lifted[part] or up end
			local base = { x = root.x, y = root.y, z = root.z + up }
			want = M.hide_now(M.distance_to_body(view.position, base), hidden ~= nil)
		end
		if hidden and (not want or hidden.avatar ~= avatar) then show() end
		if want then hide(api, avatar) end
	end)
	table.insert(env.on_release, function()
		unstow()
		show()
		drop_all()
	end)
end

M._lifted = function() return lifted end -- for tests
M._hidden = function() return hidden end
M._stowed = function() return stowed end
return M
