-- This is a lua module to be used with neovim and vimtex
-- It provides a live preview of the pdf file in kitty/tmux/zellij panes.

local M = {}

if not vim.g.__tex_kitty_module_was_loaded then
    vim.fn.system('pdftex-figures watch')
end
vim.g.__tex_kitty_module_was_loaded = true

------------------------------------------------------------------------------
-- Configuration {{{

local DEFAULT_CONFIG = {
    set_shorcuts = true,
    live_enabled = true,
    viewer_cmd = 'pdfcat',
    viewer_args = {},
    force_tinted = true,
    backend = 'tmux', -- tmux|kitty|auto|zellij
    panel_title = 'live_preview',
    presenter_enabled = true,
    presenter_title = 'live_presenter',
    presenter_session_prefix = 'tex_kitty_presenter',
}

M.config = vim.tbl_deep_extend('force', {}, DEFAULT_CONFIG)

vim.g.pdfcat_panel_opened = false
vim.g.pdfcat_last_called = 0
vim.g.tex_kitty_backend = nil
vim.g.tex_kitty_tmux_pane = ''
vim.g.tex_kitty_kitty_window = ''
vim.g.tex_kitty_current_pdf = ''
vim.g.tex_kitty_tmux_presenter_session = ''
vim.g.tex_kitty_tmux_presenter_window = ''
vim.g.tex_kitty_tmux_presenter_pane = ''
vim.g.tex_kitty_presenter_kitty_window = ''

vim.g.live_enabled = true
vim.g.live_typeset_triggered = false
vim.g.live_typeset_last_called = 0
vim.g.set_shorcuts = true

local kitty_to = ' '
if vim.fn.empty(vim.fn.getenv('SSH_TTY')) == 0 then
    kitty_to = ' --to=tcp:localhost:$KITTY_PORT '
end

function M.setup(user_config)
    user_config = user_config or {}
    M.config = vim.tbl_deep_extend('force', DEFAULT_CONFIG, user_config)

    vim.g.set_shorcuts = M.config.set_shorcuts
    vim.g.live_enabled = M.config.live_enabled
end

-- }}}
------------------------------------------------------------------------------

local function shell_quote_if_needed(value)
    local s = tostring(value)
    if s == '' then return "''" end
    if s:match('[^%w%-%._/:]') then return vim.fn.shellescape(s) end
    return s
end

local function normalize_path(path)
    if path == nil or path == '' then return '' end
    return vim.fn.fnamemodify(path, ':p')
end

local function detect_backend()
    if M.config.backend ~= 'auto' then return M.config.backend end

    if vim.fn.empty(vim.fn.getenv('TMUX')) == 0 then return 'tmux' end
    if vim.fn.empty(vim.fn.getenv('ZELLIJ')) == 0 then return 'zellij' end
    return 'kitty'
end

local function build_viewer_command(pdf_file, pdf_page)
    local args = { ' ' .. tostring(M.config.viewer_cmd) }
    local has_force_tinted = false
    local has_nvim_listen_address = false
    local viewer_basename =
        vim.fn.fnamemodify(tostring(M.config.viewer_cmd), ':t')
    local viewer_is_pdfcat = (
        viewer_basename == 'pdfcat' or viewer_basename == 'termpdf.py'
    )

    if type(M.config.viewer_args) == 'table' then
        for _, arg in ipairs(M.config.viewer_args) do
            table.insert(args, shell_quote_if_needed(arg))
            if tostring(arg) == '--force-tinted' then
                has_force_tinted = true
            end
            if tostring(arg) == '--nvim-listen-address' then
                has_nvim_listen_address = true
            end
        end
    elseif
        type(M.config.viewer_args) == 'string'
        and M.config.viewer_args ~= ''
    then
        table.insert(args, shell_quote_if_needed(M.config.viewer_args))
        has_force_tinted = string.find(
            M.config.viewer_args,
            '--force-tinted',
            1,
            true
        ) ~= nil
        has_nvim_listen_address = string.find(
            M.config.viewer_args,
            '--nvim-listen-address',
            1,
            true
        ) ~= nil
    end

    if viewer_is_pdfcat and M.config.force_tinted and not has_force_tinted then
        table.insert(args, '--force-tinted')
    end

    local nvim_server = tostring(vim.v.servername or '')
    if
        viewer_is_pdfcat
        and nvim_server ~= ''
        and not has_nvim_listen_address
    then
        table.insert(args, '--nvim-listen-address')
        table.insert(args, shell_quote_if_needed(nvim_server))
    end

    if pdf_page ~= nil and tostring(pdf_page) ~= '' then
        table.insert(args, '-p')
        table.insert(args, tostring(pdf_page))
    end

    -- Keep filename shell-escaped, but leave command/flags readable.
    table.insert(args, vim.fn.shellescape(pdf_file))
    return table.concat(args, ' ')
