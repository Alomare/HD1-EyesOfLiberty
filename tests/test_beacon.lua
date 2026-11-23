-- Beacon icon (src/beacon.lua): where on the beam the icon goes.
local function beacon() return obsidian.module("src/beacon") end

return {
	{ "the icon goes to the crosshair's height on the beam", function()
		local b = beacon()
		-- A beam leaning a little on screen, from (500, 100) up to (520, 600).
		local x, y, off, t = b.on_beam(500, 100, 520, 600, 530, 350)
		near(y, 350, "the crosshair's height") near(x, 510, "on the beam's line") near(off, 20, "20 px across")
		near(t, 0.5)
	end },

	{ "the icon is whole near the beam and fades out toward the edge of the range", function()
		local b = beacon()
		eq(b.opacity(0), 1) eq(b.opacity(b.CORE), 1, "whole within the core")
		near(b.opacity((b.CORE + b.NEAR) / 2), 0.5, "half way out")
		eq(b.opacity(b.NEAR), 0, "gone at the edge")
		near(b.SIZE, 0.7, "30 percent smaller")
	end },

	{ "the icon stays within the beam", function()
		local b = beacon()
		local x, y, _, t = b.on_beam(500, 100, 500, 600, 500, 900)
		eq(y, 600, "held at the top") eq(t, 1)
		local _, y2, off = b.on_beam(500, 100, 500, 600, 500, 20)
		eq(y2, 100, "held at the beacon") near(off, 80, "and that far from a crosshair under it")
		eq(x, 500)
	end },
}
