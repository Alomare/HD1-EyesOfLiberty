-- First person, camera modes, the overall height, sprinting and the Hellpod hold on the view.
local E = dofile("tests/engine.lua")

local function rig() return obsidian.module("src/rig") end

local function frame(e, env, masters, dt)
	E.hook("InputComponent", "update_masters")(function() end, {}, masters, dt or 0.016)
	E.hook("CameraManager", "update")(function() end, CameraManager, dt or 0.016)
end

-- The engine fake with a head node, character master states and meshes.
local function started(api)
	local e = E.install()
	Unit.has_node = function(u, name) return name == "head" and e.units[u] ~= nil end
	Unit.node = function() return 7 end
	local plain = Unit.world_position
	Unit.world_position = function(u, node)
		local p = plain(u)
		if node == 7 then return E.V3(p.x, p.y, p.z + 1.6) end
		return p
	end
	e.meshes = {}
	Unit.num_meshes = function(u) return e.meshes[u] and #e.meshes[u] or 0 end
	Unit.mesh_visibility = function(u, i) return e.meshes[u][i + 1] end
	Unit.set_mesh_visibility = function(u, i, on) e.meshes[u][i + 1] = on end
	EntityAux.state_master = function(u, name)
		local s = e.units[u] and e.units[u][name .. "_master"]
		if s then return s end
		error("no " .. name)
	end
	local env = E.env(api)
	env.config.start(env)
	obsidian.module("src/camera").start(env)
	return e, env
end

local function helmet_api()
	return { world = { part_units = function(_, part) if part == "helmet" then return { "helmet" } end return {} end } }
end

