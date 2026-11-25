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

	{ "a point close under the hand still bends down, to the limit; no point at all gives nothing to hold", function()
		local a = obsidian.module("src/aimpose")
		local f, p = { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1.4 }
		eq(a.target_bend(f, p, { x = 0, y = 0.5, z = 0 }), -a.MAX, "looking far down, 0.5 m ahead: bent down all the way")
		eq(a.target_bend(f, p, { x = 0, y = 0.01, z = 0 }), nil, "straight under the hand")
		eq(a.target_bend(f, p, nil), nil)
	end },

	{ "a bone that still holds last frame's bend goes back; one the animation moved stays", function()
		local a = obsidian.module("src/aimpose")
		local bones = { [1] = { 0, 0, 0.3, 0.95 }, [2] = { 0.5, 0, 0, 0.87 } }
		local U = { alive = function() return true end, local_rotation = function(_, i) return bones[i] end,
			set_local_rotation = function(_, i, q) bones[i] = q end }
		local Q = { to_elements = function(q) return q[1], q[2], q[3], q[4] end,
			from_elements = function(x, y, z, w) return { x, y, z, w } end }
		local updated = 0
		local W = { update_unit = function() updated = updated + 1 end }
		a.written = { avatar = "me", world = "w", nodes = {
			[1] = { was = { 0, 0, 0, 1 }, now = { 0, 0, 0.3, 0.95 } },
			[2] = { was = { 0, 0, 0, 1 }, now = { 0.1, 0, 0, 0.99 } },
		} }
		a.restore(U, Q, W)
		eq(bones[1][4], 1, "back to the pose before the bend")
		eq(bones[2][1], 0.5, "the animation's pose is left alone")
		eq(updated, 1, "the unit is updated once")
		eq(a.written, nil, "nothing left to restore")
		a.restore(U, Q, W)
		eq(updated, 1, "a second restore does nothing")
	end },

	{ "the bend comes out before the next animation update of the Helldiver's world", function()
		local E2 = E.install()
		local a = obsidian.module("src/aimpose")
		local env = E.env()
		env.config.start(env)
		a.start(env)
		local bones = { [3] = { 0, 0, 0.3, 0.95 } }
		Unit.local_rotation = function(_, i) return bones[i] end
		Unit.set_local_rotation = function(_, i, q) bones[i] = q end
		Quaternion.to_elements = function(q) return q[1], q[2], q[3], q[4] end
		Quaternion.from_elements = function(x, y, z, w) return { x, y, z, w } end
		E2.units.me = { position = { x = 0, y = 0, z = 0 } }
		a.written = { avatar = "me", world = "w", nodes = { [3] = { was = { 0, 0, 0, 1 }, now = { 0, 0, 0.3, 0.95 } } } }
		local animate = E.hook("World", "update_animations_with_callback")
		local seen
		animate(function() seen = bones[3][4] end, "other world", 0.016)
		eq(seen, 0.95, "another world: left alone")
		animate(function() seen = bones[3][4] end, "w", 0.016)
		eq(seen, 1, "the animation starts from the pose before the bend")
		eq(a.written, nil)
		E.remove()
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

	{ "the hidden cursor is held only with a mouse turning the view in a mission", function()
		E.install()
		local cam = obsidian.module("src/camera")
		local cursor = obsidian.module("src/cursor")
		local had = cursor.available
		cursor.available = function() return true end
		cam.frame = 10
		cam.input = { kbm = true, look = true, frame = 10 }
		local env = { state = { active = true } }
		local cm = { state = "follow" }
		eq(cam.hold_wanted(env, cm), true)
		env.state.claimed_by = "alomare.customcrosshair"
		eq(cam.hold_wanted(env, cm), true, "another mod's crosshair changes nothing")
		env.state.vehicle = true
		eq(cam.hold_wanted(env, cm), true, "in a vehicle too")
		env.state.claimed_by, env.state.vehicle = nil, nil
		cam.input.kbm = false
		eq(cam.hold_wanted(env, cm), false, "a pad")
		cam.input.kbm = true
		cam.input.look = false
		eq(cam.hold_wanted(env, cm), false, "a menu or the map")
		cam.input.look = true
		eq(cam.hold_wanted(env, { state = "follow_menu" }), false, "the ship")
		cursor.available = had
		E.remove()
	end },
}
