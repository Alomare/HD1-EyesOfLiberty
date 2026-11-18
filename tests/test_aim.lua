-- Aim: the crosshair ray, the character's aim input, shots along the crosshair, throws, the crosshair.
local E = dofile("tests/engine.lua")

local function rig() return obsidian.module("src/rig") end

local function started(api)
	local e = E.install()
	local env = E.env(api)
	env.config.start(env)
	obsidian.module("src/camera").start(env)
	obsidian.module("src/aim").start(env)
	return e, env
end

local function frame(e, env, masters)
	E.hook("InputComponent", "update_masters")(function() end, {}, masters, 0.016)
	E.hook("CameraManager", "update")(function() end, CameraManager, 0.016)
end

return {
	{ "the crosshair ray starts past the Helldiver and skips the own body", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.aim_hit = { pos = { x = 0, y = 30, z = 1 }, unit = "rock" }
		frame(e, env, masters)
		local p = env.state.aim_point
		eq(p.y, 30, "hit point") eq(env.state.aim_hit, true)
		eq(env.state.crosshair.x, 960) eq(env.state.crosshair.y, 540)
		-- Only the own body on the line: the point is the far end of the ray.
		e.aim_hit = { pos = { x = 0, y = 2, z = 1 }, unit = "me" }
		frame(e, env, masters)
		eq(env.state.aim_hit, false, "own body skipped")
		assert(env.state.aim_point.y > 200, "far end")
		E.remove()
	end },

	{ "a carried shield doesn't stop the crosshair ray", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.units.pack = { equipment = { wielder = "me" } }
		e.aim_hit = nil
		e.aim_hits = {
			{ pos = { x = 0, y = 40, z = 0 }, distance = 40, unit = "ground" },
			{ pos = { x = 0, y = 3, z = 1 }, distance = 2.5, unit = "pack" },     -- the shield of the own backpack
			{ pos = { x = 0, y = 0.6, z = 1 }, distance = 0, unit = "bubble" },  -- a shape the ray starts in
			{ pos = { x = 0, y = 25, z = 1 }, distance = 25, unit = "rock" },
		}
		frame(e, env, masters)
		eq(env.state.aim_hit, true)
		eq(env.state.aim_point.y, 25, "the closest hit that isn't own gear or the start")
		e.aim_hits = nil
		E.remove()
	end },

	{ "a vehicle gun fires level, the way it points", function()
		local r = rig()
		local d = r.gun_dir({ x = 0, y = 0, z = 2 }, { x = 10, y = 20, z = 12 }, { x = 0, y = 1, z = -0.3 })
		near(d.x, 0, "heading of the gun") near(d.y, 1)
		eq(d.z, 0, "level, whatever the crosshair height")
		eq(r.gun_dir({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 1, z = 0 }), nil, "too close")
		eq(r.gun_dir({ x = 0, y = 0, z = 0 }, { x = 0, y = -20, z = 0 }, { x = 0, y = 1, z = 0 }), nil, "behind the gun")
	end },

	{ "ray start sits past the pivot", function()
		local r = rig()
		local s = r.ray_start({ x = 0, y = -3, z = 1.5 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1.5 })
		near(s, 3.5, "past the pivot")
		eq(r.ray_start({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 0, y = -5, z = 0 }), 0.5, "pivot behind")
	end },

	{ "the aim input points at the crosshair while aiming, and a pad stick stops turning the body", function()
		local aim = obsidian.module("src/aim")
		local view = { pivot = { x = 0, y = 0, z = 1.5 }, target_position = { x = 0, y = 0, z = 0 } }
		local data = { aim = { x = 0, y = 0, z = 0 } }
		eq(aim.steer(data, { look = true, kbm = true, aiming = true }, view, { x = 10, y = 10, z = 5 }), true)
		near(data.aim.x, math.sqrt(0.5)) near(data.aim.y, math.sqrt(0.5)) eq(data.aim.z, 0, "flat")
		local idle = { aim = { x = 0, y = 0, z = 0 } }
		eq(aim.steer(idle, { look = true, kbm = true }, view, { x = 10, y = 0, z = 0 }), false, "not aiming: the game's own")
		eq(idle.aim.x, 0)
		local pad = { aim = { x = 1, y = 0, z = 0 } }
		aim.steer(pad, { look = true, kbm = false }, view, { x = 0, y = 10, z = 0 })
		eq(pad.aim.x, 0, "stick looks, not turns") eq(pad.aim.y, 0)
		local firing = { aim = { x = 0, y = 0, z = 0 } }
		aim.steer(firing, { look = true, kbm = false, fire = true }, view, { x = 0, y = 10, z = 0 })
		near(firing.aim.y, 1, "pad fires at the crosshair")
	end },

	{ "a pad aims with the left trigger, and the reload button throws while it does", function()
		local e = E.install()
		local cam = obsidian.module("src/camera")
		local function read(data)
			data.is_active = true
			data.fire_button = data.fire_button or 0
			data.throw = data.throw or 0
			return cam.read_input(nil, "me", { state = { pad_number = 0, input_data = data, has_focus = true } }, false, 0.016)
		end
		local idle = read({ aim = { x = 1, y = 0, z = 0 } })
		eq(idle.aiming, false, "the stick alone doesn't aim") eq(idle.pad_aim, nil)
		local held = read({ left_trigger = 1, throw = 1, reload_button = 0 })
		eq(held.aiming, true, "the left trigger aims") eq(held.throw, false, "and doesn't throw")
		local q = { throw = true, throw_amount = 1, reload = true }
		eq(cam.pad_buttons(q, held), true)
		eq(q.throw, false) eq(q.reload, false, "no reload while aiming")
		local toss = read({ left_trigger = 1, throw = 1, reload_button = 1 })
		eq(toss.throw, true, "the reload button throws")
		q = { throw = false, throw_amount = 0, reload = true }
		cam.pad_buttons(q, toss)
		eq(q.throw, true) eq(q.throw_amount, 1) eq(q.reload, false)
		local free = { throw = true, reload = true }
		eq(cam.pad_buttons(free, idle), false, "not aiming: the game's buttons")
		eq(free.throw, true) eq(free.reload, true)
		local mouse = cam.read_input(nil, "me", { state = { pad_number = 99, has_focus = true,
			input_data = { is_active = true, fire_button = 0, throw = 0, left_trigger = 1 } } }, false, 0.016)
		eq(mouse.pad_aim, nil, "keyboard and mouse untouched")
		eq(read({ push_to_talk = 1 }).swap, false, "pressed: not yet")
		eq(read({ push_to_talk = 0 }).swap, true, "a right stick tap swaps the shoulder")
		eq(read({ push_to_talk = 0 }).swap, false, "once")
		for _ = 1, 30 do read({ push_to_talk = 1 }) end
		eq(read({ push_to_talk = 0 }).swap, false, "holding it to talk doesn't swap")
		E.remove()
	end },

	{ "the queued aim command of this player is steered", function()
		local e, env = started()
		local masters = E.player(e, "me", { aiming = true })
		e.aim_hit = { pos = { x = 5, y = 5, z = 0 }, unit = "rock" }
		frame(e, env, masters)
		local queue = E.hook("InputComponent", "queue_command_master")
		local data = { aim = { x = 0, y = 1, z = 0 } }
		local got = nil
		queue(function(_, _, _, _, d) got = d end, {}, "me", "character", "input", data)
		near(got.aim.x, math.sqrt(0.5)) near(got.aim.y, math.sqrt(0.5))
		local other = { aim = { x = 0, y = 1, z = 0 } }
		queue(function() end, {}, "bot", "character", "input", other)
		eq(other.aim.y, 1, "other units untouched")
		E.remove()
	end },

	{ "shot directions: to the point, nil when too close or behind", function()
		local r = rig()
		local d = r.shot_dir({ x = 0, y = 0, z = 1.4 }, { x = 0, y = 30, z = 11.4 }, { x = 0, y = 1, z = 0 })
		near(d.z, 10 / math.sqrt(900 + 100), "pitch included")
		eq(r.shot_dir({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }), nil, "too close")
		eq(r.shot_dir({ x = 0, y = 0, z = 0 }, { x = 0, y = -10, z = 0 }, { x = 0, y = 1, z = 0 }), nil, "behind")
	end },

	{ "this player's weapon fires along the crosshair with no dip, only during the call", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		e.units.gun = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, equipment = { wielder = "me" } }
		e.units.their_gun = { position = { x = 5, y = 0, z = 0 }, forward = { x = 1, y = 0, z = 0 }, equipment = { wielder = "them" } }
		e.units.them = { position = { x = 5, y = 0, z = 0 }, forward = { x = 1, y = 0, z = 0 } }
		local view = { avatar = "me", target = "me" }
		local point = { x = 0, y = 30, z = 11 }
		local slaves = { gun = { state = { attach_node = 3 } }, their_gun = { state = { attach_node = 3 } } }
		local list = aim.collect(slaves, view, point, Quaternion.forward)
		assert(#list >= 1, "own gun found")
		for _, o in ipairs(list) do eq(o.f.x, 0, "only the own forward") end
		local spread_calls = {}
		WeaponUtility = { get_random_spread = function(offset, f) spread_calls[#spread_calls + 1] = offset.z return f end }
		local mine, theirs, offset_z
		aim.redirect(list, function()
			mine = Quaternion.forward(Unit.world_rotation("me", 3))
			theirs = Quaternion.forward(Unit.world_rotation("them", 3))
			WeaponUtility.get_random_spread(E.V3(0.2, 0.5, 1.4), mine, 0.01, 30)
			WeaponUtility.get_random_spread(E.V3(0.2, 0.5, 1.4), theirs, 0.01, 30)
		end)
		assert(mine.z > 0.3, "pitched up at the point: " .. mine.z)
		eq(theirs.x, 1, "another player's gun untouched")
		eq(spread_calls[1], 0, "no dip for the own shot") eq(spread_calls[2], 1.4, "dip kept for others")
		eq(Quaternion.forward(Unit.world_rotation("me", 3)).z, 0, "given back after the call")
		WeaponUtility = nil
		E.remove()
	end },

	{ "the shot's way starts where the game's shot starts: 1.5 m up by default", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		e.units.gun = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, equipment = { wielder = "me" } }
		-- A head at 1.6 m, 10 m ahead: the shot from 1.5 m rises 0.1 m over 10 m.
		local slaves = { gun = { state = { attach_node = 0, ray_source_offset = { x = 0, y = 0, z = 1.5 } } } }
		local list = aim.collect(slaves, { avatar = "me", target = "me" }, { x = 0, y = 10, z = 1.6 }, Quaternion.forward)
		near(list[1].dir.z / list[1].dir.y, 0.01, "rises from the game's origin")
		E.remove()
	end },

	{ "the game's spread around this player's shot is turned to the crosshair way, with no dip", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		local s = math.sqrt(0.5)
		local list = { { f = { x = 0, y = 1, z = 0 }, dir = { x = 0, y = s, z = s } } }
		local seen
		-- A spread that leans 0.1 to the right of the level way it is given.
		WeaponUtility = { get_random_spread = function(offset, f)
			seen = { f = f, oz = offset.z }
			local l = math.sqrt(1 + 0.01)
			return E.V3((f.x + 0.1 * f.y) / l, (f.y - 0.1 * f.x) / l, f.z / l)
		end }
		local got
		aim.redirect(list, function()
			local f = Quaternion.forward(Unit.world_rotation("me", 0))
			got = WeaponUtility.get_random_spread(E.V3(0, 0, 1.5), f, 0.01, 30)
		end)
		eq(seen.oz, 0, "no dip") near(seen.f.z, 0, "made around the level way")
		near(got.z, s / math.sqrt(1.01), "pitched up with the crosshair", 1e-6)
		near(got.x, 0.1 / math.sqrt(1.01), "the spread kept", 1e-6)
		WeaponUtility = nil
		E.remove()
	end },

	{ "turn_to turns a vector as from turns to to", function()
		local r = rig()
		local t = r.turn_to({ x = 0, y = 1, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1 })
		near(t.z, 1) near(t.y, 0)
		local same = r.turn_to({ x = 1, y = 2, z = 3 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 1, z = 0 })
		eq(same.y, 2)
	end },

	{ "a throw of this player flies with the aimed velocity, others as the game has them", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.aim_hit = { pos = { x = 0, y = 6, z = 0 }, unit = "ground" }
		frame(e, env, masters)
		e.units.nade = { position = { x = 0, y = 0.3, z = 1.5 }, forward = { x = 0, y = 1, z = 0 } }
		local sets = {}
		Actor = { unit = function(a) return a end, set_velocity = function(_, v) sets[#sets + 1] = v end }
		local do_throw = E.hook("CharacterComponent", "do_throw")
		local thrown = E.hook("ThrowableComponent", "command_master")
		local ctx = { settings = { throwable_info = { throw_distance_min = 2, throw_distance_max = 9 } } }
		local game = function() Actor.set_velocity("actor", E.V3(0, 5, 5)) end
		thrown(game, {}, "nade", ctx, "thrown", {})
		eq(sets[1].y, 5, "no throw marked: the game's")
		do_throw(function() end, {}, "me", { state = { throw_range_multiplier = 1 } }, 0.5)
		thrown(game, {}, "nade", ctx, "thrown", {})
		local v = sets[2]
		local t = 5.7 / v.y
		near(1.5 + v.z * t - 9 * t * t, 0, "lands on the crosshair point", 1e-4)
		thrown(game, {}, "nade", ctx, "thrown", {})
		eq(sets[3].y, 5, "once per throw")
		Actor = { unit = function(a) return a end }
		E.remove()
	end },

	{ "a laser sight on this player's weapon lands on the crosshair point", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		e.units.gun = { position = { x = 0, y = 0, z = 1.4 }, forward = { x = 0, y = 1, z = 0 }, equipment = { wielder = "me" } }
		local slaves = { gun = { state = { laser_enabled = true, attach_node = 2, range = 30 } } }
		local list = aim.collect_lasers(slaves, { avatar = "me", target = "me" }, { x = 0, y = 30, z = 1.4 }, Quaternion.forward)
		eq(#list, 1)
		WeaponUtility = { get_random_spread = function() end }
		local got = nil
		aim.redirect(list, function()
			local f = Quaternion.forward(Unit.world_rotation("gun", 2))
			f.z = f.z - 1.5 / 30 -- what the game does next
			got = f
		end)
		near(got.z, 0, "level after the game's own lowering", 1e-9)
		WeaponUtility = nil
		E.remove()
	end },

	{ "a grenade throw measures to the crosshair point", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.aim_hit = { pos = { x = 0, y = 12, z = 0 }, unit = "ground" }
		frame(e, env, masters)
		local throw = E.hook("CharacterStateThrow", "update")
		local s2w = E.hook("CameraManager", "screen_to_world")
		local got = nil
		throw(function(unit) got = s2w(function() return "cursor" end, CameraManager, E.V3()) end, "me")
		eq(got.y, 12, "crosshair point")
		eq(s2w(function() return "cursor" end, CameraManager, E.V3()), "cursor", "outside a throw")
		E.remove()
	end },

	{ "the game's crosshair shows in a vehicle, while aiming or firing, or always by the game option", function()
		local cross = obsidian.module("src/crosshair")
		local busy = false
		local env = { state = { active = true, crosshair = { x = 1, y = 1 } }, camera = { input = { look = true } },
			api = { capture = { busy = function() return busy end }, map = { is_open = function() return false end } } }
		eq(cross.visible(env), false, "on foot between shots")
		eq(cross.visible(env, true), true, "the game option keeps it up")
		eq(cross.look(env, true), "idle", "between shots: the game's idle cursor")
		env.state.firing = true
		eq(cross.visible(env), true, "firing")
		eq(cross.look(env, true), "aim", "firing: the aiming cursor")
		env.state.firing, env.state.vehicle = false, true
		eq(cross.visible(env), true, "in a vehicle")
		busy = true
		eq(cross.visible(env), false, "picture")
		busy = false
		env.camera.input.look = false
		eq(cross.visible(env), false, "a menu has the mouse")
		env.camera.input.look = true
		env.state.claimed_by = "alomare.customcrosshair"
		eq(cross.visible(env), false, "claimed")
		env.state.claimed_by, env.state.active = nil, false
		eq(cross.visible(env), false, "top-down")
		local x, y, s = cross.rect(960, 540)
		eq(x, 944) eq(y, 524) eq(s, 32)
	end },

	{ "the game's crosshair image goes on the cursor gui after the input update", function()
		local e = E.install()
		local env = E.env()
		env.state.active, env.state.crosshair, env.state.aiming = true, { x = 960, y = 540 }, true
		env.camera = { input = { look = true } }
		local drawn = nil
		rawset(_G, "Gui", { bitmap_uv = function(gui, material, _, _, pos, size) drawn = { gui, material, pos.x, pos.y, size.x } end })
		rawset(_G, "Vector2", function(x, y) return { x = x, y = y } end)
		rawset(_G, "Color", function(...) return { ... } end)
		obsidian.module("src/crosshair").start(env)
		local ran = false
		E.hook("InputComponent", "update_masters")(function() ran = true return "done" end, { cursor_gui = "cg" }, {}, 0.016)
		eq(ran, true)
		eq(drawn[1], "cg") eq(drawn[2], "cursor_game") eq(drawn[3], 944) eq(drawn[4], 524) eq(drawn[5], 32)
		drawn = nil
		env.state.claimed_by = "alomare.customcrosshair"
		E.hook("InputComponent", "update_masters")(function() end, { cursor_gui = "cg" }, {}, 0.016)
		eq(drawn, nil, "claimed: Custom Crosshair draws it")
		E.remove()
	end },

	{ "the hardware cursor of the game stays out under the shoulder camera", function()
		local cam = obsidian.module("src/camera")
		local hidden = 0
		local cursors = { shown = true, current_cursor = "hud/cursors/game", next_cursor = "hud/cursors/game_inactive",
			cursor_transition_timer = 0.035, cursor_transition_index = 1,
			set_show_cursor = function(self, on) if not on then hidden = hidden + 1 self.shown = false end end }
		cam.hide_game_cursor(cursors)
		eq(cursors.next_cursor, nil, "no transition steps left")
		eq(cursors.current_cursor, "hud/cursors/game_inactive")
		eq(hidden, 1)
		cursors.shown, cursors.current_cursor = true, "hud/cursors/menu"
		cam.hide_game_cursor(cursors)
		eq(hidden, 1, "a menu cursor stays")
	end },
}
