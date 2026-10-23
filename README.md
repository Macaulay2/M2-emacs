Emacs Package for Macaulay2
===========================

To get started with running Macaulay2 with Emacs, look at the file [`M2-emacs-help.txt`](M2-emacs-help.txt), which is a text version of the documentation node available via `help "running Macaulay2 in Emacs"`. To learn how to edit a file with Macaulay2 code in it using Emacs, see the file `M2-emacs.m2`, which is a text version of the documentation node available via `help "editing Macaulay2 code with Emacs"`.

The files `M2.el` and `M2-mode.el` provide modes for editing Macaulay2 source in Emacs and running a Macaulay2 session within an Emacs buffer. The syntax highlighting symbols are defined in `M2-symbols.el`.

## Installation

### Installing from a distribution package

The Macaulay2 distribution packages typically install the M2-mode package somewhere in the `share/emacs/site-lisp` subdirectory of the installation prefix. For instance, on Ubuntu the package `elpa-macaulay2` is installed along with `macaulay2`, unless installing recommended packages is disabled. Therefore if Macaulay2 is installed from the distribution, this package already exists on your system.

If Emacs doesn't automatically find the package, you may need to start M2 in a terminal and run:
```m2
setupEmacs()
```

<!--
### Installing from MELPA

Alternatively, for those who would like to install M2-mode without installing Macaulay2 itself, you can install this package from MELPA:

1. Add the following to your Emacs init file (`~/.emacs`) to [enable the MELPA repository](https://melpa.org/#/getting-started):
```elisp
(package-initialize)

(setq package-archives '(("melpa" . "https://melpa.org/packages/")))
```

2. Press `M-x package-list-packages`, then find and install M2-mode.
-->

### Installing a package tarball

Run `make dist` to create `dist/M2-<version>.tar` from the checked-in Lisp and
help files. Building the tarball requires standard shell tools; neither Emacs
nor Macaulay2 is needed. In Emacs, run `M-x package-install-file` and select the
tarball without unpacking it first.

Maintainers can also run the **Build package distribution** workflow manually
from the Actions tab to download the tarball as a workflow artifact.

### Installing with Emacs package managers

The M2-mode package can be installed with a single line of code using several package managers.

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
(require 'M2-mode)
```

Using this method, you can fetch the most recent version of the package by running `git pull` in the `~/.emacs.d/site-lisp/Macaulay2` directory.

## Configuration

`M-x M2` starts a session. Opening an `.m2` file selects `M2-mode` automatically.
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
For nonstandard local documentation locations, customize `M2-info-directory`:

```elisp
(setq M2-info-directory "/opt/Macaulay2/share/info")
(setq Info-hide-note-references 'hide)
(global-set-key (kbd "<f12>") #'M2)
```

The Info path is used when displaying documentation requested by an M2 session.
The bundled `M-x M2-help` introduction needs no M2 installation. Remote Info paths
are not automatically downloaded or translated into local paths.

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

## Testing

`make check` installs the tarball in a temporary Emacs package directory and
tests autoloads, editing, command configuration, help, Info routing, and session
communication. Set `M2_TEST_COMMAND` to test evaluation with a real M2 as well.

`make check-lsp` tests discovery and client registration. Client-specific tests
are skipped when that client is unavailable. To run initialization and completion
checks against a real server too, set `M2_LSP_TEST_COMMAND` to a Lisp list:

```sh
M2_LSP_TEST_COMMAND='("/path/to/M2-language-server")' make check-lsp
```

These tests use a temporary package directory. Make installed client dependencies
visible with `LSP_EMACS_ARGS` if necessary; CI activates Ubuntu's system ELPA
package directory. CI runs the real-server checks only when its M2 distribution
provides `M2-language-server`.


## Why install M2-mode without Macaulay2?

Under certain circumstances, users who are unable to install Macaulay2 locally (e.g. the version provided by the university cluster is too old) can still use this package and choose an alternative method for running the Macaulay2 executable:

1. Press `C-u F12` to choose how to run M2, for instance:
  - Remotely via SSH, e.g. `ssh math.umn.edu M2 --no-readline --print-width 125`
  - Remotely via SSH to a containerized version of Habanero!
  - Locally via Docker, e.g. `docker run -it --entrypoint M2 mahrud/macaulay2:v1.15`

2. Press `M-x M2` to start Macaulay2.

Using this package, any machine running Emacs can run M2 via SSH or Docker, and your files would still be saved locally.

## Contributing

Contributions are welcome! Please submit pull requests.
