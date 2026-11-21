-- The in-game settings page (src/config.lua ROWS) against obsidian.json: every option that applies at
-- once has a row, in the same order, of the same kind, range and choices.
local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

-- The options of obsidian.json, in order: { id, type, group, min, max, step, choices = { ids } }. Each
-- option starts a line with `{ "id":` inside the options block (the file's own layout).
local function manifest_options()
	local s = read("obsidian.json")
	local block = s:match('"options": %[(.-)\n  %],')
	assert(block, "options block")
	local out = {}
	local starts = {}
	local at = 1
	while true do
		local i = block:find('\n    { "id": ', at, true)
		if not i then break end
		starts[#starts + 1] = i
		at = i + 1
	end
	for k, i in ipairs(starts) do
		local chunk = block:sub(i + #'\n    { "id": ', (starts[k + 1] or #block + 1) - 1)
		local o = { id = chunk:match('^"([%w_]+)"') }
		o.type = chunk:match('"type": "(%a+)"')
		o.group = chunk:match('"group": "([%w_]+)"')
		o.min = tonumber(chunk:match('"min": ([-%d.]+)'))
		o.max = tonumber(chunk:match('"max": ([-%d.]+)'))
		o.step = tonumber(chunk:match('"step": ([-%d.]+)'))
		local choices = chunk:match('"choices": %[(.-)%],')
		if choices then
			o.choices = {}
			for id in choices:gmatch('{ "id": "([%w_]+)"') do o.choices[#o.choices + 1] = id end
		end
		out[#out + 1] = o
	end
	return out
end

-- What the page leaves to Obsidian: options that need a deploy.
local DEPLOY = { fix_sky = true }

return {
	{ "every option that applies at once has a row, in the order of obsidian.json", function()
		local rows = obsidian.module("src/config").ROWS
		local want = {}
		for _, o in ipairs(manifest_options()) do
			if o.group ~= "lobby" and not DEPLOY[o.id] then want[#want + 1] = o end
		end
		eq(#want > 30, true, "options read")
		eq(#rows, #want, "rows")
		for i, o in ipairs(want) do
			local r = rows[i]
			eq(r.id, o.id, "row " .. i)
			eq(r.kind, o.type, o.id .. " kind")
			eq(r.group, o.group, o.id .. " group")
			eq(r.min, o.min, o.id .. " min") eq(r.max, o.max, o.id .. " max") eq(r.step, o.step, o.id .. " step")
			if o.choices then
				eq(#r.choices, #o.choices, o.id .. " choices")
				for k, id in ipairs(o.choices) do eq(r.choices[k].id, id, o.id .. " choice " .. k) end
			end
			assert(r.label and r.label.en and r.info and r.info.en, o.id .. " words")
			if o.type == "number" then
				local steps = (o.max - o.min) / o.step
				eq(steps <= 100, true, o.id .. ": at most 100 steps")
			end
		end
	end },

	{ "every group of a row is one of the groups of the page", function()
		local c = obsidian.module("src/config")
		local known = {}
		for _, g in ipairs(c.GROUPS) do known[g.id] = true end
		for _, r in ipairs(c.ROWS) do eq(known[r.group], true, r.id .. " group") end
	end },

	{ "numbers read plainly", function()
		local c = obsidian.module("src/config")
		eq(c.number_text(0.30000000000000004), "0.3")
		eq(c.number_text(15), "15")
	end },
}