end

local function send_reverse_synctex_trigger(backend)
    if backend == 'kitty' then
        local kitty_match = 'title:' .. M.config.panel_title
        if
            vim.g.tex_kitty_kitty_window ~= nil
            and vim.g.tex_kitty_kitty_window ~= ''
        then
            kitty_match = 'id:' .. vim.g.tex_kitty_kitty_window
        end
        vim.fn.system(
            'kitty @'
                .. kitty_to
                .. 'send-key --match '
                .. kitty_match
                .. ' ctrl+s'
        )
        return true
    end

    if backend == 'tmux' then
        if vim.g.tex_kitty_tmux_pane == '' then return false end
        vim.fn.system(
            'tmux send-keys -t ' .. vim.g.tex_kitty_tmux_pane .. ' C-s'
        )
        return true
    end

    if backend == 'zellij' then
        local ctrl_s = vim.fn.nr2char(19)
        vim.fn.system(
            'zellij action write-chars --pane-name '
                .. M.config.panel_title
                .. ' '
                .. vim.fn.shellescape(ctrl_s)
        )
        return true
    end

    return false
end

local function tmux_send_command_to_pane(pane_id, cmd)
    if pane_id == nil or pane_id == '' then return false end
    vim.fn.system('tmux send-keys -t ' .. pane_id .. ' C-c')
    vim.fn.system(
        'tmux send-keys -t ' .. pane_id .. ' -l ' .. vim.fn.shellescape(cmd)
    )
    vim.fn.system('tmux send-keys -t ' .. pane_id .. ' C-m')
    return true
end

local function tmux_send_jump_to_pane(pane_id, jump)
    if pane_id == nil or pane_id == '' then return false end
    vim.fn.system('tmux send-keys -t ' .. pane_id .. ' Escape')
    for ch in jump:gmatch('.') do
        vim.fn.system(
            'tmux send-keys -t ' .. pane_id .. ' ' .. vim.fn.shellescape(ch)
        )
    end
    return true
end

local function close_presenter_mode()
    if
        vim.g.tex_kitty_presenter_kitty_window ~= nil
        and vim.g.tex_kitty_presenter_kitty_window ~= ''
    then
        vim.fn.system(
            'kitty @'
                .. kitty_to
                .. 'close-window --match id:'
                .. vim.g.tex_kitty_presenter_kitty_window
        )
    end

    if
        vim.g.tex_kitty_tmux_presenter_session ~= nil
        and vim.g.tex_kitty_tmux_presenter_session ~= ''
    then
        vim.fn.system(
            'tmux kill-session -t '
                .. shell_quote_if_needed(vim.g.tex_kitty_tmux_presenter_session)
        )
    elseif
        vim.g.tex_kitty_tmux_presenter_window ~= nil
        and vim.g.tex_kitty_tmux_presenter_window ~= ''
    then
        vim.fn.system(
            'tmux kill-window -t ' .. vim.g.tex_kitty_tmux_presenter_window
        )
    elseif
        vim.g.tex_kitty_tmux_presenter_pane ~= nil
        and vim.g.tex_kitty_tmux_presenter_pane ~= ''
    then
        vim.fn.system(
            'tmux kill-pane -t ' .. vim.g.tex_kitty_tmux_presenter_pane
        )
    end

    vim.g.tex_kitty_tmux_presenter_session = ''
    vim.g.tex_kitty_tmux_presenter_window = ''
    vim.g.tex_kitty_tmux_presenter_pane = ''
    vim.g.tex_kitty_presenter_kitty_window = ''
