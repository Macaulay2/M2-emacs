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

For a local installation outside `PATH`, customize `M2-exe`, for example:

```elisp
(setq M2-exe "/opt/Macaulay2/bin/M2")
```

When `M2-command` is nil (the default), the command is constructed from `M2-exe`
each time a new session is started. Existing custom `M2-command` strings remain
supported. To use a remote or container installation, set the complete shell
command instead:

```elisp
(setq M2-command "ssh my-server M2 --no-readline")
```

`C-u M-x M2` lets you edit the command for a session. Emacs does not install M2
itself. Use your operating system's package manager or M2's installation guide.

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

The registration functions are autoloaded by the Emacs package manager. For a
manual checkout, load `M2` before using them. These configuration forms work
whether the client is already loaded or is loaded later. Upgrading users should
add the appropriate form: loading `M2` no longer registers clients automatically.

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

## Why install the M2 package without Macaulay2?

Under certain circumstances, users who are unable to install Macaulay2 locally (e.g. the version provided by the university cluster is too old) can still use this package and choose an alternative method for running the Macaulay2 executable:

1. Press `C-u F12` to choose how to run M2, for instance:
  - Remotely via SSH, e.g. `ssh math.umn.edu M2 --no-readline --print-width 125`
  - Remotely via SSH to a containerized version of Habanero!
  - Locally via Docker, e.g. `docker run -it --entrypoint M2 mahrud/macaulay2:v1.15`

2. Press `M-x M2` to start Macaulay2.

Using this package, any machine running Emacs can run M2 via SSH or Docker, and your files would still be saved locally.

## Contributing

Contributions are welcome! Please submit pull requests.
