;;;; put these lines in your .emacs file
;; (setq auto-mode-alist (append auto-mode-alist '(("\\.g$" . M2-mode))))
;; (autoload 'M2-mode "M2-mode.el" "Macaulay 2 editing mode" t)
;;;;

(provide 'M2-mode)

(defvar M2-mode-hook nil
  "*Hook evaluated when first loading Macaulay 2 mode.")

(autoload 'M2-dynamic-complete-symbol "M2.el"
  "Dynamic completion function for Macaulay 2 symbols." t)

(defun m2-mode() (M2-mode))		;setting file variables lowers the case

(defun M2-mode()
  "Major mode used for editing contents of a Macaulay 2 source file.

\\{M2-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (use-local-map M2-mode-map)
  (setq major-mode 'M2-mode)
  (setq mode-name "Macaulay 2")
  (setq local-abbrev-table M2-mode-abbrev-table)
  (set-syntax-table M2-mode-syntax-table)
  (set-buffer-modified-p (buffer-modified-p))
  (make-local-variable 'comment-start)
  (setq comment-start "-- ")
  (make-local-variable 'comment-end)
  (setq comment-end "")
  (make-local-variable 'comment-column)
  (setq comment-column 42)
  (make-local-variable 'comment-start-skip)
  (setq comment-start-skip "-- *")
  (local-set-key "\^C\t" 'M2-dynamic-complete-symbol)
  (turn-on-font-lock)
  (run-hooks 'M2-mode-hook)
  )

(defvar M2-mode-abbrev-table nil
  "Abbrev table in use in M2-mode buffers.")
(define-abbrev-table 'M2-mode-abbrev-table ())
(defvar M2-mode-map nil "Keymap containing M2-mode commands.")
(if M2-mode-map
    nil
  (setq M2-mode-map (make-sparse-keymap))
  (define-key M2-mode-map "\177" 'backward-delete-char-untabify)
  (define-key M2-mode-map "\^M" 'M2-newline-and-indent)
  (define-key M2-mode-map "\t" 'M2-electric-tab)
  (define-key M2-mode-map "}" 'M2-electric-right-brace)
  (define-key M2-mode-map ";" 'M2-electric-semi)
  )

(defvar M2-mode-syntax-table nil
  "Syntax table in use in M2-mode buffers.")
(setq M2-mode-syntax-table (copy-syntax-table))

(modify-syntax-entry ?\\ "\\"   M2-mode-syntax-table)
(modify-syntax-entry ?-  ". 12" M2-mode-syntax-table)
(modify-syntax-entry ?*  "."    M2-mode-syntax-table)
(modify-syntax-entry ?+  "."    M2-mode-syntax-table)
(modify-syntax-entry ?=  "."    M2-mode-syntax-table)
(modify-syntax-entry ?%  "."    M2-mode-syntax-table)
(modify-syntax-entry ?<  "."    M2-mode-syntax-table)
(modify-syntax-entry ?>  "."    M2-mode-syntax-table)
(modify-syntax-entry ?&  "."    M2-mode-syntax-table)
(modify-syntax-entry ?|  "."    M2-mode-syntax-table)
(modify-syntax-entry ?\n ">"    M2-mode-syntax-table)
(modify-syntax-entry ?\^m ">"   M2-mode-syntax-table)

(defconst M2-indent-level 5 "*Indentation increment in Macaulay 2 mode")

(defun parse-line ()
     (save-excursion
	  (let (eol)
	       (end-of-line)
	       (setq eol (point))
	       (beginning-of-line)
	       (parse-partial-sexp (point) eol))))

(defun paren-change ()
     (car (parse-line)))

(defun M2-electric-semi ()
     (interactive)
     (insert ?;)
     (and (eolp) (next-line-blank) (= 0 (paren-change))
	 (M2-newline-and-indent))
     )

(defun next-line-indent-amount ()
     (+ (current-indentation) (* (paren-change) M2-indent-level)))

(defun this-line-indent-amount ()
     (save-excursion
	  (beginning-of-line)
	  (if (bobp)
	      0
	      (previous-line 1)
	      (next-line-indent-amount))))

(defun in-front ()
     (save-excursion (skip-chars-backward " \t") (bolp)))

(defun blank-line ()
     (save-excursion (beginning-of-line) (skip-chars-forward " \t") (eolp)))
     		   
(defun next-line-blank()
     (save-excursion
	  (end-of-line)
	  (or (eobp)
	      (progn (forward-char) (blank-line))
	      )))

(defun M2-newline-and-indent ()
     "Start a new line and indent it properly for Macaulay 2 code."
     (interactive)
     (newline)
     (indent-to (this-line-indent-amount))
     )

(defun M2-electric-right-brace()
     (interactive)
     (self-insert-command 1)
     (and (eolp) (next-line-blank) (< (paren-change) 0) (M2-newline-and-indent))
     )

(defun M2-electric-tab ()
     (interactive)
     (if (or (not (in-front)) (blank-line))
	 (indent-to (+ (current-column) M2-indent-level))
	 (let ((i (this-line-indent-amount))
	       (j (current-indentation)))
	      (if (not (= i j))
		  (progn
		       (if (< i j)
			    (delete-region (progn (beginning-of-line) (point))
					   (progn (back-to-indentation) (point)))
			    (back-to-indentation))
		       (indent-to i)
		       ) ) ) ) )

