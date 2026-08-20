;;; M2-smie-tests.el --- Tests for M2-mode indentation  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Daniel R. Grayson and Doug Torrance

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Tests for the SMIE-based indentation in M2.el.  Load this file and run
;; `ert', or run them in batch the way .github/workflows/test.yml does.

;;; Code:

(require 'ert)
(require 'M2)

(defun M2-smie-tests--reindent (text)
  "Strip all indentation from TEXT, re-indent it in `M2-mode', and return it."
  (with-temp-buffer
    (insert text)
    (M2-mode)
    (goto-char (point-min))
    (while (not (eobp))
      (delete-horizontal-space)
      (forward-line 1))
    (indent-region (point-min) (point-max))
    (buffer-string)))

(defmacro M2-smie-tests--deftest (name text)
  "Define an indentation test NAME asserting that TEXT re-indents to itself."
  (declare (indent 1))
  `(ert-deftest ,name ()
     (should (equal (M2-smie-tests--reindent ,text) ,text))))

;;; Keyword expressions, one per production in the Macaulay2 language grammar.

(M2-smie-tests--deftest M2-smie-test-if-then-else "\
f = x -> (
    if x
    then y
    else z)
")

(M2-smie-tests--deftest M2-smie-test-if-then-else-blocks "\
if x then (
    a;
    b) else (
    c;
    d)
")

(M2-smie-tests--deftest M2-smie-test-try-then-else "\
f = (
    try g
    then h
    else k)
")

(M2-smie-tests--deftest M2-smie-test-try-except-do "\
f = (
    try g
    except e do
        h)
")

(M2-smie-tests--deftest M2-smie-test-while-do "\
while x do (
    a;
    b)
")

(M2-smie-tests--deftest M2-smie-test-while-list-do "\
f = (
    while x
    list y
    do z)
")

(M2-smie-tests--deftest M2-smie-test-for-in-do "\
for i in L do (
    a;
    b)
")

(M2-smie-tests--deftest M2-smie-test-for-from-to-when-list "\
f = (
    for i
    from 1
    to 10
    when odd i
    list i^2)
")

(M2-smie-tests--deftest M2-smie-test-new-of-from "\
f = (
    new HashTable
    of Thing
    from {})
")

;;; Installing a method on a `new' expression.  Macaulay2 binds := more
;;; loosely than of and from, so these are method definitions and the body
;;; belongs to the statement, not to the from.

(M2-smie-tests--deftest M2-smie-test-new-from-method "\
new X from Y := (x, y) -> (
    a;
    b)
")

(M2-smie-tests--deftest M2-smie-test-new-of-from-method "\
new X of Y from Z := (x, y) -> (
    a;
    b)
")

(M2-smie-tests--deftest M2-smie-test-new-from-method-chain "\
new X from Y :=
new X from Z := f
")

;;; Brackets, separators, and operators.

(M2-smie-tests--deftest M2-smie-test-argument-alignment "\
longFunctionName(x,
                 y)
")

(M2-smie-tests--deftest M2-smie-test-argument-list-hanging "\
longFunctionName(
    x,
    y)
")

(M2-smie-tests--deftest M2-smie-test-nested-brackets "\
L = {
    1,
    2,
    {
        3,
        4}
}
")

(M2-smie-tests--deftest M2-smie-test-method-options "\
foo = method(
    Options => {
        A => 1,
        B => 2})
")

(M2-smie-tests--deftest M2-smie-test-hanging-arrow "\
f = (a,b) -> (
    a+b)
")

;;; A bracket left hanging inside an argument list indents its contents from
;;; the line that opens it, not from the argument list.

(M2-smie-tests--deftest M2-smie-test-hanging-arrow-in-arguments "\
f = new HashTable from apply(L, i -> (
    a;
    b))
")

(M2-smie-tests--deftest M2-smie-test-hanging-arrow-nested "\
f = (
    apply(L, i -> (
        a;
        b)))
")

(M2-smie-tests--deftest M2-smie-test-documentation-block "\
beginDocumentation()
document {
    Key => foo,
    Headline => \"bar\",
    PARA {
        \"text\"
    }
}
")

(M2-smie-tests--deftest M2-smie-test-top-level-statements "\
a = 1;
b = 2;
c = 3
")

(M2-smie-tests--deftest M2-smie-test-binary-continuation "\
x = a +
    b +
    c
")

;;; An operator after one of the quote words is a name, not an operator
;;; waiting for its right operand, so the statement ends with it.

(M2-smie-tests--deftest M2-smie-test-quoted-operators "\
a = symbol <
b = global <
c = local <
d = threadLocal <
e = threadVariable <
f = 3
")

(M2-smie-tests--deftest M2-smie-test-angle-bar-brackets "\
x = <|
    a,
    b|>
")

;;; Regressions.

(M2-smie-tests--deftest M2-smie-test-trailing-comment "\
a = 1
b = 2   -- a trailing comment must not drag the next statement rightwards
c = 3
")

(M2-smie-tests--deftest M2-smie-test-assignment-then-statement "\
x = 20
y := 3
z <- identity
w = 4
")

(ert-deftest M2-smie-test-block-comment ()
  "Code after a -* ... *- comment must still be indented to the block."
  (with-temp-buffer
    (insert "f = (\n-* a block\n   comment *-\n1)\n")
    (M2-mode)
    (indent-region (point-min) (point-max))
    (goto-char (point-min))
    (forward-line 1)
    (should (= (current-indentation) M2-indent-level))
    (forward-line 2)                    ; past the comment's second line
    (should (= (current-indentation) M2-indent-level))))

(M2-smie-tests--deftest M2-smie-test-string-with-brackets "\
f = (
    print \"( unbalanced [ brackets { in a string\",
    1)
")

(ert-deftest M2-smie-test-no-tabs ()
  "Indentation must never insert a literal tab."
  (should-not (string-match-p "\t" (M2-smie-tests--reindent "\
f = (
    g = {
        1,
        2};
    h)
"))))

(ert-deftest M2-smie-test-idempotent ()
  "Indenting an already-indented buffer must change nothing."
  (let ((text "\
f = x -> (
    if x
    then (
        a;
        b)
    else c)
"))
    (should (equal (M2-smie-tests--reindent
                    (M2-smie-tests--reindent text))
                   text))))

;;; The lexer.

(defconst M2-smie-tests--operators
  (append (apply #'append (mapcar #'cdr M2-operators-binary))
          M2-operators-postfix)
  "Every operator the lexer has to recognize.
Derived from the generated table rather than listed here, so that an
operator added to Macaulay2 is covered as soon as it is regenerated.
The sum-of-twists operator (*) is absent from that table on purpose: it
is already balanced parentheses, so both directions of the lexer decline
it and let SMIE step over it as a sexp.")

(ert-deftest M2-smie-test-lexer-round-trip ()
  "Forward and backward tokenization must agree on every operator.
SMIE requires the two token functions to be exact inverses; when they are
not, it scans past the tokens it is looking for."
  (let (failures)
    (dolist (op M2-smie-tests--operators)
      (with-temp-buffer
        (insert "a " op " b")
        (M2-mode)
        (goto-char (point-min))
        (M2-smie-forward-token)
        (let ((forward (M2-smie-forward-token)))
          (goto-char (point-max))
          (M2-smie-backward-token)
          (let ((backward (M2-smie-backward-token)))
            (unless (and (equal forward op) (equal backward op))
              (push (format "%s: forward %S, backward %S" op forward backward)
                    failures))))))
    (should-not (nreverse failures))))

(ert-deftest M2-smie-test-lexer-makes-progress ()
  "Tokenizing must always move point, in both directions.
A token function that returns without moving makes SMIE loop."
  (let ((text "x = \"a string\" + ///a raw string/// - f(1,2) -- comment\ny = 3\n"))
    (with-temp-buffer
      (insert text)
      (M2-mode)
      (goto-char (point-min))
      (while (< (point) (point-max))
        (let ((start (point)))
          (M2-smie-forward-token)
          (when (= (point) start)
            ;; An empty token that does not move is SMIE's signal to step
            ;; over the object at point itself; emulate that.
            (goto-char (or (ignore-errors
                             (let ((forward-sexp-function nil))
                               (scan-sexps (point) 1)))
                           (point-max))))
          (should (> (point) start))))
      (goto-char (point-max))
      (while (> (point) (point-min))
        (let ((start (point)))
          (M2-smie-backward-token)
          (when (= (point) start)
            (goto-char (or (ignore-errors
                             (let ((forward-sexp-function nil))
                               (scan-sexps (point) -1)))
                           (point-min))))
          (should (< (point) start)))))))

(ert-deftest M2-smie-test-unterminated-literals ()
  "Half-typed comments and strings must not make indentation hang."
  (dolist (text '("f = (\n-* an unterminated block comment\n"
                  "f = (\n\"an unterminated string\n"
                  "f = (\n///an unterminated raw string\n"
                  "f = (\n--\n"))
    (with-temp-buffer
      (insert text)
      (M2-mode)
      ;; SMIE reports and absorbs the scan-error an unterminated string
      ;; provokes, but only when `debug-on-error' is off, which it is not
      ;; under ERT.  What is being checked here is that we come back at all.
      (let ((debug-on-error nil))
        (with-timeout (10 (ert-fail (format "timed out on %S" text)))
          (ignore-errors (indent-region (point-min) (point-max))))))))

(ert-deftest M2-smie-test-triple-slash-is-not-a-string ()
  "///.../// must not be given string syntax.
It is used for doc and TEST strings whose contents are Macaulay2 code, and
we want that code treated as code."
  (with-temp-buffer
    (insert "TEST ///\n  R = QQ[x,y]\n  assert(dim R == 2)\n///\n")
    (M2-mode)
    (syntax-propertize (point-max))
    (goto-char (point-min))
    (while (not (eobp))
      (should-not (nth 3 (syntax-ppss (point))))
      (forward-char 1))))

(defconst M2-smie-tests--doc "\
doc ///
  Key
    (foo, ZZ)
  Description
    Text
      Some prose that runs
      onto a second line.
    Example
      R = QQ[x]
///
x = 1
")

(ert-deftest M2-smie-test-documentation-is-left-alone ()
  "Indenting must not disturb a doc string.
Those are written in SimpleDoc, whose indentation is significant and which
this mode does not understand."
  (with-temp-buffer
    (insert M2-smie-tests--doc)
    (M2-mode)
    (indent-region (point-min) (point-max))
    (should (equal (buffer-string) M2-smie-tests--doc))))

(ert-deftest M2-smie-test-documentation-continues-previous-line ()
  "A new line inside a doc string picks up the previous line's indentation."
  (with-temp-buffer
    (insert M2-smie-tests--doc)
    (M2-mode)
    (goto-char (point-min))
    (forward-line 6)                    ; "      onto a second line."
    (end-of-line)
    (newline)
    (indent-according-to-mode)
    (should (= (current-indentation) 6))
    ;; ...and the line it was split from is untouched.
    (forward-line -1)
    (should (= (current-indentation) 6))))

(ert-deftest M2-smie-test-test-blocks-indent-as-code ()
  "TEST ///...///  holds Macaulay2 code, so it is indented as code."
  (should (equal (M2-smie-tests--reindent "\
TEST ///
R = QQ[x]
f = i -> (
    a := i^2;
    a+1)
///
")
                 "\
TEST ///
R = QQ[x]
f = i -> (
    a := i^2;
    a+1)
///
")))

(ert-deftest M2-smie-test-stray-triple-slash-is-ignored ()
  "A /// inside a comment or a string must not be taken for a delimiter.
Counting one would flip the open/close parity and silently stop
indentation for the rest of the buffer."
  (dolist (prefix '("-- see /// for raw strings\n" "s = \"///\"\n"))
    (should (equal (M2-smie-tests--reindent (concat prefix "f = (\na;\nb)\n"))
                   (concat prefix "f = (\n    a;\n    b)\n")))))

(ert-deftest M2-smie-test-bracket-with-trailing-comment ()
  "A bracket followed by a comment is still hanging.
Otherwise its contents line up with the comment, and the first element
gets a different column from the rest."
  (should (equal (M2-smie-tests--reindent "\
someLongName = { -- why
    a,
    b,
    c}
")
                 "\
someLongName = { -- why
    a,
    b,
    c}
")))

(ert-deftest M2-smie-test-separator-cache-respects-narrowing ()
  "The newline cache must not carry a narrowed answer back out.
`M2-smie--matching-block-data' runs the lexer inside `narrow-to-region',
where a newline near the edge looks like a statement separator because
the token before it is out of reach."
  (with-temp-buffer
    (insert "x = aaa +\nbbb\n")
    (M2-mode)
    (goto-char (point-min))
    (end-of-line)                       ; the newline after "+"
    (let ((pos (point)))
      (should-not (M2-smie--newline-separator-p))
      (should (save-restriction (narrow-to-region pos (point-max))
                                (M2-smie--newline-separator-p)))
      ;; Unrestricted again, and the buffer has not changed.
      (should-not (M2-smie--newline-separator-p)))))

(ert-deftest M2-smie-test-blank-line-in-documentation-kept ()
  "A whitespace-only line in a doc string keeps its whitespace.
It may well be significant to SimpleDoc."
  (let ((text "doc ///\n  Key\n    foo\n  \n  Headline\n///\n"))
    (with-temp-buffer
      (insert text)
      (M2-mode)
      (indent-region (point-min) (point-max))
      (should (equal (buffer-string) text)))))

(ert-deftest M2-smie-test-comment-syntax-is-respected ()
  "The lexer must take -- to start a comment only where the syntax does.
`M2-syntax-propertize-function' clears the comment flags inside comint
output blocks, where -- is part of Macaulay2's output."
  (with-temp-buffer
    (M2-comint-mode)
    (insert "i1 : 3-4\n")
    (let ((start (point)))
      (insert "o1 = -- output, not a comment\n")
      (put-text-property start (point) 'field 'output))
    (syntax-propertize (point-max))
    (goto-char (point-min))
    (search-forward "--")
    (backward-char 2)
    (should-not (M2-smie--comment-start-p (point)))
    ;; Lexed as the subtraction operator, so the rest of the line survives.
    (should (equal (M2-smie-forward-token) "-")))
  (with-temp-buffer
    (M2-mode)
    (insert "x = 1 -- a real comment\ny = 2\n")
    (syntax-propertize (point-max))
    (goto-char (point-min))
    (search-forward "--")
    (backward-char 2)
    (should (M2-smie--comment-start-p (point)))
    ;; Skipped, leaving the newline to end the statement.
    (should (equal (M2-smie-forward-token) ";"))))

(defun M2-smie-tests--indentations (text)
  "Return the indentation of each line of TEXT after re-indenting it."
  (with-temp-buffer
    (insert text)
    (M2-mode)
    (goto-char (point-min))
    (while (not (eobp))
      (delete-horizontal-space)
      (forward-line 1))
    (indent-region (point-min) (point-max))
    (let (columns)
      (goto-char (point-min))
      (while (not (eobp))
        (push (current-indentation) columns)
        (forward-line 1))
      (nreverse columns))))

(defun M2-smie-tests--face-at (text string)
  "Return the face on the first occurrence of STRING in TEXT."
  (with-temp-buffer
    (insert text)
    (M2-mode)
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward string)
    (get-text-property (- (point) (length string)) 'face)))

(ert-deftest M2-smie-test-documentation-string-is-not-a-string ()
  "A doc string stays ordinary text, so Macaulay2 inside it is marked up.
In particular a \"...\" written in one is a real string; Emacs has no
nested strings, so this only works while the block itself is not one."
  (let ((text "doc ///\nideal \"foo\" here\n///\n"))
    (should-not (nth 3 (with-temp-buffer
                         (insert text) (M2-mode)
                         (syntax-propertize (point-max))
                         (syntax-ppss (+ (point-min) 12)))))
    (should (eq (M2-smie-tests--face-at text "\"foo\"") 'font-lock-string-face))
    (should (eq (M2-smie-tests--face-at text "ideal")
                'font-lock-function-name-face))))

(ert-deftest M2-smie-test-documentation-prose-cannot-leak ()
  "An unbalanced delimiter in doc prose must not displace what follows."
  (dolist (prose '("a lone ( paren" "a lone \" quote" "a lone ) paren"))
    (should (equal (M2-smie-tests--indentations
                    (concat "doc ///\n" prose "\n///\nf = (\na;\nb)\n"))
                   '(0 0 0 0 4 4)))))

(ert-deftest M2-smie-test-documentation-tab-computes-a-column ()
  "TAB in a doc string computes the column, and pressing it again does nothing.
The engine in M2-simple-doc.el reads the structure of the SimpleDoc
around the line, so there is nothing for a second press to add.  (It used
to step one level further in each time, which was all a mode that did not
understand the language could offer.)"
  (with-temp-buffer
    (insert "doc ///\nKey\n\n///\n")
    (M2-mode)
    (goto-char (point-min))
    (forward-line 2)
    (let ((this-command 'indent-for-tab-command))
      (indent-according-to-mode))
    ;; The body of `Key', one fallback step in from it.
    (should (= (current-indentation) M2-simple-doc-indent-level))
    (let ((this-command 'indent-for-tab-command))
      (indent-according-to-mode))
    (should (= (current-indentation) M2-simple-doc-indent-level)))
  ;; The same at the very end of the buffer, where a doc string being typed
  ;; has no closing /// yet and there is no character to carry the property.
  (with-temp-buffer
    (insert "doc ///\nKey\n")
    (M2-mode)
    (goto-char (point-max))
    (should (M2-inside-simple-doc-p (point)))
    (let ((this-command 'indent-for-tab-command))
      (indent-according-to-mode))
    (should (= (current-indentation) M2-simple-doc-indent-level)))
  ;; A keyword goes where its table says it goes, however far off it starts:
  ;; `Text' is legal only inside a `Description', so it lands in this one.
  (with-temp-buffer
    (insert "doc ///\n  Description\nText\n///\n")
    (M2-mode)
    (goto-char (point-min))
    (forward-line 2)
    (let ((this-command 'indent-for-tab-command))
      (indent-according-to-mode))
    (should (= (current-indentation) (+ 2 M2-simple-doc-indent-level)))))

(ert-deftest M2-smie-test-plain-raw-string-is-a-string ()
  "A ///.../// with no recognized word in front of it is just a string."
  (dolist (opener '("TEX" "lines"))
    (let ((text (concat "s = " opener " ///\nraw ( data\n///\nf = (\na;\nb)\n")))
      (should (nth 3 (with-temp-buffer
                       (insert text) (M2-mode)
                       (syntax-propertize (point-max))
                       (syntax-ppss (- (point-max) 20)))))
      (should (equal (M2-smie-tests--indentations text) '(0 0 0 0 4 4))))))

(ert-deftest M2-smie-test-propertize-past-region-end ()
  "Propertizing a region that a raw string runs past must not signal.
`syntax-propertize' works in chunks, so a string routinely reaches beyond
the region being handled; propertizing it carries point past the end."
  (with-temp-buffer
    (insert "s = TEX ///\n" (make-string 400 ?x) "\n///\nf = 1\n")
    (M2-mode)
    (should (progn (M2-syntax-propertize (point-min) 15) t))
    (should (progn (M2-syntax-propertize (point-min) (point-max)) t))))

(ert-deftest M2-smie-test-raw-string-escapes ()
  "A run of slashes closes a raw string only when it is odd and at least 3.
See the documentation of /// in Macaulay2: a run of four stands for a
literal ///, and one of nine for /// followed by the terminator."
  (dolist (literal '("///-- //// -- /////////"
                     "///-- ////// -- ///////////"
                     "//////////////"))
    (should (equal (M2-smie-tests--indentations
                    (concat "s = " literal "\nf = (\na;\nb)\n"))
                   '(0 0 4 4)))))

(ert-deftest M2-smie-test-triple-slash-lexes-atomically ()
  "/// must lex as one token, not as the quotient operators // and /."
  (with-temp-buffer
    (insert "TEST ///\nx = 1\n///\n")
    (M2-mode)
    (goto-char (point-min))
    (should (equal (M2-smie-forward-token) "TEST"))
    (should (equal (M2-smie-forward-token) "///"))
    (goto-char (point-max))
    (M2-smie-backward-token)             ; the trailing newline
    (should (equal (M2-smie-backward-token) "///"))))

(ert-deftest M2-smie-test-indent-region-signals-nothing ()
  "Indenting a buffer of assorted Macaulay2 constructs must not signal."
  (with-temp-buffer
    (insert "\
needs \"foo.m2\"
f = method(Options => {A => 1})
f ZZ := o -> n -> (
    if n < 0 then error \"negative\";
    for i from 1 to n list (
        g := i^2;
        g));
doc ///
  Key
    (f, ZZ)
  Description
    Text
      prose with ( unbalanced brackets and a -- dash
///
")
    (M2-mode)
    (should-not (condition-case err
                    (progn (indent-region (point-min) (point-max)) nil)
                  (error err)))))

(provide 'M2-smie-tests)

;;; M2-smie-tests.el ends here
