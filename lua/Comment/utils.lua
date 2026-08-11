---@mod comment.utils Utilities

local filetypes = require("Comment.ft")

---@class UtilsMetaTable : table
local meta = {}

---Comment context
---@class CommentCtx
---@field type integer See |comment.utils.ctype|
---@field mode integer See |comment.utils.cmode|
---@field motion integer See |comment.utils.cmotion|
---@field range CommentRange

---Range of the selection that needs to be commented
---@class CommentRange
---@field start_row integer Starting row
---@field start_col integer Starting column
---@field end_row integer Ending row
---@field end_col integer Ending column

---Comment modes - Can be manual or computed via operator-mode
---@class CommentMode
---@field toggle integer Toggle action
---@field comment integer Comment action
---@field uncomment integer Uncomment action

---Comment types
---@class CommentType
---@field linewise integer Use linewise commentstring
---@field blockwise integer Use blockwise commentstring

---Comment motion types
---@class CommentMotion
---@field line integer Line motion (ie. 'gc2j')
---@field char integer Character/left-right motion (ie. 'gc2w')
---@field visual integer Visual motion (ie. 'v3jgc')
---@field visual_line integer Visual-line motion (ie. 'V10kgc')
---@field visual_block integer Visual operator-pending motion


---@class CommentParamEnums
---@field mode CommentMode
---@field type CommentType
---@field motion CommentMotion

---@type CommentParamEnums
meta.com_param_enums = {
	mode = {
		toggle = 1,
		comment = 2,
		uncomment = 3,
	},
	type = {
		linewise = 1,
		blockwise = 2,
	},
	motion = {
		line = 1,
		char = 2,
		visual = 3,
		visual_line = 4,
		visual_block = 5,
	},
}

---Check whether the line is empty
---@param iter string|string[]
---@return boolean
function meta.is_empty(iter)
	return #iter == 0
end

---Helper to get padding character
---@param flag boolean
---@return string string
function meta.get_padding(flag)
	return flag and " " or ""
end

---@private
---Helper to get padding pattern
---@param flag boolean
---@return string string
function meta.get_padpat(flag)
	return flag and "%s?" or ""
end

---Call a function if exists
---@param fn unknown|fun(...):unknown Wanna be function
---@return unknown
function meta.is_fn(fn, ...)
	if type(fn) == "function" then
		return fn(...)
	end
	return fn
end

---Check if the given line is ignored or not with the given pattern
---@param ignore_line string Line to be ignored
---@param pattern string Lua regex
---@return boolean
function meta.ignore(ignore_line, pattern)
	return pattern and string.find(ignore_line, pattern) ~= nil
end

---Get region for line movement or visual selection
---NOTE: Returns the current line region, if `opmode` is not given.
---@param opmode? OpMotion
---@return CommentRange
function meta.get_region(opmode)
	if not opmode then
		local row = unpack(vim.api.nvim_win_get_cursor(0))
		---@type CommentRange
		return {
			start_row = row,
			start_col = 0,
			end_row = row,
			end_col = 0
		}
	end

	local marks = string.match(opmode, "[vV]") and { "<", ">" } or { "[", "]" }
	local sln, eln = vim.api.nvim_buf_get_mark(0, marks[1]), vim.api.nvim_buf_get_mark(0, marks[2])

	---@type CommentRange
	return {
		start_row = sln[1],
		start_col = sln[2],
		end_row = eln[1],
		end_col = eln[2]
	}
end

---Get lines from the current position to the given count
---@param count integer Probably 'vim.v.count'
---@return string[] #List of lines
---@return CommentRange
function meta.get_count_lines(count)
	local start_row = unpack(vim.api.nvim_win_get_cursor(0))
	local end_row = (start_row + count) - 1
	local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
	local range = {
		start_row = start_row,
		start_col = 0,
		end_row = end_row,
		end_col = 0
	}

	return lines, range
end

---Get lines from a NORMAL/VISUAL mode
---@param range CommentRange
---@return string[] #List of lines
function meta.get_lines(range)
	-- If start and end is same, then just return the current line
	if range.start_row == range.end_row then
		return { vim.api.nvim_get_current_line() }
	end

	return vim.api.nvim_buf_get_lines(0, range.start_row - 1, range.end_row, false)
end

---@class UnwrapComStrReturn
---@field com_mark_prefix string Left side of the commentstring
---@field com_mark_suffix string Right side of the commentstring
---@private
---Validates and unwraps the given commentstring
---@param com_str_line string See 'commentstring'
---@return UnwrapComStrReturn
function meta.unwrap_com_str(com_str_line)
	local left, right = string.match(com_str_line, "(.*)%%s(.*)")

	assert(
		(left or right),
		{ msg = string.format("Invalid commentstring for %s! Read `:h commentstring` for help.", vim.bo.filetype) }
	)

	return {
		com_mark_prefix = vim.trim(left),
		com_mark_suffix = vim.trim(right)
	}
