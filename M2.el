;;; M2.el --- Major mode for editing Macaulay2 source core -*- lexical-binding: t -*-

;; Copyright (C) 1997-2026 The Macaulay2 Authors

;; Version: 1.26.06
;; Keywords: languages
;; URL: https://github.com/Macaulay2/M2-emacs
;; Package-Requires: ((emacs "24.4"))

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
(require 'smie)
(require 'thingatpt)
(require 'M2-symbols)
(require 'M2-operators)

(defgroup M2 nil
  "Support for Macaulay2 language development."
  :group 'languages
  :prefix "M2-")

(defcustom M2-indent-level 4
  "Indentation increment in Macaulay2 mode."
  :type 'integer
  :group 'M2)

;; Required after the group it adds to is defined, and before anything
;; below uses `M2-simple-doc-string-openers'.
(require 'M2-simple-doc)

;;; SMIE (Simple Minded Indentation Engine)

;; The operator tables come from M2-operators.el, which is generated from the
;; parsing tables of Macaulay2 itself; see generate-operators.m2.

(eval-and-compile

  (defconst M2-smie--block-keywords
    '("if" "then" "else" "try" "except" "while" "for" "new"
      "do" "list" "of" "from" "in" "to" "when")
    "Macaulay2 keywords that introduce or continue a block expression.")

  (defconst M2-smie--operators
    ;; "///" is here so that a doc or TEST string delimiter lexes as one
    ;; token rather than as the quotient operators // and /.  Its contents
    ;; are deliberately left as ordinary code, not marked as a string.
    (let ((ops (append M2-operators-postfix '("<|" "|>" ";" "///"))))
      (dolist (row M2-operators-binary)
        (dolist (op (cdr row))
          ;; The word operators (and, or, xor) are lexed as words.
          (unless (string-match-p "\\`[[:alpha:]]" op)
            (push op ops))))
      (delete-dups ops))
    "Every Macaulay2 operator spelled with punctuation.")

  (defconst M2-smie--operator-regexp (regexp-opt M2-smie--operators)
    "Regexp matching the longest Macaulay2 operator at point.")

  (defconst M2-smie--continuation-tokens
    (let ((toks (append M2-smie--block-keywords
                        '("(" "[" "{" "<|" "and" "or" "xor" "not"
                          ;; `quote' expressions: an identifier must follow.
                          "symbol" "global" "local"
                          "threadLocal" "threadVariable"))))
      (dolist (row M2-operators-binary)
        (dolist (op (cdr row)) (push op toks)))
      (delete-dups toks))
    "Tokens after which a newline continues the current statement.
Every binary and prefix operator qualifies, since a right operand is still
expected.  Postfix operators do not, and neither do the prefix control-flow
words (`return', `break', `continue', ...): each of those can legitimately
be the last thing on a line."))

(defconst M2-smie-grammar
  (eval-when-compile
    (smie-prec2->grammar
     (smie-merge-prec2s
      (smie-bnf->prec2
       ;; Every slot but the final body uses BEXP, which admits only
       ;; bracketed expressions.  With EXP throughout, `smie-bnf->prec2'
       ;; relates every pair of inner keywords in both directions at once
       ;; (each is both preceded by EXP and a member of its last-ops), and
       ;; `smie-prec2->grammar' then reports an unresolvable precedence
       ;; cycle such as "then < in < then".  Resolvers cannot help: they
       ;; only apply where a conflict already exists.  Final bodies stay
       ;; EXP, so `else if' chains and do/from bodies remain exact.
       '((bexp ("(" exps ")") ("[" exps "]") ("{" exps "}") ("<|" exps "|>"))
         (exp (bexp)
              ("if"  bexp "then" exp)
              ("if"  bexp "then" bexp "else" exp)
              ("try" bexp "then" exp)
              ("try" bexp "then" bexp "else" exp)
              ("try" bexp "else" exp)
              ("try" bexp "then" bexp "except" bexp "do" exp)
              ("try" bexp "except" bexp "do" exp)
              ("while" bexp "do" exp)
              ("while" bexp "list" exp)
              ("while" bexp "list" bexp "do" exp)
              ("for" bexp "in" bexp "do" exp)
              ("for" bexp "in" bexp "list" exp)
              ("for" bexp "in" bexp "list" bexp "do" exp)
              ("for" bexp "in" bexp "when" bexp "list" bexp "do" exp)
              ("for" bexp "from" bexp "do" exp)
              ("for" bexp "from" bexp "to" bexp "when" bexp "do" exp)
              ("for" bexp "from" bexp "list" bexp "do" exp)
              ("for" bexp "to" bexp "do" exp)
              ("for" bexp "to" bexp "list" exp)
              ("for" bexp "when" bexp "do" exp)
              ("for" bexp "do" exp)
              ("for" bexp "list" bexp "do" exp)
              ("new" bexp "of" exp)
              ("new" bexp "from" exp)
              ("new" bexp "of" bexp "from" exp))
         (exps (exps ";" exps) (exps "," exps) (exp)))
       '((assoc ";")) '("," > ",") '(";" < ",") '("," > ";"))
      (smie-precs->prec2 M2-operators-binary))))
  "Macaulay2 grammar table for Simple Minded Indentation Engine.")

