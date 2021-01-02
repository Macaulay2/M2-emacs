Emacs Package for Macaulay2
===========================

To get started with running Macaulay2 with Emacs, look at the file `M2-emacs-help.txt`, which is a text version of the documentation node available via `help "running Macaulay2 in emacs"`. To learn how to edit a file with Macaulay2 code in it using Emacs, see the file `M2-emacs.m2`, which is a text version of the documentation node available via `help "editing Macaulay2 code with emacs"`.

The files `M2.el` and `M2-mode.el` provide modes for editing Macaulay2 source in Emacs and running a Macaulay2 session within an Emacs buffer. The syntax highlighting symbols are defined in `M2-symbols.el.gz`.

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
