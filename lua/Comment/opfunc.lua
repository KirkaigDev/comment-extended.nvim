---@mod comment.opfunc Operator-mode API
---@brief [[
---Underlying functions that powers the |comment.api.toggle|, |comment.api.comment|,
---and |comment.api.uncomment| lua API.
---@brief ]]

local utils = require("Comment.utils")
local config = require("Comment.config")

---@class OpfuncMetaTable : table
local meta = {}

---Vim operator-mode motion enum. Read |:map-operator|
---@alias OpMotion
---| '"line"' # Vertical motion
---| '"char"' # Horizontal motion
---| '"visual"' # Visual Block motion
---| '"visual_line"' # Visual Line motion

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
	local motion = input_motion == nil and utils.com_param_enums.motion.line or utils.com_param_enums.motion[input_motion]

	-- If we are doing char or visual motion on the same line
	-- then we would probably want block comment instead of line comment
	local is_partial = motion == utils.com_param_enums.motion.char or motion == utils.com_param_enums.motion.visual
	local is_blockx = is_partial and range.start_row == range.end_row

	local lines = utils.get_lines(range)

	-- sometimes there might be a case when there are no lines
	-- like, executing a text object returns nothing
	if utils.is_empty(lines) then
		return
	end

	---@type CommentCtx
	local com_params = {
		mode = mode,
		motion = motion,
		type = is_blockx and utils.com_param_enums.type.blockwise or type,
		range = range,
	}

	local com_split = utils.parse_cstr(user_config, com_params)
	local com_marker_prefix, com_marker_suffix = com_split.com_mark_prefix, com_split.com_mark_suffix

	---@type OpFnParams
	local op_params = {
		user_config = user_config,
		lines = lines,
		com_mark_prefix = com_marker_prefix,
		com_mark_suffix = com_marker_suffix,
		mode = mode,
		range = range,
	}

	if input_motion ~= nil and (is_blockx or type == utils.com_param_enums.type.blockwise) then
		com_params.mode = meta.blockwise(op_params, is_partial)
	else
		com_params.mode = meta.linewise(op_params)
	end

	-- We only need to restore cursor if both sticky and position are available
	-- As this function is also called for visual mapping where we are not storing the position
	--
	-- And I found out that if someone presses `gc` but doesn't provide operators and
	-- does visual comments then cursor jumps to previous stored position. Thus the check for visual modes
	if user_config.sticky and config.position and (motion ~= utils.com_param_enums.motion.visual) and
		(motion ~= utils.com_param_enums.motion.visual_line) then
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
		mode = mode,
		motion = utils.com_param_enums.motion.line,
		type = type,
		range = range,
	}
	local com_split = utils.parse_cstr(user_config, com_params)
	local com_marker_prefix, com_marker_suffix = com_split.com_mark_prefix, com_split.com_mark_suffix

	---@type OpFnParams
	local op_params = {
		user_config = user_config,
		mode = com_params.mode,
		lines = lines,
		com_mark_prefix = com_marker_prefix,
		com_mark_suffix = com_marker_suffix,
		range = range,
	}

	if type == utils.com_param_enums.type.blockwise then
		com_params.mode = meta.blockwise(op_params)
	else
		com_params.mode = meta.linewise(op_params)
	end

	utils.is_fn(user_config.post_hook, com_params)
end

---Operator-mode function parameters
---@class OpFnParams
---@field user_config CommentConfig
---@field mode integer See |comment.utils.cmode|
---@field lines string[] List of lines
---@field com_mark_prefix string RHS of commentstring
---@field com_mark_suffix string LHS of commentstring
---@field range CommentRange