end

local function launch_panel_if_needed(backend)
    if vim.g.pdfcat_panel_opened then return end

    if backend == 'kitty' then
        local launch_output = vim.fn.system(
            'kitty @'
                .. kitty_to
                .. 'launch --location=vsplit --cwd=current --copy-env --allow-remote-control --title='
                .. M.config.panel_title
        )
        vim.g.tex_kitty_kitty_window = vim.trim(launch_output or '')
        vim.fn.sleep(80)
        vim.g.pdfcat_panel_opened = true
        return
    end

    if backend == 'tmux' then
        local panes_before =
            vim.fn.systemlist('tmux list-panes -F "#{pane_id}"')
        vim.fn.system('tmux split-window -d -h')
        local panes_after = vim.fn.systemlist('tmux list-panes -F "#{pane_id}"')

        for _, pane in ipairs(panes_after) do
            if not vim.tbl_contains(panes_before, pane) then
                vim.g.tex_kitty_tmux_pane = pane
                break
            end
        end

        if vim.g.tex_kitty_tmux_pane ~= '' then
            vim.fn.system(
                'tmux select-pane -t '
                    .. vim.g.tex_kitty_tmux_pane
                    .. ' -T '
                    .. M.config.panel_title
            )
            vim.g.pdfcat_panel_opened = true
        end
        return
    end

    if backend == 'zellij' then
        vim.fn.system('zellij action new-pane --name ' .. M.config.panel_title)
        vim.g.pdfcat_panel_opened = true
        return
    end

    print('No supported terminal multiplexer found')
end

local function send_viewer_command(backend, cmd)
    if backend == 'kitty' then
        local kitty_match = 'title:' .. M.config.panel_title
        if
            vim.g.tex_kitty_kitty_window ~= nil
            and vim.g.tex_kitty_kitty_window ~= ''
        then
            kitty_match = 'id:' .. vim.g.tex_kitty_kitty_window
        end

        vim.fn.system(
            'kitty @'
                .. kitty_to
                .. 'send-text --match '
                .. kitty_match
                .. ' '
                .. vim.fn.shellescape(cmd .. '\n')
        )
        return true
    end

    if backend == 'tmux' then
        local sent_main =
            tmux_send_command_to_pane(vim.g.tex_kitty_tmux_pane, cmd)
        if
            vim.g.tex_kitty_tmux_presenter_pane ~= nil
            and vim.g.tex_kitty_tmux_presenter_pane ~= ''
        then
            tmux_send_command_to_pane(vim.g.tex_kitty_tmux_presenter_pane, cmd)
        end
        return sent_main
    end

    if backend == 'zellij' then
        vim.fn.system(
            'zellij action write-chars --pane-name '
                .. M.config.panel_title
                .. ' '
                .. vim.fn.shellescape(cmd .. '\n')
        )
        return true
    end

    return false
end

local function send_page_jump(backend, page)
    if page == nil or tostring(page) == '' then return true end

    local n = tonumber(page)
    if n == nil then return false end

    local jump = tostring(math.floor(n)) .. 'G'

    if backend == 'kitty' then
        local kitty_match = 'title:' .. M.config.panel_title
        if
            vim.g.tex_kitty_kitty_window ~= nil
            and vim.g.tex_kitty_kitty_window ~= ''
        then
            kitty_match = 'id:' .. vim.g.tex_kitty_kitty_window
        end
        vim.fn.system(
            'kitty @'
                .. kitty_to
                .. 'send-text --match '
                .. kitty_match
                .. ' '
                .. vim.fn.shellescape(jump)
        )
        return true
    end

    if backend == 'tmux' then
        local jumped_main =
            tmux_send_jump_to_pane(vim.g.tex_kitty_tmux_pane, jump)
        if
            vim.g.tex_kitty_tmux_presenter_pane ~= nil
            and vim.g.tex_kitty_tmux_presenter_pane ~= ''
        then
            tmux_send_jump_to_pane(vim.g.tex_kitty_tmux_presenter_pane, jump)
        end
        return jumped_main
    end

    if backend == 'zellij' then
        vim.fn.system(
            'zellij action write-chars --pane-name '
                .. M.config.panel_title
                .. ' '
                .. vim.fn.shellescape(jump)
        )
        return true
    end

    return false
