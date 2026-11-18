-- Camera shake for the shoulder view. The game shakes only its top-down camera (CameraManager.update
-- adds CameraShaker:update's offset to the top-down pose, camera_manager.lua:476-479), and that pose
-- never reaches the screen under the shoulder view. The offset the game works out each frame is kept
-- (game) and added to the shoulder pose, scaled by the Camera shake option, with shakes of this mod's
-- own on top (the Hellpod landing, a weapon firing, the sway of a sprint). Plain numbers only, so tests can run it.
local M = {}

-- The option's levels, as a factor on every shake.
M.LEVEL = { off = 0, weak = 0.5, medium = 1, strong = 1.8 }

M.list = {}               -- own shakes: { amp, freq, left, total }
-- A soft rumble while this player's weapon fires (src/aim.lua sees it): metres, a second, and the
-- seconds it takes to die out after the last shot. A vehicle's guns rumble more.
M.FIRE = { amp = 0.02, vehicle_amp = 0.045, freq = 16, fade = 0.15 }
M.fire = { level = 0, phase = 0, vehicle = false }
-- The most the game's own shake moves the shoulder view in a frame, in metres: a run of explosions
-- (a mod with blasts on every kill) shook it all the time.
M.GAME_MOST = 0.12
M.game = { x = 0, y = 0 } -- the game's offset this frame, in metres right and up of the view
-- A slow, uneven sway while sprinting: metres and swings a second at full sprint speed. level (0 to
-- 1) is set each frame by src/camera.lua, eased in and out, and pace by how fast the Helldiver moves
-- over the ground against a full sprint (water and slowing hits make a sprint slower): both how far
-- and how fast it swings follow the pace, the speed of the swings no lower than PACE_MIN of theirs.
M.SPRINT = { amp = 0.036, freq = 1.4 }
M.SPRINT_SPEED = 7     -- m/s, move_speed_sprint_max of the Helldiver (characters/helldiver_private_01)
M.PACE_MIN = 0.35
M.PACE_MAX = 1.3
M.sprint = { level = 0, phase = 0, pace = 1 }

-- The pace for a speed over the ground in m/s.
function M.pace_of(speed)
	if type(speed) ~= "number" or speed ~= speed then return 1 end
	return math.max(0, math.min(M.PACE_MAX, speed / M.SPRINT_SPEED))
end
-- While a flamethrower of this player fires (on foot, or the Lumberer's), every shake is cut to FLAME
-- of its strength: the game shakes the camera on each puff of flame. Seconds the cut holds after the
-- last frame of fire, and how fast it eases in and out.
M.FLAME = 0.2
M.FLAME_HOLD = 0.2
M.FLAME_RATE = 12
M.flame = { left = 0, mix = 0 }

-- A flamethrower of this player fires this frame.
function M.flamed()
	M.flame.left = M.FLAME_HOLD
end

function M.factor(level)
	return M.LEVEL[level] or M.LEVEL.medium
end

-- A shake of amp metres at freq a second for dur seconds, dying out.
function M.add(amp, freq, dur)
	M.list[#M.list + 1] = { amp = amp, freq = freq, left = dur, total = dur, phase = 0 }
end

-- A weapon of this player fired this frame. vehicle: a vehicle's gun.
function M.fired(vehicle)
	M.fire.level = 1
	M.fire.vehicle = vehicle and true or false
end

local function clamp_length(x, y, most)
	local len = math.sqrt(x * x + y * y)
	if len <= most or len == 0 then return x, y end
	return x / len * most, y / len * most
end

-- The offset of this frame, metres right and up, and moves the own shakes on by dt.
function M.offset(dt, factor)
	local x, y = clamp_length(M.game.x or 0, M.game.y or 0, M.GAME_MOST)
	local f = M.fire
	if f.level > 0 then
		f.phase = f.phase + dt
		local a = (f.vehicle and M.FIRE.vehicle_amp or M.FIRE.amp) * f.level
		local w = f.phase * M.FIRE.freq * 2 * math.pi
		x = x + a * math.sin(w * 1.7)
		y = y + a * math.cos(w)
		f.level = math.max(0, f.level - dt / M.FIRE.fade)
	end
	local sp = M.sprint
	if sp.level > 0 then
		local pace = sp.pace or 1
		sp.phase = sp.phase + dt * math.max(M.PACE_MIN, pace)
		local w = sp.phase * M.SPRINT.freq * 2 * math.pi
		local a = M.SPRINT.amp * sp.level * pace
		-- Two swings that never line up, so the sway doesn't read as a loop.
		x = x + a * (0.7 * math.sin(w) + 0.3 * math.sin(w * 2.37 + 1.1))
		y = y + a * (0.6 * math.sin(w * 2 + 0.4) + 0.4 * math.sin(w * 3.13))
	else
		sp.phase = 0
	end
	for i = #M.list, 1, -1 do
		local s = M.list[i]
		s.phase = s.phase + dt
		s.left = s.left - dt
		if s.left <= 0 then
			table.remove(M.list, i)
		else
			local fade = s.left / s.total
			local a = s.amp * fade * fade
			local w = s.phase * s.freq * 2 * math.pi
			x = x + a * math.sin(w * 1.3)
			y = y + a * math.cos(w)
		end
	end
	local fl = M.flame
	local want = fl.left > 0 and 1 or 0
	fl.left = math.max(0, fl.left - dt)
	fl.mix = fl.mix + (want - fl.mix) * (1 - math.exp(-M.FLAME_RATE * dt))
	local cut = 1 - (1 - M.FLAME) * fl.mix
	return x * factor * cut, y * factor * cut
end

function M.clear()
	M.list = {}
	M.fire.level, M.fire.phase = 0, 0
	M.game.x, M.game.y = 0, 0
	M.sprint.level, M.sprint.phase, M.sprint.pace = 0, 0, 1
	M.flame.left, M.flame.mix = 0, 0
end

return M
