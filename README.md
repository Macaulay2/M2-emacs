Emacs Package for Macaulay2
===========================

To get started with running Macaulay2 with Emacs, look at the file [`M2-emacs-help.txt`](M2-emacs-help.txt), which is a text version of the documentation node available via `help "running Macaulay2 in Emacs"`. To learn how to edit a file with Macaulay2 code in it using Emacs, see the file `M2-emacs.m2`, which is a text version of the documentation node available via `help "editing Macaulay2 code with Emacs"`.

`M2.el` provides `M2-mode`, for editing Macaulay2 source, and `M2-comint-mode`, for running a Macaulay2 session within an Emacs buffer. The syntax highlighting symbols are defined in `M2-symbols.el`. `M2-mode.el` is kept for compatibility with older configurations.

After installation, `M-x M2` starts a session. Opening an `.m2` file selects
`M2-mode` automatically, where F12 starts or switches to a session. To make F12
available in every buffer, add this to your Emacs configuration:

```elisp
(global-set-key (kbd "<f12>") #'M2)
```

## Usage

The main key bindings are:

| Key | Command | `.m2` buffers | Session buffer |
|---|---|:---:|:---:|
| F12 | Start or switch to a session | ✅ | ✅ |
| F11 | Send the current line (or the active region, in `.m2` buffers) | ✅ | ✅ |
| `C-RET` | Send the current line, or the region if active | ✅ |  |
| `C-c C-j` / `C-c C-r` / `C-c C-b` / `C-c C-p` | Send the line / region / buffer / paragraph | ✅ |  |
| `C-c C-<up>` / `C-c C-<down>` | Send from the start of the buffer to point / from point to the end | ✅ |  |
| `C-c TAB`, `M-TAB` | Complete the symbol at point | ✅ | ✅ |
| `TAB` | Complete the symbol at point |  | ✅ |
| F10 / `M-F10` | Move to the next / previous bracketed input | ✅ | ✅ |
| F2 or `C-c :` | Scroll horizontally to center point |  | ✅ |
| F3 or `C-c <` / F4 or `C-c >` | Scroll left / right |  | ✅ |
| `C-c C-t` | Toggle line truncation |  | ✅ |

With a prefix argument, the send commands ask which session buffer to send to.
Press `C-h m` in either mode for the full list of bindings, or use the
Macaulay2 menu in the menu bar, and see the help files mentioned above for a
walkthrough.

## Demos

Demo mode is for presenting Macaulay2 live, for example in a lecture or a talk
with a projector. You prepare the code you want to run in a script buffer that
the audience doesn't see. During the talk, only the Macaulay2 session is on
screen, in a separate frame with a large font. Each press of F11 in the session
brings the next line of the script to the prompt so the audience can read it,
and the next press runs it. You don't have to type during the talk or switch
windows, and the script itself stays off screen.

To give a demo:

1. Open the script, for example a `.m2` file, and press `M-F11` to make it the
   demo buffer.
2. Move point to the line where the demo should start.
3. Start a session with F12, then press `M-F12` to open the presentation frame
   for it. To present a different session, use `C-u M-F12`.
4. In that frame, press F11 repeatedly to step through the script. You can
   still type your own input at any point; F11 sends it as usual.
5. Close the frame with `C-x 5 0` when you're done.

| Key | Command | `.m2` buffers | Session buffer |
|---|---|:---:|:---:|
| `M-F11` | Make the current buffer the demo buffer | ✅ | ✅ |
| F11 | On a blank input line, fetch the next line of the demo buffer; otherwise send the input | | ✅ |
| `C-F11` | Switch to the demo buffer, for example to skip ahead or back | ✅ | ✅ |
| `M-F12` | Open a frame with a large font for presenting | ✅ | ✅ |

## Installation

### Installing from a distribution package

The Macaulay2 distribution packages typically install the M2 package somewhere in the `share/emacs/site-lisp` subdirectory of the installation prefix. For instance, on Ubuntu the package `elpa-macaulay2` is installed along with `macaulay2`, unless installing recommended packages is disabled. Therefore if Macaulay2 is installed from the distribution, this package already exists on your system.

If Emacs doesn't automatically find the package, you may need to start M2 in a terminal and run:
```m2
setupEmacs()
```

### Installing from the Macaulay2 package archive

