-- This is a lua module to be used with neovim and vimtex
-- It provides a live preview of the pdf file in a kitty terminals
-- It also provides some keybindings to compile the pdf and to
-- open the pdf in the correct page
-- It also provides a function to create and edit svg files with inkscape
-- It also provides a function to sync the current line in the tex file
-- with the pdf file
--

local M = {}

------------------------------------------------------------------------------
-- Configuration {{{

-- save globally
vim.g.__tex_kitty_module_was_loaded = true
if vim.g.__tex_kitty_module_was_loaded then return end

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
        vim.cmd([[:w]])
        vim.g.live_typeset_last_called = 0
        vim.g.live_typeset_triggered = true
    else
        local time = tonumber(vim.fn.reltimefloat(vim.fn.reltime())) * 1000.0
        if not vim.g.live_typeset_triggered then
            if time - vim.g.live_typeset_last_called > 1000 then
                -- this will trigger the live preview every
                -- 1s after the last save
                -- save current buffer, so that the pdf is updated
                vim.cmd([[:w]])
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
    print('cache_file: ' .. cache_file)
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
    print(vim.inspect(t))
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

    print('kitty @' .. kitty_to .. 'launch --title=live_preview')

    local reload = false
    local time = tonumber(vim.fn.reltimefloat(vim.fn.reltime())) * 1000.0
    if time - vim.g.termpdf_lastcalled > 1000 then reload = true end

    if force_reload then reload = true end

    if reload then
        -- vim.fn.system("kitty @ set-background-opacity 1.0")
        -- 1. open a new kitty window
        if not vim.g.termpdf_panelopened then
            vim.fn.system(
                'kitty @' .. kitty_to .. 'launch --title=live_preview'
            )
            -- if on ssh, ssh into the machine
            if ssh_tty then
                local hostname = vim.fn.system('hostname')
                vim.fn.system(
                    'kitty @'
                        .. kitty_to
                        .. 'send-text --match title:live_preview "ssh '
                        .. hostname
                        .. '\n"'
                )
                vim.fn.sleep(1000)
            end
            vim.g.termpdf_panelopened = true
        end

        -- 2. send the file to the new window
        vim.fn.system(
            'kitty @'
                .. kitty_to
                .. 'kitten kittens/termpdf.py '
                .. pdf_file
                .. ' '
                .. pdf_page
        )
        vim.g.termpdf_lastcalled = time
    end
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
        vim.api.nvim_out_write('Compilation unsuccesful!\n')
    end
end

function M.InkscapeFigures()
    -- Get the current line
    vim.cmd([[let b:line = getline('.')]])
    -- remove \incfig{ and } in lua
    vim.cmd([[let b:line = substitute(b:line, '\\incfig{', '', '')]])
    vim.cmd([[let b:line = substitute(b:line, '}', '', '')]])

    local root = vim.b.vimtex.root .. '/figures/'
    -- check if the file exists
    if vim.fn.filereadable(root .. vim.b.line .. '.svg') == 0 then
        vim.fn.system('inkscape-figures create ' .. vim.b.line .. ' ' .. root)
    else
        vim.fn.system('inkscape-figures edit ' .. vim.b.line .. ' ' .. root)
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
        { noremap = true, silent = false }
    )
    vim.keymap.set(
        { 'i' },
        '<C-i>',
        '<esc><cmd>:lua InkscapeFigures()<cr>',
        { noremap = true, silent = false }
    )
    vim.keymap.set(
        { 'n', 'i' },
        '<C-s>',
        '<esc><cmd>:lua SyncTexView()<cr>',
        { noremap = true, silent = false }
    )
    vim.keymap.set(
        { 'n', 'i' },
        '<C-e>',
        '<esc><cmd>:lua SyncTexEdit()<cr>',
        { noremap = true, silent = false }
    )
end

-- }}}
------------------------------------------------------------------------------

return M

-- vim: foldmethod=marker
