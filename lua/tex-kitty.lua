-- This is a lua module to be used with neovim and vimtex
-- It provides a live preview of the pdf file in a kitty terminals
-- It also provides some keybindings to compile the pdf and to
-- open the pdf in the correct page
-- It also provides a function to create and edit svg files with inkscape
-- It also provides a function to sync the current line in the tex file
-- with the pdf file
--

local M = {}

-- plugin load we want to start inkscape-figures command to watch the figures
-- folder. We can do this by checking if the module was already loaded by checking if
-- the global variable __tex_kitty_module_was_loaded exists
if not vim.g.__tex_kitty_module_was_loaded then
    -- start inkscape-figures watch command
    vim.fn.system('inkscape-figures watch ' .. './figures/')
    -- we also craete a autocomand to kill the process when nvim exits
    -- this is done by checking if the process is running and killing it
    vim.api.nvim_exec(
        [[
      augroup InkscapeFiguresWatch
        autocmd!
        autocmd VimLeavePre * call system('pkill -f "inkscape-figures watch"')
      augroup end
    ]],
        false
    )
end
vim.g.__tex_kitty_module_was_loaded = true

------------------------------------------------------------------------------
-- Configuration {{{

-- save globally
-- ckec if the module was already loaded by checking if the global variable
-- __tex_kitty_module_was_loaded exists

DEFAULT_CONFIG = {
    set_shorcuts = true,
    live_enabled = true,
}

vim.g.termpdf_panelopened = false
vim.g.termpdf_lastcalled = 0

-- live typeset
vim.g.live_enabled = true
vim.g.live_typeset_triggered = false
vim.g.live_typeset_last_called = 0

-- safdsf
vim.g.set_shorcuts = true

-- buuild the to= flag for kitty
local kitty_to = ' '
local ssh_tty = false
if vim.fn.empty(vim.fn.getenv('SSH_TTY')) == 0 then
    kitty_to = ' --to=tcp:localhost:$KITTY_PORT '
    ssh_tty = true
end

-- create a setup function
function M.setup(user_config)
    user_config = user_config or {}
    -- merge the config with the default
    local config = vim.tbl_extend('force', DEFAULT_CONFIG, user_config)
    -- set the keybindings
    if config.set_shorcuts then vim.g.set_shorcuts = config.set_shorcuts end
    -- set the live typeset
    if config.live_enabled then vim.g.live_enabled = config.live_enabled end
end

-- }}}
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- Functions {{{

function LiveTypeset(force)
    if force then
        vim.cmd([[:silent! write]])
        vim.g.live_typeset_last_called = 0
        vim.g.live_typeset_triggered = true
    else
        local time = tonumber(vim.fn.reltimefloat(vim.fn.reltime())) * 1000.0
        if not vim.g.live_typeset_triggered then
            if time - vim.g.live_typeset_last_called > 1000 then
                -- this will trigger the live preview every
                -- 1s after the last save
                -- save current buffer, so that the pdf is updated
                vim.cmd([[:silent! write]])
                vim.g.live_typeset_last_called = time
                vim.g.live_typeset_triggered = true
            end
        end
        vim.g.live_typeset_last_called = time
    end
end

function TermPDFCacheRead(filename)
    -- pdfcat will create a cache file for the pdf filename with the
    -- following format:
    local cache_file = string.gsub(filename, '/', '_')
    cache_file = string.gsub(cache_file, ' ', '_')
    cache_file = string.gsub(cache_file, '%.', '_')
    cache_file = '/Users/marcos/.cache/termpdf.py/' .. cache_file
    -- print('cache_file: ' .. cache_file)
    -- print('page: ' .. page)
    -- test if that file exists
    local f = io.open(cache_file, 'r') or nil
    local t = {}
    if f ~= nil then
        local content = f:read('*a') or '{}'
        f:close()
        t = vim.json.decode(content)
    end
    return t
end

function TermPDFCacheWrite(filename, t)
    -- pdfcat will create a cache file for the pdf filename with the
    -- following format:
    if not t then return end
    local cache_file = string.gsub(filename, '/', '_')
    cache_file = string.gsub(cache_file, ' ', '_')
    cache_file = string.gsub(cache_file, '%.', '_')
    cache_file = '/Users/marcos/.cache/termpdf.py/' .. cache_file
    -- print('cache_file: ' .. cache_file .. ' page: ' .. page)
    -- print('page: ' .. page)
    -- test if that file exists
    local f = io.open(cache_file, 'w')
    -- print(vim.inspect(t))
    if f ~= nil then
        f:write(vim.json.encode(t))
        f:close()
    end
end

function SyncTexView()
    local line = vim.fn.line('.')
    local tex_file = vim.fn.expand('%:p')
    local pdf_file = vim.fn.expand('%:p:r') .. '.pdf'
    tex_file = 'main.tex'
    pdf_file = 'main.pdf'
    local synctex = io.popen(
        'synctex view -i '
            .. line
            .. ':1:'
            .. tex_file
            .. ' -o '
            .. pdf_file
            .. " | grep 'Page:' | head -1 | grep -o '[0-9]\\+'"
    )
    local page = nil
    if synctex ~= nil then
        page = tonumber(synctex:read('*a'))
        synctex:close()
    end
    if page then
        local cache_table = TermPDFCacheRead(pdf_file)
        cache_table.page = page
        TermPDFCacheWrite(pdf_file, cache_table)
        pdf_file = vim.fn.expand('%:p:r') .. '.pdf'
        -- TODO: optimize this
        -- currently we are closing the pdf and reopening it
        -- we should just update the page
        TermPDFClose()
        TermPDF(pdf_file, page, true)
    end
end

function SyncTexEdit()
    -- first we get the current buffer line number
    print('not implemented yet')
end

-- previwer
function TermPDF(pdf_file, pdf_page, force_reload)
    -- if not page, then nil
    pdf_page = pdf_page or ''
    force_reload = force_reload or false
    -- chekc if pdf_file exists
    if vim.fn.filereadable(pdf_file) == 0 then return end

    -- print('kitty @' .. kitty_to .. 'launch --title=live_preview')

    local reload = false
    local time = tonumber(vim.fn.reltimefloat(vim.fn.reltime())) * 1000.0
    if time - vim.g.termpdf_lastcalled > 1000 then reload = true end

    if force_reload then reload = true end

    local use_kitty = true
    local use_tmux = false
    local use_zellij = false
    local panes_before = {}
    if vim.fn.empty(vim.fn.getenv('TMUX')) == 0 then
        use_kitty = false
        use_tmux = true
        -- we need to check what are the tmux panes at the moment, so when we
        -- create a new one we can track the id of the new one
        panes_before = vim.fn.systemlist('tmux list-panes -F "#{pane_id}"')
        -- print(vim.inspect(panes_before))
    end
    if vim.fn.empty(vim.fn.getenv('ZELLIJ')) == 0 then
        use_kitty = false
        use_zellij = true
    end

    if reload then
        -- vim.fn.system("kitty @ set-background-opacity 1.0")
        -- 1. open a new kitty window
        if not vim.g.termpdf_panelopened then
            if use_kitty then
                vim.fn.system(
                    'kitty @' .. kitty_to .. 'launch --title=live_preview'
                )
                vim.g.termpdf_panelopened = true
            elseif use_tmux then
                vim.fn.system('tmux split-window -d -h')
                -- now we check the panes again to get the id of the new one
                -- and we rename it to live_preview
                local panes_after =
                    vim.fn.systemlist('tmux list-panes -F "#{pane_id}"')
                for _, pane in ipairs(panes_after) do
                    if not vim.tbl_contains(panes_before, pane) then
                        vim.g.new_pane = pane
                        break
                    end
                end
                if vim.g.new_pane ~= '' then
                    vim.fn.system(
                        'tmux select-pane -t '
                            .. vim.g.new_pane
                            .. ' -T live_preview'
                    )
                end
                vim.g.termpdf_panelopened = true
            elseif use_zellij then
                vim.fn.system('zellij action new-pane --name live_preview')
                vim.g.termpdf_panelopened = true
            else
                print('No supported terminal multiplexer found')
                return
            end
        end
    end

    -- 2. send the file to the new window
    if use_kitty then
        vim.fn.system(
            'kitty @'
                .. kitty_to
                .. 'kitten kittens/termpdf.py '
                .. pdf_file
                .. ' '
                .. pdf_page
        )
        vim.g.termpdf_lastcalled = time
    elseif use_tmux then
        print('sending to pane ' .. vim.g.new_pane)
        vim.fn.system(
            'tmux send-keys -t '
                .. vim.g.new_pane
                .. ' "termpdf.py '
                .. pdf_file
                .. ' '
                .. pdf_page
                .. '" C-m'
        )
        vim.g.termpdf_lastcalled = time
    elseif use_zellij then
        vim.fn.system(
            'zellij action write-chars --pane-name live_preview "termpdf.py '
                .. pdf_file
                .. ' '
                .. pdf_page
                .. '\n"'
        )
        vim.g.termpdf_lastcalled = time
    else
        print('No supported terminal multiplexer found')
        return
    end
    -- vim.fn.system(
    --     'kitty @'
    --         .. kitty_to
    --         .. 'kitten kittens/termpdf.py '
    --         .. pdf_file
    --         .. ' '
    --         .. pdf_page
    -- )
    -- zellij action write-chars --pane-id 2 "ls -la\n"
    --zellij action move-focus right;
    --zellij action write-chars $(xclip -o); zellij action move-focus left
    -- vim.fn.system('zellij action move-focus right')
    -- vim.fn.system(
    --     'zellij action write-chars "disp '
    --         .. pdf_file
    --         .. ' '
    --         .. pdf_page
    --         .. '\n"'
    -- )
    -- vim.fn.system('zellij action move-focus left')
    -- vim.g.termpdf_lastcalled = time
    -- end
    vim.g.live_typeset_triggered = false
end

function TermPDFClose()
    vim.fn.system(
        'kitty @' .. kitty_to .. 'close-window --match title:live_preview'
    )
    vim.g.termpdf_panelopened = false
end

function VimtexCallback(status)
    local pdf_file = vim.b.vimtex.base
    pdf_file = pdf_file:gsub('.tex$', '.pdf')
    if status then
        if vim.fn.filereadable(pdf_file) == 1 then TermPDF(pdf_file) end
    elseif vim.fn.filereadable(pdf_file) == 1 then
        TermPDF(pdf_file)
    end
end

function InkscapeFigures()
    -- Get the current line
    vim.cmd([[let b:line = getline('.')]])
    -- remove \incfig{ and } in lua
    vim.cmd([[let b:line = substitute(b:line, '\\incfig{', '', '')]])
    vim.cmd([[let b:line = substitute(b:line, '}', '', '')]])

    root = vim.b.vimtex.root .. '/figures/'
    -- check if the file exists
    if vim.fn.filereadable(root .. vim.b.line .. '.svg') == 0 then
        -- print('inkscape-figures create ' .. vim.b.line .. ' ' .. root)
        vim.fn.system('inkscape-figures create ' .. vim.b.line .. ' ' .. root)
    else
        -- print('inkscape-figures edit ' .. root .. '/' .. vim.b.line .. '.svg')
        vim.fn.system(
            'inkscape-figures edit ' .. root .. '/' .. vim.b.line .. '.svg'
        )
    end
end

-- }}}
------------------------------------------------------------------------------

