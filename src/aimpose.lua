-- Aim pose: while the Helldiver aims or fires on foot in third person, the upper body bends up or down
-- so the weapon points at the crosshair point. The game's animations hold the weapon level (the
-- top-down game never aims up or down), and shots left the muzzle toward the crosshair at an angle.
--
-- When: the frame runs Lua update (the camera), then the world update (animations, then the scene),
-- then StateGame.post_update, then render (Boot's frame, world_proxy.lua). Bones turned in post_update
-- are after the animations, so they stay for the frame drawn; the Helldiver and every unit linked to
-- it (the body pieces skinned to its bones, the weapon at r_hand_attach) get World.update_unit.
--
-- How much: the pitch of the weapon now (forward of r_hand_attach, the weapon's +y) and the pitch from
-- that node to the crosshair point; the difference, eased in and out with the aim and within MAX
-- degrees, is shared by the spine nodes, each turned about the Helldiver's right axis in world space.
-- Only this machine's picture: other players see the game's own pose.
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

-- Whether the pose is wanted this frame.
function M.wanted(env)
	local state, view = env.state, env.view
	return state.active and not state.vehicle and not state.watching and not state.dropping
		and (state.aiming or state.firing) and view and view.avatar and state.aim_point and true or false
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

function M.apply(env, dt)
	local want = M.wanted(env)
	M.weight = rig.ease(M.weight, want and 1 or 0, M.RATE, dt or 0.016)
	if M.weight < 0.01 then return false end
	local view = env.view
	local avatar = view and view.avatar
	local point = env.state.aim_point
	local U, Q, W = g("Unit"), g("Quaternion"), g("World")
	if not (avatar and point and U.alive(avatar) and U.has_node(avatar, "r_hand_attach")) then return false end
	local hand = U.node(avatar, "r_hand_attach")
	local f = Q.forward(U.world_rotation(avatar, hand))
	local p = U.world_position(avatar, hand)
	local to = { x = point.x - p.x, y = point.y - p.y, z = point.z - p.z }
	if to.x * to.x + to.y * to.y < 1 then return false end
	local b = M.bend(M.pitch_of({ x = f.x, y = f.y, z = f.z }), M.pitch_of(to)) * M.weight
	if math.abs(b) < 0.2 then return false end
	local nodes = {}
	for _, n in ipairs(M.SPINE) do if U.has_node(avatar, n) then nodes[#nodes + 1] = U.node(avatar, n) end end
	if #nodes == 0 then return false end
	local right = Q.right(U.world_rotation(avatar, 0))
	local turn = Q(right, math.rad(b / #nodes))
	for _, i in ipairs(nodes) do
		local wr = U.world_rotation(avatar, i)
		U.set_local_rotation(avatar, i, Q.multiply(U.local_rotation(avatar, i), Q.multiply(Q.inverse(wr), Q.multiply(turn, wr))))
	end
	local world = view.world
	if world then
		W.update_unit(world, avatar)
		for _, u in ipairs(linked(env.api, avatar)) do W.update_unit(world, u) end
	end
	return true
end

function M.start(env)
	if env.config.get("aim_pose") == false then M.off = true end
	env.config.on_change("aim_pose", function(v) M.off = v == false end)
	local failed = false
	obsidian.hook("StateGame", "post_update", function(original, self, dt, ...)
		local r = { original(self, dt, ...) }
		if not failed and not M.off then
			local ok, err = pcall(M.apply, env, type(dt) == "number" and dt or 0.016)
			if not ok then
				failed = true
				env.log("Eyes of Liberty: aim pose stopped: " .. tostring(err))
			end
		end
		return unpack(r, 1, table.maxn(r))
	end, env.VIEW)
	table.insert(env.on_release, function() M.weight = 0 end)
end

return M
