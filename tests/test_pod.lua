-- The Hellpod camera's wait in the sky and whose drop it rides (src/pod.lua, src/camera.lua), and the
-- gates of the throw arc's fade, the enemy indicators and pings.
local E = dofile("tests/engine.lua")

return {
	{ "a bot's drop isn't this player's, by the pad of its input", function()
		E.install()
		local cam = obsidian.module("src/camera")
		local own = { [0] = true, [1] = true }
		eq(cam.drop_is_mine("bot", nil, nil, 3, own), false, "a bot's pad")
		eq(cam.drop_is_mine("me", nil, nil, 0, own), true, "the keyboard's pad, no avatar yet")
		eq(cam.drop_is_mine("me", nil, nil, nil, own), true, "pad unknown: as before")
		eq(cam.drop_is_mine("me", "me", nil, 3, own), true, "the known avatar always is")
		E.remove()
	end },

	{ "the hanging camera sits HEIGHT over the first pod and moves over to this pod in SNAP seconds", function()
		E.install()
		local pod = obsidian.module("src/pod")
		local h = pod.hang({ x = 10, y = 0, z = 2 })
		local at, pitch = pod.hang_pose(h, 0)
		near(at.z, 2 + pod.HEIGHT, "high over the spot")
		eq(pitch, pod.PITCH)
		local d = pod.new({ x = 0, y = 0, z = 0 })
		eq(pod.snap(d), 1, "a drop without a wait rides at once")
		d.from = at
		eq(pod.snap(d), 0, "starts where the wait was")
		pod.step(d, pod.SNAP / 2)
		near(pod.snap(d), 0.5, "half way, eased")
		pod.step(d, pod.SNAP)
		eq(pod.snap(d), 1, "on this pod")
		E.remove()
	end },

	{ "the glide into the shoulder view starts 0.4 s sooner than in 0.14.0", function()
		local pod = obsidian.module("src/pod")
		near(pod.HOLD, 1.6, "hold on the landed pod")
	end },

	{ "a throw freezes the arc shown last, which fades over a second", function()
		local arc = obsidian.module("src/arc")
		arc.shown = { points = { { x = 0, y = 0, z = 0 } }, land = nil, scroll = 0.2, frame = 10 }
		arc.thrown(11)
		assert(arc.frozen, "frozen")
		eq(arc.frozen.scroll, 0.2, "the dashes stay where they were")
		eq(arc.shown, nil)
		near(arc.freeze_alpha(0), 1) near(arc.freeze_alpha(0.5), 0.5) eq(arc.freeze_alpha(1), 0)
		arc.frozen = nil
		arc.shown = { points = {}, frame = 1 }
		arc.thrown(20)
		eq(arc.frozen, nil, "an arc not drawn lately doesn't freeze")
	end },

	{ "enemy indicators show only while the Helldiver is alive or down", function()
		local radar = obsidian.module("src/radar")
		eq(radar.wanted({ active = true }), true)
		eq(radar.wanted({ active = false }), false, "top-down")
		eq(radar.wanted({ active = true, watching = true }), false, "death cam")
		eq(radar.wanted({ active = true, dropping = true }), false, "in the Hellpod")
	end },

	{ "pings go out alive, down, and dead while the camera is still on the body", function()
		local ping = obsidian.module("src/ping")
		eq(ping.may_ping(true, { active = true }), true)
		eq(ping.may_ping(false, { active = true }), false, "option off")
		eq(ping.may_ping(true, { active = true, watching = true, ping_centre = { x = 1, y = 1 } }), true, "on the body")
		eq(ping.may_ping(true, { active = true, watching = true }), false, "following an ally")
	end },
}