-- TODO: transform to lua
vim.api.nvim_exec(
    [[
      augroup VimtexTest
        autocmd!
        autocmd User VimtexEventCompileStopped lua TermPDFClose()
        autocmd User VimtexEventCompileSuccess lua VimtexCallback(1)
        autocmd User VimtexEventCompileStopped lua VimtexCallback(0)
        autocmd User VimtexEventCompileFailed lua VimtexCallback(0)
        autocmd User VimtexEventView lua VimtexCallback(1)
        autocmd FileType tex autocmd BufDelete <buffer> lua TermPDFClose()
        autocmd CursorHold,CursorHoldI,BufWritePost *.tex lua LiveTypeset(true)
        autocmd InsertLeave *.tex lua LiveTypeset(true)
      augroup end
    ]],
    false
)

------------------------------------------------------------------------------
-- Set keybindings {{{
------------------------------------------------------------------------------
if vim.g.set_shorcuts then
    vim.keymap.set(
        { 'n', 'i' },
        '<S-CR>',
        ':VimtexCompile<cr>',
        { noremap = true, silent = true }
    )
    vim.keymap.set(
        { 'i' },
        '<C-i>',
        '<esc><cmd>:lua InkscapeFigures()<cr>',
        { noremap = true, silent = true }
    )
    vim.keymap.set(
        { 'n' },
        '<C-w>',
        '<esc><cmd>:lua InkscapeFigures()<cr>',
        { noremap = true, silent = true }
    )
    vim.keymap.set(
        { 'n', 'i' },
        '<C-s>',
        '<cmd>:lua SyncTexView()<cr>',
        { noremap = true, silent = true }
    )
    vim.keymap.set(
        { 'n', 'i' },
        '<C-e>',
        '<esc><cmd>:lua SyncTexEdit()<cr>',
        { noremap = true, silent = true }
    )
end

-- }}}
------------------------------------------------------------------------------

return M

-- vim: foldmethod=marker
