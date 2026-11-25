-- Loose weapon parts (src/loose.lua): the free actor of a weapon held folded while the shoulder view is
-- on, given back to the physics after.
local function fakes()
	local w = {
		alive = { gun = true, mortar = true },
		actors = {
			mortar = {
				{ dyn = true, kin = true, node = 2 },
				{ dyn = true, kin = false, node = 3 },
				{ dyn = true, kin = false, node = 0 },
			},
			gun = {},
		},
		rot = {},
	}
	rawset(_G, "Unit", {
		alive = function(u) return w.alive[u] == true end,
		num_actors = function(u) return #w.actors[u] end,
		actor = function(u, i) return w.actors[u][i + 1] end,
		set_local_rotation = function(u, node, q) w.rot[u .. node] = q end,
	})
	rawset(_G, "Actor", {
		is_dynamic = function(a) return a.dyn end,
		is_kinematic = function(a) return a.kin end,
		node = function(a) return a.node end,
		set_kinematic = function(a, on) a.kin = on end,
	})
	rawset(_G, "Quaternion", { identity = function() return "identity" end })
	rawset(_G, "EntityAux", { state_master = function(_, name)
		if name == "inventory" then return { primary_weapon = "gun", support_weapon = "mortar", current_weapon = "gun" } end
	end })
	return w
end

return {
	{ "a free weapon part is folded and rides with the weapon while third person is on", function()
		local w = fakes()
		local loose = obsidian.module("src/loose")
		loose.held, loose.logged = {}, {}
		local logs = {}
		local env = { log = function(s) logs[#logs + 1] = s end }
		loose.frame(env, { avatar = "me" })
		local leg = w.actors.mortar[2]
		eq(leg.kin, true, "the leg is kinematic")
		eq(w.rot.mortar3, "identity", "and folded")
		eq(w.actors.mortar[3].kin, false, "a part on the root is left alone")
		eq(w.rot.mortar0, nil)
		eq(#logs, 1)
		leg.kin = false
		loose.frame(env, { avatar = "me" })
		eq(leg.kin, false, "once per weapon")
		leg.kin = true
		loose.give_back()
		eq(leg.kin, false, "the top-down camera gives it back")
		-- A weapon gone is forgotten.
		loose.frame(env, { avatar = "me" })
		w.alive.mortar = nil
		loose.frame(env, { avatar = "me" })
		eq(loose.held.mortar, nil)
		eq(#logs, 1, "logged once")
	end },

	{ "the death cam leaves the parts as they are", function()
		local w = fakes()
		local loose = obsidian.module("src/loose")
		loose.held = {}
		loose.frame({ log = function() end }, { avatar = "me", watching = true })
		eq(w.actors.mortar[2].kin, false)
	end },
}
