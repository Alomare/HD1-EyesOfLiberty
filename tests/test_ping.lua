-- Pings: words, sharing, timing, and what the crosshair is on.
local E = dofile("tests/engine.lua")

local function ping() return obsidian.module("src/ping") end

local function recorder()
	local calls = {}
	-- The canvas layer each call drew at is kept in the call's .z.
	local kit = setmetatable({ z = 10 }, { __index = function(_, name)
		if name == "layer" then return function(self, n) rawset(self, "z", n) end end
		return function(self, ...)
			calls[#calls + 1] = { name, ..., z = rawget(self, "z") }
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

	{ "the words fit what was pinged", function()
		local p = ping()
		eq(p.message("ground"), "Look here")
		eq(p.message("enemy", "Scout", 31.6), "Scout, 32 m")
		eq(p.message("objective", "Activate the antenna"), "Activate the antenna here")
		eq(p.message("support", "Machine Gun"), "Machine Gun here")
	end },

	{ "the name over a marker comes from what was pinged", function()
		local p = ping()
		eq(p.label("ground", nil, "Look here"), nil, "no name for the ground")
		near(p.body(2.15), 1, "an enemy's line starts half way up its body")
		near(p.body(nil), (p.ABOVE_ENEMY - p.OVER_BOX) / 2, "half the usual height when the box can't be read")
		eq(p.label("enemy", nil, "Bile Spewer, 40 m"), "Bile Spewer")
		eq(p.label("support", nil, "Machine Gun here"), "Machine Gun")
		eq(p.label("objective", "Raise the flag", "Raise the flag here"), "Raise the flag")
		eq(p.message("ammo", "Resupply"), "Resupply here")
		eq(p.message("sample", "Sample"), "Sample here")
		eq(p.decode(p.encode(1, "sample", { x = 0, y = 0, z = 0 }, "", "Sample here")).kind, "sample")
		eq(p.decode(p.encode(1, "ammo", { x = 0, y = 0, z = 0 }, "stratagem_resupply", "Resupply here")).icon, "stratagem_resupply")
	end },

	{ "the diamond is 15 percent smaller, and the line outline half as strong as the diamond's", function()
		local p = ping()
		near(p.DIAMOND, 10.4 * 0.85, nil, 1e-9)
		eq(p.LINE_EDGE, 0.5)
		eq(p.dim, nil, "no fading when looked at")
	end },

	{ "an enemy ping plays a stratagem arrow sound over the chat sound", function()
		local p = ping()
		eq(p.arrow(0), "equip_radio_press_cross")
		eq(p.arrow(0.99), "equip_radio_press_square")
		local played, chat = {}, 0
		local api = { audio = { play = function(e) played[#played + 1] = e return true end },
			game = { state = function() return { text_chat = { play_chat_sound = function() chat = chat + 1 end } } end } }
		p.sound(api, "ground")
		eq(#played, 0, "the ground: the chat sound only")
		p.sound(api, "enemy")
		eq(#played, 1)
		eq(played[1]:match("^equip_radio_press_") ~= nil, true)
		eq(chat, 2)
	end },

	{ "markers out of view sit where the game keeps allies: 96 px from the sides, 54 from top and bottom", function()
		local p = ping()
		local frustum = obsidian.module("src/frustum")
		local cam = frustum.camera_from({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, math.rad(70))
		local on, x, y = p.place(cam, { x = 0, y = 10, z = 0 }, 1920, 1080, 100, 60)
		eq(on, true) near(x, 960, nil, 1e-6) near(y, 540, nil, 1e-6)
		on, x, y = p.place(cam, { x = 100, y = 10, z = 1 }, 1920, 1080, 100, 60)
		eq(on, false) near(x, 1920 - 100, "far right in front: clamped to the margin", 1e-6)
		assert(y > 540 and y < 1080 - 60, "keeps its height: " .. y)
		on, x, y = p.place(cam, { x = 0, y = -10, z = 0 }, 1920, 1080, 100, 60)
		eq(on, false) near(y, 60, "straight behind: the bottom margin", 1e-6) near(x, 960, nil, 1e-6)
		on, x, y = p.place(cam, { x = 10, y = -10, z = 0 }, 1920, 1080, 100, 60)
		eq(on, false) near(x, 1820, "behind and right: the right margin", 1e-6)
	end },

	{ "a shared ping reads back as sent, and junk reads as nothing", function()
		local p = ping()
		local s = p.encode(4, "support", { x = 1.25, y = -2, z = 3 }, "stratagem_machinegun", "Machine Gun | here")
		local d = p.decode(s)
		eq(d.count, 4)
		eq(d.kind, "support")
		near(d.pos.x, 1.25, nil, 0.06) -- 1.2 or 1.3: printf rounds the half either way by platform
		eq(d.pos.y, -2)
		eq(d.icon, "stratagem_machinegun")
		eq(d.words, "Machine Gun / here", "the separator can't come through in words")
		eq(p.decode("nonsense"), nil)
		eq(p.decode("1|laser|0|0|0||x"), nil, "an unknown kind")
	end },

	{ "three pings in a row, then a wait of 2.5 s; a quiet 2.5 s starts a new burst", function()
		local p = ping()
		local b = {}
		eq(p.allow(b, 0), true) eq(p.allow(b, 0.1), true) eq(p.allow(b, 0.2), true)
		eq(p.allow(b, 0.3), false, "the fourth waits")
		eq(p.allow(b, 2.6), false, "still waiting")
		eq(p.allow(b, 2.7), true, "the wait is over")
		eq(p.allow(b, 2.8), true)
		eq(p.allow(b, 6), true, "a quiet spell starts a new burst")
		eq(p.allow(b, 6.1), true) eq(p.allow(b, 6.2), true)
		eq(p.allow(b, 6.3), false)
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
		env.state.aim_point = { x = 53, y = 47, z = 0 }
		t = p.target(env)
		eq(t.kind, "objective")
		eq(t.name, "Raise the flag")
		env.state.aim_point = { x = 58, y = 50, z = 0 }
		eq(p.target(env).kind, "ground", "8 m from the objective: the ground")
		env.state.aim_point = { x = -50, y = 50, z = 0 }
		eq(p.target(env).kind, "ground", "an objective still hidden isn't named")
		E.remove()
	end },

	{ "an ammo box pings with the Resupply icon, a research sample with its own", function()
		local e = E.install()
		local p = ping()
		e.units.sample = { position = { x = 10, y = 10, z = 0 } }
		local box = { unit = "box", kind = "ammo_pickup", position = { x = 0, y = 30, z = 0 } }
		local api = {
			game = { state = function() return {} end, slaves = function(name) return name == "research_sample_pickup" and { sample = {} } or {} end },
			enemies = { near = function() return {} end },
			world = { pickups = function(pos, reach) return (math.abs(pos.y - 30) <= reach and math.abs(pos.x) <= reach) and { box } or {} end },
			catalog = { text = function(k) return k == "stratagem_resupply" and "Resupply" or k end },
		}
		local env = E.env(api)
		env.state.aim_point = { x = 1, y = 30, z = 0 }
		local t = p.target(env)
		eq(t.kind, "ammo") eq(t.icon, "stratagem_resupply") eq(t.name, "Resupply")
		env.state.aim_point = { x = 11, y = 9, z = 0 }
		t = p.target(env)
		eq(t.kind, "sample") eq(t.name, "Sample")
		env.state.aim_point = { x = 15, y = 10, z = 0 }
		eq(p.target(env).kind, "ground", "5 m from the sample: the ground")
		E.remove()
	end },

	{ "the key pings three times per burst, plays the chat sound here only, shares it and draws the marker", function()
		local e = E.install()
		local kit, calls = recorder()
		obsidian.ui = { canvas = function() return kit end }
		e.units.me = { position = { x = 0, y = 0, z = 0 } }
		local chat, shared, sounds = {}, {}, 0
		local text_chat = { play_chat_sound = function() sounds = sounds + 1 end }
		local api = {
			game = { in_mission = function() return true end, my_unit = function() return "me" end, state = function() return { text_chat = text_chat } end },
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
		eq(sounds, 0, "top-down: no ping")
		env.state.active = true
		env.state.aim_point = { x = 0, y = 20, z = 0 }
		for _ = 1, 4 do key.fn() end
		eq(sounds, 3, "three in a row, then the cooldown")
		eq(#chat, 0, "nothing in the game's chat, which players without the mod read")
		eq(ping().decode(shared.ping).kind, "ground")
		for _, f in ipairs(FRAMES) do f.fn() end
		local polys = 0
		for _, c in ipairs(calls) do if c[1] == "poly" then polys = polys + 1 end end
		assert(polys >= 2, "a line and a diamond: " .. polys)
		-- The diamond covers the line: above the line's outline, which the canvas draws one layer up.
		local line_outline, diamond = nil, nil
		for _, c in ipairs(calls) do
			if c[1] == "outline" and not line_outline then line_outline = c end
			if c[1] == "poly" then diamond = c end
		end
		assert(line_outline and diamond.z >= line_outline.z + 2, "the diamond over the line")
		eq(kit.z, line_outline.z, "the layer goes back")
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