---Line commenting
---@param op_params OpFnParams
---@return integer _ Returns a calculated comment mode
function meta.linewise(op_params)
	local pattern = utils.is_fn(op_params.user_config.ignore)
	local padding_is_on = utils.is_fn(op_params.user_config.padding)
	local check_comment = utils.is_commented(op_params.com_mark_prefix, op_params.com_mark_suffix, padding_is_on)

	-- While commenting a region, there could be lines being both commented and non-commented
	-- So, if any line is uncommented then we should comment the whole block or vise-versa
	local mode = utils.com_param_enums.mode.uncomment

	---When commenting multiple line, it is to be expected that indentation should be preserved
	---So, When looping over multiple lines we need to store the indentation of the mininum length (except empty line)
	---Which will be used to semantically comment rest of the lines
	local min_indent, tabbed = -1, false

	-- If the given cmode is uncomment then we actually don't want to compute the cmode or min_indent
	if (op_params.mode == utils.com_param_enums.mode.uncomment) then goto compute_loop_end end
	for _, line in ipairs(op_params.lines) do
		-- I wish lua had `continue` statement [sad noises]
		-- `--> no problem, I found a workaround from a 2012 stack overflow post (KirkaigDev 2026-08-06)
		if utils.ignore(line, pattern) then goto continue end
		if mode == utils.com_param_enums.mode.uncomment and op_params.mode == utils.com_param_enums.mode.toggle and (not check_comment(line)) then
			mode = utils.com_param_enums.mode.comment
		end

		if not utils.is_empty(line) and op_params.mode ~= utils.com_param_enums.mode.uncomment then
			local _, len = string.find(line, "^%s*")
			if len and (min_indent == -1 or min_indent > len) then
				min_indent, tabbed = len, string.find(line, "^\t") ~= nil
			end
		end
		::continue::
	end
	::compute_loop_end::

	-- If the comment mode given is not toggle than force that mode
	if op_params.mode ~= utils.com_param_enums.mode.toggle then
		mode = op_params.mode
	end

	if mode == utils.com_param_enums.mode.uncomment then
		local uncomment = utils.uncommenter(op_params.com_mark_prefix, op_params.com_mark_suffix, padding_is_on)
		for i, line in ipairs(op_params.lines) do
			if not utils.ignore(line, pattern) then
				op_params.lines[i] = uncomment(line) --[[@as string]]
			end
		end
	else
		local comment = utils.commenter(op_params.com_mark_prefix, op_params.com_mark_suffix, padding_is_on, min_indent, nil, tabbed)
		for i, line in ipairs(op_params.lines) do
			if not utils.ignore(line, pattern) then
				op_params.lines[i] = comment(line) --[[@as string]]
			end
		end
	end

	vim.api.nvim_buf_set_lines(0, op_params.range.start_row - 1, op_params.range.end_row, false, op_params.lines)

	return mode
end

---Full/Partial/Current-Line Block commenting
---@param op_params OpFnParams
---@param partial? boolean Comment the partial region (visual mode)
---@return integer _ Returns a calculated comment mode
function meta.blockwise(op_params, partial)
	local is_str = #op_params.lines == 1 -- current-line blockwise
	local lines = is_str and op_params.lines[1] or op_params.lines

	local padding = utils.is_fn(op_params.user_config.padding)

	local start_col, end_col = nil, nil
	if is_str or partial then
		start_col, end_col = op_params.range.start_col, op_params.range.end_col
	end

	-- If given mode is toggle then determine whether to comment or not
	local mode = op_params.mode
	if mode == utils.com_param_enums.mode.toggle then
		local is_cmt = utils.is_commented(op_params.com_mark_prefix, op_params.com_mark_suffix, padding, start_col, end_col)(lines)
		mode = is_cmt and utils.com_param_enums.mode.uncomment or utils.com_param_enums.mode.comment
	end

	if mode == utils.com_param_enums.mode.uncomment then
		lines = utils.uncommenter(op_params.com_mark_prefix, op_params.com_mark_suffix, padding, start_col, end_col)(lines)
	else
		lines = utils.commenter(op_params.com_mark_prefix, op_params.com_mark_suffix, padding, start_col, end_col)(lines)
	end

	if (type(lines) == "string") then
		vim.api.nvim_set_current_line(lines)
	else
		vim.api.nvim_buf_set_lines(0, op_params.range.start_row - 1, op_params.range.end_row, false, lines)
	end

	return mode
end

return meta
