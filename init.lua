
--[[

	Copyright 2017-8 Auke Kok <sofar@foo-projects.org>
	Copyright 2018 rubenwardy <rw@rubenwardy.com>

	Permission is hereby granted, free of charge, to any person obtaining
	a copy of this software and associated documentation files (the
	"Software"), to deal in the Software without restriction, including
	without limitation the rights to use, copy, modify, merge, publish,
	distribute, sublicense, and/or sell copies of the Software, and to
	permit persons to whom the Software is furnished to do so, subject
	to the following conditions:

	The above copyright notice and this permission notice shall be included
	in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
	KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
	WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
	LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
	OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
	WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

]]--


filter = {registered_on_violations = {}}

-- local configuration
local words = {}
local muted = {}
local violations = {}
local s = minetest.get_mod_storage()

-- web configuration
local filter_config = nil
local filter_url = minetest.settings:get("filter_url") or "https://pastebin.com/raw/p5xkF0RW" -- "http://minetest.io/reputation/chat_filter.json"
-- filter_url = "https://minetest.io/reputation/chat_filter.json"
-- or "https://pastebin.com/raw/p5xkF0RW" but that may not work due to user agent allow list or other measures
local filter_fuzzy = minetest.settings:get_bool("filter_fuzzy")
if filter_fuzzy == nil then
	filter_fuzzy = true
end
local filter_deep = minetest.settings:get_bool("filter_deep")
if filter_deep == nil then
	filter_deep = true
end

local http_api = minetest.request_http_api and minetest.request_http_api()  -- must occur in outer scope; requires trusted environment

