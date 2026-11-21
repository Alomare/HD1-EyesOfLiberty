-- The closer third person pieces: the body under the camera (jump pack lift,
-- hidden when the camera presses close), the ammo bar's shape, and the scroll camera distance.
local function m(name) return obsidian.module(name) end

-- A fake engine for src/body.lua: units with a root, a hips node, meshes and children.
local function body_world()
	local units = {}
	local function unit(name, z, meshes)
		units[name] = { name = name, z = z or 0, local_z = 0, hips = nil, meshes = meshes or { true }, kids = {} }
		return name
	end
	_G.Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
	_G.Unit = {
		alive = function(u) return units[u] ~= nil end,
		world_position = function(u, node)
			local t = units[u]
			if node == "hips" then return { x = 0, y = 0, z = t.z + t.hips } end
			return { x = 0, y = 0, z = t.z + t.local_z }
		end,
		has_node = function(u, n) return n == "hips" and units[u].hips ~= nil end,
		node = function(_, n) return n end,
		local_position = function(u) return { x = 0, y = 0, z = units[u].local_z } end,
		set_local_position = function(u, _, v) units[u].local_z = v.z end,
		num_meshes = function(u) return #units[u].meshes end,
		mesh_visibility = function(u, i) return units[u].meshes[i + 1] end,
		set_mesh_visibility = function(u, i, on) units[u].meshes[i + 1] = on end,
		children = function(u, out) for _, k in ipairs(units[u].kids) do out[#out + 1] = k end end,
	}
	return units, unit
end

return {
	{ "the body's parts rise with the hips during a jump, and come down after", function()
		local units, unit = body_world()
		local avatar = unit("avatar")
		units.avatar.hips = 0.97
		unit("body") unit("helmet")
		local api = { game = {
			all_avatars = function() return { { unit = avatar } } end,
			slaves = function() return { [avatar] = { state = { body_unit = "body", helmet_unit = "helmet" } } } end,
		} }
		local env = { api = api, state = {}, on_pose = {}, on_release = {} }
		local body = m("src/body")
		body.start(env)
		local view = { avatar = avatar, position = { x = 0, y = -3, z = 1.7 } }
		local function pose() for _, fn in ipairs(env.on_pose) do fn(view) end end
		pose()
		eq(units.body.local_z, 0, "standing: left alone")
		units.avatar.hips = 5.2
		pose()
		near(units.body.local_z, 5.2 - body.LIFT_FROM, "the body part's root rises with the hips")
		near(units.helmet.local_z, 5.2 - body.LIFT_FROM, "and the helmet's")
		units.avatar.hips = 0.95
		pose()
		eq(units.body.local_z, 0, "landed: back on the root")
		units.avatar.hips = 4
		pose()
		for _, fn in ipairs(env.on_release) do fn() end
		eq(units.body.local_z, 0, "the top-down view gets the parts back where they were")
	end },

	{ "the body hides while the camera presses close, and shows what was shown before", function()
		local units, unit = body_world()
		local avatar = unit("avatar")
		units.avatar.hips = 0.97
		unit("body", 0, { true, false, true })
		unit("rifle")
		units.avatar.kids = { "rifle" }
		local api = { game = {
			all_avatars = function() return { { unit = avatar } } end,
			slaves = function() return { [avatar] = { state = { body_unit = "body" } } } end,
		} }
		local env = { api = api, state = {}, on_pose = {}, on_release = {} }
		local body = m("src/body")
		body.start(env)
		local view = { avatar = avatar, position = { x = 0, y = -3, z = 1.5 } }
		local function pose() for _, fn in ipairs(env.on_pose) do fn(view) end end
		pose()
		eq(units.body.meshes[1], true, "3 m off: shown")
		view.position = { x = 0, y = -0.4, z = 1.5 }
		pose()
		eq(units.body.meshes[1], false, "0.4 m off: hidden") eq(units.rifle.meshes[1], false, "the rifle too")
		view.position = { x = 0, y = -0.6, z = 1.5 }
		pose()
		eq(units.body.meshes[1], false, "between NEAR and FAR it stays hidden")
		unit("pistol")
		units.avatar.kids = { "rifle", "pistol" }
		pose()
		eq(units.pistol.meshes[1], false, "a weapon switched in while hidden hides too")
		view.position = { x = 0, y = -1, z = 1.5 }
		pose()
		eq(units.body.meshes[1], true) eq(units.body.meshes[2], false, "a mesh the game had off stays off")
		eq(units.body.meshes[3], true) eq(units.rifle.meshes[1], true, "shown again")
		near(body.distance_to_body({ x = 0, y = 0, z = 3 }, { x = 0, y = 0, z = 0 }), 3 - body.BODY[2], "over the head")
	end },

	{ "the stowed support weapon hides while another weapon is in hand", function()
		local units, unit = body_world()
		local avatar = unit("avatar", 0)
		unit("rifle")
		unit("tube", 0, { true, false })
		local inv = { current_weapon = "rifle", support_weapon = "tube" }
		_G.EntityAux = { state_master = function(u, name) if u == avatar and name == "inventory" then return inv end error("no") end }
		local api = { game = { all_avatars = function() return {} end, slaves = function() return {} end } }
		local listeners = {}
		local option = true
		local config = { get = function() return option end, on_change = function(_, fn) listeners[#listeners + 1] = fn end }
		local env = { api = api, config = config, state = {}, on_pose = {}, on_release = {} }
		local body = m("src/body")
		body.start(env)
		local view = { avatar = avatar, position = { x = 0, y = -3, z = 1.5 } }
		local function pose() for _, fn in ipairs(env.on_pose) do fn(view) end end
		pose()
		eq(units.tube.meshes[1], false, "stowed: hidden")
		inv.current_weapon = "tube"
		pose()
		eq(units.tube.meshes[1], true, "in hand: shown") eq(units.tube.meshes[2], false, "a mesh the game had off stays off")
		inv.current_weapon = "rifle"
		pose()
		eq(units.tube.meshes[1], false, "stowed again")
		view.vehicle = true
		pose()
		eq(units.tube.meshes[1], true, "in a vehicle: as the game has it")
		view.vehicle = nil
		pose()
		for _, fn in ipairs(listeners) do fn(false) end
		pose()
		eq(units.tube.meshes[1], true, "option off: shown")
		for _, fn in ipairs(listeners) do fn(true) end
		pose()
		for _, fn in ipairs(env.on_release) do fn() end
		eq(units.tube.meshes[1], true, "third person off: shown")
		EntityAux = nil
	end },

	{ "the ammo bar is an arc on the chosen side, filling up or across", function()
		local a = m("src/ammobar")
		local R = 100
		local f = a.shape("oppose", 1, true, 0, 0, R)
		local x0, y0 = f(0, R)
		local x1, y1 = f(1, R)
		local lo, hi = math.pi / 2 + a.SPAN / 2, math.pi / 2 - a.SPAN / 2
		near(x0, R * math.sin(lo)) near(y0, R * math.cos(lo), "starts at the bottom right")
		near(x1, R * math.sin(hi)) near(y1, R * math.cos(hi), "fills up to the top right")
		local xl = a.shape("oppose", -1, true, 0, 0, R)(0.5, R)
		near(xl, -R, "over the left shoulder the bar goes left")
		near(a.shape("same", 1, true, 0, 0, R)(0.5, R), -R, "same side as the Helldiver: left with the right shoulder")
		local tx0, ty0 = a.shape("top", 1, true, 0, 0, R)(0, R)
		local tx1 = a.shape("top", 1, true, 0, 0, R)(1, R)
		eq(tx0 < 0, true) eq(tx1 > 0, true, "the top bar fills left to right") eq(ty0 > 0, true)
		local _, by = a.shape("bottom", 1, true, 0, 0, R)(0.5, R)
		near(by, -R, "the bottom bar under the crosshair")
		local sx0, sy0 = a.shape("oppose", 1, false, 0, 0, R)(0, R)
		local sx1, sy1 = a.shape("oppose", 1, false, 0, 0, R)(1, R)
		near(sx0, R) near(sx1, R, "straight: upright at R")
		near(sy1 - sy0, 2 * R * math.sin(a.SPAN / 2), "as long as the curved bar's chord")
		eq(a.dividers, nil, "one plain band, no lines between rounds")
		eq(a.progress({ reload_time = 1, reload_duration = 2 }), 0.5)
		eq(a.progress({ reload_time = -1, reload_duration = 2 }), nil)
		local cfg = { ammo_bar = true }
		local env = { config = { get = function(k) return cfg[k] end }, state = { active = true } }
		eq(a.wanted(env), true)
		env.state.vehicle = true
		eq(a.wanted(env), false, "not in a vehicle")
		env.state.vehicle, cfg.ammo_bar = false, false
		eq(a.wanted(env), false, "option off")
	end },

	{ "the wheel moves the camera and keeps the weapon", function()
		local c = m("src/camera")
		eq(c.zoom_step(3, 1), 2.5, "a notch up: closer")
		eq(c.zoom_step(3, -120), 3.5, "a 120 notch down: farther")
		eq(c.zoom_step(1, 1), c.ZOOM_MIN) eq(c.zoom_step(10, -1), c.ZOOM_MAX)
		eq(c.zoom_step(3, 0), 3)
		local aim = m("src/aim")
		local cfg = { scroll_distance = true }
		local env = { config = { get = function(k) return cfg[k] end }, state = {} }
		local cam = { wheel = function() return 1 end }
		local data = { switch_weapon = "next" }
		eq(aim.gate_wheel(data, { kbm = true, look = true }, env, cam), true)
		eq(data.switch_weapon, nil, "the wheel's switch dropped")
		data.switch_weapon = "primary"
		cam.wheel = function() return 0 end
		eq(aim.gate_wheel(data, { kbm = true, look = true }, env, cam), false)
		eq(data.switch_weapon, "primary", "a number key still switches")
		cam.wheel = function() return 1 end
		cfg.scroll_distance = false
		eq(aim.gate_wheel(data, { kbm = true, look = true }, env, cam), false, "option off: the game's wheel")
		cfg.scroll_distance = true
		env.state.vehicle = true
		eq(aim.gate_wheel(data, { kbm = true, look = true }, env, cam), false, "not in a vehicle")
	end },
}
