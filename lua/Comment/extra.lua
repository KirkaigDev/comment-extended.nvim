---@mod comment.extra Extra API
---@brief [[
---Underlying functions that powers the |comment.api.insert| lua API.
---@brief ]]

local utils = require("Comment.utils")

local meta = {}

-- FIXME This prints `a` in i_CTRL-o
---Moves the cursor and enters INSERT mode
---@param start_row integer Starting row
---@param end_column integer Ending column
local function move_n_insert(start_row, end_column)
	vim.api.nvim_win_set_cursor(0, { start_row, end_column })
	vim.api.nvim_feedkeys("a", "ni", true)
end

---@param line_index integer Line index
---@param comment_type integer
---@param user_config CommentConfig
local function ins_on_line(line_index, comment_type, user_config)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))

	---@type CommentCtx
	local comment_params = {
		cmode = utils.cmode.comment,
		cmotion = utils.cmotion.line,
		ctype = comment_type,
		range = {
			srow = row,
			scol = col,
			erow = row,
			ecol = col
		},
	}

	local start_row = row + line_index
	local com_marker_prefix, com_marker_suffix = utils.parse_cstr(user_config, comment_params)
	local padding = utils.get_pad(utils.is_fn(user_config.padding))

	-- We need RHS of cstr, if we are doing block comments or if RHS exists
	-- because even in line comment RHS do exists for some filetypes like jsx_element, ocaml
	local if_rcs = utils.is_empty(com_marker_suffix) and com_marker_suffix or padding .. com_marker_suffix

	vim.api.nvim_buf_set_lines(0, start_row, start_row, false, { com_marker_prefix .. padding .. if_rcs })
	vim.api.nvim_win_set_cursor(0, { start_row + 1, 0 })
	vim.api.nvim_command("normal! ==")
	move_n_insert(start_row + 1, #vim.api.nvim_get_current_line() - #if_rcs - 1)
	utils.is_fn(user_config.post_hook, comment_params)
end

---Add a comment below the current line and goes to INSERT mode
---@param comment_type integer See |comment.utils.ctype|
---@param user_config CommentConfig
function meta.insert_below(comment_type, user_config)
	ins_on_line(0, comment_type, user_config)
end

---Add a comment above the current line and goes to INSERT mode
---@param comment_type integer See |comment.utils.ctype|
---@param user_config CommentConfig
function meta.insert_above(comment_type, user_config)
	ins_on_line(-1, comment_type, user_config)
end

---Add a comment at the end of current line and goes to INSERT mode
---@param comment_type integer See |comment.utils.ctype|
---@param user_config CommentConfig
function meta.insert_eol(comment_type, user_config)
	local start_row, start_col = unpack(vim.api.nvim_win_get_cursor(0))

	---@type CommentCtx
	local comment_params = {
		cmode = utils.cmode.comment,
		cmotion = utils.cmotion.line,
		ctype = comment_type,
		range = {
			srow = start_row,
			scol = start_col,
			erow = start_row,
			ecol = start_col
		},
	}
	local com_marker_prefix, com_marker_suffix = utils.parse_cstr(user_config, comment_params)

	local line = vim.api.nvim_get_current_line()
	local padding = utils.get_pad(utils.is_fn(user_config.padding))

	-- We need RHS of cstr, if we are doing block comments or if RHS exists
	-- because even in line comment RHS do exists for some filetypes like jsx_element, ocaml
	local commented_str = utils.is_empty(com_marker_suffix) and com_marker_suffix or padding .. com_marker_suffix

	local end_col
	if utils.is_empty(line) then
		-- If line is empty, start comment at the correct indentation level
		vim.api.nvim_set_current_line(com_marker_prefix .. padding .. commented_str)
		vim.api.nvim_command("normal! ==")
		end_col = #vim.api.nvim_get_current_line() - #commented_str - 1
	else
		-- NOTE:
		-- 1. Python is the only language that recommends 2 spaces between the statement and the comment
		-- 2. Other than that, I am assuming that the users wants a space b/w the end of line and start of the comment
		-- 3. Possibly move this to ft.lua, and make it an option in the config
		local space = vim.bo.filetype == "python" and "  " or " "
		local commented_str_prefix = line .. space .. com_marker_prefix .. padding
		vim.api.nvim_set_current_line(commented_str_prefix .. commented_str)
		end_col = #commented_str_prefix - 1
	end

	move_n_insert(start_row, end_col)
	utils.is_fn(user_config.post_hook, comment_params)
end

return meta
