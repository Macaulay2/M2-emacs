;;; install-package.el --- Isolated archive installation -*- lexical-binding: t -*-
(require 'package)
(let ((archive (expand-file-name (car (last command-line-args-left))))
      (test-root (make-temp-file "M2-package-test-" t)))
  (setq command-line-args-left nil
        user-emacs-directory (file-name-as-directory test-root)
        package-user-dir (expand-file-name "elpa" test-root)
        package-archives nil
        package-check-signature nil)
  (package-initialize)
  (package-install-file archive))

;;; install-package.el ends here
