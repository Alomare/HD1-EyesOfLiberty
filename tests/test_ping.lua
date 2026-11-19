-- Pings: words, sharing, timing, and what the crosshair is on.
local E = dofile("tests/engine.lua")

local function ping() return obsidian.module("src/ping") end

local function recorder()
	local calls = {}
	local kit = setmetatable({}, { __index = function(_, name)
		return function(_, ...)
			calls[#calls + 1] = { name, ... }
			if name == "icon" then return true end
		end
	end })
	return kit, calls
end

return {
	{ "stratagem names lose their code and enemy names their capitals", function()
		local p = ping()
		eq(p.trim("MG-94 Machine Gun"), "Machine Gun")
		eq(p.trim("AC-22 Dum-Dum"), "Dum-Dum")
		eq(p.trim("Rumbler"), "Rumbler")
		eq(p.trim("TOX-13 Avenger"), "Avenger")
		eq(p.title("BILE SPEWER"), "Bile Spewer")
	end },

	{ "the chat line fits what was pinged", function()
		local p = ping()
		eq(p.message("ground"), "Look here")
		eq(p.message("enemy", "Scout", 31.6), "Scout, 32 m")
		eq(p.message("objective", "Activate the antenna"), "Activate the antenna here")
		eq(p.message("support", "Machine Gun"), "Machine Gun here")
	end },

	{ "the name over a marker comes from what was pinged, and the dash is a little lighter", function()
		local p = ping()
		eq(p.label("ground", nil, "Look here"), nil, "no name for the ground")
		eq(p.label("enemy", nil, "Bile Spewer, 40 m"), "Bile Spewer")
		eq(p.label("support", nil, "Machine Gun here"), "Machine Gun")
		eq(p.label("objective", "Raise the flag", "Raise the flag here"), "Raise the flag")
		local c = p.lighter({ 235, 45, 35 }, 0.2)
		eq(c[1], 239) eq(c[2], 87) eq(c[3], 79)
	end },

	{ "a ping's chat line takes the ping's colour, once, and only that line", function()
		local p = ping()
		GAME_TIME = 100
		local history = {
			{ text = "Alomare: Scout, 32 m", time_stamp = 99.5, player_color = { 1, 2, 3 } },
			{ text = "Alomare: hello", time_stamp = 99, player_color = { 1, 2, 3 } },
		}
		local api = { game = { state = function() return { text_chat = { history = history } } end } }
		local tints = { { words = "Scout, 32 m", color = p.COLORS.enemy, left = 3 }, { words = "Look here", color = p.COLORS.ground, left = 0.01 } }
		p.tint(api, tints, 0.016)
		eq(history[1].player_color[1], p.COLORS.enemy[1], "the ping's red")
		eq(history[2].player_color[1], 1, "the other line keeps the player's colour")
		eq(#tints, 0, "done, and the one never seen dropped after its wait")
		eq(p.chat_line(history, "Scout, 32 m", 0), nil, "not tinted twice")
		GAME_TIME = nil
	end },

	{ "a shared ping reads back as sent, and junk reads as nothing", function()
		local p = ping()
		local s = p.encode(4, "support", { x = 1.25, y = -2, z = 3 }, "stratagem_machinegun", "Machine Gun | here")
		local d = p.decode(s)
		eq(d.count, 4)
		eq(d.kind, "support")
		near(d.pos.x, 1.2, nil, 0.06)
		eq(d.pos.y, -2)
		eq(d.icon, "stratagem_machinegun")
		eq(d.words, "Machine Gun / here", "the separator can't come through in words")
		eq(p.decode("nonsense"), nil)
		eq(p.decode("1|laser|0|0|0||x"), nil, "an unknown kind")
	end },

	{ "a marker rises, pops and fades out", function()
		local p = ping()
		eq(p.alpha(0), 1)
		eq(p.alpha(p.LIFE - p.FADE / 2), 0.5)
		eq(p.alpha(p.LIFE), 0)
		eq(p.rise(0), 0)
		eq(p.rise(p.GROW), 1)
		assert(p.pop(0) > 1.5, "starts big")
		eq(p.pop(p.POP), 1)
	end },

	{ "the crosshair on an enemy pings it; near an objective, the objective; else the ground", function()
		local e = E.install()
		local p = ping()
		e.units.bug = { position = { x = 0, y = 20, z = 0 }, enemy = {}, health = { is_dead = false } }
		local enemies_near = {}
		local mm = { get_objectives = function()
			return { { name = "obj_flag", state = "pending", icon = "i", position = { { x = 50, y = 50, z = 0 } } },
				{ name = "obj_hidden", state = "pending", icon = "i", position = { { x = -50, y = 50, z = 0 } }, objective_hidden_data = {} } }
		end }
		local api = {
			game = { state = function() return { mission_manager = mm } end },
			enemies = { near = function() return enemies_near end, info = function() return { key = "bug_scout", name = "SCOUT" } end },
			catalog = { enemy = function() return { loc = "enc_bug_scout" } end, text = function(k) return k == "enc_bug_scout" and "Scout" or "Raise the flag" end },
		}
		local env = E.env(api)
		env.state.aim_point, env.state.aim_unit = { x = 0, y = 20, z = 1 }, "bug"
		local t = p.target(env)
		eq(t.kind, "enemy")
		eq(t.name, "Scout")
		env.state.aim_unit = nil
		env.state.aim_point = { x = 55, y = 45, z = 0 }
		t = p.target(env)
		eq(t.kind, "objective")
		eq(t.name, "Raise the flag")
		env.state.aim_point = { x = -50, y = 50, z = 0 }
		eq(p.target(env).kind, "ground", "an objective still hidden isn't named")
		E.remove()
	end },

	{ "the key pings once per cooldown, says it in chat, shares it and draws the marker", function()
		local e = E.install()
		local kit, calls = recorder()
		obsidian.ui = { canvas = function() return kit end }
		e.units.me = { position = { x = 0, y = 0, z = 0 } }
		local chat, shared = {}, {}
		local api = {
			game = { in_mission = function() return true end, my_unit = function() return "me" end, state = function() return {} end },
			enemies = { near = function() return {} end },
			ui = { chat = function(t) chat[#chat + 1] = t return true end },
			lobby = { share = function(k, v) shared[k] = v return true end, shared = function() return {} end },
		}
		local env = E.env(api)
		env.config.get = function() return nil end
		env.view = { position = { x = 0, y = -5, z = 2 }, forward = { x = 0, y = 1, z = 0 }, fov = 70 }
		env.state.crosshair = { x = 960, y = 540 }
		ping().start(env)
		local key = KEYS.ping
		assert(key and key.opts.part == "view", "the ping key, in the view part")
		key.fn()
		eq(#chat, 0, "top-down: no ping")
		env.state.active = true
		env.state.aim_point = { x = 0, y = 20, z = 0 }
		key.fn()
		key.fn()
		eq(#chat, 1, "once per cooldown")
		eq(chat[1], "Look here")
		eq(ping().decode(shared.ping).kind, "ground")
		for _, f in ipairs(FRAMES) do f.fn() end
		local polys = 0
		for _, c in ipairs(calls) do if c[1] == "poly" then polys = polys + 1 end end
		assert(polys >= 2, "a line and a diamond: " .. polys)
		obsidian.ui = nil
		E.remove()
	end },

	{ "a teammate's ping shows once, and one shared before the mission doesn't", function()
		local e = E.install()
		local kit, calls = recorder()
		obsidian.ui = { canvas = function() return kit end }
		e.units.me = { position = { x = 0, y = 0, z = 0 } }
		local p = ping()
		local others = { peer_a = p.encode(3, "ground", { x = 0, y = 20, z = 0 }, "", "Look here") }
		local api = {
			game = { in_mission = function() return true end, my_unit = function() return "me" end, state = function() return {} end },
			enemies = { near = function() return {} end },
			lobby = { share = function() return true end, shared = function() return others end },
		}
		local env = E.env(api)
		env.config.get = function() return nil end
		env.view = { position = { x = 0, y = -5, z = 2 }, forward = { x = 0, y = 1, z = 0 }, fov = 70 }
		env.state.active = true
		p.start(env)
		local function frames(n) for _ = 1, n do for _, f in ipairs(FRAMES) do f.fn() end end end
		local function polys() local n = 0 for _, c in ipairs(calls) do if c[1] == "poly" then n = n + 1 end end return n end
		frames(30)
		eq(polys(), 0, "shared before: nothing")
		others.peer_b = p.encode(1, "ground", { x = 5, y = 20, z = 0 }, "", "Look here")
		frames(30)
		assert(polys() > 0, "a new teammate's first ping shows")
		obsidian.ui = nil
		E.remove()
	end },
}
