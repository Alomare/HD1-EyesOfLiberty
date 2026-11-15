-- First person arms: a rig of the mod's own in front of the camera, holding the player's own weapon.
--
-- The game draws a Helldiver as body part units (body, helmet, cape...) skinned bone by bone onto the
-- character's skeleton (CustomizationComponent, UnitAux.skin_item). The arms here are one more copy of
-- the player's body unit, spawned unlinked, so its bones take whatever pose the mod gives them:
--   - the torso, legs and head shrink to a point behind the camera (hips and spine1 scaled to nothing,
--     the shoulders scaled back up), so only the arms show, and only the suit mesh (mesh 1; 0 is the
--     waist piece, 2 the armour plates). The root stays full size, ahead of and below the camera: the
--     engine culls the mesh by a box round the root, which must stay in view
--   - the shoulders sit at fixed points of the camera, and two-bone IK brings the hands to the weapon
--   - the fingers copy the character's own fingers, which the game animates round the grip
--   - the weapon is the real one, moved from the character's hand to the right hand of the rig, so the
--     muzzle flash, the laser sight and the weapon's own animation show in view. The shots still leave
--     from the character, as the game aims them; other players see nothing of this
--   - the left hand takes its place on the weapon from the character's animation (the game's grip for
--     that weapon, and its reload), relative to the weapon
--   - throwing, calling stratagems, using things, reviving and carrying: the arms blend over to the
--     character's own arms, as the game animates them, moved from its head to the camera. A grenade or
--     stratagem ball in either hand moves into the rig's hand the way the weapon does
-- src/fpanim.lua moves the weapon: holds, sprint, reload, dive, downed, bob, sway, recoil. The character
-- itself is hidden mesh by mesh while the rig shows, and everything is given back as it was.
local pose = obsidian.module("src/pose")
local fpanim = obsidian.module("src/fpanim")

local M = {}

local function g(name) return rawget(_G, name) end

M.COLLAPSE = 1e-4          -- the scale that shrinks the torso, legs and head to a point
M.BEHIND = 0.35            -- metres behind the camera where they shrink to
M.ROOT = { ahead = 0.3, down = 1.3 } -- where the root sits from the camera, along the ground and down
M.SHOULDER = { side = 0.18, down = 0.21, back = 0.07 } -- the shoulders, from the camera
M.REACH = 0.3              -- metres a shoulder may move toward a hand out of reach, as a shoulder blade does
M.POLE = { side = 0.30, down = 0.55, back = 0.15 }    -- where the elbows point, from each shoulder
M.SHOW_MESH = 1            -- the suit
M.GRIP_REACH = { rifle = 0.45, pistol = 0.2 } -- metres from the weapon within which the character's left hand holds it
M.FREE_HAND = { x = -0.32, y = -0.05, z = -0.75 } -- where a left hand with nothing to hold goes, out of view
M.HAND_RATE = 18           -- how fast the left hand moves to a new place on the weapon (ease rate)
M.RELINK = 0.06            -- metres off where the weapon should be before it is taken back from the game
M.RECHECK = 60             -- frames between looks for new body part meshes to hide
M.PARTS = { "helmet", "body", "cape", "heavy_armor", "boots", "holstered", "backpack" }
M.HINGE_FRAMES = 20        -- bent-arm frames averaged for each elbow's hinge