end

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
                vim.cmd([[:silent! write]])
                vim.g.live_typeset_last_called = time
                vim.g.live_typeset_triggered = true
            end
        end
        vim.g.live_typeset_last_called = time
    end
end

function SyncTexView()
    local line = vim.fn.line('.')
    local tex_file = vim.fn.expand('%:p')
    local pdf_file = vim.fn.expand('%:p:r') .. '.pdf'

    if vim.b.vimtex and vim.b.vimtex.base then
        local vimtex_pdf = vim.b.vimtex.base:gsub('.tex$', '.pdf')
        if vim.fn.filereadable(vimtex_pdf) == 1 then pdf_file = vimtex_pdf end
    end

    if vim.fn.filereadable(pdf_file) == 0 then return end

    local synctex_cmd = 'synctex view -i '
        .. tostring(line)
        .. ':1:'
        .. vim.fn.shellescape(tex_file)
        .. ' -o '
        .. vim.fn.shellescape(pdf_file)
    local synctex = io.popen(synctex_cmd)

    local page = nil
    if synctex ~= nil then
        local output = synctex:read('*a') or ''
        page = tonumber(output:match('Page:%s*(%d+)'))
        synctex:close()
    end

    if page then
        -- For SyncTeX accuracy, relaunch viewer command in the existing pane at target page.
        -- This keeps the pane while avoiding fragile in-app key feeding.
        PdfCat(pdf_file, page, true)
    end
end

function SyncTexEdit()
    if not vim.g.pdfcat_panel_opened then
        print('Preview pane is not open')
        return
    end
    local backend = vim.g.tex_kitty_backend or detect_backend()
    local sent = send_reverse_synctex_trigger(backend)
    if not sent then
        print('Failed to trigger reverse SyncTeX in preview pane')
    end
end

function PdfCat(pdf_file, pdf_page, force_reload)
    pdf_page = pdf_page or ''
    force_reload = force_reload or false

    pdf_file = normalize_path(pdf_file)

    if vim.fn.filereadable(pdf_file) == 0 then return end

    local time = tonumber(vim.fn.reltimefloat(vim.fn.reltime())) * 1000.0

    local backend = detect_backend()
    vim.g.tex_kitty_backend = backend

    local same_pdf_open = (
        vim.g.pdfcat_panel_opened
        and vim.g.tex_kitty_current_pdf ~= nil
        and normalize_path(vim.g.tex_kitty_current_pdf) == pdf_file
    )

    if same_pdf_open and not force_reload then
        if tostring(pdf_page) ~= '' then
            local jumped = send_page_jump(backend, pdf_page)
            if not jumped then
                print('Failed to jump to page in existing preview pane')
            end
        end
        vim.g.pdfcat_last_called = time
        vim.g.live_typeset_triggered = false
        return
    end

    if
        vim.g.pdfcat_panel_opened
        and vim.g.tex_kitty_current_pdf ~= ''
        and normalize_path(vim.g.tex_kitty_current_pdf) ~= pdf_file
    then
        PdfCatClose()
    end

    if
        force_reload
        or not vim.g.pdfcat_panel_opened
        or (time - vim.g.pdfcat_last_called > 1000)
    then
        launch_panel_if_needed(backend)
    end

    local viewer_cmd = build_viewer_command(pdf_file, pdf_page)
    local sent = send_viewer_command(backend, viewer_cmd)

    if not sent then
        print('Failed to send viewer command to preview pane')
        return
    end

    vim.g.tex_kitty_current_pdf = pdf_file
    vim.g.pdfcat_last_called = time
    vim.g.live_typeset_triggered = false
end

