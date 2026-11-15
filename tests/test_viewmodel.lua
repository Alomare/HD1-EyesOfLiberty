-- First person arms: the pose math (src/pose.lua), the weapon motion (src/fpanim.lua) and the pure parts
-- of the rig (src/viewmodel.lua).
local function P() return obsidian.module("src/pose") end
local function A() return obsidian.module("src/fpanim") end
local function VM() return obsidian.module("src/viewmodel") end

local function vnear(got, want, what, tol)
	near(got.x, want.x, (what or "v") .. ".x", tol or 1e-6)
	near(got.y, want.y, (what or "v") .. ".y", tol or 1e-6)
	near(got.z, want.z, (what or "v") .. ".z", tol or 1e-6)
end

local function idle_feel(extra)
	local f = { dt = 1 / 60, family = "rifle" }
	for k, v in pairs(extra or {}) do f[k] = v end
	return f
end

local function settle(st, feel, frames)
	local out
	for _ = 1, frames or 240 do out = A().step(st, feel) end
	return out
end

return {
	{ "a quarter turn about z takes x to y, and products turn right to left", function()
		local p = P()
		local q = p.axis_angle({ x = 0, y = 0, z = 1 }, math.pi / 2)
		vnear(p.rotate(q, { x = 1, y = 0, z = 0 }), { x = 0, y = 1, z = 0 }, "turned", 1e-9)
		local r = p.axis_angle({ x = 1, y = 0, z = 0 }, math.pi / 2)
		-- r first (y to z), then q (z stays z)
		vnear(p.rotate(p.mul(q, r), { x = 0, y = 1, z = 0 }), { x = 0, y = 0, z = 1 }, "composed", 1e-9)
		vnear(p.rotate(p.conj(q), p.rotate(q, { x = 0.3, y = -2, z = 5 })), { x = 0.3, y = -2, z = 5 }, "undone", 1e-9)
	end },
	{ "euler matches the camera: yaw about z, then pitch about the turned x", function()
		local p = P()
		local q = p.euler(90, 0, 0)
		vnear(p.rotate(q, { x = 0, y = 1, z = 0 }), { x = -1, y = 0, z = 0 }, "yaw 90 looks along -x", 1e-9)
		q = p.euler(0, 30, 0)
		local f = p.rotate(q, { x = 0, y = 1, z = 0 })
		near(f.z, math.sin(math.rad(30)), "pitch up", 1e-9)
		-- the same forward as src/rig.lua
		local rig = obsidian.module("src/rig")
		vnear(p.rotate(p.euler(37, -12, 0), { x = 0, y = 1, z = 0 }), rig.forward(37, -12), "rig forward", 1e-9)
	end },
	{ "align puts a local axis and hinge onto world ones", function()
		local p = P()
		local d_local, n_local = p.normalize({ x = 1, y = 0.2, z = 0 }), { x = 0, y = 0, z = 1 }
		local d, n = p.normalize({ x = 0.1, y = 0.4, z = -0.9 }), p.normalize({ x = 1, y = 0, z = 0.1 })
		local q = p.align(d_local, n_local, d, n)
		vnear(p.rotate(q, d_local), d, "axis", 1e-6)
		local got = p.rotate(q, n_local)
		near(p.dot(got, d), 0, "hinge square to the axis", 1e-6)
		near(p.dot(got, p.normalize(p.sub(n, p.scale(d, p.dot(n, d))))), 1, "hinge where asked", 1e-6)
	end },
	{ "two-bone IK reaches the wrist, keeps the bone lengths and bends toward the pole", function()
		local p = P()
		local s, w, pole = { x = 0, y = 0, z = 0 }, { x = 0.1, y = 0.4, z = -0.1 }, { x = 0.3, y = 0, z = -0.5 }
		local e, reached = p.two_bone(s, w, 0.26, 0.28, pole)
		vnear(reached, w, "wrist", 1e-9)
		near(p.length(p.sub(e, s)), 0.26, "upper arm", 1e-9)
		near(p.length(p.sub(reached, e)), 0.28, "forearm", 1e-9)
		local mid = p.lerp(s, w, 0.5)
		local toward = p.sub(pole, mid)
		near(p.dot(p.sub(e, mid), toward) > 0 and 1 or 0, 1, "elbow on the pole's side")
		-- out of reach: just short of straight, along the line
		local _, far = p.two_bone(s, { x = 0, y = 2, z = 0 }, 0.26, 0.28, pole)
		near(far.y, 0.539, "pulled in", 1e-9)
	end },
	{ "solve_arm gives bones that point where the IK put them", function()
		local p, vm = P(), VM()
		local arm = { a = 0.26, b = 0.28, d_up = { x = 1, y = 0, z = 0 }, d_fore = { x = 1, y = 0, z = 0 },
			n_up = { x = 0, y = 0, z = 1 }, n_fore = { x = 0, y = 0, z = 1 } }
		local s, w = { x = 0.18, y = -0.07, z = -0.21 }, { x = 0.18, y = 0.26, z = -0.2 }
		local sh, el, wr = vm.solve_arm(arm, s, w, p.IDENTITY, { x = 0.48, y = -0.2, z = -0.7 })
		vnear(p.add(sh.pos, p.scale(p.rotate(sh.rot, arm.d_up), arm.a)), el.pos, "upper arm ends at the elbow", 1e-6)
		vnear(p.add(el.pos, p.scale(p.rotate(el.rot, arm.d_fore), arm.b)), wr.pos, "forearm ends at the wrist", 1e-6)
		vnear(wr.pos, w, "wrist", 1e-6)
	end },
	{ "the character's own arms show in the busy states, never while it holds the weapon", function()
		local vm = VM()
		for _, s in ipairs({ "CharacterStateThrow", "CharacterStateStratagems", "CharacterStateInteract", "CharacterStateCarry" }) do
			eq(vm.LIVE_STATES[s], true, s)
		end
		for s in pairs(vm.LIVE_STATES) do
			eq(vm.HOLD_STATES[s], nil, s .. " is no holding state")
			eq(vm.RELOAD_STATES[s], nil, s .. " is no reload")
		end
	end },
	{ "weapons are told apart by the id the engine prints", function()
		local vm, a = VM(), A()
		eq(vm.name_of("[#ID[e7d373e49b87d4ba]]"), "equipment/wep_assaultrifle_01")
		eq(vm.name_of("[#ID[d0f23cd2604fc7cb]]"), "equipment/wep_pistol_01")
		eq(vm.name_of("[#ID[0000000000000001]]"), nil)
		eq(a.family_of("equipment/wep_assaultrifle_02"), "rifle")
		eq(a.family_of("equipment/wep_pistol_01"), "pistol")
		local fam, own = a.family_of("equipment/wep_shotgun_01", false)
		eq(fam, "rifle", "another weapon: the rifle hold") eq(own, false)
		eq(a.family_of(nil, true), "pistol", "another sidearm: the pistol hold")
	end },
	{ "standing still settles at the hip hold, aiming at the aim hold", function()
		local a = A()
		local st = a.new()
		local out = settle(st, idle_feel())
		local hip = a.FAMILIES.rifle.hip
		near(out.pos.x, hip.pos.x, "x", 0.002) near(out.pos.y, hip.pos.y, "y", 0.002) near(out.pos.z, hip.pos.z, "z", 0.005)
		eq(st.w.away < 0.01, true, "the weapon came up into view")
		out = settle(st, idle_feel({ aim = true }))
		local aim = a.FAMILIES.rifle.aim
		near(out.pos.x, aim.pos.x, "aim x", 0.002) near(out.pos.y, aim.pos.y, "aim y", 0.002)
	end },
	{ "a shot kicks the weapon back and up, and it springs home", function()
		local a = A()
		local st = a.new()
		local rest = settle(st, idle_feel())
		local kicked = a.step(st, idle_feel({ shots = 1 }))
		eq(kicked.pos.y < rest.pos.y - 0.01, true, "back")
		eq(kicked.rot.pitch > rest.rot.pitch + 1, true, "up")
		local back = settle(st, idle_feel(), 120)
		near(back.pos.y, rest.pos.y, "home", 0.002)
	end },
	{ "busy hands take the weapon out of view; sprint and reload turn it", function()
		local a = A()
		local st = a.new()
		settle(st, idle_feel())
		local away = settle(st, idle_feel({ away = true }), 120)
		eq(away.pos.z < -0.45, true, "below the view")
		local sprint = settle(st, idle_feel({ sprint = true, speed = 6 }))
		eq(sprint.rot.yaw > 20, true, "carried across")
		local reload = settle(st, idle_feel({ reload = true }))
		eq(reload.rot.roll > 15, true, "tilted to the magazine")
		local melee = settle(st, idle_feel({ melee = true }), 60)
		eq(melee.pos.y > a.FAMILIES.rifle.hip.pos.y + 0.1, true, "thrust forward")
	end },
	{ "walking bobs the weapon, turning sways it", function()
		local a = A()
		local st = a.new()
		local rest = settle(st, idle_feel())
		local lo, hi = math.huge, -math.huge
		for _ = 1, 120 do
			local p = a.step(st, idle_feel({ speed = 4 })).pos
			lo, hi = math.min(lo, p.x), math.max(hi, p.x)
		end
		eq(hi - lo > 0.01, true, "side to side")
		settle(st, idle_feel())
		local swayed = a.step(st, idle_feel({ turn = { yaw = 10, pitch = 0 } }))
		eq(swayed.rot.yaw < rest.rot.yaw - 0.5, true, "trails a turn to the left")
	end },
}
