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

	{ "dashes are spaced along the flight and scroll", function()
		local m = arc()
		local line = { { x = 0, y = 0, z = 0 }, { x = 0, y = 3, z = 0 } }
		local d = m.along(line, 1, 0.25)
		eq(#d, 3) near(d[1].y, 0.25) near(d[3].y, 2.25) eq(d[1].dy, 1)
	end },
}
