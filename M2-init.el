;; Setup M2.el for autoloading

(autoload 'M2             "M2" "Run Macaulay2 in an emacs buffer" t)
(autoload 'M2-mode        "M2" "Macaulay2 editing mode" t)
(autoload 'M2-comint-mode "M2" "Macaulay2 command interpreter mode" t)
(autoload 'M2-simple-doc-mode "M2" "Macaulay2 SimpleDoc editing mode" t)
(add-to-list 'auto-mode-alist '("\\.m2\\'" . M2-mode))

;; Uncomment these lines to enable syntax highlighting for the interpreter language
;(autoload 'D-mode "D-mode" "Editing mode for the interpreter language" t)
;(add-to-list 'auto-mode-alist '("\\.dd?\\'" . D-mode))
