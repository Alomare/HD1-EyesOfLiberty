-- Patrols stay in view: encounter enemies are kept out to ENCOUNTER_RANGE, and patrol units chasing a
-- Helldiver count as on screen out to CHASE_RANGE (src/session.lua).
return {
	{ "the encounter's removal reaches farther, never nearer", function()
		local s = obsidian.module("src/session")
		eq(s.encounter_radius(40), s.ENCOUNTER_RANGE, "the game's 40 m")
		eq(s.encounter_radius(500), 500, "a larger one stays")
		eq(s.encounter_radius(nil), nil)
	end },

	{ "patrol units with a target within the chase range are kept, others not", function()
		local s = obsidian.module("src/session")
		local pos = { a = { x = 150, y = 0, z = 0 }, b = { x = 150, y = 10, z = 0 }, c = { x = 400, y = 0, z = 0 } }
		local states = { a = { target_unit = "me" }, b = {}, c = { target_unit = "me" } }
		Unit = { alive = function() return true end, world_position = function(u) return pos[u] end }
		EntityAux = { state_master = function(u) return states[u] end }
		local manager = { patrols = { { units = { { unit = "a" }, { unit = "b" } } }, { units = { { unit = "c" } } } } }
		local list = s.chasing(manager, { { x = 0, y = 0 } })
		eq(#list, 1, "only the chasing unit in range")
		eq(s.one_of(list, { x = 150, y = 0, z = 0 }), true)
		eq(s.one_of(list, { x = 150, y = 10, z = 0 }), false)
		Unit, EntityAux = nil, nil
	end },
}
