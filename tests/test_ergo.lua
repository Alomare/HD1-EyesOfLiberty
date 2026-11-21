-- Weapon handling: ergonomics, shots along the weapon's way, the game's turn keep, the crosshair where
-- the weapon points, the aim pose only in aim states, the laser's quieter camera.
local E = dofile("tests/engine.lua")

local function ergo() return obsidian.module("src/ergo") end

-- A view on foot 3 m behind a Helldiver at the origin, looking north.
local function on_foot()
	return { avatar = "me", target = "me", target_position = { x = 0, y = 0, z = 0 },
		position = { x = 0.6, y = -3, z = 1.8 }, forward = { x = 0, y = 1, z = 0 }, fov = 70, world = "world" }
end

local function env_with(aiming, fire, frame)
	local env = E.env()
	env.state.active, env.state.aiming = true, aiming
	env.camera = { input = { fire = fire } }
	env.frame = function() return frame or 10 end
	return env
end

return {
	{ "ergonomics: quick for every weapon, slower for a laser firing", function()
		local m = ergo()
		local t = m.tau(m.ergonomics(false))
		assert(t > 0 and t < 0.1, "a quick swing: " .. t)
		assert(m.tau(m.ergonomics(true)) > t * 2, "a laser firing swings slower")
		assert(m.tau(100) < m.tau(50) and m.tau(50) < m.tau(0), "higher ergonomics, faster")
		local k = m.keep(t)
		assert(k > 0 and k < 1e-4, "the game's keep: almost nothing of the old facing after a second")
		-- After one time constant about 63 percent of the way.
		near(m.ease(0, 1, 0.1, 0.1), 1 - math.exp(-1), "eased", 1e-9)
		eq(m.ease(nil, 0.4, 0.1, 0.016), 0.4, "starts where it is wanted")
	end },

	{ "the weapon's pitch swings to the crosshair while raised and back to level when lowered", function()
		local m = ergo()
		local p = 0
		for _ = 1, 60 do p = m.step_pitch(p, 0.5, true, m.tau(92), 1 / 60) end
		near(p, 0.5, "swung in within a second", 1e-3)
		for _ = 1, 60 do p = m.step_pitch(p, 0.5, false, m.tau(92), 1 / 60) end
		near(p, 0, "back to level", 1e-3)
		local d = m.dir({ x = 0, y = 2 }, math.rad(30))
		near(d.z, 0.5, "pitch", 1e-9) near(d.y, math.sqrt(3) / 2, "heading kept", 1e-9)
		eq(m.dir({ x = 0, y = 0 }, 0), nil, "no heading")
		local t = m.dir({ x = 1, y = 0 }, 0, math.pi / 2)
		near(t.x, 0, "turned", 1e-9) near(t.y, 1, "anticlockwise", 1e-9)
		-- Shots start 0.3 m right of the root; the facing points from the root at a point 30 m ahead.
		local turn = m.converge({ x = 0, y = 0, z = 0 }, { x = 0.3, y = 0, z = 1.5 }, { x = 0, y = 30, z = 1.5 })
		local d = m.dir({ x = 0, y = 1 }, 0, turn)
		near(0.3 + d.x / d.y * 30, 0, "the shot meets the point", 1e-9)
		near(m.pitch_to({ x = 0, y = 0, z = 1.5 }, { x = 0, y = 10, z = 11.5 }), math.rad(45), "pitch to a point", 1e-9)
	end },

	{ "on foot, this player's shots leave along the weapon's way, not at the crosshair point", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		e.units.gun = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, equipment = { wielder = "me" } }
		aim.frame_now = function() return 20 end
		aim.gun.pitch, aim.gun.frame = math.rad(10), 20
		local slaves = { gun = { state = { attach_node = 0, was_firing = true } } }
		-- The crosshair point is 45 degrees up, but the weapon has only swung 10 degrees.
		local list = aim.collect(slaves, { avatar = "me", target = "me" }, { x = 0, y = 10, z = 11.5 }, Quaternion.forward)
		near(list[1].dir.z, math.sin(math.rad(10)), "the weapon's pitch", 1e-9)
		eq(list[1].firing, true, "firing noted")
		-- A way worked out long ago doesn't count: the crosshair point again.
		aim.gun.frame = 0
		list = aim.collect(slaves, { avatar = "me", target = "me" }, { x = 0, y = 10, z = 11.5 }, Quaternion.forward)
		assert(list[1].dir.z > 0.6, "stale: to the point")
		-- In a vehicle the gun keeps its own rule.
		aim.gun.frame = 20
		list = aim.collect(slaves, { avatar = "me", target = "me", vehicle = true }, { x = 0, y = 10, z = 11.5 }, Quaternion.forward)
		eq(list[1].dir.z, 0, "a vehicle gun fires level")
		aim.gun.pitch, aim.frame_now = nil, nil
		E.remove()
	end },

	{ "the game's turn keep is set from the ergonomics in aim states only", function()
		E.install()
		local aim = obsidian.module("src/aim")
		local m = ergo()
		CharacterStateAim, CharacterStateThrow = {}, {}
		local env = env_with(true, false, 50)
		aim.gun.laser = -100
		local ctx = { state = { current_state = CharacterStateAim } }
		eq(aim.turn(ctx, env), true)
		near(ctx.state.forced_rotation_speed, m.keep(m.tau(m.ERGONOMICS)), "every weapon's handling", 1e-12)
		local laser = { state = { current_state = CharacterStateAim } }
		aim.gun.laser = 48
		aim.turn(laser, env)
		assert(laser.state.forced_rotation_speed > ctx.state.forced_rotation_speed, "a laser firing turns slower")
		local throw = { state = { current_state = CharacterStateThrow } }
		eq(aim.turn(throw, env), false, "not while throwing")
		eq(throw.state.forced_rotation_speed, nil)
		local own = { state = { current_state = CharacterStateAim, forced_rotation_speed = 1 } }
		eq(aim.turn(own, env), false, "a state's own keep stays")
		eq(own.state.forced_rotation_speed, 1)
		CharacterStateAim, CharacterStateThrow = nil, nil
		aim.gun.laser = -100
		E.remove()
	end },

	{ "the crosshair goes where the weapon points while raised, the middle otherwise", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		-- The Helldiver faces east while the camera looks north.
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 1, y = 0, z = 0 } }
		local view = on_foot()
		local idle = env_with(false, false)
		idle.state.aim_point = { x = 0, y = 30, z = 1.5 }
		idle.state.centre = { x = 960, y = 540 }
		aim.gun.pitch, aim.gun.cross = nil, 0
		aim.gun_frame(idle, view, CameraManager, 0.016)
		eq(idle.state.crosshair, nil, "lowered: left at the middle (set by the pose)")
		local env = env_with(true, false)
		env.state.aim_point = { x = 0, y = 30, z = 1.5 }
		env.state.centre = { x = 960, y = 540 }
		env.state.crosshair = env.state.centre
		for _ = 1, 30 do
			env.state.crosshair = env.state.centre
			aim.gun_frame(env, view, CameraManager, 0.016)
		end
		local c = env.state.crosshair
		assert(c.x > 960 + 100, "off to the right, where the weapon points: " .. c.x)
		assert(c.x <= 1920 and c.y >= 0 and c.y <= 1080, "kept on screen")
		-- Facing the crosshair point, the weapon's point is the middle.
		e.units.me.forward = { x = 0, y = 1, z = 0 }
		for _ = 1, 60 do
			env.state.crosshair = env.state.centre
			aim.gun_frame(env, view, CameraManager, 0.016)
		end
		assert(math.abs(env.state.crosshair.x - 960) < 60, "near the middle: " .. env.state.crosshair.x)
		aim.gun.pitch, aim.gun.cross, aim.gun.dir = nil, 0, nil
		E.remove()
	end },

	{ "the aim pose bends only in states that hold the weapon up", function()
		E.install()
		local pose = obsidian.module("src/aimpose")
		local env = E.env()
		env.state.active, env.state.aiming, env.state.aim_point = true, true, { x = 0, y = 10, z = 0 }
		env.view = { avatar = "me" }
		eq(pose.wanted(env, true), true)
		eq(pose.wanted(env, nil), true, "state unknown: as before")
		eq(pose.wanted(env, false), false, "throwing or switching weapons: no bend")
		-- The bend goes to the weapon's swung pitch when there is one.
		near(pose.target_bend({ x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 0, y = 10, z = 10 }, math.rad(20)), 20, "the weapon's pitch", 1e-9)
		near(pose.target_bend({ x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 0 }, { x = 0, y = 10, z = 10 }), 45, "else the point's", 1e-9)
		E.remove()
	end },

	{ "a laser firing cuts the camera shake by 75 percent", function()
		local shake = obsidian.module("src/shake")
		shake.clear()
		shake.game.x, shake.game.y = 0.1, 0
		local x = shake.offset(0.016, 1)
		near(x, 0.1, "full shake", 1e-9)
		for _ = 1, 60 do
			shake.game.x, shake.game.y = 0.1, 0
			shake.quiet(shake.LASER)
			x = shake.offset(0.016, 1)
		end
		near(x, 0.025, "a quarter left", 1e-3)
		shake.flamed()
		eq(shake.flame.cut, shake.FLAME, "a flamethrower's stronger cut wins")
		shake.clear()
		eq(shake.flame.cut, shake.FLAME)
	end },

	{ "the game's cursor is held where the weapon points", function()
		local cursor = obsidian.module("src/cursor")
		local l, t, r, b = cursor.box(100, 50, 1920, 1080)
		eq(l, 100 + 959) eq(t, 50 + 539) eq(r, 100 + 961) eq(b, 50 + 541)
		l, t = cursor.box(100, 50, 1920, 1080, 200, -100)
		eq(l, 100 + 1159, "right") eq(t, 50 + 439, "up")
		l, t = cursor.box(0, 0, 1920, 1080, 5000, 5000)
		eq(l, 1918, "kept in the window") eq(t, 1078)
	end },

	{ "a confusion turns the camera the other way", function()
		local camera = obsidian.module("src/camera")
		local r = obsidian.module("src/rig")
		eq(camera.confused({}), false)
		eq(camera.confused({ input_filter = { invert = {}, switch = {} } }), false, "a filter with nothing in it")
		eq(camera.confused({ input_filter = { invert = { "aim", "move" } } }), true)
		eq(camera.confused({ input_filter = { switch = { move = "aim" } } }), true)
		local plain = r.look({ yaw = 0, pitch = 0 }, { x = 10, y = 10 }, nil, { speed = 1 })
		local turned = r.look({ yaw = 0, pitch = 0 }, { x = 10, y = 10 }, nil, { speed = 1, confused = true })
		near(turned.yaw, -plain.yaw, "left and right", 1e-9) near(turned.pitch, -plain.pitch, "up and down", 1e-9)
	end },
}
