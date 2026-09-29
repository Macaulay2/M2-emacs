Emacs Package for Macaulay2
===========================

To get started with running Macaulay2 with Emacs, run `M-x M2-help` to open the
bundled `M2-emacs-help.txt`, generated from `help "running Macaulay2 in Emacs"`.
For editing Macaulay2 code, see `M2-emacs.m2`, generated from
`help "editing Macaulay2 code with Emacs"`.

The files `M2.el` and `M2-mode.el` provide modes for editing Macaulay2 source in Emacs and running a Macaulay2 session within an Emacs buffer. The syntax highlighting symbols are defined in `M2-symbols.el`.

## Installation

Install this interface independently of the Macaulay2 executable. Package
installation, syntax highlighting, completion, and the bundled help do not run
M2. Interactive computations require a local M2 executable or an explicit SSH or
container command. You can run `setupEmacs()` in a recent M2 to add a
`package.el` installer and updater to `~/.emacs`, or use one of the manual
options below.

`setupEmacs()` prompts before editing `~/.emacs` and backs up an existing file.
The inserted block installs `M2` from the Macaulay2 package archive on the
next Emacs startup. On later startups, it checks for a newer package after
Emacs becomes idle. Network access is required for installation and updates;
if an update fails, Emacs uses the installed package. The block also binds F12
to `M2`; remove or customize that line if desired.

The archive is published at
`https://raw.githubusercontent.com/Macaulay2/M2-emacs/elpa/` after updates to
the repository's `main` branch. To use Emacs's package menu instead of
`setupEmacs()`, add the archive to `package-archives`, run
`M-x package-refresh-contents`, then `M-x package-install RET M2 RET`. Use
`M-x package-upgrade RET M2 RET` for later updates. The archive contains
versioned tarballs, so Emacs does not need Git.

### Installing an archive (including offline installation)

Download an `M2-<version>.tar` package artifact from a successful GitHub Actions
run, or build one from a checkout with `make package`. In Emacs, run
`M-x package-install-file` and select the tar file. Once downloaded, installation
needs neither a network connection nor a Macaulay2 installation. Do not unpack
the archive yourself. Emacs installs it, generates autoloads, and byte-compiles it.

The package declares Emacs 24.4 or newer; local standalone installation tests use Ubuntu 24.04 Emacs, and CI uses
the version provided by ubuntu-latest. The `use-package :vc` example below
requires Emacs 30. MELPA submission is presently not planned; this README does not assume that
the package has been accepted into MELPA.

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
(quelpa '(M2 :repo "Macaulay2/M2-emacs" :fetcher github :files ("*.el" "M2-emacs-help.txt" "M2-emacs.m2" "M2-session-guide.txt")))
```

####  [straight.el](https://github.com/radian-software/straight.el)

```elisp
(straight-use-package '(M2 :type git :host github :repo "Macaulay2/M2-emacs" :files ("*.el" "M2-emacs-help.txt" "M2-emacs.m2" "M2-session-guide.txt")))
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

The extended session guide is in `M2-session-guide.txt`, alongside the running
and editing guides shipped in the package.

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

## Migrating from bundled Emacs support

Older M2 versions supplied the Lisp files and offered `setupEmacs()` to edit
`~/.emacs` and create `~/.emacs-Macaulay2`. The current `setupEmacs()` replaces
its marked block in `~/.emacs` with the `package.el` installer, but leaves the old
`~/.emacs-Macaulay2` file in place. After installing this package:

1. Review the block between `;; Macaulay 2 start` and `;; Macaulay 2 end` in your
   Emacs init file. Remove the old `(load "~/.emacs-Macaulay2" t)` configuration
   when it is no longer needed.
2. Remove obsolete `load-path` entries pointing to M2's bundled `site-lisp`
   directory, and obsolete explicit loads of `M2-init`. Otherwise they can mask
   the independently installed package.
3. Preserve your desired executable, Info path, and key bindings using the
   settings above; then restart Emacs. `M-x locate-library RET M2` should identify
   the package-manager installation.

The package never rewrites your init file or deletes an older installation.
`M2-init.el` remains available for manually managed installations.

## Maintaining and distributing the package

`make package` creates a `package-install-file` archive in `dist/`, using the
checked-in Lisp and help files. It requires ordinary shell tools, not M2 or
Emacs. `make check` installs the archive into a temporary Emacs package directory
and tests that installation with no archive servers configured. CI publishes the
archive as an artifact. Distribution maintainers can package this repository
separately from M2, retaining the help files next to `M2.el`.

On each push to `main`, the publishing workflow runs `make archive` and updates
the `elpa` branch. Its `archive-contents` index points to a package tarball with
a monotonically increasing version. Emacs's built-in `package.el` reads that
index and installs upgrades from the archive URL above. The workflow needs
repository Actions permission to write branch contents.

`make update-symbols M2=/path/to/M2` is a maintainer-only operation using an
external M2 and its `Style` package. Commit the resulting `M2-symbols.el` after
review. The symbol list is a snapshot: a newer M2 may provide additional names
until it is refreshed, without preventing editing or running a session.
`M2-emacs-help.txt` and `M2-emacs.m2` are generated snapshots of the
corresponding Macaulay2Doc help nodes. The `make-M2-emacs-help.m2` script
regenerates them when updating from a Macaulay2 release; packaging the
checked-in snapshots does not require M2. `M2-session-guide.txt` is maintained
here.

Keep the package's supported M2 versions and any incompatible protocol changes
in the release notes; this initial separation does not change the comint protocol.

A proposed MELPA recipe is in `packaging/M2`. It includes the generated symbols
and help files and requires no build-time M2. Submit it to MELPA separately once
this package change has been reviewed. MELPA availability is not required for
the archive or direct-Git installation paths.

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