end

---Parses commentstring from the following places in the respective order
---  1. pre_hook - commentstring returned from the function
---  2. ft.lua - commentstring table bundled with the plugin
---  3. commentstring - Neovim's native. See 'commentstring'
---@param user_config CommentConfig
---@param com_params CommentCtx
---@return UnwrapComStrReturn
function meta.parse_cstr(user_config, com_params)
	-- 1. We ask `pre_hook` for a commentstring
	local inbuilt = meta.is_fn(user_config.pre_hook, com_params)
		-- 2. Calculate w/ the help of treesitter
		or filetypes.calculate(com_params)

	assert(inbuilt or (com_params.type ~= meta.com_param_enums.type.blockwise), {
		msg = vim.bo.filetype .. " doesn't support block comments!",
	})

	-- 3. Last resort to use native commentstring
	return meta.unwrap_com_str(inbuilt or vim.bo.commentstring)
end

---Returns a closure which is used to do comments
---
---If given {string[]} to the closure then it will do blockwise comment
---else linewise comment will be done with the given {string}
---@param com_marker_prefix string Left side of the commentstring
---@param com_marker_suffix string Right side of the commentstring
---@param padding boolean Is padding enabled?
---@param start_col? integer Starting column
---@param end_col? integer Ending column
---@param tabbed? boolean Using tab indentation
---@return fun(line: string|string[]):string|string[]
function meta.commenter(com_marker_prefix, com_marker_suffix, padding, start_col, end_col, tabbed)
	local pad = meta.get_padding(padding)
	local com_mark_prefix_padded = meta.is_empty(com_marker_prefix) and com_marker_prefix or (com_marker_prefix .. pad)
	local com_mark_suffix_padded = meta.is_empty(com_marker_suffix) and com_marker_suffix or (pad .. com_marker_suffix)
	local empty = string.rep(tabbed and "\t" or " ", start_col or 0) .. com_marker_prefix .. com_marker_suffix
	local is_linewise = start_col and not end_col

	return function(line)
		------------------
		-- for linewise --
		------------------
		if is_linewise then
			if meta.is_empty(line) then
				return empty
			end
			-- line == 0 -> start from 0 col
			if start_col == 0 then
				return (com_mark_prefix_padded .. line .. com_mark_suffix_padded)
			end
			local first = string.sub(line --[[@as string]], 0, start_col)
			local last = string.sub(line --[[@as string]], start_col + 1, -1)
			return first .. com_mark_prefix_padded .. last .. com_mark_suffix_padded
		end

		-------------------
		-- for blockwise --
		-------------------
		if type(line) == "table" then
			local first, last = line[1], line[#line]
			-- If both columns are given then we can assume it's a partial block
			if start_col and end_col then
				local sfirst = string.sub(first, 0, start_col)
				local slast = string.sub(first, start_col + 1, -1)
				local efirst = string.sub(last, 0, end_col + 1)
				local elast = string.sub(last, end_col + 2, -1)
				line[1] = sfirst .. com_mark_prefix_padded .. slast
				line[#line] = efirst .. com_mark_suffix_padded .. elast
			else
				line[1] = meta.is_empty(first) and com_marker_prefix or string.gsub(first, "^(%s*)", "%1" .. vim.pesc(com_mark_prefix_padded))
				line[#line] = meta.is_empty(last) and com_marker_suffix or (last .. com_mark_suffix_padded)
			end
			return line
		end

		--------------------------------
		-- for current-line blockwise --
		--------------------------------
		-- SOURCE: https://github.com/numToStr/Comment.nvim/issues/224
		if end_col > #line then
			return com_mark_prefix_padded .. line .. com_mark_suffix_padded
		end
		local first = string.sub(line, 0, start_col)
		local mid = string.sub(line, start_col + 1, end_col + 1)
		local last = string.sub(line, end_col + 2, -1)
		return first .. com_mark_prefix_padded .. mid .. com_mark_suffix_padded .. last
	end
end

---Returns a closure which is used to uncomment a line
---
---If given {string[]} to the closure then it will block uncomment
---else linewise uncomment will be done with the given {string}
---@param com_mark_prefix string Left side of the commentstring
---@param com_mark_suffix string Right side of the commentstring
---@param padding_enabled boolean Is padding enabled?
---@param start_col? integer Starting column
---@param end_col? integer Ending column
---@return fun(line: string|string[]):string|string[]
function meta.uncommenter(com_mark_prefix, com_mark_suffix, padding_enabled, start_col, end_col)
	local pp, plen = meta.get_padpat(padding_enabled), padding_enabled and 1 or 0
	local left_len, right_len = #com_mark_prefix + plen, #com_mark_suffix + plen
	local ll = meta.is_empty(com_mark_prefix) and com_mark_prefix or vim.pesc(com_mark_prefix) .. pp
	local rr = meta.is_empty(com_mark_suffix) and com_mark_suffix or pp .. vim.pesc(com_mark_suffix)
	local is_lw = not (start_col and start_col)
	local pattern = is_lw and "^(%s*)" .. ll .. "(.-)" .. rr .. "$" or ""

	return function(line)
		-------------------
		-- for blockwise --
		-------------------
		if type(line) == "table" then
			local first, last = line[1], line[#line]
			-- If both columns are given then we can assume it's a partial block
			if (start_col and end_col) then
				local sfirst = string.sub(first, 0, start_col)
				local slast = string.sub(first, start_col + left_len + 1, -1)
				local efirst = string.sub(last, 0, end_col - right_len + 1)
				local elast = string.sub(last, end_col + 2, -1)
				line[1] = sfirst .. slast
				line[#line] = efirst .. elast
			else
				line[1] = string.gsub(first, "^(%s*)" .. ll, "%1")
				line[#line] = string.gsub(last, rr .. "$", "")
			end
			return line
		end

		------------------
		-- for linewise --
		------------------
		if is_lw then
			local a, b, c = string.match(line, pattern)
			-- When user tries to uncomment when there is nothing to uncomment. See #221
			assert(a and b, { msg = "Nothing to uncomment!" })
			-- If there is nothing after LHS then just return ''
			-- bcz the line previously (before comment) was empty
			return meta.is_empty(b) and b or a .. b .. (c or "")
		end

		--------------------------------
		-- for current-line blockwise --
		--------------------------------
		-- SOURCE: https://github.com/numToStr/Comment.nvim/issues/224
		if end_col > #line then
			return string.sub(line, start_col + left_len + 1, #line - right_len)
		end
		local first = string.sub(line, 0, start_col)
		local mid = string.sub(line, start_col + left_len + 1, end_col - right_len + 1)
		local last = string.sub(line, end_col + 2, -1)
		return first .. mid .. last
	end
end

---Check if the given string is commented or not
---
---If given {string[]} to the closure, it will check the first and last line
---with LHS and RHS of commentstring respectively else it will check the given
---line with LHS and RHS (if given) of the commenstring
---@param com_mark_prefix string Left side of the commentstring
---@param com_mark_suffix string Right side of the commentstring
---@param padding boolean Is padding enabled?
---@param start_col? integer Starting column
---@param end_col? integer Ending column
---@return fun(line: string|string[]):boolean
function meta.is_commented(com_mark_prefix, com_mark_suffix, padding, start_col, end_col)
	local padding_pattern = meta.get_padpat(padding)
	local commented_str_prefix = (
		meta.is_empty(com_mark_prefix) and com_mark_prefix or
		("^%s*" .. vim.pesc(com_mark_prefix) .. padding_pattern)
	)

	local commented_str = (
		meta.is_empty(com_mark_suffix) and com_mark_suffix or
		(padding_pattern .. vim.pesc(com_mark_suffix) .. "$")
	)
	local pattern = commented_str_prefix .. ".-" .. commented_str
	local is_full = start_col == nil or end_col == nil

	return function(line)
		-------------------
		-- for blockwise --
		-------------------
		if type(line) == "table" then
			local first, last = line[1], line[#line]
			if is_full then
				return (string.find(first, commented_str_prefix) and string.find(last, commented_str)) ~= nil
			end
			return (string.find(string.sub(first, start_col + 1, -1), commented_str_prefix) and string.find(string.sub(last, 0, end_col + 1), commented_str))
				~= nil
		end

		------------------
		-- for linewise --
		------------------
		if is_full then
			return string.find(line, pattern) ~= nil
		end

		--------------------------------
		-- for current-line blockwise --
		--------------------------------
		-- SOURCE: https://github.com/numToStr/Comment.nvim/issues/224
		return string.find(string.sub(line, start_col + 1, (end_col > #line and #line or end_col + 1)), pattern) ~= nil
	end
end

---Error handler
---@param ... unknown
function meta.catch(fn, ...)
	xpcall(fn, function(err)
		vim.notify(string.format("[Comment.nvim] %s", err.msg), vim.log.levels.WARN)
	end, ...)
end

return meta
