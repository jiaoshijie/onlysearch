local kit = require('onlysearch.kit')
local cfg = require('onlysearch.config')
local cpo = cfg.common.chunk_process_output
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

    -- 3. add query text
    table.insert(args, "-e")
    table.insert(args, query.text)

    table.insert(args, "--")

    -- 4. add path
    if query.paths and #query.paths > 0 then
        vim.list_extend(args, kit.scan_paths(query.paths))
    else
        table.insert(args, ".")
    end

    return cmd, args
end

--- @param e_ctx table runtime_ctx.engine_ctx
--- @param raw_data string
--- @param is_stdout boolean
--- @param cb fun(data: string[])
local process_output = function(e_ctx, raw_data, is_stdout, cb)
    local last_chunk = is_stdout and e_ctx.stdout_last_chunk or e_ctx.stderr_last_chunk
    local data, remained_chunk = nil, nil

    if raw_data then
        data, remained_chunk = kit.split_last_chunk(raw_data:gsub("\r", ""))
    else
        data = last_chunk
    end

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
    uv_close_handle(uv_ctx.shutdown_check)
    uv_ctx.shutdown_check = nil
    uv_close_handle(uv_ctx.stdout)
    uv_ctx.stdout = nil
    uv_close_handle(uv_ctx.stderr)
    uv_ctx.stderr = nil
    if cpo.enabled then
        uv_close_handle(uv_ctx.cpo_timer)
        uv_ctx.cpo_timer = nil
    end
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
    kit.trace("uv_shutdown has been called", abort)
    local e_ctx = rt_ctx.engine_ctx
    local uv_ctx = e_ctx.uv_ctx

    if not uv_ctx.pid then return end
    uv_ctx.pid = nil

    if abort then
        -- NOTE: since the handle will be closed upon this operation,
        -- the callback registered in uv.spawn will never be called.
        -- then I think using SIGKILL is more suitable.
        uv.process_kill(uv_ctx.handle, vim.uv.constants.SIGKILL)
    end

    uv.check_stop(uv_ctx.shutdown_check)
    uv.read_stop(uv_ctx.stdout)
    uv.read_stop(uv_ctx.stderr)
    if cpo.enabled then
        uv.timer_stop(uv_ctx.cpo_timer)
    end

    uv_close_handles(uv_ctx)
    kit.trace("uv_shutdown has finished", e_ctx)
end