return {
	{ "the camera key cycles third person, first person and the top-down camera, and keeps the mode", function()
		local e, env = started()
		local cam = obsidian.module("src/camera")
		eq(cam.mode, "third", "the option's default")
		KEYS.toggle_view.fn()
		eq(cam.mode, "first") eq(STORED.camera_mode, "first") eq(STORED.camera_mode_option, "third")
		KEYS.toggle_view.fn()
		eq(cam.mode, "default") eq(cam.enabled, false)
		KEYS.toggle_view.fn()
		eq(cam.mode, "third")
		E.remove()
		-- The kept mode holds while the option is the same, and a changed option wins.
		STORED.camera_mode, STORED.camera_mode_option = "first", "third"
		started()
		eq(obsidian.module("src/camera").mode, "first", "kept from the key")
		E.remove()
		OPTIONS.camera_mode = "default"
		started()
		eq(obsidian.module("src/camera").mode, "default", "the option changed since")
		E.remove()
	end },

	{ "first person sits at the head a hair in front of the face, hides the helmet and gives it back", function()
		OPTIONS.camera_mode, OPTIONS.first_person_fov = "first", 85
		local e, env = started(helmet_api())
		e.meshes.helmet = { true, false, true }
		e.units.helmet = { position = { x = 0, y = 0, z = 0 } }
		local masters = E.player(e, "me", { position = { x = 1, y = 2, z = 0 } })
		frame(e, env, masters)
		local v = env.view
		eq(v.first, true)
		near(v.pivot.z, 1.6, "head height") near(v.pivot.x, 1)
		local d = rig().sub(v.position, v.pivot)
		near(rig().length(d), rig().FP_BUMP, "the bump", 1e-6)
		assert(rig().dot(d, v.forward) > 0, "in front")
		near(v.fov, 85)
		eq(e.meshes.helmet[1], false) eq(e.meshes.helmet[3], false)
		KEYS.toggle_view.fn() -- top-down
		frame(e, env, masters)
		eq(e.meshes.helmet[1], true, "given back") eq(e.meshes.helmet[2], false, "a hidden mesh stays hidden")
		E.remove()
	end },

	{ "first person body: steps back when walking backwards, turns standing only past the threshold", function()
		local r = rig()
		local body, turning = r.fp_body(0, 180, true, 1)
		near(math.abs(r.wrap(body - 180)), 0, "moving: follows the view, so S steps back", 1e-3)
		body, turning = r.fp_body(0, 40, false, 0.1, false)
		eq(body, 0, "standing, a small turn of the view leaves the body") eq(turning, false)
		body, turning = r.fp_body(0, 70, false, 0.05, false)
		eq(turning, true, "past the threshold the body turns")
		assert(body > 0 and body < 70, "on the way: " .. body)
		for _ = 1, 60 do body, turning = r.fp_body(body, 70, false, 0.05, turning) end
		eq(turning, false, "the turn ends") near(body, 70, "at the view", r.FP_TURN_STOP)
	end },

	{ "first person feeds the body's way to the aim input while not aiming", function()
		local aim = obsidian.module("src/aim")
		local data = { aim = { x = 0, y = 0, z = 0 } }
		local input = { look = true, kbm = true }
		eq(aim.steer(data, input, {}, nil, { x = 1, y = 0, z = 0 }), true)
		eq(data.aim.x, 1, "the body's way")
		data.aim = { x = 0, y = 0, z = 0 }
		input.aiming = true
		aim.steer(data, input, { pivot = { x = 0, y = 0, z = 0 } }, { x = 0, y = 10, z = 0 }, { x = 1, y = 0, z = 0 })
		near(data.aim.y, 1, "aiming: the crosshair wins")
		eq(aim.moving({ movement = { x = 0, y = 0.5 } }), true) eq(aim.moving({ movement = { x = 0, y = 0 } }), false)
	end },

	{ "the overall height lifts the third-person camera", function()
		local e, env = started()
		local masters = E.player(e, "me")
		for _ = 1, 30 do frame(e, env, masters, 0.05) end
		local base = env.view.pivot.z
		env.config.set("camera_height", 0.5)
		for _ = 1, 60 do frame(e, env, masters, 0.05) end
		near(env.view.pivot.z, base + 0.5, "half a metre up", 1e-2)
		E.remove()
	end },

	{ "sprinting fades the crosshair out and sways the camera", function()
		local e, env = started()
		CharacterStateSprint = { name = "sprint" }
		local masters = E.player(e, "me")
		e.units.me.character_master = { current_state = {} }
		frame(e, env, masters, 0.05)
		eq(env.state.sprint_fade, 1)
		e.units.me.character_master.current_state = CharacterStateSprint
		for _ = 1, 40 do frame(e, env, masters, 0.05) end
		assert(env.state.sprint_fade < 0.01, "faded: " .. env.state.sprint_fade)
		local shake = obsidian.module("src/shake")
		assert(shake.sprint.level > 0.99, "sway on")
		local x, y = shake.offset(0.1, shake.factor("medium"))
		assert(x ~= 0 or y ~= 0, "the camera moves")
		eq(select(1, shake.offset(0.1, shake.factor("off"))), 0, "Camera shake off: no sway")
		local cross = obsidian.module("src/crosshair")
		env.camera = obsidian.module("src/camera")
		env.state.vehicle = true
		eq(cross.visible(env), false, "no crosshair at full sprint")
		CharacterStateSprint = nil
		E.remove()
	end },

	{ "the view stays still while the Helldiver is in the Hellpod", function()
		local e, env = started()
		CharacterStateCutscene = { name = "cutscene" }
		local cam = obsidian.module("src/camera")
		local masters = E.player(e, "me")
		frame(e, env, masters)
		local pod = obsidian.module("src/pod")
		cam.drop = pod.new({ x = 0, y = 0, z = 0 })
		cam.drop.avatar = "me"
		e.units.me.character_master = { current_state = CharacterStateCutscene }
		local yaw = cam.view.yaw
		e.mouse.x = 50
		frame(e, env, masters)
		eq(cam.view.yaw, yaw, "held in the pod")
		e.units.me.character_master.current_state = {}
		frame(e, env, masters)
		assert(cam.view.yaw ~= yaw, "free once out")
		CharacterStateCutscene = nil
		E.remove()
	end },
}
