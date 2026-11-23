-- The Super Destroyer in the sky: where it stands, how it turns.
local E = dofile("tests/engine.lua")

local function ship() return obsidian.module("src/ship") end

return {
	{ "the ship is seen with the sun behind the viewer", function()
		local m = ship()
		near(m.bearing({ 1, 0, -1 }), 0, "light toward +x: the ship toward +x")
		near(m.bearing({ 0, -1, -1 }), -math.pi / 2)
		eq(m.bearing({ 0, 0, -1 }), 0, "sun straight up")
		eq(m.bearing(nil), 0, "no sun")
	end },

	{ "the ship rides with the camera, twice as high over the horizon as at 30 degrees", function()
		local m = ship()
		local a = m.place({ x = 0, y = 0, z = 2 }, 0)
		local b = m.place({ x = 50, y = -20, z = 7 }, 0)
		near(b.x - a.x, 50) near(b.y - a.y, -20) near(b.z - a.z, 5, "the same place from the camera")
		local flat = math.sqrt(a.x * a.x + a.y * a.y)
		near(flat, 25 * math.cos(math.rad(30)), "the flat distance of the first try", 1e-9)
		near(a.z - 2, 2 * 25 * math.sin(math.rad(30)), "twice the height", 1e-9)
		near(m.LENGTH / m.DISTANCE, 11 / 25, "the same part of the view", 1e-9)
	end },

	{ "the ship lies across the line of sight", function()
		local m = ship()
		-- The long axis is local y: turned by the bearing, it points across the bearing.
		local b = 0.7
		local t = m.turn(b)
		local ax, ay = -math.sin(t), math.cos(t)
		near(ax * math.cos(b) + ay * math.sin(b), 0, "across", 1e-12)
	end },
}
