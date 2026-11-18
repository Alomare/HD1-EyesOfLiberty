-- Hurt feedback: when the Helldiver loses health, the edges of the screen flash red ("eol_hurt" of the
-- mod's art, src/art.lua) and, in third person, the camera shakes briefly (src/shake.lua, so the
-- Camera shake option sizes it). A bigger share of health lost makes both stronger.
--
-- The loss is seen as src/hits.lua sees it: HealthComponent.command_master runs every damage command
-- ("do_damage", "request_do_damage", "set_hitpoints") on the machine that runs the unit, and the hit
-- counts when hitpoints_real drops. A personal shield that takes the hit leaves health as it was.
local scoped = obsidian.module("src/scoped")
local shake = obsidian.module("src/shake")
local art = obsidian.module("src/art")

local M = {}

M.RISE = 0.04         -- seconds to full strength
M.FADE = 0.7          -- seconds from full strength to nothing
M.LEAST = 0.3         -- strength of the smallest hit
M.PER_SHARE = 3       -- strength for each share of the health bar lost (a third of it is full)
M.COLOR = { 205, 22, 16 }
M.ALPHA = 235         -- at full strength, out of 255
M.LAYER = 60
M.SHAKE = { amp = 0.06, most = 0.16, freq = 17, time = 0.28 }
M.SHAKE_GAP = 0.12    -- seconds between two shakes: fire and acid hurt many times a second
M.DAMAGE = { do_damage = true, request_do_damage = true, set_hitpoints = true }

M.flash = { level = 0, age = math.huge }
M.since_shake = math.huge

-- The strength of a hit that took `lost` of `most` hitpoints, from LEAST to 1.
function M.strength(lost, most)
	if type(lost) ~= "number" or lost <= 0 then return 0 end
	local share = (type(most) == "number" and most > 0) and lost / most or 0
	return math.max(M.LEAST, math.min(1, share * M.PER_SHARE))
end

-- How strong the flash shows `age` seconds after a hit of strength `level`.
function M.shown(level, age)
	if age < 0 or age >= M.RISE + M.FADE then return 0 end
	if age < M.RISE then return level * age / M.RISE end
	local t = (age - M.RISE) / M.FADE
	return level * (1 - t) * (1 - t)
end

-- A hit of strength s: the flash renews (never weaker than what still shows), and a shake starts in
-- third person unless one just did.
function M.hurt(s, third_person)
	if s <= 0 then return end
	local now = M.shown(M.flash.level, M.flash.age)
	M.flash.level = math.max(s, now)
	M.flash.age = M.RISE * (now / M.flash.level)
	if third_person and M.since_shake >= M.SHAKE_GAP then
		M.since_shake = 0
		local amp = M.SHAKE.amp + (M.SHAKE.most - M.SHAKE.amp) * (s - M.LEAST) / (1 - M.LEAST)
		shake.add(amp, M.SHAKE.freq, M.SHAKE.time)
	end
end

function M.step(dt)
	M.flash.age = M.flash.age + dt
	M.since_shake = M.since_shake + dt
end

function M.clear()
	M.flash.level, M.flash.age = 0, math.huge
end

local function g(name) return rawget(_G, name) end

function M.start(env)
	local config = env.config
	local on = config.get("hurt_feedback") ~= false
	if config.on_change then config.on_change("hurt_feedback", function(v) on = v ~= false end) end
	local me = nil

	obsidian.hook("HealthComponent", "command_master", function(original, self, unit, ctx, command, data, ...)
		if not (on and me ~= nil and unit == me and M.DAMAGE[command]) then return original(self, unit, ctx, command, data, ...) end
		local st = type(ctx) == "table" and ctx.state
		local before = type(st) == "table" and st.hitpoints_real or nil
		local r = scoped.pack(original(self, unit, ctx, command, data, ...))
		if type(before) == "number" then
			local after = st.hitpoints_real
			if type(after) == "number" and after < before then
				pcall(M.hurt, M.strength(before - after, st.max_hitpoints), env.state.active and not env.state.watching)
			end
		end
		return unpack(r, 1, r.n)
	end, env.VIEW)

	local function hidden(api)
		local ui = obsidian.ui
		if type(ui) == "table" and ui.current then
			local ok, cur = pcall(ui.current)
			if ok and type(cur) == "table" and cur.screen ~= "hud" then return true end
		end
		if api.map and api.map.is_open then
			local ok, open = pcall(api.map.is_open)
			if ok and open then return true end
		end
		if api.capture and api.capture.busy then
			local ok, busy = pcall(api.capture.busy)
			if ok and busy then return true end
		end
		return false
	end

	local function frame()
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then
			me = nil
			return M.clear()
		end
		me = api.game.my_unit()
		local dt = g("ENGINE_DT")
		dt = type(dt) == "number" and dt > 0 and math.min(dt, 0.1) or 1 / 60
		M.step(dt)
		local s = M.shown(M.flash.level, M.flash.age)
		if s <= 0.004 or hidden(api) then return end
		local cm = g("CameraManager")
		if not (cm and cm.viewport) then return end
		local gui = art.gui()
		if not gui then return end
		local w, h, x0, y0 = cm.viewport:window()
		local c = M.COLOR
		art.draw(gui, "eol_hurt", x0 or 0, y0 or 0, w, h, M.LAYER, math.floor(M.ALPHA * s + 0.5), c[1], c[2], c[3])
	end

	local warned = false
	obsidian.on_frame(function()
		if not on then return M.clear() end
		local ok, err = pcall(frame)
		if not ok then
			M.clear()
			if not warned then
				warned = true
				env.log("Eyes of Liberty: hurt feedback: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
