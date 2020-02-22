
--[[

	Copyright (c) 2014 (lua-bk-tree only) Robin Hübner <robinhubner@gmail.com>
	Copyright (c) 2017-8 Auke Kok <sofar@foo-projects.org>
	Copyright (c) 2018 rubenwardy <rw@rubenwardy.com>
	Copyright (c) 2020 Poikilos (Jake Gustafson)

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
local lowest_verbosity = "info"  -- changes if filter_verbose is True

-- fuzzy configuration
local modpath = minetest.get_modpath(minetest.get_current_modname())
local default_fuzzy_distance = 1  -- only used if fuzzy_distance; must match the default in settings

local function match_first_last(s1, s2)
	return (s1:sub(1, 1) == s2:sub(1, 1)) and (s1:sub(-1)==s2:sub(-1))
end

local function filter_fuzzy_distance(s1, s2) -- from lua-bk-tree (changed to use the minetest math library)
	if s1 == s2 then return 0 end
	if s1:len() == 0 then return s2:len() end
	if s2:len() == 0 then return s1:len() end
	if s1:len() < s2:len() then s1, s2 = s2, s1 end
	local t = {}
	for i=1, #s1+1 do
		t[i] = {i-1}
	end
	for i=1, #s2+1 do
		t[1][i] = i-1
	end
	local cost
	for i=2, #s1+1 do
		for j=2, #s2+1 do
			cost = (s1:sub(i-1,i-1) == s2:sub(j-1,j-1) and 0) or 1
			t[i][j] = math.min(
				t[i-1][j] + 1,
				t[i][j-1] + 1,
				t[i-1][j-1] + cost)
		end
	end
	return t[#s1+1][#s2+1]
end

-- web configuration
-- local default_filter_url = "http://minetest.io/reputation/chat_filter.json"
local default_filter_url = "https://pastebin.com/raw/p5xkF0RW"
local http_api = minetest.request_http_api and minetest.request_http_api()  -- must occur in outer scope; requires trusted environment
local filter_config = nil

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

local function filter_describe_web_lists()
	local word_count = filter_config and filter_config.words and #filter_config.words or 0
	local deep_partials_count = filter_config and filter_config.deep_partials and #filter_config.deep_partials or 0
	local word_partials_count = filter_config and filter_config.word_partials and #filter_config.word_partials or 0
	local fuzzy_deep_partials_count = filter_config and filter_config.fuzzy_deep_partials and #filter_config.fuzzy_deep_partials or 0
	local fuzzy_word_count = filter_config and filter_config.fuzzy_words and #filter_config.fuzzy_words or 0
	return "The current web-based filter has " .. word_count .. " word(s) (+" .. fuzzy_word_count .. " fuzzy) and " .. deep_partials_count .. " deep partial(s) (+"..fuzzy_deep_partials_count.." fuzzy) and "..word_partials_count.." partial word(s)."
end

local function filter_download(delay, player_name, this_filter_url)
	if http_api then
		local filter_url = this_filter_url or minetest.settings:get("filter.url") or default_filter_url
		local function p_set_config(config)
			if config.words and config.word_partials and config.deep_partials and config.fuzzy_deep_partials and config.fuzzy_words then
				filter_config = config
				local msg = "Processing downloaded filter completed. " .. filter_describe_web_lists()
				minetest.log("action", "[filter] " .. msg)
				if player_name then
					minetest.chat_send_player(player_name, msg)
				end
			else
				local msg = " web config is incomplete and will not be used. It must contain words, word_partials, deep_partials, fuzzy_deep_partials, fuzzy_words (empty lists are allowed)."
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
				if pcall(p_set_config, minetest.parse_json(result.data)) then
					minetest.log("info", "[filter] Processing downloaded filter completed.")
				else
					local msg = "Processing downloaded filter failed. " .. filter_describe_web_lists()
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
		minetest.log("info", "[filter] loading" .. filter_url .. " after "..delay.." seconds...")
		minetest.after(delay, download_filter)
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
	filter_download(3, nil)
end

local function filter_register_on_violation(func)
	table.insert(filter.registered_on_violations, func)
end

local function filter_speakable(raw_message)
	return raw_message:gsub("[%c%p]", "")
end

local filter_debug_next = true

local function filter_check_message(name, message)

	local filter_fuzzy = minetest.settings:get_bool("filter.fuzzy")
	if filter_fuzzy == nil then
		filter_fuzzy = true
	end
	local filter_deep = minetest.settings:get_bool("filter.deep")
	if filter_deep == nil then
		filter_deep = true
	end
	local filter_verbose = minetest.settings:get_bool("filter.verbose")
	if filter_verbose == nil then
		filter_verbose = true
	end
	if filter_verbose then
		lowest_verbosity = "action"
	else
		if lowest_verbosity ~= "verbose" then
			-- show next message if turned on recently
			filter_debug_next = true
		end
		lowest_verbosity = "verbose"
	end
	local max_fuzzy_distance = nil
	if filter_fuzzy then
		max_fuzzy_distance = minetest.settings:get("filter.fuzzy_distance")
		if max_fuzzy_distance == nil then
			max_fuzzy_distance = default_fuzzy_distance
		else
			max_fuzzy_distance = tonumber(max_fuzzy_distance)
		end
	end

	local message_lower = message:lower()
	for _, needle in ipairs(words) do
		if message_lower:find("%f[%a]" .. needle .. "%f[%A]") then
			return false
		end
	end
	local more = filter_config and filter_config.words
	local sanitized = filter_speakable(message_lower)

	if more then
		for _, needle in ipairs(more) do
			if sanitized:find("%f[%a]" .. needle .. "%f[%A]") then
				return false
			end
			if filter_debug_next and filter_verbose then
				minetest.log(lowest_verbosity, "[filter] \"" .. needle .. "\" is not a WORD in \"" .. sanitized .. "\"")
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
			for msg_word in sanitized:gmatch("[^%s]+") do
				for partial_match in msg_word:gmatch(needle) do
					return false
				end
			end
			if filter_debug_next and filter_verbose then
				minetest.log(lowest_verbosity, "[filter] \"" .. needle .. "\" is not a WORD in \"" .. sanitized .. "\"")
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
	local no_spaces = nil
	if filter_deep then
		no_spaces = sanitized:gsub("[%W]", "")
	end
	if filter_deep then
		if deep_partials then
			for _, needle in ipairs(deep_partials) do
				for match in no_spaces:gmatch(needle) do
					return false
				end
				if filter_debug_next and filter_verbose then
					minetest.log(lowest_verbosity, "[filter] \"" .. needle .. "\" is not in \"" .. no_spaces .. "\"")
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
	local fuzzy_deep_partials = filter_config and filter_config.deep_partials
	if filter_fuzzy and filter_deep and fuzzy_deep_partials then
		for i=1,#no_spaces do
			for _, needle in ipairs(fuzzy_deep_partials) do
				local msg_chunk = no_spaces:sub(i, i + #needle - 1)
				local fuzz = filter_fuzzy_distance(msg_chunk, needle)
				if filter_debug_next and filter_verbose then
					minetest.log(lowest_verbosity, "[filter] The fuzzy distance between \"" .. msg_chunk .. "\" and criteria \"" .. needle .. "\" is " .. fuzz .. ".")
					local tmp = " do not"
					if match_first_last(msg_chunk, needle) then
						tmp = ""
					end
					minetest.log(lowest_verbosity, "[filter] The first and last letters"..tmp.." match")
					is_debug_warning_shown = true
				end
				if (fuzz <= max_fuzzy_distance) and match_first_last(msg_chunk, needle) then
					return false
				end
			end
		end
	elseif filter_fuzzy and filter_deep then
		if filter_debug_next then
			minetest.log("error", "[filter] The fuzzy_deep_partials list is missing from the filter config.")
			is_debug_warning_shown = true
		end
	end
	local fuzzy_words = filter_config and filter_config.fuzzy_words
	if filter_fuzzy and fuzzy_words then
		for _, needle in ipairs(fuzzy_words) do
			for msg_word in sanitized:gmatch("[^%s]+") do
				local fuzz = filter_fuzzy_distance(msg_word, needle)
				if filter_debug_next and filter_verbose then
					minetest.log(lowest_verbosity, "[filter] The fuzzy distance between \"" .. msg_word .. "\" and criteria \"" .. needle .. "\" is " .. fuzz .. ".")
					local tmp = " do not"
					if match_first_last(msg_word, needle) then
						tmp = ""
					end
					minetest.log(lowest_verbosity, "[filter] The first and last letters"..tmp.." match")
					is_debug_warning_shown = true
				end
				if (fuzz <= max_fuzzy_distance) and match_first_last(msg_word, needle) then
					return false
				end
			end
		end
	elseif filter_fuzzy then
		if filter_debug_next then
			minetest.log("error", "[filter] The fuzzy_words list is missing from the filter config.")
			is_debug_warning_shown = true
		end
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
			local filter_url = minetest.settings:get("filter.url") or default_filter_url
			filter_download(0, name, filter_url)
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