local uv_gracefully_shutdown = function(rt_ctx, on_finish_cb)
    local e_ctx = rt_ctx.engine_ctx
    local uv_ctx = e_ctx.uv_ctx

    if not uv_ctx.pid then return end
    uv.check_start(uv_ctx.shutdown_check, function()
        -- NOTE: Wait the spawned process closes the stdout and stderr.
        -- Ensure all data has been processed successfully.
        if not uv_is_stdout_stderr_closed(uv_ctx) then return end
        kit.trace("uv.check stdout and stderr has been closed")

        if cpo.enabled and #e_ctx.cpo_cache ~= 0 then return end
        kit.trace("uv.check cpo has finished", cpo.enabled)

        on_finish_cb()

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

    kit.trace("=== engine search process started")

    local work_id = unique_id
    unique_id = unique_id + 1

    if uv_ctx.pid then
        uv_shutdown(rt_ctx, true)
    end

    e_ctx.id = work_id
    e_ctx.cmd, e_ctx.args = gen_cmd(backend, rt_ctx.query)
    e_ctx.cwd = vim.fn.getcwd()
    e_ctx.is_raw_data = nil
    e_ctx.is_interrupted = nil
    e_ctx.error_termed = nil
    e_ctx.stdout_last_chunk = nil
    e_ctx.stderr_last_chunk = nil

    rt_cb.on_start()

    uv_ctx.stdout = uv.new_pipe(false)
    uv_ctx.stderr = uv.new_pipe(false)
    uv_ctx.shutdown_check = uv.new_check()

    local on_result_or_error = function(v)
        if not e_ctx.error_termed then
            if not e_ctx.is_raw_data then
                v = backend.parse_output(v)
                if e_ctx.is_raw_data == nil then
                    e_ctx.is_raw_data = type(v) == "string"
                end
            end
            rt_cb.on_result(v)
        else
            rt_cb.on_error(v)
        end
    end

    local stdout_or_stderr_cb = function(values)
        if not cpo.enabled  then
            for _, v in ipairs(values) do
                on_result_or_error(v)
            end
        else
            table.insert(e_ctx.cpo_cache, values)
        end
    end

    if cpo.enabled then
        uv_ctx.cpo_timer = uv.new_timer()
        e_ctx.cpo_cache = {}
        uv.timer_start(uv_ctx.cpo_timer, 5, cpo.interval, vim.schedule_wrap(function()
            if not uv_ctx.pid or work_id ~= e_ctx.id
                or e_ctx.is_interrupted then
                e_ctx.cpo_cache = {}
            end

            local count = 0;
            while #e_ctx.cpo_cache > 0 and count <= cpo.num do
                local outer = e_ctx.cpo_cache[1]
                while #outer > 0 and count <= cpo.num do
                    on_result_or_error(table.remove(outer, 1))
                    count = count + 1
                end
                if #outer == 0 then table.remove(e_ctx.cpo_cache, 1) end
            end
        end))
    end

    uv_ctx.handle, uv_ctx.pid = uv.spawn(
        e_ctx.cmd, {
            stdio = { nil, uv_ctx.stdout, uv_ctx.stderr },
            args = e_ctx.args,
            cwd = e_ctx.cwd,
            env = { "GREP_COLORS=ms=0:mc=:sl=:cx=:fn=:ln=:bn=:se=:ne" },
        }, vim.schedule_wrap(function(code, signal)
            kit.trace("uv.spawn on_exit()", e_ctx.cmd, code, signal, e_ctx.is_interrupted)
            if code ~= 0 or (signal ~= 0 and not e_ctx.is_interrupted) then
                kit.echo_info_msg(fmt("`%s` exited with code %d and signal %d",
                        e_ctx.cmd, code, signal))
            end

            uv_gracefully_shutdown(rt_ctx, vim.schedule_wrap(function()
                if work_id == e_ctx.id then
                    kit.trace("uv.spawn on_finish_cb")
                    rt_cb.on_finish(e_ctx.is_interrupted)
                end
            end))
        end)
    )

    uv.read_start(uv_ctx.stdout, vim.schedule_wrap(function(err, data)
        if data == nil then
            kit.trace("uv.read_start close stdout handle")
            uv_close_handle(uv_ctx.stdout)
        end

        if err then
            kit.echo_err_msg("libuv reading from stdout failed")
            return
        end

        if not uv_ctx.pid or work_id ~= e_ctx.id
            or e_ctx.is_interrupted or e_ctx.error_termed then
            e_ctx.stdout_last_chunk = nil
            return
        end

        process_output(e_ctx, data, true, stdout_or_stderr_cb)
    end))

    uv.read_start(uv_ctx.stderr, vim.schedule_wrap(function(err, data)
        if data == nil then
            kit.trace("uv.read_start close stderr handle")
            uv_close_handle(uv_ctx.stderr)
            if not e_ctx.error_termed then return end  -- no error happened throughout the search process
        end

        if err then
            kit.echo_err_msg("libuv reading from stderr failed")
            return
        end

        if not uv_ctx.pid or work_id ~= e_ctx.id or e_ctx.is_interrupted then
            e_ctx.stderr_last_chunk = nil
            return
        end

        if data and not e_ctx.error_termed then
            e_ctx.error_termed = true
            if cpo.enabled then e_ctx.cpo_cache = {} end
            uv.process_kill(uv_ctx.handle, vim.uv.constants.SIGTERM)
        end

        process_output(e_ctx, data, false, stdout_or_stderr_cb)
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

_M.interrupt = function(rt_ctx, reason)
    local e_ctx = rt_ctx.engine_ctx
    local uv_ctx = e_ctx.uv_ctx

    if uv_ctx.shutdown_check and not uv.is_active(uv_ctx.shutdown_check)
        and not e_ctx.is_interrupted then
        local ret = uv.process_kill(uv_ctx.handle, vim.uv.constants.SIGINT) == 0
        kit.echo_info_msg(fmt("Interrupted(%s), reason: %s", ret, reason))
        e_ctx.is_interrupted = true
    end
end

return _M
