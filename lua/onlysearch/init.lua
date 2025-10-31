local coll = require('onlysearch.collector')

local onlysearch = {}

function onlysearch.setup(opts)
    onlysearch.coll = coll:new(opts)
end

function onlysearch.open()
    if not onlysearch.coll.bufnr then
        onlysearch.coll:open()
    else
        print("WARN: OnlySearch window has been opened!!!")
    end
end

function onlysearch.close()
    onlysearch.coll:close()
end

function onlysearch.toggle()
    local open = true
    if onlysearch.coll.bufnr then
        open = vim.fn.tabpagenr() ~= vim.fn.win_id2tabwin(onlysearch.coll.winid)[1]
        onlysearch.coll:close()
    end

    if open then
        onlysearch.coll:open()
    end
end

return onlysearch
