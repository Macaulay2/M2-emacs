Emacs Package for Macaulay2
===========================

To get started with running Macaulay2 with Emacs, read
[`M2-emacs-help.txt`](M2-emacs-help.txt), generated from
`help "running Macaulay2 in Emacs"`.
For editing Macaulay2 code, see `M2-emacs.m2`, generated from
`help "editing Macaulay2 code with Emacs"`.

The files `M2.el` and `M2-mode.el` provide modes for editing Macaulay2 source in Emacs and running a Macaulay2 session within an Emacs buffer. The syntax highlighting symbols are defined in `M2-symbols.el`.

## Installation

Install this interface independently of the Macaulay2 executable. Package
installation, syntax highlighting, completion, and the bundled help do not run
M2. Interactive computations require a local M2 executable or an explicit SSH or
container command. Choose one of the installation options below.

### Installing an archive (including offline installation)

Download an `M2-<version>.tar` package artifact from a successful **Build package
distribution** GitHub Actions run, or build one from a checkout with `make dist`.
In Emacs, run
`M-x package-install-file` and select the tar file. Once downloaded, installation
needs neither a network connection nor a Macaulay2 installation. Do not unpack
the archive yourself. Emacs installs it, generates autoloads, and byte-compiles it.

The package declares Emacs 24.4 or newer. The `use-package :vc` example below
requires Emacs 30. MELPA submission is presently not planned.

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

## Migrating from bundled Emacs support

Older M2 versions supplied the Lisp files and offered `setupEmacs()` to edit
`~/.emacs` and create `~/.emacs-Macaulay2`. After installing this package:

1. Review the block between `;; Macaulay 2 start` and `;; Macaulay 2 end` in your
   Emacs init file. Remove the old `(load "~/.emacs-Macaulay2" t)` configuration
   when it is no longer needed.
2. Remove obsolete `load-path` entries pointing to M2's bundled `site-lisp`
   directory, and obsolete explicit loads of `M2-init`. Otherwise they can mask
   the independently installed package.
3. Preserve your custom `M2-command`, Info configuration, and key bindings;
   then restart Emacs. `M-x locate-library RET M2` should identify
   the package-manager installation.

The package never rewrites your init file or deletes an older installation.
`M2-init.el` remains available for manually managed installations.

## Maintaining and distributing the package

`make dist` creates a `package-install-file` archive in `dist/`, using the
checked-in Lisp and help files. It requires ordinary shell tools, not M2 or
Emacs. Distribution maintainers can package this repository separately from
M2, retaining the help files next to `M2.el`.

Maintainers can run the **Build package distribution** workflow manually from
the Actions tab. It runs `make archive` and uploads the versioned tarball and
`archive-contents` as an artifact for download and manual publication. It does
not publish a branch or upload files to a website.

The generated index describes only M2. When publishing in a shared ELPA-like
repository (for example, on macaulay2.com), merge its entry into that
repository's index so other packages remain available. Hosting and an archive
URL are managed separately; this repository does not yet provide a public
package archive.

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
and help files and requires no build-time M2. It is retained for reference;
submission is presently not planned. MELPA availability is not required for the
archive or direct-Git installation paths.

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
