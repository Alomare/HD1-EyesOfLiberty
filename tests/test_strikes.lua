-- Ship-bound stratagems (src/strikes.lua): the way down from the ship, and the game's casts turned.
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

	{ "an orbital laser points up at the ship and keeps the game's flat forward; other homing units stay", function()
		local s = strikes()
		local turned = {}
		local U = {
			is_a = function(unit, path) return unit == "laser" and path == s.LASER end,
			world_position = function() return { x = 0, y = 0, z = 0 } end,
			local_rotation = function() return "game" end,
			teleport_local_rotation = function(unit, i, q) turned[unit] = { i, q } end,
			set_local_scale = function(unit, i, v) turned["scale " .. unit] = v end,
		}
		-- The game's turn faces the laser along +y, flat.
		local Q = { forward = function() return { x = 0, y = 1, z = 0 } end,
			look = function(fw, up) return { fw = fw, up = up } end }
		local V3 = function(x, y, z) return { x = x, y = y, z = z } end
		local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
		s.lean(U, Q, V3, { laser = {}, missile = {} }, 0)
		eq(turned.missile, nil, "a homing missile stays")
		eq(s.lasers.missile, false, "known as no laser")
		eq(turned.laser[1], 0, "the root")
		local q = turned.laser[2]
		local d = s.toward(0)
		near(q.up.x, d.x, "up along the bearing", 1e-12) near(q.up.z, d.z, nil, 1e-12)
		near(dot(q.fw, q.up), 0, "forward square to up", 1e-12)
		near(q.fw.x, 0, "the same flat way as the game's", 1e-12)
		eq(q.fw.y > 0, true)
		eq(turned["scale laser"].z, 1, "no ship: as long as the game draws it")
		-- With the ship in the sky at (10, 0, 10): up at the ship, drawn as long as the way there.
		s.lean(U, Q, V3, { laser = {} }, 0, { x = 10, y = 0, z = 10 })
		q = turned.laser[2]
		near(q.up.x, math.sqrt(0.5), "meets the ship", 1e-12) near(q.up.z, math.sqrt(0.5), nil, 1e-12)
		near(q.fw.x, 0, "the same flat way", 1e-12) near(dot(q.fw, q.up), 0, nil, 1e-12)
		near(turned["scale laser"].z, math.sqrt(200) / s.BEAM, "drawn as long as the way to the ship", 1e-12)
		eq(turned["scale laser"].x, 1, "no wider")
		eq(turned["scale missile"], nil, "a homing missile keeps its size")
	end },

	{ "the lifted forward keeps the flat way and is square to up", function()
		local s = strikes()
		local up = s.toward(1.0)
		local f = s.forward({ x = math.cos(0.3), y = math.sin(0.3) }, up)
		near(f.x * up.x + f.y * up.y + f.z * up.z, 0, "square", 1e-12)
		near(math.atan2(f.y, f.x), 0.3, "the flat way", 1e-12)
		near(f.x * f.x + f.y * f.y + f.z * f.z, 1, "a unit", 1e-12)
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
