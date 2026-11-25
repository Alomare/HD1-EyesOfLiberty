-- A squad split up (src/session.lua, part free_movement): one top-down screen centred on each living
-- Helldiver while one is off the shared screen.
local function camera()
	local frustum = obsidian.module("src/frustum")
	-- Looking down at 60 degrees from 20 m up and 11.5 m back, as the game's top-down camera does.
	local a = math.rad(60)
	return frustum.camera_from({ x = 0, y = -20 / math.tan(a), z = 20 }, { x = 0, y = math.cos(a), z = -math.sin(a) }, math.rad(45))
end

return {
	{ "a screen centred on a Helldiver shows them in the middle", function()
		local s = obsidian.module("src/session")
		local frustum = obsidian.module("src/frustum")
		local cam = camera()
		local p = { x = 120, y = -40, z = 3 }
		local moved = s.screen_at(cam, p)
		local x, depth, y = frustum.project(moved, p, 1920, 1080)
		near(x, 960, "x", 1e-6) near(y, 540, "y", 1e-6)
		assert(depth > 0)
		near(moved.position.z, cam.position.z, "the same camera height", 1e-6)
	end },

	{ "on screen within the game's margins", function()
		local s = obsidian.module("src/session")
		local cam = camera()
		local mid = { x = 0, y = 0, z = 0 }
		eq(s.on_screen(cam, mid, 1920, 1080), true)
		eq(s.on_screen(cam, { x = 200, y = 0, z = 0 }, 1920, 1080), false, "far to the side")
		local frustum = obsidian.module("src/frustum")
		-- A point just inside the right edge: in with no margin, out with a margin of 0.1 inside the edge,
		-- in again with -0.5 past it.
		local edge = frustum.unproject(cam, 1900, 540, 23, 1920, 1080)
		eq(s.on_screen(cam, edge, 1920, 1080), true)
		eq(s.on_screen(cam, edge, 1920, 1080, 0.1, 0.1, 0.1, 0.1), false)
		local past = frustum.unproject(cam, 2300, 540, 23, 1920, 1080)
		eq(s.on_screen(cam, past, 1920, 1080), false)
		eq(s.on_screen(cam, past, 1920, 1080, -0.5, -0.5, -0.5, -0.5), true)
		local behind = { x = 0, y = -60, z = 30 }
		eq(s.on_screen(cam, behind, 1920, 1080), false, "behind the camera")
	end },

	{ "the screens are there only while the squad is apart", function()
		local s = obsidian.module("src/session")
		local frustum = obsidian.module("src/frustum")
		local had = frustum.top_down
		frustum.top_down = function() return camera() end
		local cm = { screen_resolution = { width = 1920, height = 1080 }, position = {}, rotation = {} }
		local near_one = { x = 2, y = 1, z = 0 }
		local far_one = { x = 300, y = 0, z = 0 }
		local function inside(p) return s.on_screen(camera(), p, 1920, 1080) end
		eq(s.split_screens(cm, { near_one, { x = -3, y = 2, z = 0 } }, inside), false, "together")
		eq(s.split_screens(cm, { near_one }, inside), false, "alone")
		local got = s.split_screens(cm, { near_one, far_one }, inside)
		eq(#got.screens, 2)
		eq(s.on_screen(got.screens[2], { x = 305, y = 3, z = 0 }, got.w, got.h), true, "around the far Helldiver")
		eq(s.on_screen(got.screens[1], { x = 305, y = 3, z = 0 }, got.w, got.h), false)
		frustum.top_down = had
	end },
}