-- The states where the weapon goes out of view: the hands are busy with something else.
M.AWAY_STATES = {
	CharacterStateSwitchWeapon = true, CharacterStateDownedSwitchWeapon = true, CharacterStateStratagems = true,
	CharacterStateStratagemsThrow = true, CharacterStateDownedStratagems = true, CharacterStateDownedStratagemsThrow = true,
	CharacterStateThrow = true, CharacterStateDownedThrow = true, CharacterStateInteract = true,
	CharacterStateInteractObjective = true, CharacterStateRevive = true, CharacterStateCarry = true, CharacterStateMap = true,
	CharacterStateKnockedDown = true,
	CharacterStateDownedKnockedDown = true, CharacterStateDownedGetUp = true, CharacterStateSeated = true,
	CharacterStateExtract = true, CharacterStateTeleport = true, CharacterStateDialogue = true, CharacterStateSleep = true,
	CharacterStateJump = true,
}
M.RELOAD_STATES = { CharacterStateReload = true, CharacterStateDownedReload = true }
M.MELEE_STATES = { CharacterStateMelee = true, CharacterStateDownedMelee = true }
-- The states the character's own arms show in, with the game's animation.
M.LIVE_STATES = {
	CharacterStateThrow = true, CharacterStateDownedThrow = true, CharacterStateStratagems = true,
	CharacterStateStratagemsThrow = true, CharacterStateDownedStratagems = true, CharacterStateDownedStratagemsThrow = true,
	CharacterStateInteract = true, CharacterStateInteractObjective = true, CharacterStateRevive = true, CharacterStateCarry = true,
}
M.LIVE_RATE = 10           -- how fast the arms go over to the character's and back (ease rate)
M.LIVE_OFFSET = { x = 0.05, y = 0.16, z = 0.07 } -- where the character's head lands, from the camera
M.LIVE_TILT = 14            -- degrees the character's arms tilt up, into view
-- The states where the character holds the weapon as it should be held: its left hand is learnt there.
M.HOLD_STATES = {
	CharacterStateIdle = true, CharacterStateWalk = true, CharacterStateAim = true, CharacterStateAimWalk = true,
	CharacterStateFire = true, CharacterStateAimFire = true, CharacterStateWalkFire = true, CharacterStateAimWalkFire = true,
	CharacterStateDownedIdle = true, CharacterStateDownedAim = true, CharacterStateDownedAimFire = true,
}
-- The rig goes away in these: the camera is elsewhere, or there is no body to hold anything.
M.OFF_STATES = { CharacterStateDead = true, CharacterStateCutscene = true }

-- Unit names by the id the engine prints for a unit ("[#ID[...]]"): the weapons, so the family can be
-- told (murmur64 of the equipment path, as the engine hashes resource names).
M.NAMES = {
	e7d373e49b87d4ba = "equipment/wep_assaultrifle_01", d680178da7fe9268 = "equipment/wep_assaultrifle_02",
	["75c4b9fee32fefbd"] = "equipment/wep_assaultrifle_03", d0f23cd2604fc7cb = "equipment/wep_pistol_01",
}
function M.name_of(unit)
	local s = tostring(unit)
	local hex = s:match("#ID%[(%x+)%]")
	return hex and M.NAMES[hex:lower()] or nil
end

local rig = nil       -- the arms: { unit, world, path, node = {}, fingers = {}, arm = { l = {}, r = {} } }
local held = nil      -- the weapon taken from the character
local items = {}      -- other things taken from its hands: unit -> { side, rel_pos, rel_rot, saved, ... }
local live = { w = 0 } -- how far the arms are the character's own
local hidden = {}     -- unit -> { [mesh] = shown before }
local seen = { avatar = nil, frame = -1000 }
local anim = fpanim.new()
local last = { yaw = nil, pitch = nil, pos = nil, rounds = nil, weapon = nil }
local hand = { pos = nil, rot = nil } -- the left hand, relative to the weapon
local frame = 0
M.why = nil           -- why the rig is off, for the log

-- Engine values to plain tables and back ----------------------------------------------------------

local function vec(v) return { x = v.x, y = v.y, z = v.z } end
local function quat(q)
	local x, y, z, w = g("Quaternion").to_elements(q)
	return { x = x, y = y, z = z, w = w }
end
local function V(p) return g("Vector3")(p.x, p.y, p.z) end
local function Qe(q) return g("Quaternion").from_elements(q.x, q.y, q.z, q.w) end
local function matrix(p, q) return g("Matrix4x4").from_quaternion_position(Qe(q), V(p)) end

local function world_of_node(unit, node)
	local U = g("Unit")
	return vec(U.world_position(unit, node)), quat(U.world_rotation(unit, node))
end

-- The body part meshes of the character, hidden while the rig shows -------------------------------

-- A unit given back as it was, and forgotten: the weapon in hand, which the rig shows.
local function unhide(u)
	local kept = hidden[u]
	if not kept then return end
	hidden[u] = nil
	local U = g("Unit")
	pcall(function()
		if U.alive(u) then
			for i, was in pairs(kept) do if was then U.set_mesh_visibility(u, i, true) end end
		end
	end)
end

