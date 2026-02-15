# tex-kitty

A lightweight Neovim plugin for TeX/LaTeX that compiles documents and opens
live PDF preview in a side pane (kitty/tmux/zellij).

The preview command is now powered by ``pdfcat`` (configurable).



https://github.com/user-attachments/assets/638f51e5-42d4-48c1-a62f-a4675efaf866




## Installation


Example with lazy.nvim:

```lua

    {
      'marromlam/tex-kitty',
      ft = 'tex',
      dependencies = {
        'lervag/vimtex',
      },
      config = function()
        require('tex-kitty').setup({
          live_enabled = true,
          viewer_cmd = 'pdfcat',
          viewer_args = {},
          force_tinted = true,
          backend = 'tmux',
        })
      end,
    }
```

## Requirements

- Neovim
- vimtex
- ``pdfcat`` in ``PATH`` (or configure ``viewer_cmd``)
- ``synctex`` command available


## Usage

Commands:

- ``:PdfCat [page]``: manually open/update preview for current TeX/PDF buffer.
- ``:ViewPDF [page]``: alias for ``:PdfCat`` (backward compatibility).
- ``:lua SyncTexView()``: jump preview to the current source line.
- ``:lua SyncTexEdit()``: trigger reverse SyncTeX (PDF -> source) in the preview pane.
- ``:lua PdfCat(pdf_file, page, force_reload)``: open/update preview pane.
- ``:lua PdfCatClose()``: close preview pane.
- ``:lua InkscapeFigures()``: create/edit figure under cursor.

Default mappings:

- ``<S-CR>`` / ``<S-Enter>``: compile with vimtex
- ``<F13>``: compile fallback (useful with tmux remap from ``S-Enter``)
- ``<C-i>``: create/edit figure
- ``<C-s>``: SyncTeX source -> preview
- ``<C-e>``: trigger reverse SyncTeX in preview pane


## Configuration

```lua

    {
      set_shorcuts = true,
      live_enabled = true,
      viewer_cmd = 'pdfcat',
      viewer_args = {},      -- extra args appended before file path
      force_tinted = true,   -- append --force-tinted to viewer command
      backend = 'tmux',      -- tmux|kitty|auto|zellij
      panel_title = 'live_preview',
    }

```

## Notes


- ``SyncTexView`` now drives preview via CLI page argument (``-p``), not cache-file edits.
- Reverse SyncTeX from viewer uses ``Ctrl+S`` in ``pdfcat``.
- If ``Ctrl+S`` is intercepted by terminal flow control, run ``stty -ixon``.
- Default backend is tmux. Use backend kitty for right-side kitty panes, or backend auto for environment-based detection.
