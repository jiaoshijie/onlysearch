local coll = require('onlysearch.collector')

local onlysearch = {}

function onlysearch.setup(opts)
    onlysearch.coll = coll:new(opts)
end

function onlysearch.open()
    onlysearch.coll:open()
end

function onlysearch.close()
    onlysearch.coll:close()
end

function onlysearch.toggle()
    if onlysearch.coll.bufnr then
        onlysearch.coll:close()
    else
        onlysearch.coll:open()
    end
end

return onlysearch
