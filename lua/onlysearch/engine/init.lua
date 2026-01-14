local kit = require('onlysearch.kit')
local cfg = require('onlysearch.config')
local uv = vim.uv
local fmt = string.format

local _M = {}
local unique_id = 0

--- @param backend table rg_backend or grep_backend
--- @param query Query
--- @return string  -- cmd
--- @return table  -- args
local gen_cmd = function(backend, query)
    local cmd, args, mandatory_args = cfg.get_engine_info()
    assert(cmd ~= nil)
    -- the args is an array of strings, so do not track the reused table field
    args = vim.deepcopy(args or {}, true)

    -- 1. add flags
    if query.flags and #query.flags > 0 then
        for flag in vim.gsplit(query.flags, ' ') do
            if #flag > 0 then table.insert(args, flag) end
        end
    end
    vim.list_extend(args, mandatory_args or {})

    -- 2. add filter
    if query.filters and #query.filters > 0 then
        backend.parse_filters(args, query.filters)
    end
    table.insert(args, "--")

    -- 3. add query text
    table.insert(args, query.text)
    -- 4. add path
    if query.paths and #query.paths > 0 then
        vim.list_extend(args, kit.scan_paths(query.paths))
    else
        table.insert(args, '.')
    end

    return cmd, args
end

--- @param e_ctx table runtime_ctx.engine_ctx
--- @param raw_data string
--- @param is_stdout boolean
--- @param cb fun(data: string[])
local process_output = function(e_ctx, raw_data, is_stdout, cb)
    raw_data = raw_data:gsub("\r", "")
    local data, remained_chunk = kit.split_last_chunk(raw_data)

    local last_chunk = is_stdout and e_ctx.stdout_last_chunk or e_ctx.stderr_last_chunk
    if data then
        if last_chunk then
            data = last_chunk .. data
        end
        cb(vim.split(data, '\n', { plain = true, trimempty = false }))
        last_chunk = remained_chunk
    else
        if remained_chunk then
            last_chunk = (last_chunk or '') .. remained_chunk
        end
    end

    if is_stdout then
        e_ctx.stdout_last_chunk = last_chunk
    else
        e_ctx.stderr_last_chunk = last_chunk
    end
end

local uv_close_handle = function(handle)
    if handle and not uv.is_closing(handle) then
        uv.close(handle)
    end
end

local uv_close_handles = function(uv_ctx)
    uv_close_handle(uv_ctx.stdout)
    uv_ctx.stdout = nil
    uv_close_handle(uv_ctx.stderr)
    uv_ctx.stderr = nil
    uv_close_handle(uv_ctx.handle)
    uv_ctx.handle = nil
end

--- @return boolean
local uv_is_stdout_stderr_closed = function(uv_ctx)
    if uv_ctx.stdout and not uv.is_closing(uv_ctx.stdout) then
        return false
    end

    if uv_ctx.stderr and not uv.is_closing(uv_ctx.stderr) then
        return false
    end

    return true
end

local uv_shutdown = function(rt_ctx, abort)
    local e_ctx = rt_ctx.engine_ctx
    local uv_ctx = e_ctx.uv_ctx

    if not uv_ctx.pid then return end
    uv_ctx.pid = nil

    if abort and uv_ctx.handle then
        -- uv.kill needs pid
        uv.process_kill(uv_ctx.handle, vim.uv.constants.SIGTERM)
    end

    uv.read_stop(uv_ctx.stdout)
    uv.read_stop(uv_ctx.stderr)

    if abort then
        uv.check_stop(uv_ctx.shutdown_check)
        uv_close_handle(uv_ctx.shutdown_check)
        uv_ctx.shutdown_check = nil
    end

    uv_close_handles(uv_ctx)
end

local uv_gracefully_shutdown = function(rt_ctx)
    local e_ctx = rt_ctx.engine_ctx
    local uv_ctx = e_ctx.uv_ctx

    if not uv_ctx.pid then return end

    uv.check_start(uv_ctx.shutdown_check, function()
        if not uv_is_stdout_stderr_closed(uv_ctx) then return end

        uv.check_stop(uv_ctx.shutdown_check)
        uv_close_handle(uv_ctx.shutdown_check)
        uv_ctx.shutdown_check = nil

        uv_shutdown(rt_ctx, false)
    end)