local function hide_parts(api, avatar, keep)
	for u in pairs(keep) do unhide(u) end
	local world = api and api.world
	if not (world and world.part_units) then return end
	if seen.avatar == avatar and frame - seen.frame < M.RECHECK then return end
	seen.avatar, seen.frame = avatar, frame
	local U = g("Unit")
	for _, kind in ipairs(M.PARTS) do
		local ok, units = pcall(world.part_units, avatar, kind)
		for _, u in ipairs(ok and units or {}) do
			if not keep[u] then
				local kept = hidden[u]
				if not kept then kept = {} hidden[u] = kept end
				local n = U.num_meshes(u)
				for i = 0, n - 1 do
					if kept[i] == nil then
						kept[i] = U.mesh_visibility(u, i) and true or false
						U.set_mesh_visibility(u, i, false)
					end
				end
			end
		end
	end
end

local function show_parts()
	local U = g("Unit")
	for u, kept in pairs(hidden) do
		pcall(function()
			if U.alive(u) then
				for i, was in pairs(kept) do if was then U.set_mesh_visibility(u, i, true) end end
			end
		end)
	end
	hidden = {}
	seen.avatar, seen.frame = nil, -1000
end

-- The weapon ------------------------------------------------------------------------------------------

-- The weapon in the character's hand, its component and slot, or nil.
function M.wielded(api, avatar)
	local gear = api and api.gear
	if not (gear and gear.weapons_of) then return nil end
	local ok, list = pcall(gear.weapons_of, avatar)
	if not ok or type(list) ~= "table" then return nil end
	for _, w in ipairs(list) do
		local ctx = api.game.slaves("equipment")[w.unit]
		if ctx and ctx.state and ctx.state.wielded then return w end
	end
	return nil
end

local function give_back()
	if not held then return end
	local U, W = g("Unit"), g("World")
	local h = held
	held = nil
	pcall(function()
		if not (U.alive(h.unit) and U.alive(h.avatar)) then return end
		W.unlink_unit(h.world, h.unit)
		W.link_unit(h.world, h.unit, 0, h.avatar, U.node(h.avatar, "r_hand_attach"))
		U.set_local_pose(h.unit, 0, h.saved)
	end)
end

-- Takes the weapon from the character's right hand into the rig's. Only a weapon that sits in the right
-- hand right now is taken: one the game is just moving waits a frame.
local function take(w, avatar, world)
	local U, W = g("Unit"), g("World")
	if not (U.has_node(avatar, "r_hand_attach") and U.has_node(avatar, "r_wrist")) then return false end
	local attach = U.node(avatar, "r_hand_attach")
	local at = vec(U.world_position(avatar, attach))
	local wp = vec(U.world_position(w.unit, 0))
	if pose.length(pose.sub(at, wp)) > 0.05 then return false end
	-- The weapon in the frame of the right wrist: the attach node's local pose, then the weapon's own.
	local a_pos, a_rot = vec(U.local_position(avatar, attach)), quat(U.local_rotation(avatar, attach))
	local w_pos, w_rot = vec(U.local_position(w.unit, 0)), quat(U.local_rotation(w.unit, 0))
	local rel_pos, rel_rot = pose.compose(a_pos, a_rot, w_pos, w_rot)
	held = { unit = w.unit, avatar = avatar, world = world, saved = U.local_pose(w.unit, 0), rel_pos = rel_pos, rel_rot = rel_rot,
		component = w.component, slot = w.slot, info = w.info, expected = nil }
	W.unlink_unit(world, w.unit)
	W.link_unit(world, w.unit, 0, rig.unit, rig.node.r_wrist)
	U.set_local_pose(w.unit, 0, matrix(rel_pos, rel_rot))
	return true
end

-- Grenades, stratagem balls and the like: wielded equipment of the character that sits in a hand.
local function give_items()
	local U, W = g("Unit"), g("World")
	for u, it in pairs(items) do
		pcall(function()
			if not (U.alive(u) and U.alive(it.avatar)) then return end
			W.unlink_unit(it.world, u)
			W.link_unit(it.world, u, 0, it.avatar, U.node(it.avatar, it.side .. "_hand_attach"))
			U.set_local_pose(u, 0, it.saved)
		end)
	end
	items = {}
end

