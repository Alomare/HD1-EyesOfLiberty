-- Aim pose: while the Helldiver aims or fires on foot in third person, the upper body bends up or down
-- so the weapon points at the crosshair point. The game's animations hold the weapon level (the
-- top-down game never aims up or down), and shots left the muzzle toward the crosshair at an angle.
--
-- When: just before World.update_scene of the world of the Helldiver (see M.start); the Helldiver and
-- every unit linked to it (the body pieces skinned to its bones, the weapon at r_hand_attach) get
-- World.update_unit.
--
-- How much: the pitch of the weapon now (forward of r_hand_attach, the weapon's +y) and the pitch the
-- weapon has swung to (src/aim.lua M.gun, eased by src/ergo.lua), or else the pitch from that node to
-- the crosshair point; the difference, eased in and out with the aim and within MAX degrees, is shared
-- by the spine nodes, each turned about the Helldiver's right axis in world space. Only this machine's
-- picture: other players see the game's own pose.
--
-- Only in the states that hold the weapon up to shoot (src/ergo.lua AIM_STATES). A throw, a weapon
-- switch or a reload moves the hand far from the weapon's line, and measuring it there bent the
-- Helldiver far back; out of those states the last bend eases out as it was.
local rig = obsidian.module("src/rig")

local M = {}

local function g(name) return rawget(_G, name) end

M.SPINE = { "spine1", "spine2", "spine3" }
M.MAX = 60            -- degrees the body bends at the most, up or down
M.RATE = 10           -- how fast the bend eases in and out
M.weight = 0          -- 0 to 1, how far the bend is in

-- The pitch in degrees of a direction.
function M.pitch_of(d)
	local flat = math.sqrt(d.x * d.x + d.y * d.y)
	return math.deg(math.atan2(d.z, flat))
end

-- The bend in degrees for the weapon's pitch now and the pitch it should have, within MAX.
function M.bend(now, want)
	local b = want - now
	return math.max(-M.MAX, math.min(M.MAX, b))
end

-- Whether the pose is wanted this frame. posed: the Helldiver is in a state that holds the weapon up.
function M.wanted(env, posed)
	local state, view = env.state, env.view
	return state.active and not state.vehicle and not state.watching and not state.dropping and posed ~= false
		and (state.aiming or state.firing) and view and view.avatar and state.aim_point and true or false
end

-- Whether the Helldiver's state holds the weapon up (src/aim.lua aim_state), nil when unknown.
function M.posed(avatar)
	local EA = g("EntityAux")
	local ok, cs = pcall(EA.state_master, avatar, "character")
	if not ok or type(cs) ~= "table" then return nil end
	return obsidian.module("src/aim").aim_state(cs.current_state)
end

-- Every unit drawn with the Helldiver: its body pieces and what is linked under it.
local function linked(api, avatar)
	local U = g("Unit")
	local list, seen = {}, { [avatar] = true }
	local function add(u)
		if u ~= nil and not seen[u] and U.alive(u) then
			seen[u] = true
			list[#list + 1] = u
			local kids = {}
			pcall(U.children, u, kids)
			for _, k in ipairs(kids) do add(k) end
		end
	end
	local slaves = api.game.slaves and api.game.slaves("customization")
	local c = slaves and slaves[avatar]
	local s = c and c.state
	if type(s) == "table" then
		for _, k in ipairs({ "body_unit", "helmet_unit", "cape_unit", "heavy_armor_unit", "all_terrain_boots_unit" }) do add(s[k]) end
	end
	local kids = {}
	pcall(U.children, avatar, kids)
	for _, k in ipairs(kids) do add(k) end
	return list
end

-- A rotation as four numbers, which last past the frame (a Quaternion lasts one frame), and back.
local function elements(Q, q)
	local x, y, z, w = Q.to_elements(q)
	return { x, y, z, w }
end

local function same(Q, q, e)
	local x, y, z, w = Q.to_elements(q)
	local d = math.abs(x - e[1]) + math.abs(y - e[2]) + math.abs(z - e[3]) + math.abs(w - e[4])
	return d < 1e-4
end

-- The bones bent last frame go back to the pose before the bend, where they still hold the bend: before
-- the scene update the game leaves them as they were (checked in game, 2026-11-20), so a bend added on
-- top of the last one would pile up and stay after aiming stops.
function M.restore(U, Q, W)
	local last = M.written
	M.written = nil
	if not (last and U.alive(last.avatar)) then return end
	local any = false
	for i, e in pairs(last.nodes) do
		if same(Q, U.local_rotation(last.avatar, i), e.now) then
			U.set_local_rotation(last.avatar, i, Q.from_elements(e.was[1], e.was[2], e.was[3], e.was[4]))
			any = true
		end
	end
	if any and last.world then W.update_unit(last.world, last.avatar) end
end

-- The whole bend toward the point for a weapon facing f at p, or nil when the point gives no pitch to
-- aim at: none, or almost straight under the hand, as when looking far down. The last bend is then held
-- (M.held), so the pose doesn't snap back to the animation's.
M.UNDER = 0.05 -- metres across from the hand within which a point is straight under it
function M.target_bend(f, p, point, pitch)
	if pitch then return M.bend(M.pitch_of({ x = f.x, y = f.y, z = f.z }), math.deg(pitch)) end
	if not point then return nil end
	local to = { x = point.x - p.x, y = point.y - p.y, z = point.z - p.z }
	if to.x * to.x + to.y * to.y < M.UNDER * M.UNDER then return nil end
	return M.bend(M.pitch_of({ x = f.x, y = f.y, z = f.z }), M.pitch_of(to))
end

function M.apply(env, dt)
	local U, Q, W = g("Unit"), g("Quaternion"), g("World")
	M.restore(U, Q, W)
	local posed = env.view and env.view.avatar and M.posed(env.view.avatar)
	local want = M.wanted(env, posed)
	M.weight = rig.ease(M.weight, want and 1 or 0, M.RATE, dt or 0.016)
	if M.weight < 0.01 then
		M.held = nil
		return false
	end
	local view = env.view
	local avatar = view and view.avatar
	local point = env.state.aim_point
	if not (avatar and U.alive(avatar) and U.has_node(avatar, "r_hand_attach")) then return false end
	-- The animation has set the bones for this frame, but their world transforms are still those of the
	-- last scene update, bend and all (checked in game, 2026-11-20): bring them up to date before measuring.
	if view.world then W.update_unit(view.world, avatar) end
	local hand = U.node(avatar, "r_hand_attach")
	local f = Q.forward(U.world_rotation(avatar, hand))
	local p = U.world_position(avatar, hand)
	local full = nil
	if want then
		local gun = obsidian.module("src/aim").gun
		full = M.target_bend(f, p, point, gun and gun.pitch)
	end
	if full then M.held = full else full = M.held end
	if not full then return false end
	local b = full * M.weight
	if math.abs(b) < 0.2 then return false end
	local nodes = {}
	for _, n in ipairs(M.SPINE) do if U.has_node(avatar, n) then nodes[#nodes + 1] = U.node(avatar, n) end end
	if #nodes == 0 then return false end
	local right = Q.right(U.world_rotation(avatar, 0))
	local turn = Q(right, math.rad(b / #nodes))
	local written = { avatar = avatar, world = view.world, nodes = {} }
	for _, i in ipairs(nodes) do
		local was = U.local_rotation(avatar, i)
		local wr = U.world_rotation(avatar, i)
		local now = Q.multiply(was, Q.multiply(Q.inverse(wr), Q.multiply(turn, wr)))
		written.nodes[i] = { was = elements(Q, was), now = elements(Q, now) }
		U.set_local_rotation(avatar, i, now)
	end
	M.written = written
	local world = view.world
	if world then
		W.update_unit(world, avatar)
		for _, u in ipairs(linked(env.api, avatar)) do W.update_unit(world, u) end
	end
	return true
end

-- The bend goes in just before the scene update of the Helldiver's world, after the animations: that is
-- what the frame draws. Bones turned later, in StateGame.post_update, aren't drawn (checked in game
-- through the Memory Bridge, 2026-11-20).
function M.start(env)
	if env.config.get("aim_pose") == false then M.off = true end
	env.config.on_change("aim_pose", function(v) M.off = v == false end)
	local failed = false
	obsidian.hook("World", "update_scene", function(original, world, ...)
		if not failed and not M.off and env.view and world == env.view.world then
			local ok, err = pcall(M.apply, env, rawget(_G, "ENGINE_DT") or 0.016)
			if not ok then
				failed = true
				env.log("Eyes of Liberty: aim pose stopped: " .. tostring(err))
			end
		elseif M.off and M.written then
			pcall(M.restore, g("Unit"), g("Quaternion"), g("World"))
		end
		return original(world, ...)
	end, env.VIEW)
	table.insert(env.on_release, function() M.weight = 0 end)
end

return M
