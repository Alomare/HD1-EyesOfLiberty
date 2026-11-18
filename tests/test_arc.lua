-- Throw arc: the game's throw maths and the flight.
local function arc() return obsidian.module("src/arc") end
local grenade = { throw_distance_min = 2, throw_distance_max = 9 }

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
