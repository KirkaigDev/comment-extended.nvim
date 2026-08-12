---@mod comment.api Core Lua API
---@brief [[
---This module provides the core lua APIs which is used by the default keybindings
---and <Plug> (Read |comment.plugmap|) mappings. These API can be used to setup your
---own custom keybindings or to even make your (un)comment function.
---@brief ]]

local config_import = require("Comment.config")
local utils = require("Comment.utils")
local opfunc = require("Comment.opfunc")
local extra = require("Comment.extra")

---@class ApiMetaTable: table
local meta = {
	toggle = {},
	comment = {},
	uncomment = {},
	insert = {}
}

---@class RangeTypeEnums
---@field full_line integer
---@field motion integer vim motions
---@field lines integer

---@type RangeTypeEnums
local range_types = {
	full_line = 1,
	motion = 2,
	lines = 3
}

---@class ApiExecuteCommentParams
---@field mode integer
---@field range_type integer
---@field op_motion? OpMotion
---@field line_count? integer
---@field user_config CommentConfig
---@field style integer

---@alias ApiExecuteCommentFn fun(opts: ApiExecuteCommentParams)
---@return nil

---@type ApiExecuteCommentFn
local function execute_comment(opts)
	local user_config = opts.user_config or config_import:get()
	local line_count = opts.line_count or vim.api.nvim_get_vvar("count")

	if opts.range_type == range_types.motion then
		utils.catch(opfunc.opfunc, opts.op_motion, user_config, opts.mode, opts.style)

	elseif opts.range_type == range_types.lines then
		utils.catch(opfunc.count, line_count, user_config, opts.mode, opts.style)

    elseif opts.range_type == range_types.full_line then
        utils.catch(opfunc.opfunc, nil, user_config, opts.mode, opts.style)
	end
end

---@class ApiFunctionsTable
---@field current fun(_, user_config: CommentConfig): nil
---@field count fun(_, line_count: integer, user_config: CommentConfig): nil

---@alias ApiFunctionsTableCall fun(_, motion: OpMotion, user_config: CommentConfig)
---@return nil

---@param mode integer
---@param style integer
---@return ApiFunctionsTable | ApiFunctionsTableCall
local function init_api(mode, style)
	---@type ApiFunctionsTable
	local created_api_table = {
		current = function(_, user_config)
			execute_comment({
				mode = mode,
				style = style,
				range_type = range_types.full_line,
				user_config = user_config
			})
		end,

		count = function(_, line_count, user_config)
			execute_comment({
				mode = mode,
				style = style,
				range_type = range_types.lines,
				line_count = line_count,
				user_config = user_config
			})
		end,
	}

	setmetatable(created_api_table, {
		---@type ApiFunctionsTableCall
		__call = function(_, motion, user_config)
			execute_comment({
				mode = mode,
				style = style,
				range_type = range_types.motion,
				op_motion = motion,
				user_config = user_config
			})
		end,
	})

	return created_api_table
end

for mode_name, mode_id in pairs(utils.com_param_enums.mode) do
	meta[mode_name]["linewise"] = init_api(mode_id, utils.com_param_enums.type.linewise)
	meta[mode_name]["blockwise"] = init_api(mode_id, utils.com_param_enums.type.blockwise)
end

---@alias ApiInsertMethodFns fun(user_config: CommentConfig)
---@return nil

---@class ApiInsertMethods
---@field above ApiInsertMethodFns
---@field below ApiInsertMethodFns
---@field eol ApiInsertMethodFns

---@class ApiInsertTable
---@field linewise ApiInsertMethods
---@field blockwise ApiInsertMethods

---@type ApiInsertTable
meta.insert = {
	linewise = {
		above = function(user_config)
			utils.catch(
				extra.insert_above,
				utils.com_param_enums.type.linewise,
				user_config or config_import:get()
			)
		end,
		below = function(user_config)
			utils.catch(
				extra.insert_below,
				utils.com_param_enums.type.linewise,
				user_config or config_import:get()
			)
		end,
		eol = function(user_config)
			utils.catch(
				extra.insert_eol,
				utils.com_param_enums.type.linewise,
				user_config or config_import:get()
			)
		end
	},
	blockwise = {
		above = function(user_config)
			utils.catch(
				extra.insert_above,
				utils.com_param_enums.type.blockwise,
				user_config or config_import:get()
			)
		end,
		below = function(user_config)
			utils.catch(
				extra.insert_below,
				utils.com_param_enums.type.blockwise,
				user_config or config_import:get()
			)
		end,
		eol = function(user_config)
			utils.catch(
				extra.insert_eol,
				utils.com_param_enums.type.blockwise,
				user_config or config_import:get()
			)
		end
	}
}

---Wraps the given API function with 'lockmarks' to preserve marks/jumps
---@param fn_name string Name of API function
---@return fun(motion:OpMotion) #Callback function
---@see lockmarks
---@see comment.opfunc.OpMotion
---@usage [[
---local api = require('Comment.api')
---
---vim.keymap.set(
---    'n', '<leader>c', api.locked('toggle.linewise.current')
---)
---
---local esc = vim.api.nvim_replace_termcodes(
---    '<ESC>', true, false, true
---)
---vim.keymap.set('x', '<leader>c', function()
---    vim.api.nvim_feedkeys(esc, 'nx', false)
---    api.locked('toggle.linewise')(vim.fn.visualmode())
---end)
---
----- NOTE: `locked` method is just a wrapper around `lockmarks`
---vim.api.nvim_command([[
---    lockmarks lua require('Comment.api').toggle.linewise.current()
---]])
---@usage ]]
function meta.locked(fn_name)
	return function(motion)
		return vim.api.nvim_command(
			('lockmarks lua require("Comment.api").%s(%s)'):format(fn_name, motion and ("%q"):format(motion))
		)
	end
end

---Callback function which does the following
---  1. Sets 'operatorfunc' for dot-repeat
---  2. Preserves jumps and marks
---  3. Stores last cursor position
---@param fn_name string Name of the API function to call
---@param op_mode '"g@"'|'"g@$"' Operator-mode expression
---@return fun():string #Keymap RHS callback
---@see g@
---@see operatorfunc
---@usage [[
---local api = require('Comment.api')
---vim.keymap.set(
---    'n', 'gc', api.call('toggle.linewise', 'g@'),
---    { expr = true }
---)
---vim.keymap.set(
---    'n', 'gcc', api.call('toggle.linewise.current', 'g@$'),
---    { expr = true }
---)
---@usage ]]
function meta.call(fn_name, op_mode)
	return function()
		vim.o.operatorfunc = ("v:lua.require'Comment.api'.locked'%s'"):format(fn_name)
		config_import.position = config_import:get().sticky and vim.api.nvim_win_get_cursor(0) or nil
		return op_mode
	end
end

return meta
