---@mod comment.opfunc Operator-mode API
---@brief [[
---Underlying functions that powers the |comment.api.toggle|, |comment.api.comment|,
---and |comment.api.uncomment| lua API.
---@brief ]]

local utils = require("Comment.utils")
local config = require("Comment.config")

local meta = {}

---Vim operator-mode motion enum. Read |:map-operator|
---@alias OpMotion
---| '"line"' # Vertical motion
---| '"char"' # Horizontal motion
---| '"v"' # Visual Block motion
---| '"V"' # Visual Line motion

---Common operatorfunc callback
---This function contains the core logic for comment/uncomment
---@param input_motion? OpMotion
---If given 'nil', it'll only (un)comment
---the current line
---@param user_config CommentConfig
---@param mode integer See |comment.utils.cmode|
---@param type integer See |comment.utils.ctype|
function meta.opfunc(input_motion, user_config, mode, type)
	local range = utils.get_region(input_motion)
	-- NOTE:
	-- This shouldn't have been implemented this way
	-- something that should be fixed (KirkaigDev - 2026-08-06)
	local motion = input_motion == nil and utils.cmotion.line or utils.cmotion[input_motion]

	-- If we are doing char or visual motion on the same line
	-- then we would probably want block comment instead of line comment
	local is_partial = motion == utils.cmotion.char or motion == utils.cmotion.v
	local is_blockx = is_partial and range.srow == range.erow

	local lines = utils.get_lines(range)

	-- sometimes there might be a case when there are no lines
	-- like, executing a text object returns nothing
	if utils.is_empty(lines) then
		return
	end

	---@type CommentCtx
	local com_params = {
		cmode = mode,
		cmotion = motion,
		ctype = is_blockx and utils.ctype.blockwise or type,
		range = range,
	}

	local com_marker_prefix, com_marker_suffix = utils.parse_cstr(user_config, com_params)

	---@type OpFnParams
	local op_params = {
		cfg = user_config,
		lines = lines,
		lcs = com_marker_prefix,
		rcs = com_marker_suffix,
		cmode = mode,
		range = range,
	}

	if input_motion ~= nil and (is_blockx or type == utils.ctype.blockwise) then
		com_params.cmode = meta.blockwise(op_params, is_partial)
	else
		com_params.cmode = meta.linewise(op_params)
	end

	-- We only need to restore cursor if both sticky and position are available
	-- As this function is also called for visual mapping where we are not storing the position
	--
	-- And I found out that if someone presses `gc` but doesn't provide operators and
	-- does visual comments then cursor jumps to previous stored position. Thus the check for visual modes
	if user_config.sticky and config.position and motion ~= utils.cmotion.v and motion ~= utils.cmotion.V then
		vim.api.nvim_win_set_cursor(0, config.position)
		config.position = nil
	end

	utils.is_fn(user_config.post_hook, com_params)
end

---Line commenting with count
---@param count integer Value of |v:count|
---@param user_config CommentConfig
---@param mode integer See |comment.utils.cmode|
---@param type integer See |comment.utils.ctype|
function meta.count(count, user_config, mode, type)
	local lines, range = utils.get_count_lines(count)

	---@type CommentCtx
	local com_params = {
		cmode = mode,
		cmotion = utils.cmotion.line,
		ctype = type,
		range = range,
	}
	local com_marker_prefix, com_marker_suffix = utils.parse_cstr(user_config, com_params)

	---@type OpFnParams
	local op_params = {
		cfg = user_config,
		cmode = com_params.cmode,
		lines = lines,
		lcs = com_marker_prefix,
		rcs = com_marker_suffix,
		range = range,
	}

	if type == utils.ctype.blockwise then
		com_params.cmode = meta.blockwise(op_params)
	else
		com_params.cmode = meta.linewise(op_params)
	end

	utils.is_fn(user_config.post_hook, com_params)
end

---Operator-mode function parameters
---@class OpFnParams
---@field cfg CommentConfig
---@field cmode integer See |comment.utils.cmode|
---@field lines string[] List of lines
---@field rcs string RHS of commentstring
---@field lcs string LHS of commentstring
---@field range CommentRange

