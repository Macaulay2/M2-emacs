;;; macaulay2.el --- Major mode for editing Macaulay2 source core -*- lexical-binding: t -*-

;; Copyright (C) 1997-2026 The Macaulay2 Authors

;; Version: 1.25.11
;; Keywords: languages
;; URL: https://github.com/Macaulay2/M2-emacs
;; Package-Requires: ((emacs "24.3"))

;;; Commentary:
;; Macaulay2 makes no attempt to wrap long output lines, so we provide
;; functions that make horizontal scrolling easier.  In addition:
;;    - run Macaulay2 as a command interpreter in an Emacs buffer
;;    - provide a major mode used for editing Macaulay2 source files

;;; TODO:
;; Do we still wish to enable ansi-color-for-comint-mode?

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Code:

(require 'font-lock)
(require 'comint)
(require 'thingatpt)
(require 'macaulay2-symbols)

(defgroup macaulay2 nil
  "Support for Macaulay2 language development."
  :group 'languages
  :prefix "macaulay2-")

(defmacro macaulay2-legacy-defun (name arglist &rest body)
  "Define a function NAME and mark its legacy M2-namespaced version obsolete.
Pass ARGLIST and BODY as in `defun'."
  (declare (doc-string 3) (indent defun))
  `(progn
     (defun ,name ,arglist
       ,@body)
     (define-obsolete-function-alias
       (intern (replace-regexp-in-string "^macaulay2" "M2" (symbol-name ',name)))
       ',name "1.26.05")))

(defmacro macaulay2-legacy-defcustom (symbol standard doc &rest args)
  "Define a variable SYMBOL and mark its legacy M2-namespaced version obsolete.
Pass STANDARD, DOC, and ARGS as in `defcustom'."
  (declare (doc-string 3) (debug (name body))
           (indent defun))
  `(progn
     (defcustom ,symbol ,standard ,doc ,@args)
     (define-obsolete-variable-alias
       (intern (replace-regexp-in-string "^macaulay2" "M2" (symbol-name ',symbol)))
       ',symbol "1.26.05" ,doc)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; key bindings
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun macaulay2-define-common-keys (map)
  "Define keys in MAP that are common to both major modes."
  (define-key map (kbd "<f12>") #'macaulay2) ; user may want to make this one global
  (define-key map (kbd "M-<f12>") #'macaulay2-demo)
  (define-key map (kbd "C-<f11>") #'macaulay2-switch-to-demo-buffer)
  (define-key map (kbd "M-<f11>") #'macaulay2-set-demo-buffer)
  (define-key map (kbd "C-c TAB") #'completion-at-point)
  (define-key map (kbd "M-<tab>") #'completion-at-point)
  (define-key map (kbd "<f10>") #'macaulay2-match-next-bracketed-input)
  (define-key map (kbd "M-<f10>") #'macaulay2-match-previous-bracketed-input))

(defvar macaulay2-mode-map
  (let ((map (make-sparse-keymap)))
    (macaulay2-define-common-keys map)
    (define-key map (kbd "DEL") #'backward-delete-char-untabify)
    (define-key map (kbd ";") #'macaulay2-electric-semi)
    (define-key map (kbd "<C-return>") #'macaulay2-send-to-program)
    (define-key map (kbd "<f11>") #'macaulay2-send-to-program)
    (define-key map (kbd "C-c C-j") #'macaulay2-send-line-to-program)
    (define-key map (kbd "C-c C-r") #'macaulay2-send-region-to-program)
    (define-key map (kbd "C-c C-b") #'macaulay2-send-buffer-to-program)
    (define-key map (kbd "C-c <C-up>") #'macaulay2-send-buffer-from-beg-to-here-to-program)
    (define-key map (kbd "C-c <C-down>") #'macaulay2-send-buffer-from-here-to-end-to-program)
    (define-key map (kbd "C-c C-p") #'macaulay2-send-paragraph-to-program)
    map))

(defvar macaulay2-comint-mode-map
  (let ((map (make-sparse-keymap)))
    (macaulay2-define-common-keys map)
    (define-key map (kbd "TAB") #'completion-at-point)
    (define-key map (kbd "<f2>") #'macaulay2-position-point)
    (define-key map (kbd "C-c :") #'macaulay2-position-point)
    (define-key map (kbd "<f3>") #'macaulay2-jog-left)
    (define-key map (kbd "C-c <") #'macaulay2-jog-left)
    (define-key map (kbd "<f4>") #'macaulay2-jog-right)
    (define-key map (kbd "C-c >") #'macaulay2-jog-right)
    (define-key map (kbd "C-c C-t") #'macaulay2-toggle-truncate-lines)
    (define-key map (kbd "<f11>") #'macaulay2-send-input-or-get-input-from-demo-buffer)
    map))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; macaulay2-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;###autoload
(define-derived-mode macaulay2-mode prog-mode "Macaulay2"
  "Major mode for editing Macaulay2 source code.

\\\{macaulay2-mode-map}."
  (macaulay2-common))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.m2\\'" . macaulay2-mode))

;;;###autoload
(define-obsolete-function-alias
  'M2-mode #'macaulay2-mode "1.26.05")

(macaulay2-legacy-defcustom macaulay2-indent-level 4
  "Indentation increment in Macaulay2 mode."
  :type 'integer
  :group 'macaulay2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; macaulay2-comint-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst macaulay2-comint-prompt-regexp "^\\([ \t]*\\(i*[1-9][0-9]* :\\|o*[1-9][0-9]* =\\) \\)?"
  "Regular expression for the Macaulay2 prompt.")

(defvar macaulay2-error-regexp-alist
  '(
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; printMessage (stdiop.d) ;;
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; error messages, e.g.,
    ;; i1 : load "packages/Macaulay2Doc/demo1.m2"; g 2
    ;; packages/Macaulay2Doc/demo1.m2:8:12:(3):[2]: error: division by zero
    ;;  (1                                                           1)   (2      2)   (3      3)
    ("\\(?:\\(?1:[[:alnum:]/._][[:alnum:]/._-]*\\)\\|\"\\(?1:.+\\)\"\\):\\([0-9]+\\):\\([0-9]+\\):([0-9]+):\\[[0-9]+\\]"
     1 2 3)
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; net(FilePosition) (debugging.m2) ;;
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; start & end line/column numbers, e.g.,:
    ;; i1 : locate (rank, Matrix)
    ;; o1 = m2/matrix1.m2:663:19-666:20
    ;;  (1                                                           1)   (2      2)   (3      3)   (4      4)   (5      5)
    ("\\(?:\\(?1:[[:alnum:]/._][[:alnum:]/._-]*\\)\\|\"\\(?1:.+\\)\"\\):\\([0-9]+\\):\\([0-9]+\\)-\\([0-9]+\\):\\([0-9]+\\)"
     1 (2 . 4) (3 . 5) 0)
    ;; no end line/column numbers, e.g.,:
    ;; i2 : locate makeDocumentTag rank
    ;; o2 = ../Macaulay2Doc/functions/rank-doc.m2:34:0
    ;;  (1                                                          1)   (2      2)   (3      3)
    ("\\(?:\\(?1:[[:alnum:]/._][[:alnum:]/._-]*\\)\\|\"\\(?1:.+\\)\"\\):\\([0-9]+\\):\\([0-9]+\\)"
     1 2 3 0))
  "Regular expressions for matching file positions in Macaulay2 output.")

(defvar macaulay2-transform-file-match-alist
  '(("^stdio$" nil)
    ("^currentString$" nil)
    ("^[0-9][0-9]$" nil))
  "List of filenames not to match in Macaulay2 output.")

;;;###autoload
(define-derived-mode macaulay2-comint-mode comint-mode "Macaulay2 Interaction"
  "Major mode for interacting with a Macaulay2 process.

\\{macaulay2-comint-mode-map}"
  (macaulay2-common)
  (setq comint-prompt-regexp macaulay2-comint-prompt-regexp)
  (add-hook 'comint-input-filter-functions #'macaulay2-comint-forget-errors nil t)
  (add-hook 'comint-preoutput-filter-functions #'macaulay2-info-help nil t)
  (add-hook 'comint-output-filter-functions #'macaulay2-comint-fix-unclosed nil t)
  (setq-local compilation-error-regexp-alist macaulay2-error-regexp-alist)
  (setq-local compilation-transform-file-match-alist
	      macaulay2-transform-file-match-alist)
  (compilation-shell-minor-mode 1))

;;;###autoload
(define-obsolete-function-alias
  'M2-comint-mode #'macaulay2-comint-mode "1.26.05")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Common definitions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst macaulay2-mode-font-lock-keywords
  (list
   (cons macaulay2-symbols-keyword-regexp  'font-lock-keyword-face)
   (cons macaulay2-symbols-type-regexp     'font-lock-type-face)
   (cons macaulay2-symbols-function-regexp 'font-lock-function-name-face)
   (cons macaulay2-symbols-constant-regexp 'font-lock-constant-face)))

; TODO:
; font-lock-warning-face
; font-lock-variable-name-face
; font-lock-builtin-face
; font-lock-preprocessor-face
; font-lock-doc-face
; font-lock-negation-char-face

(defun macaulay2-common ()
  "Set up features common to both Macaulay2 major modes."
  (set (make-local-variable 'comment-start) "-- ")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'comment-column) 60)
  (set (make-local-variable 'comment-start-skip) "-- *")
  (set (make-local-variable 'comint-input-autoexpand) nil)
  (set (make-local-variable 'transient-mark-mode) t)
  (set (make-local-variable 'indent-line-function) #'macaulay2-electric-tab)
  (setq font-lock-defaults '( macaulay2-mode-font-lock-keywords ))
  (setq truncate-lines t)
  (setq case-fold-search nil)
  (add-hook 'completion-at-point-functions #'macaulay2-completion-at-point nil t))

;; menus

(defvar macaulay2-common-menu
      '(["Match previous bracketed input" macaulay2-match-previous-bracketed-input]
	["Match next bracketed input"     macaulay2-match-next-bracketed-input]
	["Set demo buffer"                macaulay2-set-demo-buffer]
	["Switch to demo buffer"          macaulay2-switch-to-demo-buffer]
	["Start demo"                     macaulay2-demo])
      "Common parts of menus for both `macaulay2-mode' and `macaulay2-comint-mode'.")

(easy-menu-define macaulay2-menu macaulay2-mode-map
  "Menu for Macaulay2 major mode."
  (append
   '("Macaulay2"
     ["Start Macaulay2"               macaulay2]
     ["Send line/region to Macaulay2" macaulay2-send-to-program]
     ["Send line to Macaulay2"        macaulay2-send-line-to-program]
     ["Send region to Macaulay2"      macaulay2-send-region-to-program]
     ["Send buffer to Macaulay2"      macaulay2-send-buffer-to-program]
     ["Send buffer to here to Macaulay2"
      macaulay2-send-buffer-from-beg-to-here-to-program]
     ["Send buffer from here to Macaulay2"
      macaulay2-send-buffer-from-here-to-end-to-program]
     ["Send paragraph to Macaulay2"   macaulay2-send-paragraph-to-program]
     ["Highlight evaluated region"    macaulay2-toggle-blink-region-flag
      :style toggle :selected macaulay2-blink-region-flag]
     "-")
   macaulay2-common-menu))

(easy-menu-define macaulay2-comint-menu macaulay2-comint-mode-map
  "Menu for Macaulay2 Interaction major mode."
  (append
   '("Macaulay2 Interaction"
     ["Send to Macaulay2"   comint-send-input]
     ["Get demo input"      macaulay2-get-input-from-demo-buffer]
     ["Send to macaulay2 or get demo input"
      macaulay2-send-input-or-get-input-from-demo-buffer]
     ["Go to end of prompt" macaulay2-to-end-of-prompt]
     ["Center point"        macaulay2-position-point]
     ["Jog left"            macaulay2-jog-left]
     ["Jog right"           macaulay2-jog-right]
     ["Toggle word wrap"    macaulay2-toggle-truncate-lines]
    "-")
   macaulay2-common-menu))

;; syntax

; bug: ///A"B"C/// vs ///ABC///

(mapc
 (function
  (lambda (syntax-table)
    (modify-syntax-entry ?\\ "\\" syntax-table) ; we use \, signifying an escape character, to get "asdf\"asdf" to be correctly colorized
    (modify-syntax-entry ?-  ". 124b" syntax-table)
    (modify-syntax-entry ?\n "> b" syntax-table)
    (modify-syntax-entry ?\^m "> b" syntax-table)
    (modify-syntax-entry ?*  ". 23" syntax-table)
    (modify-syntax-entry ?_  "." syntax-table)
    (modify-syntax-entry ?+  "." syntax-table)
    (modify-syntax-entry ?=  "." syntax-table)
    (modify-syntax-entry ?%  "." syntax-table)
    (modify-syntax-entry ?<  "." syntax-table)
    (modify-syntax-entry ?>  "." syntax-table)
    (modify-syntax-entry ?'  "_" syntax-table) ; part of a symbol
    (modify-syntax-entry ?&  "." syntax-table)
    (modify-syntax-entry ?|  "." syntax-table)))
 (list macaulay2-mode-syntax-table macaulay2-comint-mode-syntax-table))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; macaulay2 interpreter
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(macaulay2-legacy-defcustom macaulay2-exe "M2"
  "The default Macaulay2 executable name."
  :type 'string
  :group 'macaulay2)
(macaulay2-legacy-defcustom macaulay2-command
  (concat macaulay2-exe " --no-readline --print-width " (number-to-string (- (window-body-width) 1)) " ")
  "The default Macaulay2 command line."
  :type 'string
  :group 'macaulay2)

(defvar macaulay2-shell-exe "/bin/sh" "The default shell executable name.")
(defvar macaulay2-history nil "The history of recent Macaulay2 command lines.")
(defvar macaulay2-send-to-buffer-history nil "The history of recent Macaulay2 send-to buffers.")
(defvar macaulay2-current-tag "M2" "The current Macaulay2 command name tag.")
(defvar macaulay2-tag-history () "The history of recent Macaulay2 command name tags.")
(defvar macaulay2-usual-jog 30 "Usual distance scrolled by `macaulay2-jog-left' and `macaulay2-jog-right'.")

(defun macaulay2-add-width-option (command)
  "Set the print width specified in COMMAND to match the window width."
  (let ((print-width (concat "--print-width "
			     (number-to-string (1- (window-body-width))))))
    (if (string-match "--print-width +[0-9]+" command)
	(replace-match print-width t t command)
      (concat command " " print-width))))

;;;###autoload
(defun macaulay2 (command name)
  "Run Macaulay2 in a buffer.
With a prefix argument \\[universal-argument], set COMMAND, the command line
given to the shell to run Macaulay2 can be edited in the minibuffer.  With
prefix argument \\[universal-argument] \\[universal-argument], set NAME, the
tag from which the buffer name is constructed (by prepending and appending
asterisks) can be entered in the minibuffer.  The command line will always have
the appropriate option for the width of the current window added to it."
  (interactive
   (list
    (cond
     (current-prefix-arg
      (read-from-minibuffer
       "M2 command line: "
       (macaulay2-add-width-option (if macaulay2-history (car macaulay2-history) macaulay2-command))
       nil nil (if macaulay2-history '(macaulay2-history . 1) 'macaulay2-history)))
     (macaulay2-history (macaulay2-add-width-option (car macaulay2-history)))
     (t (macaulay2-add-width-option macaulay2-command)))
    (cond
     ((equal current-prefix-arg '(16))
      (setq macaulay2-current-tag
	    (read-from-minibuffer
	     "M2 buffer name tag: "
	     (if macaulay2-tag-history (car macaulay2-tag-history) macaulay2-current-tag)
	     nil nil
	     (if macaulay2-tag-history '(macaulay2-tag-history . 1) 'macaulay2-tag-history))))
     (t macaulay2-current-tag))))
  (let* ((buffer-name (concat "*" name "*"))
	(buffer (get-buffer-create buffer-name)))
    (pop-to-buffer buffer)
    (unless (comint-check-proc buffer)
      (let ((n (if (boundp 'text-scale-mode-amount) text-scale-mode-amount 0)))
	(make-comint name macaulay2-shell-exe nil "-c" (concat "echo; set -x; " command))
	(macaulay2-comint-mode)
	(text-scale-set n)))
    buffer))

;;;###autoload
(define-obsolete-function-alias
  'M2 #'macaulay2 "1.26.05")

(defun macaulay2-left-hand-column ()
  "Return the column at the left hand side of the window."
  (window-hscroll))
(defun macaulay2-right-hand-column ()
  "Return the column at the right hand side of the window."
  (+ (window-hscroll) (window-body-width) -1))
(defun macaulay2-on-screen ()
  "Return whether the current column is visible in the window."
  (and (< (macaulay2-left-hand-column) (current-column))
       (< (current-column) (macaulay2-right-hand-column))))
(macaulay2-legacy-defun macaulay2-position-point (pos)
  "Scroll display horizontally.
Point ends up at center of screen or at column position given by POS."
  (interactive "P")
  (if (listp pos) (setq pos (car pos)))
  (if (not pos)
      (setq pos (/ (window-body-width) 2))
    (if (< pos 0) (setq pos (+ pos (window-body-width)))))
  (set-window-hscroll (selected-window) (+ 1 (- (current-column) pos))))

(macaulay2-legacy-defun macaulay2-jog-right (arg)
  "Move point right and scroll display so it remains visible.
Optional prefix argument ARG tells how far to move."
  (interactive "P")
  (if (listp arg) (setq arg (car arg)))
  (goto-char
   (if arg
       (+ (point) arg)
     (min (save-excursion (end-of-line) (point)) (+ (point) macaulay2-usual-jog))))
  (if (not (macaulay2-on-screen)) (macaulay2-position-point -2)))

(macaulay2-legacy-defun macaulay2-jog-left (arg)
  "Move point left and scroll display so it remains visible.
Optional prefix argument ARG tells how far to move."
  (interactive "P")
  (if (listp arg) (setq arg (car arg)))
  (goto-char
   (if arg
       (- (point) arg)
     (max (save-excursion (beginning-of-line) (point)) (- (point) macaulay2-usual-jog))))
  (if (not (macaulay2-on-screen)) (macaulay2-position-point 1)))

(macaulay2-legacy-defun macaulay2-toggle-truncate-lines ()
  "Toggle the value of `truncate-lines'.
This is the variable which determines whether long lines are truncated or
wrapped on the screen."
  (interactive)
  (setq truncate-lines (not truncate-lines))
  (if truncate-lines
      (if (not (macaulay2-on-screen))
	  (set-window-hscroll
	   (selected-window)
	   (- (current-column) (/ (window-body-width) 2))))
    (set-window-hscroll (selected-window) 0))
  (macaulay2-update-screen))

(defun macaulay2-update-screen ()
  "Redisplay the selected window."
    (set-window-start (selected-window) (window-start (selected-window))))

(defun macaulay2-completion-at-point ()
  "Function used for `completion-at-point-functions' for the macaulay2 major modes."
  (let* ((bounds (bounds-of-thing-at-point 'symbol))
         (start (car bounds))
         (end (cdr bounds)))
    (list start end macaulay2-symbols-completion-table :exclusive 'no)))

(macaulay2-legacy-defun macaulay2-to-end-of-prompt ()
     "Move to end of prompt matching `macaulay2-comint-prompt-regexp' on this line."
     (interactive)
     (beginning-of-line)
     (let ((case-fold-search nil))
       (if (looking-at macaulay2-comint-prompt-regexp)
	   (goto-char (match-end 0))
	 (back-to-indentation))))

(macaulay2-legacy-defun macaulay2-match-next-bracketed-input ()
  "Move forward to the next region bracketed by <<< and >>>.
Mark it with the point and the mark.  After marking the region, the code
can be executed with \\[macaulay2-send-to-program]."
  (interactive)
  (goto-char
   (prog1
       (re-search-forward "<<<")
     (re-search-forward ">>>")
     (set-mark (match-beginning 0)))))

(macaulay2-legacy-defun macaulay2-match-previous-bracketed-input ()
  "Move backward to the previous region bracketed by <<< and >>>.
Mark it with the point and the mark.  After marking the region, the code
can be executed with \\[macaulay2-send-to-program]."
  (interactive)
  (goto-char
   (progn
     (re-search-backward ">>>")
     (set-mark (match-beginning 0))
     (re-search-backward "<<<")
     (match-end 0))))

(define-obsolete-function-alias
  'macaulay2-send-input #'comint-send-input "1.23")

(define-obsolete-function-alias
  'macaulay2-send-to-program-or-jump-to-source-code #'comint-send-input "1.22")

(defun macaulay2--get-send-to-buffer ()
  "Helper function for `macaulay2-send-to-program' and friends.
Gets buffer for Macaulay2 inferior process from minibuffer or history."
  (list
   (cond (current-prefix-arg
	  (read-from-minibuffer
	   "buffer to send command to: "
	   (if macaulay2-send-to-buffer-history
	       (car macaulay2-send-to-buffer-history)
	     (concat "*" macaulay2-current-tag "*"))
	   nil nil
	   (if macaulay2-send-to-buffer-history
	       '(macaulay2-send-to-buffer-history . 1)
	     'macaulay2-send-to-buffer-history)))
	 (macaulay2-send-to-buffer-history (car macaulay2-send-to-buffer-history))
	 (t (concat "*" macaulay2-current-tag "*")))))

(defun macaulay2--send-to-program-helper (send-to-buffer start end)
  "Helper function for `macaulay2-send-to-program' and friends.
Sends code between START and END to Macaulay2 inferior process in
SEND-TO-BUFFER."
  (unless (and (get-buffer send-to-buffer) (get-buffer-process send-to-buffer))
    (user-error
     "Start a Macaulay2 process first with `M-x macaulay2' or `%s'.?"
     (key-description (where-is-internal #'macaulay2 overriding-local-map t))))
  (display-buffer send-to-buffer '(nil (inhibit-same-window . t)))
  (let ((cmd (buffer-substring start end)))
    (macaulay2-blink-region start end)
    (with-current-buffer send-to-buffer
      (goto-char (point-max))
      (insert cmd)
      (comint-send-input)
      (set-window-point (get-buffer-window send-to-buffer 'visible) (point)))))

(macaulay2-legacy-defun macaulay2-send-region-to-program (send-to-buffer)
  "Send the current region to the macaulay2 process in SEND-TO-BUFFER.
See `macaulay2-send-to-program' for more."
  (interactive (macaulay2--get-send-to-buffer))
  (macaulay2--send-to-program-helper send-to-buffer (region-beginning) (region-end)))

(macaulay2-legacy-defun macaulay2-send-line-to-program (send-to-buffer)
  "Send the current line to the macaulay2 process in SEND-TO-BUFFER.
See `macaulay2-send-to-program' for more."
  (interactive (macaulay2--get-send-to-buffer))
  (macaulay2--send-to-program-helper send-to-buffer
			      (save-excursion (macaulay2-to-end-of-prompt) (point))
			      (line-end-position))
  (forward-line)
  ;; add a newline after a nonempty line at the end of the buffer
  (when (and (eobp) (not (bolp))) (newline)))

(macaulay2-legacy-defun macaulay2-send-to-program (send-to-buffer)
  "Send the current line or region to the macaulay2 process in SEND-TO-BUFFER.
Send the current line except for a possible prompt, or the region, if the
mark is active, to Macaulay2 in its buffer, making its window visible.
Afterwards, in the case where the mark is not active, move the cursor to
the next line.  With a prefix argument, the name of the buffer to
which this and future uses of the command (in this buffer) should be
sent can be entered, with history."
     (interactive (macaulay2--get-send-to-buffer))
     (if (region-active-p)
	 (macaulay2-send-region-to-program send-to-buffer)
       (macaulay2-send-line-to-program send-to-buffer)))

(macaulay2-legacy-defun macaulay2-send-buffer-to-program (send-to-buffer)
  "Send the entire buffer to the macaulay2 process in SEND-TO-BUFFER.
See `macaulay2-send-to-program' for more."
  (interactive (macaulay2--get-send-to-buffer))
  (macaulay2--send-to-program-helper send-to-buffer (point-min) (point-max)))

(macaulay2-legacy-defun macaulay2-send-buffer-from-beg-to-here-to-program (send-to-buffer)
  "Send everything before the the point the macaulay2 process in SEND-TO-BUFFER.
See `macaulay2-send-to-program' for more."
  (interactive (macaulay2--get-send-to-buffer))
  (macaulay2--send-to-program-helper send-to-buffer (point-min) (point)))

(macaulay2-legacy-defun macaulay2-send-buffer-from-here-to-end-to-program (send-to-buffer)
  "Send everything after the the point the macaulay2 process in SEND-TO-BUFFER.
See `macaulay2-send-to-program' for more."
  (interactive (macaulay2--get-send-to-buffer))
  (macaulay2--send-to-program-helper send-to-buffer (point) (point-max)))

(macaulay2-legacy-defun macaulay2-send-paragraph-to-program (send-to-buffer)
  "Send the current paragraph to the macaulay2 process in SEND-TO-BUFFER.
See `macaulay2-send-to-program' for more."
  (interactive (macaulay2--get-send-to-buffer))
  (let ((end (progn (forward-paragraph) (point)))
	(start (progn (backward-paragraph) (point))))
    (macaulay2--send-to-program-helper send-to-buffer start end))
  (forward-paragraph))

(defvar macaulay2-demo-buffer
  (with-current-buffer (get-buffer-create "*M2-demo-buffer*")
    (macaulay2-mode)
    (current-buffer))
  "Buffer from which lines are obtained by `macaulay2-get-input-from-demo-buffer'.
Set it with `macaulay2-set-demo-buffer'." )

(macaulay2-legacy-defun macaulay2-set-demo-buffer ()
  "Set the variable `macaulay2-demo-buffer' to the current buffer.
Later, `macaulay2-get-input-from-demo-buffer' can obtain lines from this buffer."
  (interactive)
  (setq macaulay2-demo-buffer (current-buffer)))

(macaulay2-legacy-defun macaulay2-switch-to-demo-buffer ()
  "Switch to the buffer given by the variable `macaulay2-demo-buffer'."
  (interactive)
  (switch-to-buffer macaulay2-demo-buffer))

(declare-function toggle-scroll-bar "scroll-bar")

(macaulay2-legacy-defun macaulay2-demo ()
  "Set up a new frame with a big font for a Macaulay2 demo."
  (interactive)
  (let* ((f (prog1
	      (select-frame
	       (make-frame
		'((height . 30)
		  (width . 80)
		  (menu-bar-lines . 0)
		  (visibility . t)
		  ; (minibuffer . nil)
		  ;; (reverse . t)
		  (modeline . nil);; doesn't work
		  (name . "DEMO"))))
	      (toggle-scroll-bar 0)
	      (set-frame-font (font-spec :size 24.0)))))
    (modify-frame-parameters f '((left + 20) (top + 30)))
    ; (macaulay2)
    (with-current-buffer "*M2*"
      (setq comint-scroll-show-maximum-output t))))

(macaulay2-legacy-defun macaulay2-get-input-from-demo-buffer ()
  "Copy the current line from `macaulay2-demo-buffer' to the prompt."
  (interactive)
  (insert (with-current-buffer macaulay2-demo-buffer
	    (prog1
		(if (eobp)
		    (concat "-- end of buffer " (buffer-name (current-buffer)))
		  (buffer-substring
		   (prog2 (macaulay2-to-end-of-prompt) (point))
		   (line-end-position)))
	      (forward-line)))))

(macaulay2-legacy-defun macaulay2-send-input-or-get-input-from-demo-buffer ()
  "Either send input to Macaulay2 or get input from the demo buffer.
If current line is blank, then copy the current line of `macaulay2-demo-buffer'.
Otherwise, send the input to Macaulay2."
  (interactive)
  (if (save-excursion (macaulay2-to-end-of-prompt) (looking-at-p "[[:blank:]]*$"))
      (macaulay2-get-input-from-demo-buffer)
    (comint-send-input)))

(defun macaulay2-info-help (string)
  "Load info documentation for Macaulay2.
When using the infoHelp function, macaulay2 emits a special string.  If the M2
output given by STRING matches, then load the corresponding documentation."
  (if (string-match "-\\* infoHelp: \\(.*\\) \\*-" string)
      (let ((end (1+ (match-end 0))))
	(save-excursion
	  (with-demoted-errors "%S"
	    (info-other-window (match-string 1 string))))
	(substring string end))
    string))

(defun macaulay2-comint-insert-invisible-at-bol (string)
  "Insert STRING with the invisible property at the beginning of the line."
  (save-excursion
    (beginning-of-line)
    (insert string)
    (put-text-property (- (point) (length string)) (point) 'invisible t)))

(defun macaulay2-comint-fix-unclosed (string)
  "Close any unclosed strings or comments from the output.
STRING is the current Macaulay2 output, which we check to see whether we're at
a new input prompt."
  (ignore string)
  (when (string-match-p "^[ \t]*i+[1-9][0-9]* : " string)
    (let ((syntax (syntax-ppss (point))))
      (cond
       ((nth 3 syntax) (macaulay2-comint-insert-invisible-at-bol "\""))
       ((nth 4 syntax) (macaulay2-comint-insert-invisible-at-bol "*-"))))))

(declare-function compilation-forget-errors "compile")

(defun macaulay2-comint-forget-errors (string)
  "Run `compilation-forget-errors' to flush compilation mode's cache.
Otherwise, jumping to source will go to the wrong location when a file has
been modified and reloaded.  STRING is ignored, but we need it so that this
function can be added to `comint-input-filter-functions' so that it is run each
time we send new input to the macaulay2 process."
  (ignore string)
  (compilation-forget-errors))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; macaulay2-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(if (not (boundp 'font-lock-constant-face))
    (setq font-lock-constant-face font-lock-function-name-face))

(defun macaulay2-paren-change ()
  "Return change in paren depth on current line."
  (save-excursion
    (car (parse-partial-sexp (prog2 (beginning-of-line) (point))
			     (prog2 (end-of-line) (point))))))

(macaulay2-legacy-defun macaulay2-electric-semi ()
  "Insert a semicolon and start a new line."
     (interactive)
     (insert ?\;)
     (and (eolp) (macaulay2-next-line-blank) (= 0 (macaulay2-paren-change))
	 (newline nil t)))

(defun macaulay2-next-line-indent-amount ()
  "Determine how much to indent the next line."
     (+ (current-indentation) (* (macaulay2-paren-change) macaulay2-indent-level)))

(defun macaulay2-this-line-indent-amount ()
     "Determine how much to indent the current line."
     (save-excursion
	  (beginning-of-line)
	  (if (bobp)
	      0
	      (forward-line -1)
	      ;; if the previous line is blank, then keep going
	      (while (and (not (bobp)) (looking-at-p "[[:blank:]]*$"))
		(forward-line -1))
	      (macaulay2-next-line-indent-amount))))

(defun macaulay2-in-front ()
  "Determine whether we are at the front of the line."
     (save-excursion (skip-chars-backward " \t") (bolp)))

(defun macaulay2-blank-line ()
  "Determine whether the line is blank."
     (save-excursion (beginning-of-line) (skip-chars-forward " \t") (eolp)))

(defun macaulay2-next-line-blank ()
  "Determine whether the next line is blank."
     (save-excursion
	  (end-of-line)
	  (or (eobp)
	      (progn (forward-char) (macaulay2-blank-line)))))

(define-obsolete-function-alias
  'macaulay2-newline-and-indent #'newline "1.23")

(macaulay2-legacy-defun macaulay2-electric-right-brace ()
  "Insert a right brace and start a new line."
     (interactive)
     (self-insert-command 1)
     (and (eolp) (macaulay2-next-line-blank) (< (macaulay2-paren-change) 0) (newline nil t)))

(macaulay2-legacy-defcustom macaulay2-insert-tab-commands '(indent-for-tab-command org-cycle)
  "Commands for which `macaulay2-electric-tab' should insert a tab."
  :type '(repeat function)
  :group 'macaulay2)

(macaulay2-legacy-defun macaulay2-electric-tab ()
  "`indent-line-function' for Macaulay2.
If called by command in `macaulay2-insert-tab-commands', and if the point is
either to right of non-whitespace characters in the same line or if the line is
blank, then insert `macaulay2-indent-level' spaces.  Otherwise, indent the line
based on the depth of the parentheses in the code."
  (interactive)
  (indent-to
   (prog1 (if (and (memq this-command macaulay2-insert-tab-commands)
		   (or (not (macaulay2-in-front)) (macaulay2-blank-line)))
	      (+ (current-column) macaulay2-indent-level)
	    (macaulay2-this-line-indent-amount))
     (delete-horizontal-space))))

;;; "blink" evaluated region (heavily inspired by ESS)

(macaulay2-legacy-defcustom macaulay2-blink-region-flag t
  "Non-nil means evaluated region is highlighted.
The duration is `macaulay2-blink-delay' seconds."
  :type 'boolean
  :group 'macaulay2)

(macaulay2-legacy-defcustom macaulay2-blink-delay .3
  "The number of seconds that the evaluated region is highlighted.
Only if `macaulay2-blink-region-flag' is non-nil."
  :type 'number
  :group 'macaulay2)

(defvar macaulay2-current-region-overlay
  (let ((overlay (make-overlay (point) (point))))
    (overlay-put overlay 'face 'highlight)
    overlay)
  "The overlay for highlighting currently evaluated region or line.")

(defun macaulay2-blink-region (start end)
  "Highlight the evaluated region for `macaulay2-blink-delay' seconds.
Only if `macaulay2-blink-region-flag' is non-nil.  The highlighted region is
bounded by START and END."
  (when macaulay2-blink-region-flag
    (move-overlay macaulay2-current-region-overlay start end)
    (run-with-timer macaulay2-blink-delay nil
                    (lambda ()
                      (delete-overlay macaulay2-current-region-overlay)))))

(macaulay2-legacy-defun macaulay2-toggle-blink-region-flag ()
  "Toggle the value of `macaulay2-blink-region-flag'."
  (interactive)
  (setq macaulay2-blink-region-flag (not macaulay2-blink-region-flag)))

(provide 'macaulay2)

; Local Variables:
; compile-command: "make -C $macaulay2BUILDDIR/Macaulay2/emacs "
; coding: utf-8
; End:
;;; macaulay2.el ends here
