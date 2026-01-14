;;; M2-init.el --- Setup M2.el for autoloading (legacy)
;; URL: https://github.com/Macaulay2/M2-emacs
;; Version: 1.25.11

;;; Commentary:

;; This file is used to set up autoloads for the M2 package.  It is used as a
;; legacy fallback if M2 was not installed using package-install or similar.
;;
;; In particular, users can add the following to their .emacs:
;; (add-to-list 'load-path "/path/to/M2")
;; (load "M2-init")
;; This is done automatically by the Macaulay2 method "setupEmacs()".

;;; Code:

(autoload 'M2             "M2" "Run Macaulay2 in an emacs buffer" t)
(autoload 'M2-mode        "M2" "Macaulay2 editing mode" t)
(autoload 'M2-comint-mode "M2" "Macaulay2 command interpreter mode" t)
(add-to-list 'auto-mode-alist '("\\.m2\\'" . M2-mode))

(provide 'M2-init)

;;; M2-init.el ends here