local function take_item(u, avatar, world, side)
	local U, W = g("Unit"), g("World")
	local attach = U.node(avatar, side .. "_hand_attach")
	local a_pos, a_rot = vec(U.local_position(avatar, attach)), quat(U.local_rotation(avatar, attach))
	local i_pos, i_rot = vec(U.local_position(u, 0)), quat(U.local_rotation(u, 0))
	local rel_pos, rel_rot = pose.compose(a_pos, a_rot, i_pos, i_rot)
	items[u] = { side = side, avatar = avatar, world = world, saved = U.local_pose(u, 0), rel_pos = rel_pos, rel_rot = rel_rot }
	W.unlink_unit(world, u)
	W.link_unit(world, u, 0, rig.unit, rig.node[side .. "_wrist"])
	U.set_local_pose(u, 0, matrix(rel_pos, rel_rot))
end

-- Takes what the character holds besides the weapon, and forgets what it let go of (thrown, put away:
-- the game moved those itself).
local function update_items(api, avatar, world, weapon)
	local U = g("Unit")
	local slaves = api.game.slaves("equipment")
	for u, it in pairs(items) do
		local ctx = slaves[u]
		local gone = not U.alive(u) or not (ctx and ctx.state and ctx.state.wielded and ctx.state.wielder == avatar)
		if not gone and it.expected then
			gone = pose.length(pose.sub(vec(U.world_position(u, 0)), it.expected)) > M.RELINK
		end
		if gone then items[u] = nil end
	end
	for u, ctx in pairs(slaves) do
		local st = type(ctx) == "table" and ctx.state
		if st and st.wielded and st.wielder == avatar and u ~= weapon and not items[u] and U.alive(u) then
			local at = vec(U.world_position(u, 0))
			for _, side in ipairs({ "l", "r" }) do
				if U.has_node(avatar, side .. "_hand_attach") then
					local hp = vec(U.world_position(avatar, U.node(avatar, side .. "_hand_attach")))
					if pose.length(pose.sub(at, hp)) < 0.05 then pcall(take_item, u, avatar, world, side) break end
				end
			end
		end
	end
end

-- The rig ---------------------------------------------------------------------------------------------

local function remove_rig()
	give_back()
	give_items()
	if rig then
		local U, W = g("Unit"), g("World")
		local r = rig
		rig = nil
		pcall(function() if U.alive(r.unit) then W.destroy_unit(r.world, r.unit) end end)
	end
end

local function body_path(api, avatar)
	local custom = api.game.slaves("customization")[avatar]
	local s = custom and custom.state
	local CS = g("CustomizationSettings")
	if not (s and CS and s.body and s.gender) then return nil end
	local ok, path = pcall(function() return CS.body[s.body][CS.gender[s.gender].name].unit_path end)
	return ok and type(path) == "string" and path or nil
end