Macaulay2 hosts a package archive containing the M2 package and related
packages such as [`ob-M2`](https://github.com/d-torrance/ob-M2), which provides
Org Babel support. Add it to your Emacs init file:

```elisp
(require 'package)
(add-to-list 'package-archives
             '("M2" . "https://macaulay2.com/Repositories/Emacs/") t)
```

Then run `M-x package-refresh-contents` followed by
`M-x package-install RET M2 RET`. With use-package, `(use-package M2 :ensure t)`
works once the archive has been added.

<!--
### Installing from MELPA

Alternatively, for those who would like to install the M2 package without installing Macaulay2 itself, you can install this package from MELPA:

1. Add the following to your Emacs init file (`~/.emacs`) to [enable the MELPA repository](https://melpa.org/#/getting-started):
```elisp
(package-initialize)

(setq package-archives '(("melpa" . "https://melpa.org/packages/")))
```

2. Press `M-x package-list-packages`, then find and install M2.
-->

### Installing a package tarball

Run `make dist` to create `dist/M2-<version>.tar` from the checked-in Lisp and
help files. Building the tarball requires standard shell tools; neither Emacs
nor Macaulay2 is needed. In Emacs, run `M-x package-install-file` and select the
tarball without unpacking it first.

Maintainers can also run the **Build package distribution** workflow manually
from the Actions tab to download the tarball as a workflow artifact.

### Installing with Emacs package managers

The M2 package can be installed with a single line of code using several package managers.

#### use-package

This requires Emacs version 30 or greater.

```elisp
(use-package M2
  :vc (:url "https://github.com/Macaulay2/M2-emacs")
  :bind ("<f12>" . M2))
```

#### [Quelpa](https://github.com/quelpa/quelpa)

```elisp
(quelpa '(M2 :repo "Macaulay2/M2-emacs" :fetcher github :files ("*.el")))
```

####  [straight.el](https://github.com/radian-software/straight.el)

```elisp
(straight-use-package '(M2 :type git :host github :repo "Macaulay2/M2-emacs" :files ("*.el")))
```

### Installing from the Git Repository

For those who like to live dangerously, or to develop this package, you can also install directly from this repository:

1. Clone this repository:
```bash
git clone https://github.com/Macaulay2/M2-emacs.git ~/.emacs.d/site-lisp/Macaulay2
```

2. Add the following to your Emacs init file:
```elisp
(add-to-list 'load-path "~/.emacs.d/site-lisp/Macaulay2")
(load "M2-init")
```

Using this method, you can fetch the most recent version of the package by running `git pull` in the `~/.emacs.d/site-lisp/Macaulay2` directory.

## Configuration

All options are in the `M2` customization group (`M-x customize-group RET M2`).
Those covered below are the most commonly changed; others include
`M2-indent-level` (default 4) and `M2-blink-region-flag` and `M2-blink-delay`,
which control the brief highlight of code sent to a session.

For a local installation outside `PATH`, customize `M2-exe`, for example:

```elisp
(setq M2-exe "/opt/Macaulay2/bin/M2")
```

When `M2-command` is nil (the default), the command is constructed from `M2-exe`
each time a new session is started. Existing custom `M2-command` strings remain
supported. To use a remote or container installation, for example when
Macaulay2 isn't installed locally or the version on a shared machine is too old,
set the complete shell command instead. Your files stay on your local machine
either way:

```elisp
(setq M2-command "ssh my-server M2 --no-readline")
;; Or:
(setq M2-command "docker run --rm -i <image> M2 --no-readline")
```

`C-u M-x M2` lets you edit the command for a session. Emacs does not install M2
itself. Use your operating system's package manager or M2's installation guide.

`C-u C-u M-x M2` also asks for a name, so you can run several sessions side by
side, for example a local `*M2*` and a remote `*M2-server*` (enter the name
without the asterisks). Later uses of F12 go to the most recently named session,
and the send commands accept a prefix argument to choose which session receives
the code.

The `infoHelp` function in M2 opens Texinfo documentation in Emacs. If the local
manuals are outside the standard Info directories, add their directory to your
Emacs configuration so links between package manuals also work:

```elisp
(with-eval-after-load 'info
  (add-to-list 'Info-additional-directory-list "/opt/Macaulay2/share/info"))
```

This supplements the standard search paths in `Info-default-directory-list`.
A remote M2 session does not automatically make its documentation available to
local Emacs.

To hide the literal `*Note` markers in cross-references, use the following setting.
It affects all Texinfo manuals viewed in Emacs, including manuals unrelated to M2:

```elisp
(setq Info-hide-note-references 'hide)
```

## Language-server support

Choose Eglot or lsp-mode and register `M2-mode` in your Emacs configuration.
For Eglot (included in Emacs 29 and later):

```elisp
(with-eval-after-load 'eglot
  (M2-register-eglot))
```

For lsp-mode:

```elisp
(with-eval-after-load 'lsp-mode
  (M2-register-lsp))
```

The registration functions are autoloaded by the Emacs package manager and by
`M2-init.el`, which `setupEmacs()` configures Emacs to load. For a manual
checkout, load `M2` before using them. These configuration forms work whether
the client is already loaded or is loaded later. Upgrading users should add the
appropriate form: loading `M2` no longer registers clients automatically.

Open an `.m2` file and run `M-x eglot` or `M-x lsp`.
The language server is supplied by M2's
`LanguageServer` package and `M2-language-server` executable, not by this Emacs
package. An older M2 installation may not provide it.

By default, both clients look for `M2-language-server` beside the executable
selected by `M2-exe`, then fall back to Emacs's `exec-path`. This avoids needing
`setupEmacs()` to modify `PATH`. For a custom or remote installation, set a list
of program and arguments (not a shell command string):

```elisp
(setq M2-language-server-command '("/opt/Macaulay2/bin/M2-language-server"))
;; Or:
(setq M2-language-server-command '("ssh" "my-server" "M2-language-server"))
```

`M2-command` configures the interactive session only; it does not select an LSP
server. Configure the LSP command separately when using SSH or containers, and
ensure that the server can access the document paths used by the client.
A launcher outside `PATH` must itself locate the matching M2 executable; this
is addressed by Macaulay2/M2#4453. If that fix is absent, ensure the matching M2
bin directory is on the server process's `PATH` as well.

## Contributing

Contributions are welcome! Please submit pull requests.