---Line commenting
---@param op_params OpFnParams
---@return integer _ Returns a calculated comment mode
function meta.linewise(op_params)
	local pattern = utils.is_fn(op_params.cfg.ignore)
	local padding = utils.is_fn(op_params.cfg.padding)
	local check_comment = utils.is_commented(op_params.lcs, op_params.rcs, padding)

	-- While commenting a region, there could be lines being both commented and non-commented
	-- So, if any line is uncommented then we should comment the whole block or vise-versa
	local cmode = utils.cmode.uncomment

	---When commenting multiple line, it is to be expected that indentation should be preserved
	---So, When looping over multiple lines we need to store the indentation of the mininum length (except empty line)
	---Which will be used to semantically comment rest of the lines
	local min_indent, tabbed = -1, false

	-- If the given cmode is uncomment then we actually don't want to compute the cmode or min_indent
	if op_params.cmode ~= utils.cmode.uncomment then
		for _, line in ipairs(op_params.lines) do
			-- I wish lua had `continue` statement [sad noises]
			if not utils.ignore(line, pattern) then
				if cmode == utils.cmode.uncomment and op_params.cmode == utils.cmode.toggle and (not check_comment(line)) then
					cmode = utils.cmode.comment
				end

				if not utils.is_empty(line) and op_params.cmode ~= utils.cmode.uncomment then
					local _, len = string.find(line, "^%s*")
					if len and (min_indent == -1 or min_indent > len) then
						min_indent, tabbed = len, string.find(line, "^\t") ~= nil
					end
				end
			end
		end
	end

	-- If the comment mode given is not toggle than force that mode
	if op_params.cmode ~= utils.cmode.toggle then
		cmode = op_params.cmode
	end

	if cmode == utils.cmode.uncomment then
		local uncomment = utils.uncommenter(op_params.lcs, op_params.rcs, padding)
		for i, line in ipairs(op_params.lines) do
			if not utils.ignore(line, pattern) then
				op_params.lines[i] = uncomment(line) --[[@as string]]
			end
		end
	else
		local comment = utils.commenter(op_params.lcs, op_params.rcs, padding, min_indent, nil, tabbed)
		for i, line in ipairs(op_params.lines) do
			if not utils.ignore(line, pattern) then
				op_params.lines[i] = comment(line) --[[@as string]]
			end
		end
	end

	vim.api.nvim_buf_set_lines(0, op_params.range.srow - 1, op_params.range.erow, false, op_params.lines)

	return cmode
end

---Full/Partial/Current-Line Block commenting
---@param op_params OpFnParams
---@param partial? boolean Comment the partial region (visual mode)
---@return integer _ Returns a calculated comment mode
function meta.blockwise(op_params, partial)
	local is_x = #op_params.lines == 1 -- current-line blockwise
	local lines = is_x and op_params.lines[1] or op_params.lines

	local padding = utils.is_fn(op_params.cfg.padding)

	local start_column, end_column = nil, nil
	if is_x or partial then
		start_column, end_column = op_params.range.scol, op_params.range.ecol
	end

	-- If given mode is toggle then determine whether to comment or not
	local mode = op_params.cmode
	if mode == utils.cmode.toggle then
		local is_cmt = utils.is_commented(op_params.lcs, op_params.rcs, padding, start_column, end_column)(lines)
		mode = is_cmt and utils.cmode.uncomment or utils.cmode.comment
	end

	if mode == utils.cmode.uncomment then
		lines = utils.uncommenter(op_params.lcs, op_params.rcs, padding, start_column, end_column)(lines)
	else
		lines = utils.commenter(op_params.lcs, op_params.rcs, padding, start_column, end_column)(lines)
	end

	if (type(lines) == "string") then
		vim.api.nvim_set_current_line(lines)
	else
		vim.api.nvim_buf_set_lines(0, op_params.range.srow - 1, op_params.range.erow, false, lines)
	end

	return mode
end

return meta
