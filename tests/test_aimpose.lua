-- Aim pose (src/aimpose.lua) and the game's own crosshair held at the middle (src/cursor.lua, camera).
local E = dofile("tests/engine.lua")

return {
	{ "the bend is the gap between the weapon's pitch and the way to the point, within MAX", function()
		local a = obsidian.module("src/aimpose")
		near(a.pitch_of({ x = 1, y = 0, z = 1 }), 45, "45 up", 1e-9)
		near(a.pitch_of({ x = 0, y = 2, z = 0 }), 0, "level", 1e-9)
		eq(a.bend(-5, 20), 25, "raise by the gap")
		eq(a.bend(0, 80), a.MAX, "within MAX up")
		eq(a.bend(0, -80), -a.MAX, "and down")
	end },

	{ "the pose wants third person on foot, aiming or firing, with a point", function()
		local a = obsidian.module("src/aimpose")
		local env = { state = { active = true, aiming = true, aim_point = {} }, view = { avatar = "me" } }
		eq(a.wanted(env), true)
		env.state.aiming = false
		eq(a.wanted(env), false, "not aiming nor firing")
		env.state.firing = true
		eq(a.wanted(env), true, "firing")
		env.state.vehicle = true
		eq(a.wanted(env), false, "in a vehicle")
	end },

	{ "the cursor is held in a 2 x 2 box at the middle of the window", function()
		local c = obsidian.module("src/cursor")
		local l, t, r, b = c.box(100, 50, 1920, 1080)
		eq(l, 1059) eq(t, 589) eq(r, 1061) eq(b, 591)
	end },

	{ "the game's crosshair stays only with a mouse, in a mission, and with no other mod's crosshair", function()
		E.install()
		local cam = obsidian.module("src/camera")
		local cursor = obsidian.module("src/cursor")
		local had = cursor.available
		cursor.available = function() return true end
		cam.frame = 10
		cam.input = { kbm = true, look = true, frame = 10 }
		local env = { state = { active = true } }
		local cm = { state = "follow" }
		eq(cam.vanilla_wanted(env, cm), true)
		env.state.claimed_by = "alomare.customcrosshair"
		eq(cam.vanilla_wanted(env, cm), false, "Custom Crosshair draws it")
		env.state.claimed_by = nil
		cam.input.kbm = false
		eq(cam.vanilla_wanted(env, cm), false, "a pad")
		cam.input.kbm = true
		cam.input.look = false
		eq(cam.vanilla_wanted(env, cm), false, "a menu or the map")
		cam.input.look = true
		eq(cam.vanilla_wanted(env, { state = "follow_menu" }), false, "the ship")
		cursor.available = had
		E.remove()
	end },
}
