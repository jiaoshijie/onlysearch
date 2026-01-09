local _M = {}
local fmt = string.format

--- @param msg string
_M.echo_err_msg = function(msg)
    vim.api.nvim_echo({ { fmt("ffmk: %s", msg) } }, true, { err = true })
end

--- @return number? major
--- @return number? minor
_M.get_cmd_version = function(cmd, ver_flag, ver_fmt)
    if vim.fn.executable(cmd) ~= 1 then
        return nil, nil
    end
    local obj = vim.system({ cmd, ver_flag }, {
        text = true,
        clear_env = true,
    }):wait()
    if obj.code ~= 0 or obj.signal ~= 0
        or #obj.stderr > 0 then
        return nil, nil
    end
    local major, minor = obj.stdout:match(ver_fmt)

    if not major or not minor then
        return nil, nil
    end

    return tonumber(major), tonumber(minor)
end

--- @param winid ?number
--- @return boolean
_M.winid_in_tab = function(winid)
    if winid == nil then return false end
    return vim.fn.tabpagenr() == vim.fn.win_id2tabwin(winid)[1]
end

--- @param bufnr number
_M.buf_delete = function(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr)
      or not vim.api.nvim_buf_is_loaded(bufnr) then
      return
  end

  -- Suppress the buffer deleted message for those with &report<2
  local start_report = vim.o.report
  vim.o.report = 2

  vim.api.nvim_buf_delete(bufnr, { force = true })

  vim.o.report = start_report
end

--- @param win_id number
--- @param force boolean see :h nvim_win_close
_M.win_delete = function(win_id, force)
  if not win_id or not vim.api.nvim_win_is_valid(win_id) then
    return
  end

  local save_ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.api.nvim_win_close(win_id, force)
  vim.o.eventignore = save_ei
end

return _M
