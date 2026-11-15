-- Camera modes, the overall height, sprinting and the Hellpod hold on the view.
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

return {
	{ "the camera key switches third person and the top-down camera, and keeps the mode", function()
		local e, env = started()
		local cam = obsidian.module("src/camera")
		eq(cam.mode, "third", "the option's default")
		KEYS.toggle_view.fn()
		eq(cam.mode, "default") eq(cam.enabled, false) eq(STORED.camera_mode, "default") eq(STORED.camera_mode_option, "third")
		KEYS.toggle_view.fn()
		eq(cam.mode, "third")
		E.remove()
		-- The kept mode holds while the option is the same, and a changed option wins. A first person
		-- mode kept from an older version falls back to the option.
		STORED.camera_mode, STORED.camera_mode_option = "default", "third"
		started()
		eq(obsidian.module("src/camera").mode, "default", "kept from the key")
		E.remove()
		STORED.camera_mode, STORED.camera_mode_option = "first", "third"
		started()
		eq(obsidian.module("src/camera").mode, "third", "no first person")
		E.remove()
		OPTIONS.camera_mode = "default"
		started()
		eq(obsidian.module("src/camera").mode, "default", "the option changed since")
		E.remove()
	end },

	{ "a flamethrower of this player firing cuts the camera shake to a fifth", function()
		local shake = obsidian.module("src/shake")
		shake.clear()
		shake.add(0.1, 3, 10)
		local x0, y0 = shake.offset(0.001, 1)
		local plain = math.sqrt(x0 * x0 + y0 * y0)
		local aim = obsidian.module("src/aim")
		E.install()
		local view = { avatar = "me" }
		eq(aim.note_flames({ flamer = { state = { firing_auto = true } } }, view), false, "another player's flamer")
		EntityAux.has_component = function(u, name) return u == "flamer" and name == "equipment" end
		EntityAux.state = function(u, name) return { wielder = "me" } end
		eq(aim.note_flames({ flamer = { state = { firing_auto = true } } }, view), true, "this player's")
		for _ = 1, 30 do shake.flamed() shake.offset(0.02, 1) end
		local x, y = shake.offset(0.0001, 1)
		local cut = math.sqrt(x * x + y * y)
		assert(cut < plain * 0.3, "about a fifth: " .. cut .. " of " .. plain)
		shake.clear()
		E.remove()
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
