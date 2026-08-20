;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

;; M2.el is the main file of the package: it carries the Package-Requires
;; header, and the others are loaded from it.  Telling `package-lint' so
;; lets it check them against that header, rather than reporting every
;; dependency they use as undeclared.
((emacs-lisp-mode . ((package-lint-main-file . "M2.el"))))
