function! onlysearch#foldexpr() abort
    return luaeval(printf('_G.__jsj_onlysearch_foldexpr(%d)', v:lnum))
endfunction
