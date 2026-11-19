-- Hurt feedback: strength from the share of health lost, the flash over time, renewing and the shake.
local function hurt() return obsidian.module("src/hurt") end

return {
	{ "a bigger share of health lost makes a stronger flash, between the least and full", function()
		local h = hurt()
		eq(h.strength(0, 100), 0, "nothing lost")
		eq(h.strength(1, 100), h.LEAST, "a scratch shows at the least")
		near(h.strength(20, 100), 0.6, "a fifth of the bar")
		eq(h.strength(50, 100), 1, "half the bar is full")
	end },

	{ "the flash rises fast and fades out", function()
		local h = hurt()
		eq(h.shown(1, 0), 0, "starts from nothing")
		near(h.shown(1, h.RISE), 1, "full after the rise")
		assert(h.shown(1, h.RISE + h.FADE / 2) < 0.5, "fading")
		eq(h.shown(1, h.RISE + h.FADE), 0, "gone")
	end },

	{ "a new hit renews the flash and shakes only in third person, not twice at once", function()
		local h = hurt()
		local shake = obsidian.module("src/shake")
		shake.clear()
		h.clear()
		h.since_shake = math.huge
		h.hurt(0.5, false)
		eq(#shake.list, 0, "top-down: no shake")
		h.step(h.RISE)
		near(h.shown(h.flash.level, h.flash.age), 0.5, "at strength")
		h.since_shake = math.huge
		h.hurt(0.3, true)
		near(h.shown(h.flash.level, h.flash.age), 0.5, "a weaker hit keeps what shows")
		eq(#shake.list, 1, "a shake")
		h.hurt(1, true)
		eq(#shake.list, 1, "not another one right away")
		h.step(h.SHAKE_GAP)
		h.hurt(1, true)
		eq(#shake.list, 2, "after the gap")
		near(shake.list[2].amp, h.SHAKE.most, "a full hit shakes the most")
	end },

	{ "in the game's top-down view a hit neither counts nor flashes", function()
		local E = dofile("tests/engine.lua")
		E.install()
		local drawn = 0
		Gui = { bitmap_uv = function() drawn = drawn + 1 end }
		World.create_screen_gui = function() return {} end
		Vector2 = function(x, y) return { x = x, y = y } end
		Vector3 = Vector3 or function(x, y, z) return { x = x, y = y, z = z } end
		Color = function(...) return { ... } end
		local state_obj = {}
		local game = { in_mission = function() return true end, state = function() return state_obj, "game" end, my_unit = function() return "me" end }
		local env = E.env({ game = game })
		env.config.get = function() return nil end
		obsidian.module("src/art").start(env)
		local h = hurt()
		h.clear()
		h.start(env)
		local function frame() for _, f in ipairs(FRAMES) do f.fn() end end
		local hook = E.hook("HealthComponent", "command_master")
		local function hit()
			local ctx = { state = { hitpoints_real = 100, max_hitpoints = 100 } }
			hook(function(_, _, c) c.state.hitpoints_real = 50 end, nil, "me", ctx, "do_damage", nil)
		end
		env.state.active = false
		frame()
		hit()
		frame()
		eq(h.flash.level, 0, "top-down: the hit is not counted")
		eq(drawn, 0, "top-down: nothing drawn")
		env.state.active = true
		frame()
		hit()
		frame()
		assert(h.flash.level > 0, "third person: the hit counts")
		assert(drawn > 0, "third person: the flash is drawn")
		Gui, Vector2, Color = nil, nil, nil
		E.remove()
	end },
}