local function make_rig(api, avatar, world, at)
	local U, W = g("Unit"), g("World")
	local path = body_path(api, avatar)
	if not path then return nil end
	local unit = W.spawn_unit(world, path, V(at))
	local r = { unit = unit, world = world, path = path, avatar = avatar, node = {}, fingers = {}, arm = {} }
	for _, b in ipairs(U.bones(unit)) do r.node[b] = U.node(unit, b) end
	for i = 0, U.num_meshes(unit) - 1 do U.set_mesh_visibility(unit, i, i == M.SHOW_MESH) end
	-- Torso, legs and head: hips and spine1 shrink everything under them to the boss bone.
	local M4 = g("Matrix4x4")
	local tiny = M4.identity()
	M4.set_scale(tiny, g("Vector3")(M.COLLAPSE, M.COLLAPSE, M.COLLAPSE))
	U.set_local_pose(unit, r.node.hips, tiny)
	U.set_local_pose(unit, r.node.spine1, tiny)
	for _, b in ipairs({ "spine2", "spine3", "spine4", "neck" }) do
		if r.node[b] then U.set_local_pose(unit, r.node[b], M4.identity()) end
	end
	-- Each arm: the bone directions and lengths of the bind pose.
	for _, side in ipairs({ "l", "r" }) do
		local up, el, wr = r.node[side .. "_shoulder"], r.node[side .. "_elbow"], r.node[side .. "_wrist"]
		local e, w = vec(U.local_position(unit, el)), vec(U.local_position(unit, wr))
		r.arm[side] = { shoulder = up, elbow = el, wrist = wr, a = pose.length(e), b = pose.length(w),
			d_up = pose.normalize(e), d_fore = pose.normalize(w), n_up = nil, n_fore = nil, sum_up = { x = 0, y = 0, z = 0 },
			sum_fore = { x = 0, y = 0, z = 0 }, frames = 0 }
	end
	-- The fingers copy the character's.
	for b, n in pairs(r.node) do
		if b:find("finger") and U.has_node(avatar, b) then r.fingers[#r.fingers + 1] = { U.node(avatar, b), n } end
	end
	return r
end

-- Each elbow's hinge in the frames of its two bones, from the character's arm while it is bent.
local function learn_hinges(avatar)
	local U = g("Unit")
	for side, arm in pairs(rig.arm) do
		if arm.frames < M.HINGE_FRAMES then
			local s, sq = world_of_node(avatar, U.node(avatar, side .. "_shoulder"))
			local e, eq = world_of_node(avatar, U.node(avatar, side .. "_elbow"))
			local w = vec(U.world_position(avatar, U.node(avatar, side .. "_wrist")))
			local u, f = pose.normalize(pose.sub(e, s)), pose.normalize(pose.sub(w, e))
			local n = pose.hinge(s, e, w)
			if n and pose.dot(u, f) < 0.9 then -- bent more than about 25 degrees
				arm.sum_up = pose.add(arm.sum_up, pose.rotate(pose.conj(sq), n))
				arm.sum_fore = pose.add(arm.sum_fore, pose.rotate(pose.conj(eq), n))
				arm.frames = arm.frames + 1
				arm.n_up, arm.n_fore = pose.normalize(arm.sum_up), pose.normalize(arm.sum_fore)
			end
		end
	end
end

-- A side's arm to a wrist pose: shoulder s, the wrist wanted at w_pos/w_rot, elbow toward pole.
-- Answers the world poses of the shoulder, elbow and wrist bones.
function M.solve_arm(arm, s, w_pos, w_rot, pole)
	local e, w = pose.two_bone(s, w_pos, arm.a, arm.b, pole)
	local n = pose.hinge(s, e, w) or pose.normalize(pose.cross(pose.sub(w, s), pose.sub(pole, s)))
	local n_up = arm.n_up or pose.normalize(pose.cross(arm.d_up, { x = 0, y = 0, z = 1 }), { x = 1, y = 0, z = 0 })
	local n_fore = arm.n_fore or pose.normalize(pose.cross(arm.d_fore, { x = 0, y = 0, z = 1 }), { x = 1, y = 0, z = 0 })
	local up_rot = pose.align(arm.d_up, n_up, pose.sub(e, s), n)
	local fore_rot = pose.align(arm.d_fore, n_fore, pose.sub(w, e), n)
	return { pos = s, rot = up_rot }, { pos = e, rot = fore_rot }, { pos = w, rot = w_rot }
end

local function place_arm(arm, spine_inv, sh, el, wr)
	local U, M4 = g("Unit"), g("Matrix4x4")
	U.set_local_pose(rig.unit, arm.shoulder, M4.multiply(matrix(sh.pos, sh.rot), spine_inv))
	local lp, lr = pose.relative(sh.pos, sh.rot, el.pos, el.rot)
	U.set_local_pose(rig.unit, arm.elbow, matrix(lp, lr))
	lp, lr = pose.relative(el.pos, el.rot, wr.pos, wr.rot)
	U.set_local_pose(rig.unit, arm.wrist, matrix(lp, lr))
end

-- The character's own arm, moved from its head to the camera: { pos, rot } for the shoulder, elbow and
-- wrist. head_pos/char_rot: the character's head and facing; anchor/cam_rot: where they land.
local function live_arm(avatar, side, head_pos, turn, anchor)
	local U = g("Unit")
	local out = {}
	for i, b in ipairs({ "_shoulder", "_elbow", "_wrist" }) do
		local p, q = world_of_node(avatar, U.node(avatar, side .. b))
		out[i] = { pos = pose.add(anchor, pose.rotate(turn, pose.sub(p, head_pos))), rot = pose.mul(turn, q) }
	end
	return out[1], out[2], out[3]
end

local function mix(a, b, t)
	return { pos = pose.lerp(a.pos, b.pos, t), rot = pose.nlerp(a.rot, b.rot, t) }
end

-- What the character is doing, for fpanim.
local function feel_of(env, avatar, view, dt)
	local EA = g("EntityAux")
	local name
	local ok, cs = pcall(EA.state_master, avatar, "character")
	if ok and type(cs) == "table" and type(cs.current_state) == "table" then name = cs.current_state.name end
	local ok_h, hs = pcall(EA.state, avatar, "health")
	hs = ok_h and type(hs) == "table" and hs or {}
	local sprint = false
	if ok and type(cs) == "table" then
		local a, b = g("CharacterStateSprint"), g("CharacterSubstateSprint")
		sprint = (a ~= nil and cs.current_state == a) or (b ~= nil and cs.current_substate == b)
	end
	local feel = { dt = dt, state = name, aim = env.state.aiming and true or false, sprint = sprint,
		reload = M.RELOAD_STATES[name] or false, away = M.AWAY_STATES[name] or not held, melee = M.MELEE_STATES[name] or false,
		dive = hs.is_dodging == true or name == "CharacterStateDodge", downed = hs.is_downed == true }
	-- Speed along the ground.
	local p = vec(g("Unit").world_position(avatar, 0))
	if last.pos and dt > 0 then
		local d = math.sqrt((p.x - last.pos.x) ^ 2 + (p.y - last.pos.y) ^ 2)
		feel.speed = d < 5 and d / dt or 0
	end
	last.pos = p
	-- The turn of the view.
	if last.yaw then
		local dy = (view.yaw - last.yaw + 540) % 360 - 180
		feel.turn = { yaw = dy, pitch = view.pitch - last.pitch }
	end
	last.yaw, last.pitch = view.yaw, view.pitch
	-- Shots: the rounds in the magazine going down; beam and flame weapons while they fire.
	if held then
		local okw, ws = pcall(EA.state_master, held.unit, held.component)
		ws = okw and type(ws) == "table" and ws or {}
		if ws.is_reloading then feel.reload = true end
		local rounds = tonumber(ws.rounds)
		if last.weapon == held.unit and rounds and last.rounds and rounds < last.rounds then feel.shots = last.rounds - rounds end
		last.weapon, last.rounds = held.unit, rounds
		feel.firing_beam = (ws.firing_auto or ws.firing_single) and true or false
	end
	return feel
end

-- The left hand on the weapon: where the character's own left hand is, relative to where the weapon
-- would be in its right hand. nil when that hand is elsewhere (a one-handed hold, a throw).
local function left_grip(avatar, family)
	local U = g("Unit")
	local wp, wq = world_of_node(avatar, U.node(avatar, "r_wrist"))
	local gp, gq = pose.compose(wp, wq, held.rel_pos, held.rel_rot)
	local lp, lq = world_of_node(avatar, U.node(avatar, "l_wrist"))
	if pose.length(pose.sub(lp, gp)) > (M.GRIP_REACH[family] or M.GRIP_REACH.rifle) then return nil end
	return pose.relative(gp, gq, lp, lq)
end

-- One frame of the rig, after the camera is placed. Answers whether it shows.
function M.update(env, view, dt)
	frame = frame + 1
	local api, U = env.api, g("Unit")
	local avatar = view.avatar
	if not (view.first and env.config.get("first_person_arms") ~= false) then M.why = "off" return false end
	if not (avatar and U.alive(avatar) and U.has_node(avatar, "r_wrist")) then M.why = "no body" return false end
	local EA = g("EntityAux")
	local ok, cs = pcall(EA.state_master, avatar, "character")
	local state_name = ok and type(cs) == "table" and type(cs.current_state) == "table" and cs.current_state.name or nil
	if M.OFF_STATES[state_name] then M.why = state_name return false end
	local world = U.world(avatar)

	local cam_rot = pose.euler(view.yaw, view.pitch, 0)
	local cam = view.position
	local right, fwd, upv = pose.rotate(cam_rot, { x = 1, y = 0, z = 0 }), pose.rotate(cam_rot, { x = 0, y = 1, z = 0 }), pose.rotate(cam_rot, { x = 0, y = 0, z = 1 })
	local behind = pose.mad(cam, fwd, -M.BEHIND)

	if rig and not (U.alive(rig.unit) and rig.world == world and rig.avatar == avatar and rig.path == body_path(api, avatar)) then remove_rig() end
	if not rig then
		rig = make_rig(api, avatar, world, behind)
		if not rig then M.why = "no body unit" return false end
		anim = fpanim.new()
		last.yaw, last.pos, last.rounds, last.weapon = nil, nil, nil, nil
		hand.pos, hand.rot = nil, nil
	end
	learn_hinges(avatar)

	-- The weapon: take the one in hand, give back one put away.
	local w = M.wielded(api, avatar)
	if held and (not w or w.unit ~= held.unit or not U.alive(held.unit)) then
		-- The game moved the old one itself (to the back, or dropped it): nothing to give back.
		held = nil
		hand.pos, hand.rot = nil, nil
	end
	if held and held.expected then
		local now = vec(U.world_position(held.unit, 0))
		if pose.length(pose.sub(now, held.expected)) > M.RELINK then held = nil end
	end
	if w and not held then pcall(take, w, avatar, world) end
	update_items(api, avatar, world, w and w.unit)

	local feel = feel_of(env, avatar, view, dt)
	local family = "rifle"
	if held then
		local sidearm = held.slot == "sidearm_weapon" or (type(held.info) == "table" and type(held.info.attributes) == "table" and held.info.attributes.sidearm)
		family = fpanim.family_of(M.name_of(held.unit), sidearm)
	end
	feel.family = family
	local held_pose = fpanim.step(anim, feel)

	-- The weapon in the world.
	local r = held_pose.rot
	local gun_rot = pose.mul(cam_rot, pose.euler(r.yaw, r.pitch, r.roll))
	local gun_pos = pose.add(cam, pose.rotate(cam_rot, held_pose.pos))
	local rel_pos, rel_rot = held and held.rel_pos or { x = 0, y = 0, z = 0 }, held and held.rel_rot or pose.IDENTITY
	-- The right wrist that puts the weapon there.
	local rw_rot = pose.mul(gun_rot, pose.conj(rel_rot))
	local rw_pos = pose.sub(gun_pos, pose.rotate(rw_rot, rel_pos))

	-- The left hand: on the weapon where the character holds it, else low and out of view.
	-- A grip seen once is kept for that weapon: the character holds a pistol two-handed only while it
	-- aims, and the rig always does.
	local grip_pos, grip_rot
	if held then
		-- Live in the holding states and the reload (the game's own hand on the magazine); kept only
		-- from the holding states.
		local live = M.HOLD_STATES[feel.state] or feel.reload
		local okg, gp, gq = false, nil, nil
		if live then okg, gp, gq = pcall(left_grip, avatar, family) end
		if okg and gp then
			if M.HOLD_STATES[feel.state] and not feel.reload then held.grip_pos, held.grip_rot = gp, gq end
		elseif held.grip_pos then
			okg, gp, gq = true, held.grip_pos, held.grip_rot
		end
		if okg and gp then
			if hand.pos then
				local t = 1 - math.exp(-M.HAND_RATE * dt)
				hand.pos, hand.rot = pose.lerp(hand.pos, gp, t), pose.nlerp(hand.rot, gq, t)
			else
				hand.pos, hand.rot = gp, gq
			end
		end
	end
	if hand.pos then
		grip_pos, grip_rot = pose.compose(gun_pos, gun_rot, hand.pos, hand.rot)
	else
		grip_pos = pose.add(cam, pose.rotate(cam_rot, M.FREE_HAND))
		grip_rot = pose.mul(cam_rot, pose.euler(0, -70, 0))
	end

	-- The skeleton: the root ahead and below, the shrunken torso behind the camera, then the arms.
	local M4 = g("Matrix4x4")
	local flat = pose.normalize({ x = fwd.x, y = fwd.y, z = 0 }, fwd)
	local root = pose.add(pose.mad(cam, flat, M.ROOT.ahead), { x = 0, y = 0, z = -M.ROOT.down })
	U.set_local_pose(rig.unit, 0, matrix(root, pose.IDENTITY))
	U.set_local_pose(rig.unit, rig.node.boss, matrix(pose.sub(behind, root), pose.IDENTITY))
	local spine = M4.from_quaternion_position(Qe(pose.IDENTITY), V(behind))
	M4.set_scale(spine, g("Vector3")(M.COLLAPSE, M.COLLAPSE, M.COLLAPSE))
	local spine_inv = M4.inverse(spine)
	-- The character's own arms: from its head and facing to the camera.
	live.w = live.w + ((M.LIVE_STATES[feel.state] and 1 or 0) - live.w) * (1 - math.exp(-M.LIVE_RATE * dt))
	local head_pos, turn, anchor
	if live.w > 0.002 and U.has_node(avatar, "head") then
		head_pos = vec(U.world_position(avatar, U.node(avatar, "head")))
		turn = pose.mul(pose.mul(cam_rot, pose.euler(0, M.LIVE_TILT, 0)), pose.conj(quat(U.world_rotation(avatar, 0))))
		anchor = pose.add(cam, pose.rotate(cam_rot, M.LIVE_OFFSET))
	end
	local wrists = {}
	for side, sign in pairs({ r = 1, l = -1 }) do
		local s = pose.add(cam, pose.rotate(cam_rot, { x = sign * M.SHOULDER.side, y = -M.SHOULDER.back, z = -M.SHOULDER.down }))
		local pole = pose.add(s, pose.rotate(cam_rot, { x = sign * M.POLE.side, y = -M.POLE.back, z = -M.POLE.down }))
		local wp, wq
		if side == "r" then wp, wq = rw_pos, rw_rot else wp, wq = grip_pos, grip_rot end
		local arm = rig.arm[side]
		local far = pose.length(pose.sub(wp, s)) - (arm.a + arm.b) * 0.97
		if far > 0 then s = pose.mad(s, pose.normalize(pose.sub(wp, s)), math.min(far, M.REACH)) end
		local sh, el, wr = M.solve_arm(arm, s, wp, wq, pole)
		if head_pos then
			local lsh, lel, lwr = live_arm(avatar, side, head_pos, turn, anchor)
			sh, el, wr = mix(sh, lsh, live.w), mix(el, lel, live.w), mix(wr, lwr, live.w)
		end
		place_arm(rig.arm[side], spine_inv, sh, el, wr)
		wrists[side] = wr
	end
	for i = 1, #rig.fingers do
		local f = rig.fingers[i]
		U.set_local_pose(rig.unit, f[2], U.local_pose(avatar, f[1]))
	end
	-- Where what the hands hold should be next frame: anywhere else, the game took it back.
	if held then held.expected = pose.compose(wrists.r.pos, wrists.r.rot, held.rel_pos, held.rel_rot) end
	local keep = {}
	if w then keep[w.unit] = true end
	for u, it in pairs(items) do
		local wr = wrists[it.side]
		it.expected = pose.compose(wr.pos, wr.rot, it.rel_pos, it.rel_rot)
		keep[u] = true
	end
	M.last = { cam = cam, rot = cam_rot, gun = gun_pos, right_wrist = rw_pos, left_wrist = grip_pos, family = family, feel = feel, live = live.w }
	hide_parts(api, avatar, keep)
	M.why = nil
	return true
end

function M.release()
	remove_rig()
	show_parts()
	live.w = 0
	last.yaw, last.pos, last.rounds, last.weapon = nil, nil, nil, nil
	hand.pos, hand.rot = nil, nil
end

function M.active() return rig ~= nil end

function M.start(env)
	-- After an error the rig rests a while before it tries again, and each message is logged once.
	local rest, said = 0, {}
	table.insert(env.on_pose, function(view, cm, dt)
		if rest > 0 then rest = rest - 1 return end
		local ok, on = pcall(M.update, env, view, dt or 0.016)
		if not ok then
			local text = tostring(on)
			if not said[text] then
				said[text] = true
				env.log("Unleashed Camera: first person arms: " .. text)
			end
			M.why = "error"
			rest = 300
		end
		if not (ok and on) and (rig or held or next(hidden) or next(items)) then M.release() end
	end)
	table.insert(env.on_release, function() M.release() end)
end

M._state = function() return { rig = rig, held = held, hidden = hidden, anim = anim, hand = hand, items = items, live = live } end -- for tests
return M