function PdfCatClose()
    local backend = vim.g.tex_kitty_backend or detect_backend()

    if backend == 'kitty' then
        local kitty_match = 'title:' .. M.config.panel_title
        if
            vim.g.tex_kitty_kitty_window ~= nil
            and vim.g.tex_kitty_kitty_window ~= ''
        then
            kitty_match = 'id:' .. vim.g.tex_kitty_kitty_window
        end
        vim.fn.system(
            'kitty @' .. kitty_to .. 'close-window --match ' .. kitty_match
        )
        vim.g.tex_kitty_kitty_window = ''
    elseif backend == 'tmux' then
        if vim.g.tex_kitty_tmux_pane ~= '' then
            vim.fn.system('tmux kill-pane -t ' .. vim.g.tex_kitty_tmux_pane)
            vim.g.tex_kitty_tmux_pane = ''
        end
    elseif backend == 'zellij' then
        vim.fn.system(
            'zellij action close-pane --pane-name ' .. M.config.panel_title
        )
    end

    close_presenter_mode()

    vim.g.pdfcat_panel_opened = false
    vim.g.tex_kitty_current_pdf = ''
end

function VimtexCallback(status)
    local pdf_file = vim.b.vimtex.base
    pdf_file = pdf_file:gsub('.tex$', '.pdf')
    if status then
        if vim.fn.filereadable(pdf_file) == 1 then PdfCat(pdf_file) end
    elseif vim.fn.filereadable(pdf_file) == 1 then
        PdfCat(pdf_file)
    end
end

function InkscapeFigures()
    vim.cmd([[let b:line = getline('.')]])
    vim.cmd([[let b:line = substitute(b:line, '\\incfig{', '', '')]])
    vim.cmd([[let b:line = substitute(b:line, '}', '', '')]])

    local root = vim.b.vimtex.root .. '/figures/'
    local file_ext = '.afdesign'

    if vim.fn.filereadable(root .. vim.b.line .. file_ext) == 0 then
        vim.fn.system('pdftex-figures create ' .. vim.b.line .. ' ' .. root)
    else
        vim.fn.system(
            'pdftex-figures edit ' .. root .. '/' .. vim.b.line .. file_ext
        )
    end
end

local function resolve_pdf_for_current_buffer()
    local current_file = vim.fn.expand('%:p')
    if current_file == '' then
        return nil, 'PdfCat: current buffer has no file path'
    end

    if current_file:match('%.pdf$') then return current_file, nil end

    if current_file:match('%.tex$') then
        local direct_pdf = current_file:gsub('%.tex$', '.pdf')
        if vim.fn.filereadable(direct_pdf) == 1 then return direct_pdf, nil end
    end

    if vim.b.vimtex and vim.b.vimtex.base then
        local vimtex_pdf = vim.b.vimtex.base:gsub('%.tex$', '.pdf')
        if vim.fn.filereadable(vimtex_pdf) == 1 then return vimtex_pdf, nil end
    end

    return nil, 'PdfCat: could not resolve a readable PDF for current buffer'
end

