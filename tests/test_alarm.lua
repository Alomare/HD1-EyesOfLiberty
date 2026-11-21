-- The alarm effect (src/alarm.lua), the compass's map markers and alarm look (src/compass.lua) and when
-- a crosshair shows (src/crosshair.lua).
local function m(name) return obsidian.module(name) end

return {
	{ "the alarm is the camera particle of the alarm, while the game still plays it", function()
		local a = m("src/alarm")
		eq(a.is_alarm("effects/camera_alarm"), true)
		eq(a.is_alarm("effects/camera_sandstorm"), false)
		eq(a.is_alarm(nil), false)
		eq(a.up({ siren = { alarm = true } }, { siren = 7 }), true, "up and playing")
		eq(a.up({ siren = { alarm = true } }, {}), false, "the game dropped it: over")
		eq(a.up({ dust = { alarm = false } }, { dust = 3 }), false, "another effect")
	end },

	{ "the edges pulse once and fade off", function()
		local a = m("src/alarm")
		eq(a.pulse(0), 0, "starts low")
		near(a.pulse(a.ATTACK), 1, "peaks after the rise", 1e-9)
		eq(a.pulse(a.ATTACK + 1.5) < 0.5, true, "falls")
		eq(a.pulse(a.ATTACK + a.PULSE_FADE), 0, "gone after 3 s")
		eq(a.pulse(30), 0, "and stays gone")
		near(a.ease(0, true, a.FADE_IN / 2), 0.5, "fades in", 1e-9)
		eq(a.ease(1, true, 1), 1)
		eq(a.ease(0.1, false, 1), 0, "fades out")
	end },

	{ "the stripes flash at full strength, settle to a fifth and fade toward the middle", function()
		local a = m("src/alarm")
		eq(a.stripe_strength(0), 1, "full as the alarm sounds")
		near(a.stripe_strength(1.5), 0.6, "half way down", 1e-9)
		near(a.stripe_strength(3), 0.2, "a fifth after 3 s", 1e-9)
		near(a.stripe_strength(60), 0.2, "and stays there", 1e-9)
		near(a.slice_alpha(1, 10), 0.95, "strong at the edge", 1e-9)
		near(a.slice_alpha(10, 10), 0.05, "faint at the inside", 1e-9)
	end },

	{ "hazard stripes stay inside their box", function()
		local a = m("src/alarm")
		local list = a.stripes(10, 20, 12, 300, 22, 10, 5)
		eq(#list > 10, true, "stripes all along")
		for _, p in ipairs(list) do
			eq(#p >= 6, true)
			for i = 1, #p, 2 do
				eq(p[i] >= 10 - 1e-9 and p[i] <= 22 + 1e-9, true, "x inside")
				eq(p[i + 1] >= 20 - 1e-9 and p[i + 1] <= 320 + 1e-9, true, "y inside")
			end
		end
		local whole = a.clip({ 0, 0, 4, 0, 4, 4, 0, 4 }, -1, -1, 5, 5)
		eq(#whole, 8, "a shape inside comes out whole")
		eq(#a.clip({ 10, 10, 12, 10, 12, 12 }, 0, 0, 5, 5), 0, "one outside: nothing")
	end },

	{ "a map marker comes back to the world where it was placed", function()
		local c = m("src/compass")
		for _, p in ipairs({ { x = 100, y = 250 }, { x = 0, y = 0 }, { x = 480, y = 37 } }) do
			local ping = c.ping_map(p, 40, 30, 40, 30)
			local back = c.ping_world(ping, 40, 30, 40, 30)
			near(back.x, p.x, "x", 1e-6) near(back.y, p.y, "y", 1e-6)
		end
		local mid = c.ping_world({ 0, 0 }, 40, 30, 40, 30)
		near(mid.x, 480, "the map's middle is the level's", 1e-9) near(mid.y, 360, nil, 1e-9)
		eq(c.has_ping({ -1000, -1000 }), false, "none")
		eq(c.has_ping({ 12.5, -3 }), true)
		eq(c.has_ping(nil), false)
		local l = c.lighter({ 255, 0, 100 }, 0.5)
		eq(l[1], 255) eq(l[2], 128) eq(l[3], 178)
	end },

	{ "a crosshair only while the Helldiver can shoot", function()
		local x = m("src/crosshair")
		eq(x.can_shoot("normal"), true, "on foot, down or carrying alike")
		eq(x.can_shoot(nil), true, "no HUD state read: shows")
		eq(x.can_shoot("custom"), true, "a vehicle's own HUD")
		eq(x.can_shoot("dead"), false)
		eq(x.can_shoot("map"), false)
		eq(x.can_shoot("stratagems"), false)
		local env = { state = { active = true, crosshair = { x = 1, y = 1 }, aiming = true, armed = false } }
		eq(x.look(env, true), nil, "not armed: no cursor")
		env.state.armed = true
		eq(x.look(env, true), "aim")
		-- In a Hellpod of the Super Destroyer: a seat with the drop_pod component.
		local had = rawget(_G, "EntityAux")
		EntityAux = { has_component = function(u, name) return u == "pod" and name == "drop_pod" end,
			state = function() return {} end }
		eq(x.drop_pod("pod"), true) eq(x.drop_pod("tank"), false) eq(x.drop_pod(nil), false)
		eq(x.armed({ state = {} }, { avatar = "me", target = "pod", vehicle = "turret" }), false, "in the ship's Hellpod: no crosshair")
		EntityAux = had
	end },

	{ "a finished reload swells the ammo bar and fades it out, as the Better HUD ring", function()
		local b = m("src/ammobar")
		local grow, alpha = b.finish(0)
		eq(grow, 1) eq(alpha, 1)
		grow, alpha = b.finish(b.DONE / 2)
		near(grow, 1 + b.GROW / 2, "half way", 1e-9) near(alpha, 0.5, nil, 1e-9)
		eq(b.finish(b.DONE), nil, "gone")
	end },
}
