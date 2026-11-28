-- Loose weapon parts held still in third person. The Rumbler (equipment/wep_mortar_01) has a tripod
-- leg on a free physics actor (actor 1, node 3; the other two legs are kinematic): it swings up to 90
-- degrees a frame while the Helldiver walks, in hand and on the back, in the top-down camera too
-- (probe 2026-11-25), where it is too far to see. Close behind the shoulder it flickered between folded
-- and out.
--
-- While the shoulder view is on, the Rumbler of this player's Helldiver gets the node of each such actor
-- (dynamic, not kinematic, on a node other than the root) back to the pose it is made with (the
-- identity: every node of a freshly spawned Rumbler has it) and the actor turned kinematic, so the
-- part rides with the weapon, folded. The top-down camera, the death cam and a Rumbler leaving the
-- inventory give them back to the physics.
--
-- Only the units in KINDS: other weapons have free actors too (the ME-1 Sniffer), and turning those
-- kinematic ended the game on pickup (report, 1.2.2).
local M = {}

local function g(name) return rawget(_G, name) end

M.SLOTS = { "primary_weapon", "sidearm_weapon", "support_weapon" }
M.KINDS = { "equipment/wep_mortar_01" }

-- Whether a weapon unit is one whose loose parts are held.
function M.wanted(unit)
	local U = g("Unit")
	if not (U and U.is_a) then return false end
	for _, path in ipairs(M.KINDS) do
		local ok, yes = pcall(U.is_a, unit, path)
		if ok and yes == true then return true end
	end
	return false
end
M.held = {}           -- weapon unit -> list of actors made kinematic
M.logged = {}

-- The free actors of a unit: { actor, node } for each dynamic, not kinematic actor off the root.
function M.loose_actors(unit)
	local U, A = g("Unit"), g("Actor")
	local out = {}
	local n = U.num_actors(unit) or 0
	for i = 0, n - 1 do
		local ok, a = pcall(U.actor, unit, i)
		if ok and a ~= nil then
			local _, dyn = pcall(A.is_dynamic, a)
			local _, kin = pcall(A.is_kinematic, a)
			local _, node = pcall(A.node, a)
			if dyn == true and kin == false and type(node) == "number" and node > 0 then
				out[#out + 1] = { actor = a, node = node }
			end
		end
	end
	return out
end

-- Holds the free parts of a weapon unit, once. Answers how many.
function M.hold(unit)
	if M.held[unit] then return #M.held[unit] end
	local U, A, Q = g("Unit"), g("Actor"), g("Quaternion")
	local list = M.loose_actors(unit)
	for _, p in ipairs(list) do
		U.set_local_rotation(unit, p.node, Q.identity())
		A.set_kinematic(p.actor, true)
	end
	M.held[unit] = list
	return #list
end

-- Gives the held parts of one weapon unit back to the physics.
local function release(unit)
	local U, A = g("Unit"), g("Actor")
	local list = M.held[unit]
	M.held[unit] = nil
	if list and U.alive(unit) then
		for _, p in ipairs(list) do pcall(A.set_kinematic, p.actor, false) end
	end
end

-- Gives every held part back to the physics.
function M.give_back()
	for unit in pairs(M.held) do release(unit) end
	M.held = {}
end

-- The weapon units of a Helldiver now.
function M.weapons(avatar)
	local EA = g("EntityAux")
	local ok, inv = pcall(EA.state_master, avatar, "inventory")
	if not ok or type(inv) ~= "table" then return {} end
	local out = {}
	for _, slot in ipairs(M.SLOTS) do
		if inv[slot] ~= nil then out[#out + 1] = inv[slot] end
	end
	return out
end

function M.frame(env, view)
	local U = g("Unit")
	-- Weapons gone (dropped, replaced) are forgotten.
	for unit in pairs(M.held) do
		if not U.alive(unit) then M.held[unit] = nil end
	end
	if not (view and view.avatar) or view.watching then
		M.give_back()
		return
	end
	local carried = {}
	for _, unit in ipairs(M.weapons(view.avatar)) do carried[unit] = true end
	-- Weapons no longer carried (dropped, swapped for a pickup) go back to the physics.
	for unit in pairs(M.held) do
		if not carried[unit] then release(unit) end
	end
	for _, unit in ipairs(M.weapons(view.avatar)) do
		if U.alive(unit) and not M.held[unit] and M.wanted(unit) then
			local n = M.hold(unit)
			if n > 0 and not M.logged[tostring(unit)] then
				M.logged[tostring(unit)] = true
				env.log("Eyes of Liberty: " .. n .. " loose part(s) of " .. tostring(unit) .. " held still")
			end
		end
	end
end

function M.start(env)
	local failed = false
	table.insert(env.on_pose, function(view)
		if failed then return end
		local ok, err = pcall(M.frame, env, view)
		if not ok then
			failed = true
			env.log("Eyes of Liberty: loose parts stopped: " .. tostring(err))
		end
	end)
	table.insert(env.on_release, function() pcall(M.give_back) end)
end

return M