end

--- @param rt_ctx table runtime_ctx
_M.search = function(rt_ctx)
    assert(rt_ctx.query ~= nil)
    local rt_cb = rt_ctx.cbs_weak_ref
    local e_ctx = rt_ctx.engine_ctx
    local uv_ctx = e_ctx.uv_ctx

    local ok, backend = pcall(require, 'onlysearch.engine.' .. cfg.common.engine)
    if not ok then
        kit.echo_err_msg("No backend engine found")
        return
    end

    local work_id = unique_id
    unique_id = unique_id + 1

    e_ctx.id = work_id
    e_ctx.cmd, e_ctx.args = gen_cmd(backend, rt_ctx.query)
    e_ctx.cwd = vim.fn.getcwd()
    e_ctx.is_raw_data = nil
    e_ctx.stdout_last_chunk = nil
    e_ctx.stderr_last_chunk = nil

    if uv_ctx.pid then
        uv_shutdown(rt_ctx, true)
    end

    rt_cb.on_start()

    uv_ctx.stdout = uv.new_pipe(false)
    uv_ctx.stderr = uv.new_pipe(false)
    uv_ctx.shutdown_check = uv.new_check()

    uv_ctx.handle, uv_ctx.pid = uv.spawn(
        e_ctx.cmd, {
            stdio = { nil, uv_ctx.stdout, uv_ctx.stderr },
            args = e_ctx.args,
            cwd = e_ctx.cwd,
        }, vim.schedule_wrap(function(code, signal)
            if code ~= 0 or signal ~= 0 then
                kit.echo_info_msg(fmt("`%s` exited with code %d and signal %d",
                        e_ctx.cmd, code, signal))
            elseif work_id == e_ctx.id then
                rt_cb.on_finish()
            end
            uv_gracefully_shutdown(rt_ctx)
        end)
    )

    local stdout_cb = function(values)
        for _, v in ipairs(values) do
            if not e_ctx.is_raw_data or e_ctx.is_raw_data == nil then
                v = backend.parse_output(v)
                if e_ctx.is_raw_data == nil then
                    e_ctx.is_raw_data = type(v) == "string"
                end
            end
            rt_cb.on_result(v)
        end
    end

    uv.read_start(uv_ctx.stdout, vim.schedule_wrap(function(err, data)
        if not uv_ctx.pid or work_id ~= e_ctx.id then return end

        if err then
            kit.echo_err_msg("libuv reading from stdout failed")
        elseif data then
            process_output(e_ctx, data, true, stdout_cb)
        else
            if e_ctx.stdout_last_chunk then
                rt_cb.on_result({ backend.parse_output(e_ctx.stdout_last_chunk) })
                e_ctx.stdout_last_chunk = nil
            end
            uv_close_handle(uv_ctx.stdout)
        end
    end))
    uv.read_start(uv_ctx.stderr, vim.schedule_wrap(function(err, data)
        if not uv_ctx.pid or work_id ~= e_ctx.id then return end

        if err then
            kit.echo_err_msg("libuv reading from stderr failed")
        elseif data then
            process_output(e_ctx, data, false, function(values)
                for _, v in ipairs(values) do rt_cb.on_error(v) end
            end)
        else
            if e_ctx.stderr_last_chunk then
                rt_cb.on_error({ e_ctx.stderr_last_chunk })
                e_ctx.stderr_last_chunk = nil
            end
            uv_close_handle(uv_ctx.stderr)
        end
    end))
end

_M.close = function(rt_ctx)
    local e_ctx = rt_ctx.engine_ctx
    local uv_ctx = e_ctx.uv_ctx
    if uv_ctx.pid then
        uv_shutdown(rt_ctx, true)
    end
    e_ctx.cmd, e_ctx.args = nil, nil
    e_ctx.cwd = nil
    e_ctx.is_raw_data = nil
    e_ctx.stdout_last_chunk = nil
    e_ctx.stderr_last_chunk = nil
end

return _M