local function open_presenter_mode()
    if not M.config.presenter_enabled then
        print('Presenter mode is disabled in tex-kitty config')
        return
    end

    local backend = detect_backend()
    if backend ~= 'tmux' then
        print('Presenter mode currently requires backend=tmux')
        return
    end

    M.ensure_viewer_running()
    if vim.g.tex_kitty_tmux_pane == nil or vim.g.tex_kitty_tmux_pane == '' then
        print('Main preview pane is not available')
        return
    end

    local pdf_file = normalize_path(vim.g.tex_kitty_current_pdf or '')
    if pdf_file == '' or vim.fn.filereadable(pdf_file) == 0 then
        local resolved_pdf, err = resolve_pdf_for_current_buffer()
        if not resolved_pdf then
            print(err)
            return
        end
        pdf_file = normalize_path(resolved_pdf)
    end

    local prefix =
        tostring(M.config.presenter_session_prefix or 'tex_kitty_presenter')
    prefix = prefix:gsub('%s+', '_')
    local presenter_session = prefix
        .. '_'
        .. tostring(vim.fn.getpid())
        .. '_'
        .. tostring(vim.fn.localtime())

    local create_cmd = 'tmux new-session -d -P -F "#{session_name} #{window_id} #{pane_id}" -s '
        .. shell_quote_if_needed(presenter_session)
    local create_output = vim.fn.system(create_cmd)
    if vim.v.shell_error ~= 0 then
        print('Failed to create presenter tmux session')
        return
    end

    local fields =
        vim.split(vim.trim(create_output or ''), '%s+', { trimempty = true })
    if #fields < 3 then
        print('Failed to parse presenter session details')
        return
    end

    local presenter_session_name = fields[1]
    local presenter_window_id = fields[2]
    local presenter_pane_id = fields[3]

    vim.g.tex_kitty_tmux_presenter_session = presenter_session_name
    vim.g.tex_kitty_tmux_presenter_window = presenter_window_id
    vim.g.tex_kitty_tmux_presenter_pane = presenter_pane_id

    vim.fn.system(
        'tmux select-pane -t '
            .. presenter_pane_id
            .. ' -T '
            .. shell_quote_if_needed(M.config.presenter_title)
    )

    local viewer_cmd = build_viewer_command(pdf_file, '')
    if not tmux_send_command_to_pane(presenter_pane_id, viewer_cmd) then
        close_presenter_mode()
        print('Failed to launch viewer in presenter pane')
        return
    end

    local attach_cmd = 'tmux attach-session -t '
        .. shell_quote_if_needed(presenter_session_name)
    local launch_cmd = 'kitty @'
        .. kitty_to
        .. 'launch --type=os-window --cwd=current --copy-env --allow-remote-control --title='
        .. shell_quote_if_needed(M.config.presenter_title)
        .. ' sh -lc '
        .. vim.fn.shellescape(attach_cmd)
    local launch_output = vim.fn.system(launch_cmd)
    if vim.v.shell_error ~= 0 then
        close_presenter_mode()
        print('Failed to launch presenter kitty window')
        return
    end

    vim.g.tex_kitty_presenter_kitty_window = vim.trim(launch_output or '')
    print('Presenter mode enabled')
end

function PdfCatPresenterToggle()
    if
        vim.g.tex_kitty_tmux_presenter_session ~= nil
        and vim.g.tex_kitty_tmux_presenter_session ~= ''
    then
        close_presenter_mode()
        print('Presenter mode disabled')
        return
    end
    open_presenter_mode()
end

local function pdfcat_command(opts)
    local pdf_file, err = resolve_pdf_for_current_buffer()
    if not pdf_file then
        print(err)
        return
    end

    local page = ''
    if opts and opts.args and opts.args ~= '' then
        local parsed_page = tonumber(opts.args)
        if parsed_page == nil then
            print('PdfCat: optional page argument must be a number')
            return
        end
        page = parsed_page
    end

    PdfCat(pdf_file, page, true)
end

function M.ensure_viewer_running()
    if vim.g.pdfcat_panel_opened then return end
    vim.cmd('silent! PdfCat')
end

if vim.fn.exists(':PdfCat') == 2 then
    pcall(vim.api.nvim_del_user_command, 'PdfCat')
end
vim.api.nvim_create_user_command('PdfCat', pdfcat_command, {
    nargs = '?',
    desc = 'Open/update preview for current TeX/PDF buffer (optional page)',
})

-- }}}
------------------------------------------------------------------------------

vim.api.nvim_exec(
    [[
      augroup VimtexTest
        autocmd!
        autocmd User VimtexEventCompileSuccess lua require('tex-kitty').ensure_viewer_running()
        autocmd User LiveTypesetSucceeded lua require('tex-kitty').ensure_viewer_running()
        autocmd User VimtexEventView lua require('tex-kitty').ensure_viewer_running()
        autocmd QuitPre * lua pcall(PdfCatClose)
        autocmd VimLeavePre * lua pcall(PdfCatClose)
        autocmd FileType tex autocmd BufDelete <buffer> lua PdfCatClose()
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
    local compile_map_rhs = '<cmd>VimtexCompile<cr>'
    vim.keymap.set(
        { 'n', 'i' },
        '<S-CR>',
        compile_map_rhs,
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
