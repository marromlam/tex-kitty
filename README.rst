tex-kitty
=========

A simple and lightweight TeX/LaTeX tool to compile and preview documents in the
Kitty terminal emulator.
It uses the `kitty` terminal emulator's image protocol to display the PDF
output of the TeX/LaTeX document side-by-side with the source code.


PREVIEW COMING SOON


Installation
------------
Using the lazy.nvim plugin manager, add the following line to your `init.vim`:
Lazy 'jbyuki/tex-kitty'

..code:block:: lua
    lua
    {
        'marromlam/tex-kitty'
        ft='tex',
        dependencies = {
            "lervag/vimtex",
        },
        config = function()
            require("tex-kitty").setup({
                tex_kitty_preview = 1,
            })
        end,
    }

Usage
-----
The plugin provides the following commands:
- [x] `:lua SyncTexView`: Update the PDF preview to the current line in the source code.
- [ ] `:lua SyncTexEdit`: Update the source code to the current page in the PDF preview.
- [x] `:lua TermPDF(pdf_file, page, force_reload)`: Open a new terminal window with the PDF preview.
- [x] `:lua TermPDFClose()`: Close the terminal window with the PDF preview.
- [x] `:lua InkscapeFigures()`: Open inkscape to edit the current figure. Also
  transforms the figure to a pdf_tex file.

The plugin also provides the following mappings:
- [x] `<S-CR>`: Turn on compliation and preview of the document.
- [x] `<C-i>`: Create/edit the figure under the cursor.
- [x] `<C-s>`: Sync the source code with the PDF preview.

When live_typeset is enable, the plugin will automatically compile the document
as the user types or moves around the document.
To disable this feature, set the `tex_kitty_preview` option to `false`.

Configuration
-------------
The plugin provides the following options:

.code-block:: lua

    DEFAULT_CONFIG = {
      set_shorcuts = true,
      live_enabled = true,
   }

To change the default configuration, use the `setup` function.







