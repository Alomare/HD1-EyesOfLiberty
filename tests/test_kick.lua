-- Explosion kick (src/kick.lua): how strong, which way, how it moves, and repeats wearing it down.
local function kick()
	local k = obsidian.module("src/kick")
	k.clear()
	return k
end

-- Runs the springs for `seconds` at 60 frames a second; answers the largest roll, pitch and lift seen.
local function run(k, seconds)
	local most = { 0, 0, 0 }
	for _ = 1, math.floor(seconds * 60) do
		local r, p, l = k.step(1 / 60, 1)
		if math.abs(r) > math.abs(most[1]) then most[1] = r end
		if p > most[2] then most[2] = p end
		if l > most[3] then most[3] = l end
	end
	return most
end

local function env_at(view, cfg)
	cfg = cfg or {}
	return { state = { active = true }, view = view, config = { get = function(k) return cfg[k] end } }
end

return {
	{ "strength grows with the blast and falls with distance", function()
		local k = kick()
		local frag = k.energy({ center_power = 600, center_radius = 1.75, blast_power = 250, blast_radius = 3.5 })
		eq(frag, 1925, "a frag grenade")
		eq(k.energy({ center_power = 0, blast_power = 0, blast_radius = 5 }), 0, "smoke: nothing")
		eq(k.strength(192, 0), 0, "a napalm tick: below LEAST")
		local near_frag, far_frag = k.strength(frag, 1), k.strength(frag, 8)
		eq(near_frag > 0 and near_frag < 0.4, true, "a grenade next to you: a small kick")
		eq(far_frag, 0, "a grenade 8 m off: nothing")
		local bomb = k.TEMPLATE.hellbomb_explosion
		eq(k.strength(bomb, 0), 1, "a Hellbomb: the full kick")
		eq(k.strength(bomb, 30) > 0, true, "and still felt 30 m off")
		eq(k.strength(bomb, 10) > k.strength(bomb, 20), true, "less the farther")
		eq(k.strength(k.TEMPLATE.airstrike, 3) > k.strength(frag, 3), true, "an airstrike kicks more than a grenade")
	end },

	{ "the view rolls away from the blast", function()
		local k = kick()
		local right = { x = 1, y = 0 }
		eq(k.side({ x = 1, y = 0 }, right), -1, "blast on the right: roll left")
		eq(k.side({ x = -1, y = 0 }, right), 1, "on the left: roll right")
		eq(k.side({ x = 0, y = 1 }, right, -1), -1, "ahead: the coin picks")
	end },

	{ "a kick snaps to its size and settles back", function()
		local k = kick()
		k.kick(1, -1)
		local most = run(k, 0.4)
		near(most[1], -k.ROLL, "rolls the full amount, left", 0.6)
		near(most[2], k.PITCH, "tips up", 0.3)
		near(most[3], k.LIFT, "rises", 0.02)
		run(k, 2)
		local r, p, l = k.step(1 / 60, 1)
		near(r, 0, "back level", 0.01) near(p, 0, nil, 0.01) near(l, 0, nil, 0.001)
		k.kick(1, 1)
		local r0 = k.step(1 / 60, 0)
		eq(r0, 0, "Camera shake off: nothing")
	end },

	{ "blasts in a row kick less each time, and fresh again after a rest", function()
		local k = kick()
		local first = k.kick(0.5, 1)
		local second = k.kick(0.5, 1)
		local third = k.kick(0.5, 1)
		eq(first, 0.5) eq(second < first, true) eq(third < second, true, "a barrage wears down")
		for _ = 1, 600 do k.step(1 / 60, 1) end
		near(k.kick(0.5, 1), 0.5, "rested: full again", 0.02)
	end },

	{ "the same blast heard twice kicks once", function()
		local k = kick()
		local view = { position = { x = 0, y = -3, z = 2 }, pivot = { x = 0, y = 0, z = 1.5 }, yaw = 0 }
		local env = env_at(view)
		local p = { x = 1, y = 1, z = 0 }
		eq(k.blast(env, 2000, p) > 0, true)
		eq(k.blast(env, 2000, { x = 1.5, y = 1, z = 0 }), 0, "the shake of the same blast")
		eq(k.blast(env_at(view, { explosion_kick = false }), 40000, { x = 30, y = 30, z = 0 }), 0, "option off")
		env.state.active = false
		eq(k.blast(env, 40000, { x = -20, y = 0, z = 0 }), 0, "top-down view: nothing")
	end },
}
