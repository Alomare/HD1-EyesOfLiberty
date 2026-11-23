-- Stratagems come from the ship (src/strikes.lua): the way down from the ship, and the game's casts turned.
local function strikes() return obsidian.module("src/strikes") end

return {
	{ "the way up points at the ship, at the ship's height over the horizon", function()
		local s = strikes()
		local ship = obsidian.module("src/ship")
		local d = s.toward(0)
		near(math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1, "a unit way", 1e-12)
		near(math.atan2(d.z, d.x), ship.ELEVATION, "the ship's elevation", 1e-12)
		near(d.y, 0, "on the bearing", 1e-12)
		-- The turn about the axis across the bearing takes straight up there.
		local axis, angle = s.tilt(0)
		near(axis.y, 1) near(angle, math.pi / 2 - ship.ELEVATION, nil, 1e-12)
	end },

	{ "a straight-down cast comes from the ship's way at the same height, and meets the same spot", function()
		local s = strikes()
		local from, dir, length = s.cast({ x = 10, y = 20, z = 25 }, { x = 0, y = 0, z = -1 }, 50, 0, 25)
		near(from.z, 25, "as high as the game's", 1e-9)
		eq(from.x > 10, true, "out toward the ship")
		-- Along dir from `from`, the ray reaches the spot after 25 / -dir.z.
		local t = 25 / -dir.z
		near(from.x + dir.x * t, 10, "the same spot", 1e-9) near(from.y + dir.y * t, 20, nil, 1e-9)
		near(length, 50 / s.toward(0).z, "longer by as much", 1e-9)
		local f2, d2, l2 = s.cast({ x = 1, y = 2, z = 3 }, { x = 1, y = 0, z = 0 }, 7, 0, 25)
		eq(f2.x, 1) eq(d2.x, 1) eq(l2, 7, "any other cast is left alone")
	end },

	{ "a falling shell goes STRETCH times as far out, once per placing by the animation", function()
		local s = strikes()
		local at = { [1] = { x = 0, y = -1, z = 18 }, [2] = { x = 0, y = 0, z = 0 } }
		local U = {
			num_scene_graph_items = function() return 3 end,
			scene_graph_parent = function(_, i) return i == 1 and 0 or 1 end,
			local_position = function(_, i) local p = at[i] return { x = p.x, y = p.y, z = p.z } end,
			set_local_position = function(_, i, v) at[i] = v end,
		}
		local V3 = function(x, y, z) return { x = x, y = y, z = z } end
		local shell = { unit = "shell", nodes = s.top_nodes(U, "shell"), last = {} }
		eq(#shell.nodes, 1, "only the part right under the root")
		s.push(U, V3, shell)
		near(at[1].z, 18 * s.STRETCH, "out along the axis") near(at[1].y, -s.STRETCH)
		s.push(U, V3, shell)
		near(at[1].z, 18 * s.STRETCH, "left by the animation: not pushed again")
		at[1] = { x = 0, y = -0.5, z = 9 }
		s.push(U, V3, shell)
		near(at[1].z, 9 * s.STRETCH, "placed again: pushed again")
	end },
}