(defsubst M2-smie--comment-start-p (pos)
  "Return non-nil if a comment can begin at POS.
`M2-syntax-propertize-function' clears the comment flags from -- inside
comint output blocks, so ask the syntax table rather than just matching
the characters."
  ;; Bit 16 of a raw syntax descriptor is the \"1\" flag: this character can
  ;; be the first of a two-character comment opener.
  (let ((syntax (car (syntax-after pos))))
    (and syntax (/= 0 (logand syntax (ash 1 16))))))

(defsubst M2-smie--string-delimiter-p (pos)
  "Return non-nil if the character at POS is a string delimiter.
Unlike `char-syntax', this honors `syntax-table' text properties.  Note
that ///.../// is not a string as far as Macaulay2 mode is concerned."
  ;; 7 is the string-quote class, 15 the generic-string-fence class.
  (memq (syntax-class (syntax-after pos)) '(7 15)))

(defvar-local M2-smie--separator-cache nil
  "Memo for `M2-smie--newline-separator-p'.
A cons of a key describing the buffer state and a hash table mapping the
position of a newline to whether it separates two statements.  The key
covers the accessible portion as well as the chars-modified-tick, since
`M2-smie--matching-block-data' runs the lexer narrowed and the answer
near the edge of a restriction differs from the unrestricted one.")

(defun M2-smie--newline-separator-p ()
  "Return non-nil if the newline at point ends a statement.
Point must be on the newline.  The newline separates two statements unless
the last real token before it still expects a right operand, that is, unless
it is one of `M2-smie--continuation-tokens'.

The answer is memoized, because SMIE asks it once for every newline it
crosses and answering it means scanning back over comments and blank lines."
  (let ((key (list (buffer-chars-modified-tick) (point-min) (point-max)))
        (pos (point)))
    (unless (equal (car M2-smie--separator-cache) key)
      (setq M2-smie--separator-cache (cons key (make-hash-table :test #'eq))))
    (let* ((cache (cdr M2-smie--separator-cache))
           (hit (gethash pos cache 'M2-smie--miss)))
      (if (not (eq hit 'M2-smie--miss))
          hit
        (puthash pos
                 (save-excursion
                   ;; Step past the newline first, so that `forward-comment'
                   ;; can treat it as the end of a -- comment on this line.
                   (forward-char 1)
                   (forward-comment (- (point)))
                   (skip-chars-backward " \t")
                   (not (member (M2-smie--backward-op-token)
                                M2-smie--continuation-tokens)))
                 cache)))))

(defun M2-smie-forward-token ()
  "Return the Macaulay2 token after point, moving over it.
A newline is reported as a virtual \";\" when it separates two statements,
and skipped otherwise.  String literals are left alone: returning an empty
token without moving is how a SMIE lexer asks the engine to step over
whatever is at point itself."
  (catch 'M2-smie--token
    (while t
      (skip-chars-forward " \t")
      (cond
       ((eobp) (throw 'M2-smie--token ""))
       ;; Stop a -- comment at the newline rather than stepping over it, so
       ;; the newline can still be seen as a statement separator.
       ((and (looking-at-p "--") (M2-smie--comment-start-p (point)))
        (end-of-line))
       ;; An unterminated -* is a state every block comment passes through
       ;; while it is being typed, and `forward-comment' declines to move
       ;; over one; without the fallback this loop would never end.
       ((and (looking-at-p "-\\*") (M2-smie--comment-start-p (point)))
        (unless (forward-comment 1) (goto-char (point-max))))
       ((eolp)
        (if (M2-smie--newline-separator-p)
            (progn (forward-char 1) (throw 'M2-smie--token ";"))
          (forward-char 1)))
       ((M2-smie--string-delimiter-p (point))
        (throw 'M2-smie--token ""))
       ((looking-at M2-smie--operator-regexp)
        (goto-char (match-end 0))
        (throw 'M2-smie--token (match-string-no-properties 0)))
       (t
        (let ((beg (point)))
          (skip-syntax-forward "w_'")
          (when (and (= beg (point))
                     (not (memq (char-syntax (char-after)) '(?\( ?\)))))
            ;; Not a word, an operator, a bracket or a string.  Consume it
            ;; anyway: an empty token means "SMIE, step over this yourself",
            ;; and SMIE can only do that for brackets and strings --- for
            ;; anything else it gives up with "Bumped into unknown token".
            (forward-char 1))
          (throw 'M2-smie--token
                 (buffer-substring-no-properties beg (point)))))))))

(defun M2-smie--backward-op-token ()
  "Return the operator or word ending at point, moving to its start."
  (let ((end (point)))
    (cond
     ;; A string delimiter, which SMIE steps over itself.  Checked before the
     ;; operator run below, since the / of a closing /// would otherwise read
     ;; as the division operator and make the newline after it look like a
     ;; continuation of the statement.
     ((and (> end (point-min)) (M2-smie--string-delimiter-p (1- end))) "")
     ;; A word, a number, or one of the word operators.
     ((< (skip-syntax-backward "w_'") 0)
      (buffer-substring-no-properties (point) end))
     ;; A run of operator characters.  Rather than try to recognize an
     ;; operator right-to-left, re-lex the run forward with the same regexp
     ;; `M2-smie-forward-token' uses and keep the token that reaches END.
     ;; The two directions then agree by construction, which is what SMIE
     ;; requires of them.  ("\\" is here because M2's syntax table gives
     ;; backslash escape syntax, to fontify "a\"b" correctly.)
     ((< (skip-syntax-backward ".\\") 0)
      (let (beg tok)
        (while (< (point) end)
          (setq beg (point))
          (setq tok (if (looking-at M2-smie--operator-regexp)
                        (progn (goto-char (match-end 0))
                               (match-string-no-properties 0))
                      (forward-char 1)
                      (buffer-substring-no-properties beg (point)))))
        (goto-char beg)
        tok))
     ;; A bracket, which SMIE steps over itself given an empty token.
     ((or (bobp) (memq (char-syntax (char-before)) '(?\( ?\)))) "")
     ;; Anything else: consume one character, as the forward lexer does.
     (t (backward-char 1)
        (buffer-substring-no-properties (point) end)))))

(defun M2-smie-backward-token ()
  "Return the Macaulay2 token before point, moving to its start.
The exact inverse of `M2-smie-forward-token'."
  (catch 'M2-smie--token
    (while t
      ;; Horizontal whitespace only: `forward-comment' would swallow the
      ;; newline before we get a chance to report it as a separator.
      (skip-chars-backward " \t")
      (cond
       ((bobp) (throw 'M2-smie--token ""))
       ((eq (char-before) ?\n)
        (backward-char)
        (if (M2-smie--newline-separator-p)
            ;; Leave point on the newline: that is where the virtual ";" is.
            (throw 'M2-smie--token ";")
          ;; Not a separator.  Step back over the newline, and over any
          ;; comment or blank lines before it, then keep looking.
          (forward-char 1)
          (forward-comment (- (point)))))
       ((M2-smie--string-delimiter-p (1- (point)))
        (throw 'M2-smie--token ""))
       (t (throw 'M2-smie--token (M2-smie--backward-op-token)))))))

(defun M2-smie--block-keyword-p (token)
  "Return non-nil if TOKEN is one of `M2-smie--block-keywords'."
  (and (stringp token) (member token M2-smie--block-keywords)))

(defconst M2-smie--narrow-keywords '("when" "of" "in" "from" "to")
  "Block keywords that Macaulay2 binds more tightly than an assignment.
Macaulay2's parsing tables give these the precedence they call \"narrow\",
one level above := and friends, which is why

    new X from Y := f

installs a method on the whole \"new X from Y\" rather than assigning to Y.
`M2-smie-grammar' cannot say the same, since a single precedence level per
token cannot make \"from\" tighter than := and at the same time hold
\"for i from 1 do ...\" together.  So \"from\" comes out as the parent of
the :=, and `M2-smie-rules' compensates.")

(defconst M2-smie--assignment-operators
  (let (ops)
    (dolist (row M2-operators-binary)
      (when (member ":=" (cdr row)) (setq ops (cdr row))))
    ops)
  "The Macaulay2 operators that bind exactly as loosely as :=.
This is one row of `M2-operators-binary', so it too comes from Macaulay2's
parsing tables: =, <-, ->, =>, >> and the augmented assignments.")

(defun M2-smie--assignment-p (token)
  "Return non-nil if TOKEN is one of `M2-smie--assignment-operators'."
  (and (stringp token) (member token M2-smie--assignment-operators)))

(defun M2-smie--bracket-indentation ()
  "Return the column for a line inside the innermost enclosing bracket.
Return nil at top level.  Only the brackets `syntax-ppss' reports count,
that is, the ones spelled with a single character.  A bracket with
something after it on its line lines its contents up with that; a bracket
left hanging indents them one step in from where the bracket itself would
go.  The measurement is taken
from the buffer rather than through SMIE's notion of the parent, which
loses track of the bracket when a separator follows it across a comment
and would then line the statement up with the comment."
  (let ((open (nth 1 (syntax-ppss))))
    (when open
      (save-excursion
        (goto-char open)
        (if (save-excursion (forward-char 1)
                            (skip-chars-forward " \t")
                            ;; A comment after the bracket still leaves it
                            ;; hanging; without this the contents line up
                            ;; with the comment, which is the very thing
                            ;; this function exists to avoid.
                            (or (eolp) (M2-smie--comment-start-p (point))))
            ;; A bracket left hanging indents its contents relative to where
            ;; the bracket itself would go, which is not always the start of
            ;; the line it is on: in "b) else (" the bracket belongs to the
            ;; "if" further up.  `smie-indent-virtual' answers `noindent'
            ;; rather than a column when it lands in a comment or a string,
            ;; and SMIE's own rules signal when they try to do arithmetic on
            ;; that; fall back to the bracket's own line either way.
            (let ((virtual (condition-case nil (smie-indent-virtual)
                             (error nil))))
              (+ (if (numberp virtual) virtual (current-indentation))
                 M2-indent-level))
          ;; Otherwise the contents line up with whatever follows it.
          (1+ (current-column)))))))

(defvar M2-smie--top-level-column 0
  "The column at which a statement at the outermost level begins.
Zero in a buffer of Macaulay2, but not in an `Example' or `Code' section
of a SimpleDoc string, whose code is a whole block indented by the
section around it.  `M2-simple-doc--smie-column' binds this while it runs
the engine over such a body.")

(defun M2-smie-rules (kind token)
  "Macaulay2 indentation rules for Simple Minded Indentation Engine.
KIND is a keyword such as `:before', `:after', or `:elem', and TOKEN
is the token string at the relevant position."
  (pcase (cons kind token)
    ('(:elem . basic) M2-indent-level)
    ('(:elem . args)  M2-indent-level)
    ;; A bracket left hanging at the end of a line indents its contents one
    ;; step in from the line that opens it, not from its own column.  The
    ;; parent is measured as well and the smaller column wins, since either
    ;; one alone can come out too far right: the line that opens the bracket
    ;; may itself be a continuation, as in "b) else (", where the expression
    ;; really begins at the "if" on an earlier line; and the parent may be an
    ;; alignment column in the middle of a line, as in "apply(L, i -> (",
    ;; where the line is where the expression really begins.  Emacs modes for
    ;; the other languages that write a function body this way agree about
    ;; that second case: js-mode, python-mode and julia-mode all indent the
    ;; body one step in from the beginning of the line rather than aligning it
    ;; with the argument list.
    (`(:before . ,(or "(" "[" "{" "<|"))
     (when (smie-rule-hanging-p)
       ;; `smie-rule-parent' signals rather than returning a column when the
       ;; parent turns out to sit next to a comment.
       (let ((parent (condition-case nil (smie-rule-parent) (error nil))))
         (cons 'column (if (eq (car-safe parent) 'column)
                           (min (current-indentation) (cdr parent))
                         (current-indentation))))))
    ;; The body of a block keyword.
    (`(:after . ,(pred M2-smie--block-keyword-p)) M2-indent-level)
    ;; A block keyword continued on a line of its own lines up with its opener.
    (`(:before . ,(pred M2-smie--block-keyword-p))
     (and (not (smie-rule-bolp)) (smie-rule-parent 0)))
    ;; An assignment that SMIE has placed inside one of the keywords of a
    ;; `new' expression, which Macaulay2 would not: see
    ;; `M2-smie--narrow-keywords'.  The assignment in fact begins a
    ;; statement, so measure it from the statement's own column rather than
    ;; from the token after the keyword; otherwise whatever continues
    ;; "new X from Y :=" on the next line lines up under the Y.
    (`(:before . ,(pred M2-smie--assignment-p))
     (and (apply #'smie-rule-parent-p M2-smie--narrow-keywords)
          (cons 'column (or (M2-smie--bracket-indentation)
                            M2-smie--top-level-column))))
    ;; Statement and sequence separators sit where the enclosing bracket
    ;; puts its contents, so that arguments written one to a line line up
    ;; with the first of them in "f(x," and one step in from f in "f(".
    (`(,(or :before :after) . ,(or ";" ","))
     (or (and (smie-rule-parent-p "<|")
              ;; <| is spelled with two characters, so `syntax-ppss' cannot
              ;; report it and `M2-smie--bracket-indentation' cannot see it.
              ;; SMIE knows it from the grammar.  `smie-rule-parent' signals
              ;; rather than returning a column when the parent sits next to
              ;; a comment.
              (condition-case nil (smie-rule-parent M2-indent-level)
                (error nil)))
         (cons 'column
               (or (M2-smie--bracket-indentation)
                   ;; No enclosing bracket at all: a top-level statement, at
                   ;; the outermost column.  This has to be an absolute column
                   ;; rather than an offset of 0, which would be measured from
                   ;; the separator's own column --- and for a newline ending a
                   ;; commented line that is the column the comment ran out to.
                   M2-smie--top-level-column))))))

(defcustom M2-smie-blink-max-distance 3000
  "How far SMIE may scan to find a matching block, in characters.
`show-paren-mode' runs on an idle timer after every cursor motion, and
SMIE's block matching walks the buffer through the lexer, so an unbounded
search makes cursor motion visibly slow in large files."
  :type 'integer
  :group 'M2)

(defun M2-smie--matching-block-data (orig &rest args)
  "Bounded replacement for `smie--matching-block-data'.
Real brackets are handed straight to ORIG, called with ARGS, since the
syntax table matches those far more cheaply than SMIE can.  For block
keywords SMIE is asked, but only within `M2-smie-blink-max-distance'
characters of point."
  (if (or (memq (char-syntax (or (char-after) ?\s)) '(?\( ?\)))
          (memq (char-syntax (or (char-before) ?\s)) '(?\( ?\))))
      (apply orig args)
    (or (save-restriction
          (narrow-to-region
           (max (point-min) (- (point) M2-smie-blink-max-distance))
           (min (point-max) (+ (point) M2-smie-blink-max-distance)))
          ;; Pass `ignore' as ORIG so that a miss inside the narrowing comes
          ;; back as nil rather than as the default matcher's answer, which
          ;; would be computed against the restricted buffer.
          (ignore-errors (apply #'smie--matching-block-data #'ignore args)))
        (apply orig args))))

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
  (M2-common)
  (setq-local indent-tabs-mode nil))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.m2\\'" . M2-mode))

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
   (cons M2-symbols-constant-regexp 'font-lock-constant-face)
   ;; The prose of a doc string is not Macaulay2, and the words it is made
   ;; of collide with the tables above.  Painted last, and over whatever
   ;; they made of it, but never over an @...@ block.
   (list #'M2-simple-doc-fontify-prose '(0 'font-lock-doc-face t))))

; TODO:
; font-lock-warning-face
; font-lock-variable-name-face
; font-lock-builtin-face
; font-lock-preprocessor-face
; font-lock-doc-face
; font-lock-negation-char-face

(defun M2--in-output-block-p (pos)
  "Return non-nil if POS is inside an output block.
This relies on `comint-mode` tagging output with the `field` text property."
  (eq (get-text-property pos 'field) 'output))

(defconst M2-syntax-propertize-function
  (syntax-propertize-rules
   ;; Make "--" act as punctuation (not a comment) in output blocks.
   ("--"
    (0 (let ((pos (match-beginning 0)))
         (when (M2--in-output-block-p pos)
           (string-to-syntax "."))))))
  "Syntax propertize rules for Macaulay2 modes.")

(defun M2-common ()
  "Set up features common to both Macaulay2 major modes."
  (set (make-local-variable 'comment-start) "-- ")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'comment-column) 60)
  (set (make-local-variable 'comment-start-skip) "-- *")
  (set (make-local-variable 'comint-input-autoexpand) nil)
  (set (make-local-variable 'transient-mark-mode) t)
  (smie-setup M2-smie-grammar #'M2-smie-rules
              :forward-token  #'M2-smie-forward-token
              :backward-token #'M2-smie-backward-token)
  ;; `smie-setup' puts its own unbounded block matcher on
  ;; `show-paren-data-function'; swap in the bounded one.
  (remove-function (local 'show-paren-data-function) #'smie--matching-block-data)
  (add-function :around (local 'show-paren-data-function)
                #'M2-smie--matching-block-data)
  (set (make-local-variable 'indent-line-function) #'M2-electric-tab)
  (setq font-lock-defaults '( M2-mode-font-lock-keywords ))
  (setq truncate-lines t)
  (setq case-fold-search nil)
  (add-hook 'completion-at-point-functions #'M2-completion-at-point nil t)
  (setq-local syntax-propertize-function #'M2-syntax-propertize)
  ;; A ///.../// spans lines, so an edit inside one has to re-propertize the
  ;; whole string rather than the line that changed.
  (add-hook 'syntax-propertize-extend-region-functions
            #'syntax-propertize-multiline nil t))

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

;; A ///.../// is not simply a string: what is written in one depends on the
;; word in front of it, and `M2-syntax-propertize' treats the three cases
;; differently.  A TEST string is Macaulay2 code and is left alone; a doc
;; string is SimpleDoc, which quotes Macaulay2 freely, so it stays ordinary
;; text with only its unbalanced delimiters demoted; anything else is a
;; string.  Note that a syntax table cannot express the delimiter itself,
;; since it is three characters long.

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
    (modify-syntax-entry ?|  "." syntax-table)
    ;; These default to word or symbol constituents, but each is an operator
    ;; in Macaulay2 and none of them can occur in an identifier.  Getting this
    ;; right keeps the SMIE lexer, `forward-word' and `bounds-of-thing-at-point'
    ;; from running an operator together with the identifier beside it.
    (modify-syntax-entry ?/  "." syntax-table)
    (modify-syntax-entry ?·  "." syntax-table)
    (modify-syntax-entry ?⊠  "." syntax-table)
    (modify-syntax-entry ?⧢  "." syntax-table)))
 (list M2-mode-syntax-table M2-comint-mode-syntax-table))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; M2 interpreter
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defcustom M2-exe "M2"
  "The default Macaulay2 executable name."
  :type 'string
  :group 'M2)
(defcustom M2-command
  (concat M2-exe " --no-readline --print-width " (number-to-string (- (window-body-width) 1)) " ")
  "The default Macaulay2 command line."
  :type 'string
  :group 'M2)

(defvar M2-shell-exe "/bin/sh" "The default shell executable name.")
(defvar M2-history nil "The history of recent Macaulay2 command lines.")
(defvar M2-send-to-buffer-history nil "The history of recent Macaulay2 send-to buffers.")
(defvar M2-current-tag "M2" "The current Macaulay2 command name tag.")
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
(defun M2 (command name &optional noselect)
  "Run Macaulay2 in a buffer.
With a prefix argument \\[universal-argument], set COMMAND, the command line
given to the shell to run Macaulay2 can be edited in the minibuffer.  With
prefix argument \\[universal-argument] \\[universal-argument], set NAME, the
tag from which the buffer name is constructed (by prepending and appending
asterisks) can be entered in the minibuffer.  The command line will always have
the appropriate option for the width of the current window added to it.
If optional argument NOSELECT is non-nil, do not select the Macaulay2 buffer."
  (interactive
   (list
    (cond
     (current-prefix-arg
      (read-from-minibuffer
       "M2 command line: "
       (M2-add-width-option (if M2-history (car M2-history) M2-command))
       nil nil (if M2-history '(M2-history . 1) 'M2-history)))
     (M2-history (M2-add-width-option (car M2-history)))
     (t (M2-add-width-option M2-command)))
    (cond
     ((equal current-prefix-arg '(16))
      (setq M2-current-tag
	    (read-from-minibuffer
	     "M2 buffer name tag: "
	     (if M2-tag-history (car M2-tag-history) M2-current-tag)
	     nil nil
	     (if M2-tag-history '(M2-tag-history . 1) 'M2-tag-history))))
     (t M2-current-tag))))
  (let* ((buffer-name (concat "*" name "*"))
	       (buffer (get-buffer-create buffer-name)))
    (unless noselect
      (pop-to-buffer buffer))
    (unless (comint-check-proc buffer)
      ;; Ensure initialization runs in the context of the target buffer
      (with-current-buffer buffer
	      (let ((n (if (boundp 'text-scale-mode-amount) text-scale-mode-amount 0)))
	        (make-comint name M2-shell-exe nil "-c" (concat "echo; set -x; " command))
	        (M2-comint-mode)
	        (text-scale-set n))))
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
	  (read-from-minibuffer
	   "buffer to send command to: "
	   (if M2-send-to-buffer-history
	       (car M2-send-to-buffer-history)
	     (concat "*" M2-current-tag "*"))
	   nil nil
	   (if M2-send-to-buffer-history
	       '(M2-send-to-buffer-history . 1)
	     'M2-send-to-buffer-history)))
	 (M2-send-to-buffer-history (car M2-send-to-buffer-history))
	 (t (concat "*" M2-current-tag "*")))))

(defun M2--send-to-program-helper (send-to-buffer start end)
  "Helper function for `M2-send-to-program' and friends.
Sends code between START and END to Macaulay2 inferior process in
SEND-TO-BUFFER."
  (unless (and (get-buffer send-to-buffer) (get-buffer-process send-to-buffer))
    (let ((name (if (string-match "\\*\\(.*\\)\\*" send-to-buffer)
                    (match-string 1 send-to-buffer)
                  M2-current-tag))
          (command (M2-add-width-option (if M2-history (car M2-history) M2-command))))
      (M2 command name t)
      ;; Wait for the process to launch and display its initial prompt
      (when-let ((proc (get-buffer-process send-to-buffer)))
        (let ((timeout 2.0)
              (patience 0.05))
          (while (and (process-live-p proc)
                      (> timeout 0)
                      (not (with-current-buffer send-to-buffer
                             (save-excursion
                               (goto-char (point-max))
                               (forward-line 0)
                               (looking-at ".*i1 : *$")))))
            (accept-process-output proc patience)
            (setq timeout (- timeout patience)))))))
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

(defun M2-in-front ()
  "Determine whether we are at the front of the line."
     (save-excursion (skip-chars-backward " \t") (bolp)))

(defcustom M2-code-string-openers '("TEST")
  "Words introducing a ///.../// string whose contents are Macaulay2 code.
Such a string is left entirely alone, so its contents are fontified and
indented as code."
  :type '(repeat string)
  :group 'M2)

(defun M2--raw-string-terminator (start limit)
  "Return the bounds of the /// closing a raw string with its body at START.
The value is a cons of the position of the closing /// and the position
after it, or nil if the string is unterminated before LIMIT.

Macaulay2 lets a raw string contain slashes by doubling them, so a run of
slashes closes the string only when its length is odd and at least three:
a run of four stands for a literal ///, and one of nine for /// followed
by the terminator.  See the documentation of /// in Macaulay2."
  (save-excursion
    (goto-char start)
    (catch 'found
      (while (re-search-forward "/+" limit t)
        (let ((n (- (match-end 0) (match-beginning 0))))
          (when (and (>= n 3) (= 1 (mod n 2)))
            (throw 'found (cons (- (match-end 0) 3) (match-end 0))))))
      nil)))

(defun M2--raw-string-opener (pos)
  "Return the word introducing the raw string whose /// begins at POS."
  (save-excursion
    (goto-char pos)
    (skip-chars-backward " \t")
    (let ((end (point)))
      (skip-chars-backward "A-Za-z0-9_'")
      (buffer-substring-no-properties (point) end))))

(defun M2--demote-unbalanced (beg end)
  "Give punctuation syntax to unbalanced delimiters between BEG and END.
A SimpleDoc string is ordinary buffer text as far as the parser is
concerned, so an unmatched bracket or quote in its prose would otherwise
run on and displace every expression after it.  Balanced ones are left
alone, so that a string or a list written inside the prose still reads as
one."
  (let ((guard 0))
    (catch 'done
      (while (< (setq guard (1+ guard)) 100)
        (let ((state (parse-partial-sexp beg end)))
          (cond
           ((nth 3 state)               ; a string is still open
            (put-text-property (nth 8 state) (1+ (nth 8 state))
                               'syntax-table (string-to-syntax ".")))
           ((> (nth 0 state) 0)         ; brackets are still open
            (dolist (open (nth 9 state))
              (put-text-property open (1+ open)
                                 'syntax-table (string-to-syntax "."))))
           ((< (nth 0 state) 0)         ; more closers than openers
            (save-excursion
              (goto-char beg)
              (let ((depth 0))
                (while (< (point) end)
                  (pcase (char-syntax (char-after))
                    (?\( (setq depth (1+ depth)))
                    (?\) (if (> depth 0)
                             (setq depth (1- depth))
                           (put-text-property (point) (1+ (point))
                                              'syntax-table
                                              (string-to-syntax ".")))))
                  (forward-char 1)))))
           (t (throw 'done t))))))))

(defun M2-syntax-propertize (start end)
  "Apply Macaulay2 syntax properties between START and END.
Handles the ///.../// raw strings, which a syntax table cannot describe
because their delimiter is three characters long.  How one is treated
depends on the word in front of it: see `M2-code-string-openers' and
`M2-simple-doc-string-openers'."
  (funcall M2-syntax-propertize-function start end)
  ;; A raw string reaching into START was propertized as a whole, so pick it
  ;; up from its beginning rather than in the middle.
  (let ((from (or (and (> start (point-min))
                       (get-text-property (1- start) 'M2-raw-string))
                  start)))
    ;; `syntax-propertize' clears the syntax-table properties it manages, but
    ;; not ours, and a stale one would keep reporting a string that is gone.
    (remove-text-properties from end '(M2-raw-string nil))
    (save-excursion
      (goto-char from)
      ;; A raw string may well run past END, and propertizing it takes point
      ;; with it, so test before searching rather than handing
      ;; `search-forward' a bound behind point.
      (while (and (< (point) end) (search-forward "///" end t))
        (let* ((open (match-beginning 0))
               (body (match-end 0))
               (state (save-excursion (syntax-ppss open))))
          ;; A /// inside a comment or an ordinary string opens nothing.
          (if (or (nth 3 state) (nth 4 state))
              (goto-char body)
            (let* ((close (M2--raw-string-terminator body (point-max)))
                   (body-end (if close (car close) (point-max)))
                   (finish (if close (cdr close) (point-max)))
                   (opener (M2--raw-string-opener open)))
              (unless (member opener M2-code-string-openers)
                (if (member opener M2-simple-doc-string-openers)
                    (M2--demote-unbalanced body body-end)
                  ;; Anything else is just a string.  Fence off the outer
                  ;; slash at each end; the syntax table has no way to spell
                  ;; a three-character delimiter.
                  (put-text-property open (1+ open) 'syntax-table
                                     (string-to-syntax "|"))
                  (when close
                    (put-text-property (1- finish) finish 'syntax-table
                                       (string-to-syntax "|")))))
              ;; Remember the extent so that an edit inside it re-propertizes
              ;; the whole string, not just the line that changed.
              (put-text-property open finish 'M2-raw-string open)
              (put-text-property open finish 'syntax-multiline t)
              (goto-char finish))))))))

(defun M2-inside-non-code-string-p (&optional pos)
  "Return non-nil if POS is inside a ///.../// that does not hold code.
That is, inside a SimpleDoc string or a plain one.  The opening delimiter
itself does not count, so the line introducing the string is still
indented as code."
  (setq pos (or pos (point)))
  (syntax-propertize (min (point-max) (1+ pos)))
  (let ((open (get-text-property
               ;; There is no character at point-max to carry the property,
               ;; so look at the one before it; that is where the point sits
               ;; while a string at the end of the buffer is being typed.
               (if (and (= pos (point-max)) (> pos (point-min))) (1- pos) pos)
               'M2-raw-string)))
    (and open
         (>= pos (+ open 3))
         (not (member (M2--raw-string-opener open) M2-code-string-openers)))))

(defun M2-inside-simple-doc-p (&optional pos)
  "Return the bounds of the SimpleDoc string containing POS, or nil.
The value is a cons of the first position after the opening /// and the
position of the closing ///, or of `point-max' while the string is still
unterminated.

Unlike `M2-inside-non-code-string-p' this is true only of the strings
introduced by a word in `M2-simple-doc-string-openers'.  A plain
///.../// is raw text with no language in it, and is left alone."
  (setq pos (or pos (point)))
  (syntax-propertize (min (point-max) (1+ pos)))
  (let* ((probe (if (and (= pos (point-max)) (> pos (point-min))) (1- pos) pos))
         (open (get-text-property probe 'M2-raw-string)))
    (when (and open
               (>= pos (+ open 3))
               (member (M2--raw-string-opener open) M2-simple-doc-string-openers))
      (let ((close (M2--raw-string-terminator (+ open 3) (point-max))))
        (cons (+ open 3) (if close (car close) (point-max)))))))

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
  :group 'M2)

(defun M2-electric-tab ()
  "`indent-line-function' for Macaulay2.
Inside a `doc' string, use the SimpleDoc engine, wherever the point may
be in the line.  Otherwise, if called by a command in
`M2-insert-tab-commands' with the point to the right of non-whitespace
characters in the same line, insert `M2-indent-level' spaces.  Inside any
other ///.../// string that does not hold Macaulay2 code, follow the
previous line when asked for an indentation explicitly and otherwise
leave the line alone.  Everywhere else, use SMIE."
  (interactive)
  (let* ((bounds (M2-inside-simple-doc-p))
         ;; A tab was asked for by hand, at a place in the line where one
         ;; could be inserted rather than the line indented.
         (tab-wanted (and (memq this-command M2-insert-tab-commands)
                          (not (M2-in-front))))
         ;; A `doc' string is SimpleDoc, which has an engine of its own.
         ;; It is asked first, and asked even with the point in the middle
         ;; of the line: a line is typed from the left margin rightwards,
         ;; so the moment one most wants TAB to indent it is the moment the
         ;; point is at the end of what was just typed --- which is exactly
         ;; when the tab below would instead push spaces in at the point.
         ;; The answer is a column, or `noindent' where SimpleDoc has
         ;; nothing to say about the line, or nil where this is not a
         ;; SimpleDoc string at all.
         (done (and bounds (M2-simple-doc-indent-line bounds))))
    (cond
     ;; Where SimpleDoc declined and a tab was asked for --- in a `Pre'
     ;; body, whose indentation is its content --- the tab is still owed.
     ((and done (not (and tab-wanted (eq done 'noindent)))) done)
     (tab-wanted
      (indent-to
       (prog1 (+ (current-column) M2-indent-level)
         (delete-horizontal-space))))
     ;; Any other ///.../// is raw text.  SMIE would flatten it, so keep
     ;; out: return `noindent' for anything that reindents in bulk ---
     ;; `indent-region' and `electric-indent-mode' both leave such a line
     ;; untouched --- and follow the previous line when TAB is pressed.
     ((M2-inside-non-code-string-p)
      (cond
       ;; An explicit TAB takes the line one step further in.  Aligning
       ;; with the line above, as `fundamental-mode' does, tells the writer
       ;; of a raw string nothing they did not already have.
       ((memq this-command M2-insert-tab-commands)
        (indent-line-to (+ (current-indentation) M2-indent-level)))
       ;; A line with nothing on it at all has nothing to lose, so carry
       ;; the previous line's indentation over to it; this is what makes
       ;; RET continue at the right level.  A line that is blank but not
       ;; empty keeps its whitespace, which may matter to the string.
       ((save-excursion (beginning-of-line) (eolp))
        (indent-line-to
         (save-excursion
           (forward-line 0)
           (skip-chars-backward " \t\n")
           (current-indentation))))
       ;; Anything else, `indent-region' most of all, leaves the line be.
       (t 'noindent)))
     (t (smie-indent-line)))))

;;; "blink" evaluated region (heavily inspired by ESS)

(defcustom M2-blink-region-flag t
  "Non-nil means evaluated region is highlighted for `M2-blink-delay' seconds."
  :type 'boolean
  :group 'M2)

(defcustom M2-blink-delay .3
  "The number of seconds that the evaluated region is highlighted.
Only if `M2-blink-region-flag' is non-nil."
  :type 'number
  :group 'M2)

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

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.m2\\'" . M2-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.dd?\\'" . M2-mode))

;; eglot support
(defvar eglot-server-programs)
(with-eval-after-load 'eglot
  (add-to-list 'eglot-server-programs '(M2-mode "M2-language-server")))

;; lsp-mode support
(declare-function lsp-activate-on "lsp-mode")
(declare-function lsp-register-client "lsp-mode")
(declare-function lsp-stdio-connection "lsp-mode")
(declare-function make-lsp-client "lsp-mode")
(defvar lsp-language-id-configuration)
(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-language-id-configuration '(M2-mode . "M2"))
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection "M2-language-server")
    :activation-fn (lsp-activate-on "M2")
    :server-id 'M2)))

(provide 'M2)

; Local Variables:
; compile-command: "make -C $M2BUILDDIR/Macaulay2/emacs "
; coding: utf-8
; End:
;;; M2.el ends here
