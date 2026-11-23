-- Throw arc: the game's throw maths and the flight.
local function arc() return obsidian.module("src/arc") end
local grenade = { throw_distance_min = 2, throw_distance_max = 9 }
-- The Rumbler's and the Obliterator's shells throw as far as an impact grenade.
local mortar = { throwable_info = grenade, explosive_info = { blast_radius = 3.5 } }

-- Where (y) a shell from start with velocity v (along y) comes down through the height h, damped as
-- shells fly in game.
local function landing(start, v, h)
	local m = obsidian.module("src/arc")
	local flat = math.sqrt(v.x * v.x + v.y * v.y)
	local speed = math.sqrt(flat * flat + v.z * v.z)
	return start.y + m.lob_reach(start, math.atan2(v.z, flat), speed, h, m.LOB_DAMPING)
end

return {
	{ "standing still, the power is the charge times the multiplier", function()
		near(arc().power(0.5, { x = 0, y = 0 }, { x = 0, y = 1, z = 1 }, 1.5), 0.75)
	end },

	{ "running along the throw raises the power up to 1.5 times", function()
		near(arc().power(1, { x = 0, y = 6 }, { x = 0, y = 1, z = 1 }, 1), 1.5, "fast along")
		near(arc().power(0.4, { x = 0, y = -6 }, { x = 0, y = 1, z = 1 }, 1), 0.16, "running away: no less than charge squared")
	end },

	{ "on flat ground a throw lands its distance away, as gravity 18 at 45 degrees gives", function()
		local m = arc()
		local v, distance = m.launch(grenade, 1, { x = 0, y = 1, z = 1 })
		eq(distance, 9)
		local _, land = m.fly({ x = 0, y = 0, z = 0 }, v, function(a, b)
			if b.z <= 0 and a.z > 0 or (b.z < 0 and a.y > 0) then
				local s = a.z / (a.z - b.z)
				return { x = a.x + (b.x - a.x) * s, y = a.y + (b.y - a.y) * s, z = 0 }
			end
		end)
		assert(land, "lands")
		near(land.y, 9, "nine metres", 0.05)
	end },

	{ "the Rumbler's power: the charge, at least the shortest, each shell of the burst weaker", function()
		local m = arc()
		local rumbler = { fire_on_release = true, power = 0.4, charge_max_extra_power = 1.7, max_charge_time = 1,
			min_charge_time = 0.25, burst_round_power_decrease = 0.2, burst_rounds = 3 }
		rumbler.shot_charge_timer = 0
		near(m.lob_power(rumbler, 1), 0.825, "the shortest shot that goes")
		rumbler.shot_charge_timer = 1
		near(m.lob_power(rumbler, 1), 2.1, "full") near(m.lob_power(rumbler, 2), 1.9, "second shell")
		near(m.lob_power(rumbler, 3), 1.5, "third shell, as seen in game")
		near(m.lob_charge(rumbler), 1)
		rumbler.shot_charge_timer = 0.5
		near(m.lob_charge(rumbler), 0.5)
		near(m.lob_power({ power = 1 }, 1), 1, "a set power")
	end },

	{ "Rumbler shells keep the game's angle and never land on the Helldiver, aimed anywhere", function()
		local m = arc()
		local rumbler = { fire_on_release = true, power = 0.4, charge_max_extra_power = 1.7, max_charge_time = 1,
			min_charge_time = 0.25, burst_round_power_decrease = 0.2, burst_rounds = 3, z_direction = math.rad(50), shot_charge_timer = 0 }
		local muzzle = { x = 0, y = 0.3, z = 1.2 }
		for _, target in ipairs({ { x = 0, y = 1, z = 300 }, { x = 0, y = 2, z = 0 }, { x = 0, y = 60, z = 0 } }) do
			local shells = m.lob_shells(rumbler, mortar, muzzle, { x = 0, y = 1, z = 0 }, target)
			eq(#shells, 3, "the burst")
			local last = math.huge
			for i, s in ipairs(shells) do
				near(math.atan2(s.v.z, s.v.y), math.atan(math.rad(50)), "the game's angle", 1e-9)
				local y = landing(s.start, s.v, 0)
				assert(y > 3.5 + 1, "clear of the blast: shell " .. i .. " at " .. y)
				assert(y < last, "each shell shorter") last = y
			end
		end
		rumbler.shot_charge_timer = 1
		local full = m.lob_shells(rumbler, mortar, muzzle, { x = 0, y = 1, z = 0 })
		assert(landing(full[1].start, full[1].v, 0) > 15, "a full charge flies far")
	end },

	{ "an Obliterator shell lands on the crosshair point within reach, at 45 degrees past it", function()
		local m = arc()
		local obliterator = { power = 1, z_direction = math.rad(50) }
		local muzzle = { x = 0, y = 0.3, z = 1.2 }
		for _, target in ipairs({ { x = 0, y = 6, z = 0 }, { x = 0, y = 9, z = 1 }, { x = 0, y = 7, z = -1 } }) do
			local s = m.lob_shells(obliterator, mortar, muzzle, { x = 0, y = 1, z = 0 }, target)[1]
			near(landing(s.start, s.v, target.z), target.y, "lands on the point", 1e-3)
		end
		-- The crosshair right in front: the shell lands clear of the blast.
		local close = m.lob_shells(obliterator, mortar, muzzle, { x = 0, y = 1, z = 0 }, { x = 0, y = 1, z = 0 })[1]
		near(landing(close.start, close.v, 0), 0.3 + 3.5 + m.LOB_CLEAR, "pushed out", 1e-3)
		-- Out of reach: the angle that reaches farthest, a little under 45 degrees with the damping.
		local far = m.lob_shells(obliterator, mortar, muzzle, { x = 0, y = 1, z = 0 }, { x = 0, y = 80, z = 0 })[1]
		local a = math.deg(math.atan2(far.v.z, far.v.y))
		assert(a > 35 and a <= 45, "out of reach: " .. a)
		local start = m.lob_start(muzzle, { x = 0, y = 1, z = 0 })
		near(start.y, 1.3, "a metre out") near(start.z, 2.2, "a metre up")
	end },

	{ "shells land where the game landed them: damped flights against the probe of 2026-11-23", function()
		local m = arc()
		-- spawn y, spawn z, way z over a flat way of 1, power, boom y, boom z; throw range doubled.
		for _, s in ipairs({ { 182.17, 2.10, 0.87, 2.1, 213.59, 0.49 }, { 182.05, 2.17, 0.87, 1.5, 206.25, 0.66 },
			{ 182.12, 2.00, 0.87, 0.629, 195.57, 0.50 }, { 182.58, 2.42, -0.20, 1.0, 188.23, 0.49 } }) do
			local speed = m.lob_speed(grenade, s[4], 2)
			local r = m.lob_reach({ x = 0, y = s[1], z = s[2] }, math.atan(s[3]), speed, s[6], m.LOB_DAMPING)
			near(s[1] + r, s[5], "power " .. s[4], 0.35)
		end
	end },

	{ "a Rumbler burst keeps the arc shown at release while the shells fly", function()
		local m = arc()
		m.frame = 100
		m.shown = { points = {}, rings = { { at = { x = 0, y = 30, z = 0 }, radius = 3.5, line = true } }, scroll = 0,
			frame = 99, span = m.LOB_FREEZE, lob = true }
		m.lob_fired()
		eq(m.frozen.rings[1].at.y, 30, "the rings at release") eq(m.frozen.span, m.LOB_FREEZE)
		near(m.freeze_alpha(m.LOB_FREEZE / 2, m.frozen.span), 0.5, "fades over the flight")
		eq(m.freeze_alpha(1.2), 0, "a throw's still fades over a second")
		-- No live arc over it, nor while the burst goes.
		local env = { view = { avatar = "me" }, state = { aiming = true }, api = { game = { master = function() return { rounds = 3 } end } } }
		local had = rawget(_G, "EntityAux")
		EntityAux = { state = function() return { current_weapon = "rumbler" } end }
		eq(m.lob_held(env), nil, "frozen")
		m.frozen = nil
		env.api.game.master = function() return { rounds = 3, burst_timer = 0.1 } end
		eq(m.lob_held(env), nil, "burst on the way")
		EntityAux = had
		m.shown = nil
	end },

	{ "the doubled throw range doubles both distances", function()
		local _, d = arc().launch(grenade, 0, { x = 0, y = 1, z = 1 }, 2)
		eq(d, 4)
	end },

	{ "an aimed throw lands on the point, near, far, above and below", function()
		local m = arc()
		local start = { x = 0, y = 0, z = 1.5 }
		local top = m.top_speed(grenade, 1)
		near(top, math.sqrt(9 * 18), "top speed from the longest throw")
		for _, target in ipairs({ { x = 0, y = 4, z = 0 }, { x = 3, y = 7, z = 0 }, { x = 0, y = 6, z = 3 }, { x = -2, y = 2, z = -2 } }) do
			local v = m.aimed(start, target, top, { x = 0, y = 1 })
			local sp = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
			assert(sp <= top + 1e-6, "no faster than the top speed")
			-- Where the flight passes the target's flat distance, it is at the target's height.
			local flat = math.sqrt(v.x * v.x + v.y * v.y)
			local d = math.sqrt(target.x * target.x + target.y * target.y)
			local t = d / flat
			near(start.z + v.z * t - m.GRAVITY * t * t / 2, target.z, "height at the point", 1e-6)
			near(v.x * t, target.x, "x", 1e-6) near(v.y * t, target.y, "y", 1e-6)
		end
	end },

	{ "an aimed throw flies low: LOB degrees over the line when the top speed allows", function()
		local m = arc()
		local v = m.aimed({ x = 0, y = 0, z = 0 }, { x = 0, y = 5, z = 0 }, 100)
		near(math.deg(math.atan2(v.z, v.y)), m.LOB, "angle", 1e-6)
	end },

	{ "an aimed throw out of reach goes at 45 degrees at the top speed", function()
		local m = arc()
		local v = m.aimed({ x = 0, y = 0, z = 0 }, { x = 0, y = 300, z = 0 }, 10)
		near(v.y, v.z, "45 degrees", 1e-6)
		near(math.sqrt(v.y * v.y + v.z * v.z), 10, "top speed", 1e-6)
	end },

	{ "an aimed throw near the top speed's reach takes the lowest arc it can", function()
		local m = arc()
		local top = 12
		local v = m.aimed({ x = 0, y = 0, z = 0 }, { x = 0, y = 7.5, z = 0 }, top)
		near(math.sqrt(v.y * v.y + v.z * v.z), top, "top speed", 1e-6)
		local t = 7.5 / v.y
		near(v.z * t - m.GRAVITY * t * t / 2, 0, "lands on the point", 1e-6)
		assert(math.deg(math.atan2(v.z, v.y)) > m.LOB, "steeper than the wanted lob")
	end },

	{ "dashes are spaced along the flight and scroll", function()
		local m = arc()
		local line = { { x = 0, y = 0, z = 0 }, { x = 0, y = 3, z = 0 } }
		local d = m.along(line, 1, 0.25)
		eq(#d, 3) near(d[1].y, 0.25) near(d[3].y, 2.25) eq(d[1].dy, 1)
	end },
}
