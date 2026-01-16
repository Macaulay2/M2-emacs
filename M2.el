;;; M2.el --- Major mode for editing Macaulay2 source core -*- lexical-binding: t -*-

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
(require 'M2-symbols)

(defgroup M2 nil
  "Support for Macaulay2 language development."
  :group 'languages
  :prefix "M2-")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; key bindings
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun M2-define-common-keys (map)
  "Define keys in MAP that are common to both `M2-mode' and `M2-comint-mode'."
  (define-key map (kbd "<f12>") #'M2) ; user may want to make this one global
  (define-key map (kbd "M-<f12>") #'M2-demo)
  (define-key map (kbd "C-<f11>") #'M2-switch-to-demo-buffer)
  (define-key map (kbd "M-<f11>") #'M2-set-demo-buffer)
  (define-key map (kbd "C-c TAB") #'completion-at-point)
  (define-key map (kbd "M-<tab>") #'completion-at-point)
  (define-key map (kbd "<f10>") #'M2-match-next-bracketed-input)
  (define-key map (kbd "M-<f10>") #'M2-match-previous-bracketed-input))

(defvar M2-mode-map
  (let ((map (make-sparse-keymap)))
    (M2-define-common-keys map)
    (define-key map (kbd "DEL") #'backward-delete-char-untabify)
    (define-key map (kbd ";") #'M2-electric-semi)
    (define-key map (kbd "<C-return>") #'M2-send-to-program)
    (define-key map (kbd "<f11>") #'M2-send-to-program)
    (define-key map (kbd "C-c C-j") #'M2-send-line-to-program)
    (define-key map (kbd "C-c C-r") #'M2-send-region-to-program)
    (define-key map (kbd "C-c C-b") #'M2-send-buffer-to-program)
    (define-key map (kbd "C-c <C-up>") #'M2-send-buffer-from-beg-to-here-to-program)
    (define-key map (kbd "C-c <C-down>") #'M2-send-buffer-from-here-to-end-to-program)
    (define-key map (kbd "C-c C-p") #'M2-send-paragraph-to-program)
    map))

(defvar M2-comint-mode-map
  (let ((map (make-sparse-keymap)))
    (M2-define-common-keys map)
    (define-key map (kbd "TAB") #'completion-at-point)
    (define-key map (kbd "<f2>") #'M2-position-point)
    (define-key map (kbd "C-c :") #'M2-position-point)
    (define-key map (kbd "<f3>") #'M2-jog-left)
    (define-key map (kbd "C-c <") #'M2-jog-left)
    (define-key map (kbd "<f4>") #'M2-jog-right)
    (define-key map (kbd "C-c >") #'M2-jog-right)
    (define-key map (kbd "C-c C-t") #'M2-toggle-truncate-lines)
    (define-key map (kbd "<f11>") #'M2-send-input-or-get-input-from-demo-buffer)
    map))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; M2-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;###autoload
(define-derived-mode M2-mode prog-mode "Macaulay2"
  "Major mode for editing Macaulay2 source code.

\\\{M2-mode-map}."
  (M2-common))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.m2\\'" . M2-mode))

(defcustom M2-indent-level 4
  "Indentation increment in Macaulay2 mode."
  :type 'integer
  :group 'Macaulay2)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; M2-comint-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst M2-comint-prompt-regexp "^\\([ \t]*\\(i*[1-9][0-9]* :\\|o*[1-9][0-9]* =\\) \\)?"
  "Regular expression for the Macaulay2 prompt.")

(defvar M2-error-regexp-alist
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

(defvar M2-transform-file-match-alist
  '(("^stdio$" nil)
    ("^currentString$" nil)
    ("^[0-9][0-9]$" nil))
  "List of filenames not to match in Macaulay2 output.")

;;;###autoload
(define-derived-mode M2-comint-mode comint-mode "Macaulay2 Interaction"
  "Major mode for interacting with a Macaulay2 process.

\\{M2-comint-mode-map}"
  (M2-common)
  (setq comint-prompt-regexp M2-comint-prompt-regexp)
  (add-hook 'comint-input-filter-functions #'M2-comint-forget-errors nil t)
  (add-hook 'comint-preoutput-filter-functions #'M2-info-help nil t)
  (add-hook 'comint-output-filter-functions #'M2-comint-fix-unclosed nil t)
  (setq-local compilation-error-regexp-alist M2-error-regexp-alist)
  (setq-local compilation-transform-file-match-alist
	      M2-transform-file-match-alist)
  (compilation-shell-minor-mode 1))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Common definitions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defconst M2-mode-font-lock-keywords
  (list
   (cons M2-symbols-keyword-regexp  'font-lock-keyword-face)
   (cons M2-symbols-type-regexp     'font-lock-type-face)
   (cons M2-symbols-function-regexp 'font-lock-function-name-face)
   (cons M2-symbols-constant-regexp 'font-lock-constant-face)))

; TODO:
; font-lock-warning-face
; font-lock-variable-name-face
; font-lock-builtin-face
; font-lock-preprocessor-face
; font-lock-doc-face
; font-lock-negation-char-face

(defun M2-common ()
  "Set up features common to both Macaulay2 major modes."
  (set (make-local-variable 'comment-start) "-- ")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'comment-column) 60)
  (set (make-local-variable 'comment-start-skip) "-- *")
  (set (make-local-variable 'comint-input-autoexpand) nil)
  (set (make-local-variable 'transient-mark-mode) t)
  (set (make-local-variable 'indent-line-function) #'M2-electric-tab)
  (setq font-lock-defaults '( M2-mode-font-lock-keywords ))
  (setq truncate-lines t)
  (setq case-fold-search nil)
  (add-hook 'completion-at-point-functions #'M2-completion-at-point nil t))

;; menus

(defvar M2-common-menu
      '(["Match previous bracketed input" M2-match-previous-bracketed-input]
	["Match next bracketed input"     M2-match-next-bracketed-input]
	["Set demo buffer"                M2-set-demo-buffer]
	["Switch to demo buffer"          M2-switch-to-demo-buffer]
	["Start demo"                     M2-demo])
      "Common parts of menus for both `M2-mode' and `M2-comint-mode'.")

(easy-menu-define M2-menu M2-mode-map
  "Menu for Macaulay2 major mode."
  (append
   '("Macaulay2"
     ["Start Macaulay2"               M2]
     ["Send line/region to Macaulay2" M2-send-to-program]
     ["Send line to Macaulay2"        M2-send-line-to-program]
     ["Send region to Macaulay2"      M2-send-region-to-program]
     ["Send buffer to Macaulay2"      M2-send-buffer-to-program]
     ["Send buffer to here to Macaulay2"
      M2-send-buffer-from-beg-to-here-to-program]
     ["Send buffer from here to Macaulay2"
      M2-send-buffer-from-here-to-end-to-program]
     ["Send paragraph to Macaulay2"   M2-send-paragraph-to-program]
     ["Highlight evaluated region"    M2-toggle-blink-region-flag
      :style toggle :selected M2-blink-region-flag]
     "-")
   M2-common-menu))

(easy-menu-define M2-comint-menu M2-comint-mode-map
  "Menu for Macaulay2 Interaction major mode."
  (append
   '("Macaulay2 Interaction"
     ["Send to Macaulay2"   comint-send-input]
     ["Get demo input"      M2-get-input-from-demo-buffer]
     ["Send to M2 or get demo input"
      M2-send-input-or-get-input-from-demo-buffer]
     ["Go to end of prompt" M2-to-end-of-prompt]
     ["Center point"        M2-position-point]
     ["Jog left"            M2-jog-left]
     ["Jog right"           M2-jog-right]
     ["Toggle word wrap"    M2-toggle-truncate-lines]
    "-")
   M2-common-menu))

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
 (list M2-mode-syntax-table M2-comint-mode-syntax-table))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; M2 interpreter
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defcustom M2-exe "M2"
  "The default Macaulay2 executable name."
  :type 'string
  :group 'Macaulay2)
(defcustom M2-command
  (concat M2-exe " --no-readline --print-width " (number-to-string (- (window-body-width) 1)) " ")
  "The default Macaulay2 command line."
  :type 'string
  :group 'Macaulay2)

(defvar M2-shell-exe "/bin/sh" "The default shell executable name.")
(defvar M2-history nil "The history of recent Macaulay2 command lines.")
(defvar M2-send-to-buffer-history nil "The history of recent Macaulay2 send-to buffers.")
(defvar M2-tag-history () "The history of recent Macaulay2 command name tags.")
(defvar M2-usual-jog 30 "Usual distance scrolled by `M2-jog-left' and `M2-jog-right'.")

(defun M2-add-width-option (command)
  "Set the print width specified in COMMAND to match the window width."
  (let ((print-width (concat "--print-width "
			     (number-to-string (1- (window-body-width))))))
    (if (string-match "--print-width +[0-9]+" command)
	(replace-match print-width t t command)
      (concat command " " print-width))))

;;;###autoload
(defun M2 (command name)
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
      (read-from-minibuffer "M2 command line: " (M2-add-width-option (if M2-history (car M2-history) M2-command))
			    nil nil (if M2-history '(M2-history . 1) 'M2-history)))
     (M2-history (M2-add-width-option (car M2-history)))
     (t (M2-add-width-option M2-command)))
    (cond
     ((equal current-prefix-arg '(16)) (read-from-minibuffer "M2 buffer name tag: " "M2" nil nil 'M2-tag-history '("M2" "M2-1.1")))
     (M2-tag-history (car M2-tag-history))
     (t "M2"))))
  (let* ((buffer-name (concat "*" name "*"))
	(buffer (get-buffer-create buffer-name)))
    (pop-to-buffer buffer)
    (unless (comint-check-proc buffer)
      (let ((n (if (boundp 'text-scale-mode-amount) text-scale-mode-amount 0)))
	(make-comint name M2-shell-exe nil "-c" (concat "echo; set -x; " command))
	(M2-comint-mode)
	(text-scale-set n)))
    buffer))

(defun M2-left-hand-column ()
  "Return the column at the left hand side of the window."
  (window-hscroll))
(defun M2-right-hand-column ()
  "Return the column at the right hand side of the window."
  (+ (window-hscroll) (window-body-width) -1))
(defun M2-on-screen ()
  "Return whether the current column is visible in the window."
  (and (< (M2-left-hand-column) (current-column))
       (< (current-column) (M2-right-hand-column))))
(defun M2-position-point (pos)
  "Scroll display horizontally.
Point ends up at center of screen or at column position given by POS."
  (interactive "P")
  (if (listp pos) (setq pos (car pos)))
  (if (not pos)
      (setq pos (/ (window-body-width) 2))
    (if (< pos 0) (setq pos (+ pos (window-body-width)))))
  (set-window-hscroll (selected-window) (+ 1 (- (current-column) pos))))

(defun M2-jog-right (arg)
  "Move point right and scroll display so it remains visible.
Optional prefix argument ARG tells how far to move."
  (interactive "P")
  (if (listp arg) (setq arg (car arg)))
  (goto-char
   (if arg
       (+ (point) arg)
     (min (save-excursion (end-of-line) (point)) (+ (point) M2-usual-jog))))
  (if (not (M2-on-screen)) (M2-position-point -2)))

(defun M2-jog-left (arg)
  "Move point left and scroll display so it remains visible.
Optional prefix argument ARG tells how far to move."
  (interactive "P")
  (if (listp arg) (setq arg (car arg)))
  (goto-char
   (if arg
       (- (point) arg)
     (max (save-excursion (beginning-of-line) (point)) (- (point) M2-usual-jog))))
  (if (not (M2-on-screen)) (M2-position-point 1)))

(defun M2-toggle-truncate-lines ()
  "Toggle the value of `truncate-lines'.
This is the variable which determines whether long lines are truncated or
wrapped on the screen."
  (interactive)
  (setq truncate-lines (not truncate-lines))
  (if truncate-lines
      (if (not (M2-on-screen))
	  (set-window-hscroll
	   (selected-window)
	   (- (current-column) (/ (window-body-width) 2))))
    (set-window-hscroll (selected-window) 0))
  (M2-update-screen))

(defun M2-update-screen ()
  "Redisplay the selected window."
    (set-window-start (selected-window) (window-start (selected-window))))

(defun M2-completion-at-point ()
  "Function used for `completion-at-point-functions' for the M2 major modes."
  (let* ((bounds (bounds-of-thing-at-point 'symbol))
         (start (car bounds))
         (end (cdr bounds)))
    (list start end M2-symbols-completion-table :exclusive 'no)))

(defun M2-to-end-of-prompt ()
     "Move to end of prompt matching `M2-comint-prompt-regexp' on this line."
     (interactive)
     (beginning-of-line)
     (let ((case-fold-search nil))
       (if (looking-at M2-comint-prompt-regexp)
	   (goto-char (match-end 0))
	 (back-to-indentation))))

(defun M2-match-next-bracketed-input ()
  "Move forward to the next region bracketed by <<< and >>>.
Mark it with the point and the mark.  After marking the region, the code
can be executed with \\[M2-send-to-program]."
  (interactive)
  (goto-char
   (prog1
       (re-search-forward "<<<")
     (re-search-forward ">>>")
     (set-mark (match-beginning 0)))))

(defun M2-match-previous-bracketed-input ()
  "Move backward to the previous region bracketed by <<< and >>>.
Mark it with the point and the mark.  After marking the region, the code
can be executed with \\[M2-send-to-program]."
  (interactive)
  (goto-char
   (progn
     (re-search-backward ">>>")
     (set-mark (match-beginning 0))
     (re-search-backward "<<<")
     (match-end 0))))

(define-obsolete-function-alias
  'M2-send-input #'comint-send-input "1.23")

(define-obsolete-function-alias
  'M2-send-to-program-or-jump-to-source-code #'comint-send-input "1.22")

(defun M2--get-send-to-buffer ()
  "Helper function for `M2-send-to-program' and friends.
Gets buffer for Macaulay2 inferior process from minibuffer or history."
  (list
   (cond (current-prefix-arg
	  (read-from-minibuffer "buffer to send command to: " "*M2*" nil nil
				'M2-send-to-buffer-history))
	 (t (car M2-send-to-buffer-history)))))

(defun M2--send-to-program-helper (send-to-buffer start end)
  "Helper function for `M2-send-to-program' and friends.
Sends code between START and END to Macaulay2 inferior process in
SEND-TO-BUFFER."
  (unless (and (get-buffer send-to-buffer) (get-buffer-process send-to-buffer))
    (user-error
     "Start a Macaulay2 process first with `M-x M2' or `%s'.?"
     (key-description (where-is-internal #'M2 overriding-local-map t))))
  (display-buffer send-to-buffer '(nil (inhibit-same-window . t)))
  (let ((cmd (buffer-substring start end)))
    (M2-blink-region start end)
    (with-current-buffer send-to-buffer
      (goto-char (point-max))
      (insert cmd)
      (comint-send-input)
      (set-window-point (get-buffer-window send-to-buffer 'visible) (point)))))

(defun M2-send-region-to-program (send-to-buffer)
  "Send the current region to the M2 process in SEND-TO-BUFFER.
See `M2-send-to-program' for more."
  (interactive (M2--get-send-to-buffer))
  (M2--send-to-program-helper send-to-buffer (region-beginning) (region-end)))

(defun M2-send-line-to-program (send-to-buffer)
  "Send the current line to the M2 process in SEND-TO-BUFFER.
See `M2-send-to-program' for more."
  (interactive (M2--get-send-to-buffer))
  (M2--send-to-program-helper send-to-buffer
			      (save-excursion (M2-to-end-of-prompt) (point))
			      (line-end-position))
  (forward-line)
  ;; add a newline after a nonempty line at the end of the buffer
  (when (and (eobp) (not (bolp))) (newline)))

(defun M2-send-to-program (send-to-buffer)
  "Send the current line or region to the M2 process in SEND-TO-BUFFER.
Send the current line except for a possible prompt, or the region, if the
mark is active, to Macaulay2 in its buffer, making its window visible.
Afterwards, in the case where the mark is not active, move the cursor to
the next line.  With a prefix argument, the name of the buffer to
which this and future uses of the command (in this buffer) should be
sent can be entered, with history."
     (interactive (M2--get-send-to-buffer))
     (if (region-active-p)
	 (M2-send-region-to-program send-to-buffer)
       (M2-send-line-to-program send-to-buffer)))

(defun M2-send-buffer-to-program (send-to-buffer)
  "Send the entire buffer to the M2 process in SEND-TO-BUFFER.
See `M2-send-to-program' for more."
  (interactive (M2--get-send-to-buffer))
  (M2--send-to-program-helper send-to-buffer (point-min) (point-max)))

(defun M2-send-buffer-from-beg-to-here-to-program (send-to-buffer)
  "Send everything before the the point the M2 process in SEND-TO-BUFFER.
See `M2-send-to-program' for more."
  (interactive (M2--get-send-to-buffer))
  (M2--send-to-program-helper send-to-buffer (point-min) (point)))

(defun M2-send-buffer-from-here-to-end-to-program (send-to-buffer)
  "Send everything after the the point the M2 process in SEND-TO-BUFFER.
See `M2-send-to-program' for more."
  (interactive (M2--get-send-to-buffer))
  (M2--send-to-program-helper send-to-buffer (point) (point-max)))

(defun M2-send-paragraph-to-program (send-to-buffer)
  "Send the current paragraph to the M2 process in SEND-TO-BUFFER.
See `M2-send-to-program' for more."
  (interactive (M2--get-send-to-buffer))
  (let ((end (progn (forward-paragraph) (point)))
	(start (progn (backward-paragraph) (point))))
    (M2--send-to-program-helper send-to-buffer start end))
  (forward-paragraph))

(defvar M2-demo-buffer
  (with-current-buffer (get-buffer-create "*M2-demo-buffer*")
    (M2-mode)
    (current-buffer))
  "The buffer from which lines are obtained by `M2-get-input-from-demo-buffer'.
Set it with `M2-set-demo-buffer'." )

(defun M2-set-demo-buffer ()
  "Set the variable `M2-demo-buffer' to the current buffer.
Later, `M2-get-input-from-demo-buffer' can obtain lines from this buffer."
  (interactive)
  (setq M2-demo-buffer (current-buffer)))

(defun M2-switch-to-demo-buffer ()
  "Switch to the buffer given by the variable `M2-demo-buffer'."
  (interactive)
  (switch-to-buffer M2-demo-buffer))

(declare-function toggle-scroll-bar "scroll-bar")

(defun M2-demo ()
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
    ; (M2)
    (with-current-buffer "*M2*"
      (setq comint-scroll-show-maximum-output t))))

(defun M2-get-input-from-demo-buffer ()
  "Copy the current line from `M2-demo-buffer' to the prompt."
  (interactive)
  (insert (with-current-buffer M2-demo-buffer
	    (prog1
		(if (eobp)
		    (concat "-- end of buffer " (buffer-name (current-buffer)))
		  (buffer-substring
		   (prog2 (M2-to-end-of-prompt) (point))
		   (line-end-position)))
	      (forward-line)))))

(defun M2-send-input-or-get-input-from-demo-buffer ()
  "Either send input to Macaulay2 or get input from the demo buffer.
If current line is blank, then copy the current line of `M2-demo-buffer'.
Otherwise, send the input to Macaulay2."
  (interactive)
  (if (save-excursion (M2-to-end-of-prompt) (looking-at-p "[[:blank:]]*$"))
      (M2-get-input-from-demo-buffer)
    (comint-send-input)))

(defun M2-info-help (string)
  "Load info documentation for Macaulay2.
When using the infoHelp function, M2 emits a special string.  If the M2
output given by STRING matches, then load the corresponding documentation."
  (if (string-match "-\\* infoHelp: \\(.*\\) \\*-" string)
      (let ((end (1+ (match-end 0))))
	(save-excursion
	  (with-demoted-errors "%S"
	    (info-other-window (match-string 1 string))))
	(substring string end))
    string))

(defun M2-comint-insert-invisible-at-bol (string)
  "Insert STRING with the invisible property at the beginning of the line."
  (save-excursion
    (beginning-of-line)
    (insert string)
    (put-text-property (- (point) (length string)) (point) 'invisible t)))

(defun M2-comint-fix-unclosed (string)
  "Close any unclosed strings or comments from the output.
STRING is the current Macaulay2 output, which we check to see whether we're at
a new input prompt."
  (ignore string)
  (when (string-match-p "^[ \t]*i+[1-9][0-9]* : " string)
    (let ((syntax (syntax-ppss (point))))
      (cond
       ((nth 3 syntax) (M2-comint-insert-invisible-at-bol "\""))
       ((nth 4 syntax) (M2-comint-insert-invisible-at-bol "*-"))))))

(declare-function compilation-forget-errors "compile")

(defun M2-comint-forget-errors (string)
  "Run `compilation-forget-errors' to flush compilation mode's cache.
Otherwise, jumping to source will go to the wrong location when a file has
been modified and reloaded.  STRING is ignored, but we need it so that this
function can be added to `comint-input-filter-functions' so that it is run each
time we send new input to the M2 process."
  (ignore string)
  (compilation-forget-errors))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; M2-mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(if (not (boundp 'font-lock-constant-face))
    (setq font-lock-constant-face font-lock-function-name-face))

(defun M2-paren-change ()
  "Return change in paren depth on current line."
  (save-excursion
    (car (parse-partial-sexp (prog2 (beginning-of-line) (point))
			     (prog2 (end-of-line) (point))))))

(defun M2-electric-semi ()
  "Insert a semicolon and start a new line."
     (interactive)
     (insert ?\;)
     (and (eolp) (M2-next-line-blank) (= 0 (M2-paren-change))
	 (newline nil t)))

(defun M2-next-line-indent-amount ()
  "Determine how much to indent the next line."
     (+ (current-indentation) (* (M2-paren-change) M2-indent-level)))

(defun M2-this-line-indent-amount ()
     "Determine how much to indent the current line."
     (save-excursion
	  (beginning-of-line)
	  (if (bobp)
	      0
	      (forward-line -1)
	      ;; if the previous line is blank, then keep going
	      (while (and (not (bobp)) (looking-at-p "[[:blank:]]*$"))
		(forward-line -1))
	      (M2-next-line-indent-amount))))

(defun M2-in-front ()
  "Determine whether we are at the front of the line."
     (save-excursion (skip-chars-backward " \t") (bolp)))

(defun M2-blank-line ()
  "Determine whether the line is blank."
     (save-excursion (beginning-of-line) (skip-chars-forward " \t") (eolp)))

(defun M2-next-line-blank ()
  "Determine whether the next line is blank."
     (save-excursion
	  (end-of-line)
	  (or (eobp)
	      (progn (forward-char) (M2-blank-line)))))

(define-obsolete-function-alias
  'M2-newline-and-indent #'newline "1.23")

(defun M2-electric-right-brace ()
  "Insert a right brace and start a new line."
     (interactive)
     (self-insert-command 1)
     (and (eolp) (M2-next-line-blank) (< (M2-paren-change) 0) (newline nil t)))

(defcustom M2-insert-tab-commands '(indent-for-tab-command org-cycle)
  "Commands for which `M2-electric-tab' should insert a tab."
  :type '(repeat function)
  :group 'Macaulay2)

(defun M2-electric-tab ()
  "`indent-line-function' for Macaulay2.
If called by command in `M2-insert-tab-commands', and if the point is either
to right of non-whitespace characters in the same line or if the line
is blank, then insert `M2-indent-level' spaces.  Otherwise, indent the
line based on the depth of the parentheses in the code."
  (interactive)
  (indent-to
   (prog1 (if (and (memq this-command M2-insert-tab-commands)
		   (or (not (M2-in-front)) (M2-blank-line)))
	      (+ (current-column) M2-indent-level)
	    (M2-this-line-indent-amount))
     (delete-horizontal-space))))

;;; "blink" evaluated region (heavily inspired by ESS)

(defcustom M2-blink-region-flag t
  "Non-nil means evaluated region is highlighted for `M2-blink-delay' seconds."
  :type 'boolean
  :group 'Macaulay2)

(defcustom M2-blink-delay .3
  "The number of seconds that the evaluated region is highlighted.
Only if `M2-blink-region-flag' is non-nil."
  :type 'number
  :group 'Macaulay2)

(defvar M2-current-region-overlay
  (let ((overlay (make-overlay (point) (point))))
    (overlay-put overlay 'face 'highlight)
    overlay)
  "The overlay for highlighting currently evaluated region or line.")

(defun M2-blink-region (start end)
  "Highlight the evaluated region for `M2-blink-delay' seconds.
Only if `M2-blink-region-flag` is non-nil.  The highlighted region is bounded
by START and END."
  (when M2-blink-region-flag
    (move-overlay M2-current-region-overlay start end)
    (run-with-timer M2-blink-delay nil
                    (lambda ()
                      (delete-overlay M2-current-region-overlay)))))

(defun M2-toggle-blink-region-flag ()
  "Toggle the value of `M2-blink-region-flag'."
  (interactive)
  (setq M2-blink-region-flag (not M2-blink-region-flag)))

(provide 'M2)

; Local Variables:
; compile-command: "make -C $M2BUILDDIR/Macaulay2/emacs "
; coding: utf-8
; End:
;;; M2.el ends here
