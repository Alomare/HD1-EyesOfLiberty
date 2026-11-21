-- The game's own crosshair in third person: the game's aiming cursor is a Windows cursor
-- (CursorManager: Window.set_cursor with hud/cursors/game, game_inactive and the five
-- game_transition_0N steps between them, 35 ms each). Windows draws it where the mouse is, so it is
-- held at the middle of the game's window with ClipCursor, a 2 x 2 pixel box, through LuaJIT's FFI.
-- The camera turns from the mouse's own movement (the "mouse" axis), which a held cursor still gives
-- (probe 2026-11-20: 400 counts right and 200 left gave 200 and a 24 degree turn while held).
--
-- Windows lets go of a clip when another window comes in front, so the box is set again every frame
-- it is wanted, and let go of (ClipCursor(NULL)) the frame it isn't.
local M = {}

local api = nil       -- false when FFI or user32 can't be had
local held = false

local function load()
	if api ~= nil then return api end
	api = false
	pcall(function()
		local ok, ffi = pcall(require, "ffi")
		if not (ok and type(ffi) == "table") then
			local loaded = package and package.loaded
			ffi = type(loaded) == "table" and loaded.ffi or nil
		end
		if type(ffi) ~= "table" or ffi.os ~= "Windows" then return end
		pcall(ffi.cdef, [[
			typedef struct { long left, top, right, bottom; } EOL_RECT;
			typedef struct { long x, y; } EOL_POINT;
			int ClipCursor(const EOL_RECT *r);
			int GetClientRect(void *w, EOL_RECT *r);
			int ClientToScreen(void *w, EOL_POINT *p);
			void *GetForegroundWindow(void);
		]])
		local user32 = ffi.load("user32")
		api = { ffi = ffi, user32 = user32, rect = ffi.new("EOL_RECT"), box = ffi.new("EOL_RECT"), point = ffi.new("EOL_POINT") }
	end)
	return api
end

-- Whether the cursor can be held on this system.
function M.available()
	return load() and true or false
end

-- The box the cursor is held in: 2 x 2 pixels around the middle of a client area w x h whose top left
-- is at (x, y) on the screen, moved by (dx, dy) pixels (right and down), within the area.
function M.box(x, y, w, h, dx, dy)
	local cx = x + math.floor(w / 2 + math.max(-w / 2, math.min(w / 2 - 1, dx or 0)))
	local cy = y + math.floor(h / 2 + math.max(-h / 2, math.min(h / 2 - 1, dy or 0)))
	return cx - 1, cy - 1, cx + 1, cy + 1
end

-- Holds the cursor at the middle of the window in front (the game's: the caller checks the focus),
-- moved by (dx, dy) pixels right and down (where the weapon points, src/aim.lua), or lets it go.
-- Answers whether it is held.
function M.hold(on, dx, dy)
	local a = load()
	if not a then return false end
	if not on then
		if held then pcall(a.user32.ClipCursor, nil) end
		held = false
		return false
	end
	local ok = pcall(function()
		local w = a.user32.GetForegroundWindow()
		if w == nil then error("no window") end
		a.user32.GetClientRect(w, a.rect)
		a.point.x, a.point.y = 0, 0
		a.user32.ClientToScreen(w, a.point)
		local l, t, r, b = M.box(a.point.x, a.point.y, a.rect.right - a.rect.left, a.rect.bottom - a.rect.top, dx, dy)
		a.box.left, a.box.top, a.box.right, a.box.bottom = l, t, r, b
		a.user32.ClipCursor(a.box)
	end)
	held = ok
	return ok
end

function M.is_held() return held end

return M