local function filter_import_file(filepath)
	local file = io.open(filepath, "r")
	if file then
		for line in file:lines() do
			line = line:trim()
			if line ~= "" then
				words[#words + 1] = line:trim()
			end
		end
		return true
	else
		return false
	end
end

local function filter_download(delay, player_name)
	if http_api then
		local function p_set_config(config)
			if config.words and config.word_partials and config.deep_partials then
				filter_config = config
				local word_count = filter_config and filter_config.words and #filter_config.words
				local deep_partials_count = filter_config and filter_config.deep_partials and #filter_config.deep_partials
				local word_partials_count = filter_config and filter_config.word_partials and #filter_config.word_partials
				local msg = "Processing downloaded filter completed. The current list has " .. word_count .. " word(s) and " .. deep_partials_count .. " deep partials and "..word_partials_count.." partial word(s)."
				minetest.log("action", "[filter] " .. msg)
				if player_name then
					minetest.chat_send_player(player_name, msg)
				end
			else
				local msg = " web config is incomplete and will not be used. It must contain words, word_partials, and deep_partials (empty lists are allowed)."
				minetest.log("error", "[filter]" .. msg)
				if player_name then
					minetest.chat_send_player(player_name, msg)
				end
			end
		end
		local function p_set_config_json(config_json)
			local config = minetest.parse_json(config_json)
			p_set_config(config)
		end
		local req_handle = nil
		-- local function read_handle()
		-- 	if req_handle then
		-- 		minetest.log("info", "[filter] reading request handle for " .. filter_url .. "...")
		-- 		local result = http_api.fetch_async_get(req_handle)
		-- 		minetest.log("info", "[filter] reading request handle for " .. filter_url .. "...checking result...")
		-- 		fetch_callback(result)
		-- 	else
		-- 		minetest.log("error", "[filter] logic error " .. filter_url .. " not ready")
		-- 	end
		-- end
		local function fetch_callback(result)
			if not result then
				minetest.log("info", "[filter] loading " .. filter_url .. "...NO RESULT")
				return
			else
				if not result.completed then
					minetest.log("info", "[filter] loading " .. filter_url .. "...")
					return
				end
			end
			if result.succeeded then
				minetest.log("info", "[filter] loading " .. filter_url .. "...OK. Parsing...")
				-- protected call (https://www.lua.org/pil/8.4.html):
				if pcall(p_set_config, minetest.parse_json(result.data)) then
					minetest.log("info", "[filter] Processing downloaded filter completed.")
				else
					local word_count = filter_config and filter_config.words and #filter_config.words
					local deep_partials_count = filter_config and filter_config.deep_partials and #filter_config.deep_partials
					local word_partials_count = filter_config and filter_config.word_partials and #filter_config.word_partials
					local msg = "Processing downloaded filter failed. The current list has " .. word_count .. " word(s) and " .. deep_partials_count .. " deep partials and " .. word_partials_count .. " partial words."
					if player_name then
						minetest.chat_send_player(player_name, msg)
					end
					minetest.log("warning", "[filter] " .. msg)
				end
			else
				if result.timeout then
					minetest.log("info", "[filter] loading " .. filter_url .. "...TIMED OUT")
				else
					minetest.log("info", "[filter] loading " .. filter_url .. "...FAILED")
				end
			end
		end
		local function download_filter()
			minetest.log("info", "[filter] fetching " .. filter_url .. "...")
			http_api.fetch({url=filter_url, timeout=15}, fetch_callback)
		end
		-- local function download_filter_async()
		-- 	req_handle = http_api.fetch_async({url=filter_url, timeout=15}, fetch_callback)
		-- 	minetest.log("info", "[filter] reading" .. filter_url .. " after 10 seconds...")
		-- 	minetest.after(10, read_handle)
		-- end
		-- if http_api.fetch_async_get then
		-- 	minetest.log("info", "[filter] loading async " .. filter_url .. " after "..delay.." seconds...")
		-- 	minetest.after(delay, download_filter_async)
		-- else
		minetest.log("info", "[filter] loading" .. filter_url .. " after "..delay.." seconds...")
		minetest.after(delay, download_filter)
		-- end
	else
		local msg = "http_api is not available (you must add filter to secure.trusted_mods to use this feature of filter)"
		if player_name then
			minetest.chat_send_player(player_name, msg)
		end
		minetest.log("warning", "[filter] " .. msg)
	end
end

local function filter_init()
	local sw = s:get_string("words")
	if sw and sw ~= "" then
		words = minetest.parse_json(sw)
	end

	if #words == 0 then
		filter_import_file(minetest.get_modpath("filter") .. "/words.txt")
	end
	filter_download(10, nil)
end

local function filter_register_on_violation(func)
	table.insert(filter.registered_on_violations, func)
end

local function filter_speakable(raw_message)
	local sanitized = raw_message
	-- local not_language = "\t\n\r"
	-- for c in string.gmatch(not_language, ".") do
	--	sanitized = sanitized:gsub(c, "")
	-- end
	-- NOTE: sanitized:gsub("[%c%p%s]", "") removes all special & space
	-- %c is control characters (includes newlines, tab, etc.)
	-- %p is punctuation [prevent rule evasion with dots/hyphens/etc]
	-- %s is all whitespace
	-- str:gsub( "%W", "" ) removes all non-word characters
	return sanitized:gsub("[%c%p]", "")
end

local filter_debug_next = true

local function filter_check_message(name, message)
	local message_lower = message:lower()
	for _, needle in ipairs(words) do
		if string.find(message_lower, "%f[%a]" .. needle .. "%f[%A]") then
			return false
		end
	end
	local more = filter_config and filter_config.words
	local sanitized = filter_speakable(message_lower)
	if more then
		for _, needle in ipairs(more) do
			if string.find(sanitized, "%f[%a]" .. needle .. "%f[%A]") then
				return false
			end
			if filter_debug_next then
				minetest.log("verbose", "[filter] " .. needle .. " is not a WORD in '" .. sanitized .. "'")
				-- is_debug_warning_shown = true
			end
		end
	else
		if filter_debug_next then
			minetest.log("warning", "[filter] has no filter_config.words")
			is_debug_warning_shown = true
		end
	end
	local word_partials = filter_config and filter_config.word_partials
	if word_partials then
		for _, needle in ipairs(word_partials) do
			for match in string.gmatch(sanitized, "[^%s]+") do
				for partial_match in string.gmatch(match, needle) do
					return false
				end
			end
			if filter_debug_next then
				minetest.log("verbose", "[filter] " .. needle .. " is not a WORD in '" .. sanitized .. "'")
				-- is_debug_warning_shown = true
			end
		end
	else
		if filter_debug_next then
			minetest.log("warning", "[filter] has no filter_config.words")
			is_debug_warning_shown = true
		end
	end
	local deep_partials = filter_config and filter_config.deep_partials
	local is_debug_warning_shown = false
	if filter_deep then
		if deep_partials then
			-- local no_spaces = sanitized:gsub("[%c%p%s]", "")
			local no_spaces = sanitized:gsub("[%W]", "")
			for _, needle in ipairs(deep_partials) do
				for match in string.gmatch(no_spaces, needle) do
					return false
				end
				if filter_debug_next then
					minetest.log("verbose", "[filter] " .. needle .. " is not in '" .. no_spaces .. "'")
					-- is_debug_warning_shown = true
				end
			end
		else
			if filter_debug_next then
				minetest.log("warning", "[filter] has no filter_config.deep_partials")
				is_debug_warning_shown = true
			end
		end
	else
		if filter_debug_next then
			minetest.log("warning", "[filter] filter_deep is off")
			is_debug_warning_shown = true
		end
	end
	if filter_fuzzy then
		-- TODO: not yet implemented
	end
	if is_debug_warning_shown then
		filter_debug_next = false
	end
	return true
end

local function filter_mute(name, duration)
	do
		local privs = minetest.get_player_privs(name)
		privs.shout = nil
		minetest.set_player_privs(name, privs)
	end

	minetest.chat_send_player(name, "You have been temporarily muted for abusing the chat.")

	muted[name] = true

	minetest.after(duration * 60, function()
		privs = minetest.get_player_privs(name)
		if privs.shout == true then
			return
		end

		muted[name] = nil
		minetest.chat_send_player(name, "Chat privilege reinstated. Please do not abuse chat.")

		privs.shout = true
		minetest.set_player_privs(name, privs)
	end)
end

local function filter_show_warning_formspec(name)
	local formspec = "size[7,3]bgcolor[#080808BB;true]" .. default.gui_bg .. default.gui_bg_img .. [[
		image[0,0;2,2;filter_warning.png]
		label[2.3,0.5;Please watch your language!]
	]]

	if minetest.global_exists("rules") and rules.show then
		formspec = formspec .. [[
				button[0.5,2.1;3,1;rules;Show Rules]
				button_exit[3.5,2.1;3,1;close;Okay]
			]]
	else
		formspec = formspec .. [[
				button_exit[2,2.1;3,1;close;Okay]
			]]
	end
	minetest.show_formspec(name, "filter:warning", formspec)
end

local function filter_on_violation(name, message)
	violations[name] = (violations[name] or 0) + 1

	local resolution

	for _, cb in pairs(filter.registered_on_violations) do
		if cb(name, message, violations) then
			resolution = "custom"
		end
	end

	if not resolution then
		if violations[name] == 1 and minetest.get_player_by_name(name) then
			resolution = "warned"
			filter_show_warning_formspec(name)
		elseif violations[name] <= 3 then
			resolution = "muted"
			filter_mute(name, 1)
		else
			resolution = "kicked"
			minetest.kick_player(name, "You have been kicked for abusing the chat.")
		end
	end

	local logmsg = "VIOLATION (" .. resolution .. "): <" .. name .. "> "..  message
	minetest.log("action", "[filter] " .. logmsg)

	local email_to = minetest.settings:get("filter.email_to")
	if email_to and minetest.global_exists("email") then
		email.send_mail(name, email_to, logmsg)
	end
end

table.insert(minetest.registered_on_chat_messages, 1, function(name, message)
	if message:sub(1, 1) == "/" then
		return
	end

	local privs = minetest.get_player_privs(name)
	if not privs.shout and muted[name] then
		minetest.chat_send_player(name, "You are temporarily muted.")
		return true
	end

	if not filter_check_message(name, message) then
		filter_on_violation(name, message)
		return true
	end
end)


local function make_checker(old_func)
	return function(name, param)
		if not filter_check_message(name, param) then
			filter_on_violation(name, param)
			return false
		end

		return old_func(name, param)
	end
end

for name, def in pairs(minetest.registered_chatcommands) do
	if def.privs and def.privs.shout then
		def.func = make_checker(def.func)
	end
end

local old_register_chatcommand = minetest.register_chatcommand
function minetest.register_chatcommand(name, def)
	if def.privs and def.privs.shout then
		def.func = make_checker(def.func)
	end
	return old_register_chatcommand(name, def)
end


local function step()
	for name, v in pairs(violations) do
		violations[name] = math.floor(v * 0.5)
		if violations[name] < 1 then
			violations[name] = nil
		end
	end
	minetest.after(10*60, step)
end
minetest.after(10*60, step)

minetest.register_chatcommand("filter", {
	params = "filter server",
	description = "manage swear word filter",
	privs = {server = true},
	func = function(name, param)
		local cmd, val = param:match("(%w+) (.+)")
		if param == "list" then
			return true, #words .. " words: " .. table.concat(words, ", ")
		elseif param == "download" then
			filter_download(0, name)
			return true, "Checking " .. filter_url .. "."
		elseif cmd == "add" then
			table.insert(words, val)
			s:set_string("words", minetest.write_json(words))
			return true, "Added \"" .. val .. "\"."
		elseif cmd == "remove" then
			for i, needle in ipairs(words) do
				if needle == val then
					table.remove(words, i)
					s:set_string("words", minetest.write_json(words))
					return true, "Removed \"" .. val .. "\"."
				end
			end
			return true, "\"" .. val .. "\" not found in list."
		else
			return true, "I know " .. #words .. " words.\nUsage: /filter <add|remove|list> [<word>]"
		end
	end,
})

if minetest.global_exists("rules") and rules.show then
	minetest.register_on_player_receive_fields(function(player, formname, fields)
		if formname == "filter:warning" and fields.rules then
			rules.show(player)
		end
	end)
end

minetest.register_on_shutdown(function()
	for name, _ in pairs(muted) do
		local privs = minetest.get_player_privs(name)
		privs.shout = true
		minetest.set_player_privs(name, privs)
	end
end)

filter_init()
