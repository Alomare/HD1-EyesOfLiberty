-- The death cam (src/deathcam.lua) and how the camera draws it (src/camera.lua).
local E = dofile("tests/engine.lua")

local function D() return obsidian.module("src/deathcam") end

-- A fake Obsidian API game: the unit my_unit answers, and the living avatars, mine first.
local function game_api(e)
	local g = { mine = "me", others = {}, extracted = false }
	g.api = { game = {
		my_unit = function()
			local u = g.mine
			if u and e.units[u] and e.units[u].alive ~= false then return u end
			return nil
		end,
		all_avatars = function()
			local out = {}
			for _, u in ipairs({ g.mine, unpack(g.others) }) do
				if u and e.units[u] and e.units[u].alive ~= false then out[#out + 1] = { unit = u, owned = u == g.mine } end
			end
			return out
		end,
		me = function()
			return { player_go = { has = function() return true end, get = function() return g.extracted end } }
		end,
	} }
	return g
end

local function body(e, name, x)
	e.units[name] = { position = { x = x or 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, health = { is_dead = false } }
end

local function kill(e, name) e.units[name].health.is_dead = true end

return {
	{ "browsing wraps round the allies, and a lost ally gives the first", function()
		local d = D()
		eq(d.pick({ "a", "b", "c" }, "c", 1), "a")
		eq(d.pick({ "a", "b", "c" }, "a", -1), "c")
		eq(d.pick({ "a", "b", "c" }, "b", 0), "b")
		eq(d.pick({ "a", "b" }, "gone", 0), "a")
		eq(d.pick({ "a", "b" }, "gone", -1), "b")
		eq(d.pick({}, "a", 1), nil)
	end },

	{ "a death watches the body, then a living ally after the delay, and a respawn ends it", function()
		local e = E.install()
		local g = game_api(e)
		local d = D()
		d.reset()
		body(e, "me", 0) body(e, "ally", 10) body(e, "other", 20)
		g.others = { "ally", "other" }
		eq(d.update(g.api, "world", 0.1), nil, "alive: nothing to watch")
		kill(e, "me")
		local w = d.update(g.api, "world", 0.1)
		eq(w.body, "me") eq(w.ally, nil, "the body first")
		near(w.at.x, 0, "on the body")
		e.units.me.position = { x = 3, y = 0, z = 0 }
		near(d.update(g.api, "world", 0.1).at.x, 3, "the body moves: the camera follows")
		e.units.me.alive = false
		near(d.update(g.api, "world", 0.1).at.x, 3, "the body gone: where it was")
		w = d.update(g.api, "world", d.ALLY_DELAY)
		eq(w.ally, "ally", "after the delay: the first ally")
		eq(d.update(g.api, "world", 0.1, 1).ally, "other", "right click: the next")
		eq(d.update(g.api, "world", 0.1, 1).ally, "ally", "and round again")
		eq(d.update(g.api, "world", 0.1, -1).ally, "other", "left click: the one before")
		kill(e, "other")
		eq(d.update(g.api, "world", 0.1).ally, "ally", "a fallen ally: the camera moves on")
		kill(e, "ally")
		w = d.update(g.api, "world", 0.1)
		eq(w.ally, nil) near(w.at.x, 10, "the last ally fell: on that body")
		-- Reinforced: a new living Helldiver of this player.
		body(e, "me2", 30)
		g.mine = "me2"
		eq(d.update(g.api, "world", 0.1), nil, "dropped in again: the watch ends")
		eq(d.watch, nil)
		E.remove()
	end },

	{ "alone, the camera stays on the body; a click before the delay goes straight to an ally", function()
		local e = E.install()
		local g = game_api(e)
		local d = D()
		d.reset()
		body(e, "me", 0)
		d.update(g.api, "world", 0.1)
		kill(e, "me")
		local w = d.update(g.api, "world", 60)
		eq(w.ally, nil, "nobody to watch: the body stays")
		body(e, "ally", 10)
		g.others = { "ally" }
		d.reset()
		body(e, "me", 0)
		d.update(g.api, "world", 0.1)
		kill(e, "me")
		eq(d.update(g.api, "world", 0.1, 1).ally, "ally", "clicked at once")
		E.remove()
	end },

	{ "no watch in another world, before the first drop or after extraction", function()
		local e = E.install()
		local g = game_api(e)
		local d = D()
		d.reset()
		g.mine = nil
		eq(d.update(g.api, "world", 0.1), nil, "no Helldiver yet")
		g.mine = "me"
		body(e, "me", 0)
		d.update(g.api, "world", 0.1)
		e.units.me.alive = false
		eq(d.update(g.api, "next mission", 0.1), nil, "a new world never starts on the old body")
		d.reset()
		e.units.me.alive = nil
		d.update(g.api, "world", 0.1)
		e.units.me.alive = false
		g.extracted = true
		eq(d.update(g.api, "world", 0.1), nil, "extracted, not dead")
		E.remove()
	end },

	{ "after boarding, the camera rides the shuttle and no ally takes it", function()
		local e = E.install()
		local g = game_api(e)
		local d = D()
		d.reset()
		body(e, "me", 0) body(e, "ally", 10) body(e, "shuttle", 50)
		g.others = { "ally" }
		d.update(g.api, "world", 0.1)
		d.board("someone else", "shuttle", "world")
		eq(d.shuttle, nil, "another player's boarding is not ours")
		d.board("me", "shuttle", "world")
		g.mine, g.extracted = nil, true
		local w = d.update(g.api, "world", 0.1)
		assert(w and w.ride, "the ride")
		eq(w.body, "shuttle") near(w.at.x, 50) near(w.at.z, d.RIDE_LIFT)
		e.units.shuttle.position.z = 30
		w = d.update(g.api, "world", 10)
		eq(w.ally, nil, "allies stay behind") near(w.at.z, 30 + d.RIDE_LIFT, "follows the shuttle up")
		d.reset()
		body(e, "me", 0) g.mine, g.extracted = "me", false
		d.update(g.api, "world", 0.1)
		d.board("me", "shuttle", "world")
		d.ride_on = false
		g.mine, g.extracted = nil, true
		eq(d.update(g.api, "world", 0.1), nil, "the option off: no ride")
		d.ride_on = true
		E.remove()
	end },

	{ "the camera keeps drawing after a death: farther back, no crosshair, then the ally", function()
		local e = E.install()
		local g = game_api(e)
		body(e, "ally", 10)
		g.others = { "ally" }
		local env = E.env(g.api)
		env.config.start(env)
		local cam = obsidian.module("src/camera")
		D().reset()
		cam.start(env)
		obsidian.module("src/aim").start(env)
		local masters = E.player(e, "me")
		e.units.me.health = { is_dead = false }
		local input, update = E.hook("InputComponent", "update_masters"), E.hook("CameraManager", "update")
		local placed = 0
		local function game()
			e.calls.set_local_position = nil
			Camera.set_local_position("camera", "camera_unit", "top-down")
			if e.calls.set_local_position then placed = placed + 1 end
		end
		for _ = 1, 20 do input(function() end, {}, masters, 0.05) update(game, CameraManager, 0.05) end
		eq(env.state.active, true) eq(env.state.watching, false)
		local p = env.view.position
		local close = math.sqrt(p.x * p.x + p.y * p.y)
		kill(e, "me")
		-- The dead Helldiver reads no input: only the camera update runs.
		placed = 0
		for _ = 1, 40 do update(game, CameraManager, 0.05) end
		eq(env.state.active, true, "still drawing")
		eq(env.state.watching, true, "the death cam")
		eq(env.state.crosshair, nil, "no crosshair")
		eq(placed, 0, "the game's pose stays out of the engine")
		eq(env.view.target, "me", "on the body")
		p = env.view.position
		assert(math.sqrt(p.x * p.x + p.y * p.y) > close + 1, "farther back than on foot")
		for _ = 1, 80 do update(game, CameraManager, 0.05) end
		eq(env.view.target, "ally", "after the delay: the ally")
		-- Dropped in again.
		e.units.me = nil
		g.mine = "me2"
		local again = E.player(e, "me2", { position = { x = 50, y = 0, z = 0 } })
		e.units.me2.health = { is_dead = false }
		for _ = 1, 3 do input(function() end, {}, again, 0.05) update(game, CameraManager, 0.05) end
		eq(env.state.watching, false, "the shoulder camera is back")
		eq(env.view.avatar, "me2")
		E.remove()
	end },

	{ "with the Death cam option off, a death gives the view back to the game", function()
		local e = E.install()
		local g = game_api(e)
		OPTIONS.death_cam = false
		local env = E.env(g.api)
		env.config.start(env)
		local cam = obsidian.module("src/camera")
		D().reset()
		cam.start(env)
		local masters = E.player(e, "me")
		e.units.me.health = { is_dead = false }
		local input, update = E.hook("InputComponent", "update_masters"), E.hook("CameraManager", "update")
		for _ = 1, 5 do input(function() end, {}, masters, 0.05) update(function() end, CameraManager, 0.05) end
		kill(e, "me")
		e.units.me.alive = false
		for _ = 1, 40 do update(function() end, CameraManager, 0.05) end
		eq(env.state.active, false, "top-down")
		E.remove()
	end },
}
