-- The death cam: what the camera watches once this player's Helldiver dies.
--
-- The game (StateGame, state_game.lua) handles a death three ways, and the camera follows each:
--   - alone with lives left, the Helldiver drops in again after a few seconds (on_player_death sends
--     rpc_on_respawn, which sets spawn_timer): a new living unit ends the watch
--   - with allies, one of them has to call Reinforce; until then the camera watches them
--   - with nobody left alive, game_over_timer runs out and the mission ends; the watch lasts until the
--     game's camera state changes
-- The watch starts only for a death seen while the camera ran in the same world, so a new mission or
-- the ship never starts on a stale body. A player who extracted isn't dead: the camera rides the
-- shuttle out instead (the extraction ride), until the mission ends.
--
-- Boarding: ObjectiveExtractLZComponent.overlap_callback_extract_players raises "on_avatar_extract"
-- (avatar, shuttle) on the machine that owns the avatar, and StateGame.on_avatar_extract clears the
-- player's avatar_unit and sets has_extracted (state_game.lua). src/camera.lua hands the shuttle over
-- through M.board.
local M = {}

local function g(name) return rawget(_G, name) end

M.ALLY_DELAY = 4      -- seconds on the body before the camera moves to a living ally
M.BODY_LIFT = 0.6     -- metres above the hips that the camera turns about
M.BACK = 1.5          -- metres farther back than the on-foot distance, so the body shows whole
M.RIDE_LIFT = 3       -- metres above the shuttle's root that the ride camera turns about
M.RIDE_DISTANCE = 16  -- metres between the ride camera and the shuttle

-- The shuttle this player's Helldiver boarded: { unit, world }, until the next living Helldiver.
M.shuttle = nil
-- Whether the extraction ride runs (the Extraction camera option).
M.ride_on = true

-- The living Helldiver last seen: { unit, world, at }.
M.mine = nil
-- The watch under way: { body, at, t, ally }. body is this player's dead unit, at the point the camera
-- turns about when no unit is left to follow, t the seconds since the death, ally the unit watched.
M.watch = nil

-- Whether a unit is a living Helldiver: still in the world, and not dead. Downed counts as living.
function M.living(unit)
	if unit == nil then return false end
	local U, EA = g("Unit"), g("EntityAux")
	local ok, alive = pcall(U.alive, unit)
	if not (ok and alive) then return false end
	local got, hs = pcall(EA.state, unit, "health")
	return not (got and type(hs) == "table" and hs.is_dead == true)
end

-- The point of a unit the camera turns about: the hips of a body (the root of a ragdoll can stay
-- where the Helldiver fell), else the root. nil when the unit is gone.
function M.point(unit, lift)
	local U = g("Unit")
	local ok, p = pcall(function()
		if not U.alive(unit) then return nil end
		local node = 0
		if U.has_node and U.has_node(unit, "hips") then node = U.node(unit, "hips") end
		local v = U.world_position(unit, node)
		return { x = v.x, y = v.y, z = v.z + (lift or 0) }
	end)
	return ok and p or nil
end

-- This player's Helldiver boarded the shuttle `shuttle` in `world`.
function M.board(avatar, shuttle, world)
	local mine = M.mine
	if mine and avatar ~= nil and avatar == mine.unit and shuttle ~= nil then
		M.shuttle = { unit = shuttle, world = world }
	end
end

-- Whether this player has left the mission by extraction.
function M.extracted(api)
	local game = api and api.game
	if not (game and game.me) then return false end
	local ok, gone = pcall(function()
		local me = game.me()
		local go = me and me.player_go
		return go and go:has("has_extracted") and go:get("has_extracted") and true or false
	end)
	return ok and gone or false
end

-- The other living Helldivers, in the order of the game's player list.
function M.allies(api, except)
	local out = {}
	local game = api and api.game
	if not (game and game.all_avatars) then return out end
	local ok, list = pcall(game.all_avatars)
	for _, a in ipairs(ok and type(list) == "table" and list or {}) do
		if a.unit ~= except and M.living(a.unit) then out[#out + 1] = a.unit end
	end
	return out
end

-- The ally `step` places from `current` in `list` (1 next, -1 previous, 0 the same), wrapping round.
-- A current ally no longer in the list gives the first one, or the last stepping back.
function M.pick(list, current, step)
	local n = #list
	if n == 0 then return nil end
	local at = nil
	for i, u in ipairs(list) do if u == current then at = i end end
	if not at then return step < 0 and list[n] or list[1] end
	return list[(at - 1 + step) % n + 1]
end

-- One frame. world: the world the camera draws, step: the ally clicks this frame (1 right, -1 left).
-- Answers the watch while there is one, nil while this player's Helldiver lives or has none to watch.
function M.update(api, world, dt, step)
	step = step or 0
	local game = api and api.game
	local unit = game and game.my_unit and game.my_unit() or nil
	if M.living(unit) then
		local mine = M.mine
		if not mine or mine.unit ~= unit or mine.world ~= world then
			mine = { unit = unit, world = world }
			M.mine = mine
		end
		mine.at = M.point(unit, M.BODY_LIFT) or mine.at
		M.watch, M.shuttle = nil, nil
		return nil
	end
	local w = M.watch
	if not w then
		local mine = M.mine
		if not (mine and mine.world == world) then
			M.mine = nil
			return nil
		end
		if M.extracted(api) then
			local ride = M.shuttle
			if not (M.ride_on and ride and ride.world == world and M.point(ride.unit)) then
				M.mine = nil
				return nil
			end
			w = { body = ride.unit, at = M.point(ride.unit, M.RIDE_LIFT), t = 0, ally = nil, world = world, ride = true }
			M.watch = w
		elseif not M.dead_on then
			return nil
		else
			w = { body = mine.unit, at = mine.at, t = 0, ally = nil, world = world }
			M.watch = w
		end
	end
	w.t = w.t + math.max(0, dt or 0)
	-- The ride follows the shuttle up and away; allies left behind don't take the camera.
	if w.ride then
		w.at = M.point(w.body, M.RIDE_LIFT) or w.at
		return w
	end
	-- The body, while the game keeps it; its last point after.
	if w.ally == nil then w.at = M.point(w.body, M.BODY_LIFT) or w.at end
	local list = M.allies(api, w.body)
	if #list > 0 and (w.ally ~= nil or step ~= 0 or w.t >= M.ALLY_DELAY) then
		local was = w.ally
		w.ally = M.pick(list, was, was and step or 0)
		if was == nil and step < 0 then w.ally = list[#list] end
	elseif w.ally ~= nil and not M.living(w.ally) then
		-- The last ally fell too: the camera stays on that body, then where it was.
		w.at = M.point(w.ally, M.BODY_LIFT) or w.at
		w.last_ally, w.ally = w.ally, nil
	end
	if w.ally == nil and w.last_ally then w.at = M.point(w.last_ally, M.BODY_LIFT) or w.at end
	return w
end

-- Forgets the watch and the Helldiver behind it (leaving the mission, tests).
function M.reset()
	M.mine, M.watch, M.shuttle = nil, nil, nil
end

-- Whether the death cam runs (the Death cam option); the ride follows M.ride_on.
M.dead_on = true

return M
