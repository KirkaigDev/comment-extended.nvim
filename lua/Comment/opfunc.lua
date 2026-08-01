---@mod comment.opfunc Operator-mode API
---@brief [[
---Underlying functions that powers the |comment.api.toggle|, |comment.api.comment|,
---and |comment.api.uncomment| lua API.
---@brief ]]

local utils = require("Comment.utils")
local config = require("Comment.config")

local Op = {}

---Vim operator-mode motion enum. Read |:map-operator|
---@alias OpMotion
---| '"line"' # Vertical motion
---| '"char"' # Horizontal motion
---| '"v"' # Visual Block motion
---| '"V"' # Visual Line motion

---Common operatorfunc callback
---This function contains the core logic for comment/uncomment
---@param motion? OpMotion
---If given 'nil', it'll only (un)comment
---the current line
---@param cfg CommentConfig
---@param cmode integer See |comment.utils.cmode|
---@param ctype integer See |comment.utils.ctype|
function Op.opfunc(motion, cfg, cmode, ctype)
	local range = utils.get_region(motion)
	local cmotion = motion == nil and utils.cmotion.line or utils.cmotion[motion]

	-- If we are doing char or visual motion on the same line
	-- then we would probably want block comment instead of line comment
	local is_partial = cmotion == utils.cmotion.char or cmotion == utils.cmotion.v
	local is_blockx = is_partial and range.srow == range.erow

	local lines = utils.get_lines(range)

	-- sometimes there might be a case when there are no lines
	-- like, executing a text object returns nothing
	if utils.is_empty(lines) then
		return
	end

	---@type CommentCtx
	local ctx = {
		cmode = cmode,
		cmotion = cmotion,
		ctype = is_blockx and utils.ctype.blockwise or ctype,
		range = range,
	}

	local lcs, rcs = utils.parse_cstr(cfg, ctx)

	---@type OpFnParams
	local params = {
		cfg = cfg,
		lines = lines,
		lcs = lcs,
		rcs = rcs,
		cmode = cmode,
		range = range,
	}

	if motion ~= nil and (is_blockx or ctype == utils.ctype.blockwise) then
		ctx.cmode = Op.blockwise(params, is_partial)
	else
		ctx.cmode = Op.linewise(params)
	end

	-- We only need to restore cursor if both sticky and position are available
	-- As this function is also called for visual mapping where we are not storing the position
	--
	-- And I found out that if someone presses `gc` but doesn't provide operators and
	-- does visual comments then cursor jumps to previous stored position. Thus the check for visual modes
	if cfg.sticky and config.position and cmotion ~= utils.cmotion.v and cmotion ~= utils.cmotion.V then
		vim.api.nvim_win_set_cursor(0, config.position)
		config.position = nil
	end

	utils.is_fn(cfg.post_hook, ctx)
end

---Line commenting with count
---@param count integer Value of |v:count|
---@param cfg CommentConfig
---@param cmode integer See |comment.utils.cmode|
---@param ctype integer See |comment.utils.ctype|
function Op.count(count, cfg, cmode, ctype)
	local lines, range = utils.get_count_lines(count)

	---@type CommentCtx
	local ctx = {
		cmode = cmode,
		cmotion = utils.cmotion.line,
		ctype = ctype,
		range = range,
	}
	local lcs, rcs = utils.parse_cstr(cfg, ctx)

	---@type OpFnParams
	local params = {
		cfg = cfg,
		cmode = ctx.cmode,
		lines = lines,
		lcs = lcs,
		rcs = rcs,
		range = range,
	}

	if ctype == utils.ctype.blockwise then
		ctx.cmode = Op.blockwise(params)
	else
		ctx.cmode = Op.linewise(params)
	end

	utils.is_fn(cfg.post_hook, ctx)
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
---@param param OpFnParams
---@return integer _ Returns a calculated comment mode
function Op.linewise(param)
	local pattern = utils.is_fn(param.cfg.ignore)
	local padding = utils.is_fn(param.cfg.padding)
	local check_comment = utils.is_commented(param.lcs, param.rcs, padding)

	-- While commenting a region, there could be lines being both commented and non-commented
	-- So, if any line is uncommented then we should comment the whole block or vise-versa
	local cmode = utils.cmode.uncomment

	---When commenting multiple line, it is to be expected that indentation should be preserved
	---So, When looping over multiple lines we need to store the indentation of the mininum length (except empty line)
	---Which will be used to semantically comment rest of the lines
	local min_indent, tabbed = -1, false

	-- If the given cmode is uncomment then we actually don't want to compute the cmode or min_indent
	if param.cmode ~= utils.cmode.uncomment then
		for _, line in ipairs(param.lines) do
			-- I wish lua had `continue` statement [sad noises]
			if not utils.ignore(line, pattern) then
				if cmode == utils.cmode.uncomment and param.cmode == utils.cmode.toggle and (not check_comment(line)) then
					cmode = utils.cmode.comment
				end

				if not utils.is_empty(line) and param.cmode ~= utils.cmode.uncomment then
					local _, len = string.find(line, "^%s*")
					if min_indent == -1 or min_indent > len then
						min_indent, tabbed = len, string.find(line, "^\t") ~= nil
					end
				end
			end
		end
	end

	-- If the comment mode given is not toggle than force that mode
	if param.cmode ~= utils.cmode.toggle then
		cmode = param.cmode
	end

	if cmode == utils.cmode.uncomment then
		local uncomment = utils.uncommenter(param.lcs, param.rcs, padding)
		for i, line in ipairs(param.lines) do
			if not utils.ignore(line, pattern) then
				param.lines[i] = uncomment(line) --[[@as string]]
			end
		end
	else
		local comment = utils.commenter(param.lcs, param.rcs, padding, min_indent, nil, tabbed)
		for i, line in ipairs(param.lines) do
			if not utils.ignore(line, pattern) then
				param.lines[i] = comment(line) --[[@as string]]
			end
		end
	end

	vim.api.nvim_buf_set_lines(0, param.range.srow - 1, param.range.erow, false, param.lines)

	return cmode
end

---Full/Partial/Current-Line Block commenting
---@param param OpFnParams
---@param partial? boolean Comment the partial region (visual mode)
---@return integer _ Returns a calculated comment mode
function Op.blockwise(param, partial)
	local is_x = #param.lines == 1 -- current-line blockwise
	local lines = is_x and param.lines[1] or param.lines

	local padding = utils.is_fn(param.cfg.padding)

	local scol, ecol = nil, nil
	if is_x or partial then
		scol, ecol = param.range.scol, param.range.ecol
	end

	-- If given mode is toggle then determine whether to comment or not
	local cmode = param.cmode
	if cmode == utils.cmode.toggle then
		local is_cmt = utils.is_commented(param.lcs, param.rcs, padding, scol, ecol)(lines)
		cmode = is_cmt and utils.cmode.uncomment or utils.cmode.comment
	end

	if cmode == utils.cmode.uncomment then
		lines = utils.uncommenter(param.lcs, param.rcs, padding, scol, ecol)(lines)
	else
		lines = utils.commenter(param.lcs, param.rcs, padding, scol, ecol)(lines)
	end

	if is_x then
		vim.api.nvim_set_current_line(lines)
	else
		vim.api.nvim_buf_set_lines(0, param.range.srow - 1, param.range.erow, false, lines)
	end

	return cmode
end

return Op
