;;; M2-simple-doc-tests.el --- Tests for SimpleDoc indentation  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Daniel R. Grayson and Doug Torrance

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

;;; Commentary:

;; Tests for the SimpleDoc engine in M2-simple-doc.el.  Load this file and
;; run `ert', or run them in batch the way .github/workflows/test.yml does.
;;
;; Note that these do not strip the indentation off first, as the tests in
;; M2-smie-tests.el do.  SimpleDoc follows the off-side rule, so its
;; indentation is its structure: stripping it would not pose the question
;; harder, it would erase it.  What is asserted instead is that text
;; already indented as it should be is left exactly as it is, and that
;; text indented otherwise is moved to where the grammar puts it.

;;; Code:

(require 'ert)
(require 'M2)

(defun M2-simple-doc-tests--indent (text)
  "Indent TEXT in `M2-mode' and return the result."
  (with-temp-buffer
    (insert text)
    (M2-mode)
    (let ((inhibit-message t))
      (indent-region (point-min) (point-max)))
    (buffer-string)))

(defmacro M2-simple-doc-tests--deftest (name text &optional expected)
  "Define a test NAME asserting that TEXT is indented as EXPECTED.
EXPECTED defaults to TEXT itself, so that the usual case is the assertion
that a docstring already indented as it should be is left alone.  The
result is indented a second time as well, since an indentation that is
not a fixed point would creep every time the file was touched."
  (declare (indent 1))
  `(ert-deftest ,name ()
     (let ((once (M2-simple-doc-tests--indent ,text)))
       (should (equal once ,(or expected text)))
       (should (equal (M2-simple-doc-tests--indent once) once)))))

;;; The keyword tables.

(M2-simple-doc-tests--deftest M2-simple-doc-test-node-keywords
  "doc ///
  Key
    (foo, ZZ)
  Headline
    a headline
  Usage
    foo n
  Acknowledgement
    thanks
  Contributors
    someone
  References
    a paper
  Caveat
    beware
  SeeAlso
    bar
  SourceCode
    (foo, ZZ)
  Subnodes
    baz
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-description-keywords
  "doc ///
  Description
    Text
      prose
    Example
      2+2
    CannedExample
      i1 : 2+2
    Pre
      preformatted
    Code
      PARA \"hi\"
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-consequences-keywords
  "doc ///
  Consequences
    Item
      one thing happens
    Item
      another does
///
")

(defun M2-simple-doc-tests--tab (text line &optional column)
  "Press TAB on LINE of TEXT in `M2-mode' and return the result.
The point is put at COLUMN of that line first, or at its beginning."
  (with-temp-buffer
    (insert text)
    (M2-mode)
    (goto-char (point-min))
    (forward-line line)
    (forward-char (or column 0))
    (let ((this-command 'indent-for-tab-command))
      (indent-according-to-mode))
    (buffer-string)))

(ert-deftest M2-simple-doc-test-tab-works-where-the-point-actually-is ()
  "TAB indents the line with the point wherever it is in it.
A line is typed from the left margin rightwards, so when TAB is wanted
the point is at the end of what was just typed, not at the beginning of
the line.  Every test that moved to the beginning of the line first
missed that `M2-electric-tab' would push in a tab's worth of spaces
there instead, leaving the line where it was."
  (let ((text "doc ///
  Description
    Example
      x
y
///
")
        (want "doc ///
  Description
    Example
      x
      y
///
"))
    ;; With the point after the `y', where it is when it has just been typed.
    (should (equal (M2-simple-doc-tests--tab text 4 1) want))
    ;; ...and at the beginning of the line.
    (should (equal (M2-simple-doc-tests--tab text 4 0) want)))
  ;; The point ends after the text, so that typing can go on.
  (with-temp-buffer
    (insert "doc ///\n  Description\n    Example\n      x\ny\n///\n")
    (M2-mode)
    (goto-char (point-min))
    (forward-line 4)
    (forward-char 1)
    (let ((this-command 'indent-for-tab-command))
      (indent-according-to-mode))
    (should (= (current-column) 7))))

(ert-deftest M2-simple-doc-test-tab-works-where-the-point-is-in-an-example ()
  "The rule of the test above holds on the path through SMIE as well.
`smie-indent-calculate' indents for the point, not for the line the point
is on --- `smie-indent-line' moves to the indentation before calling it.
Reached from `indent-line-function' it must do the same, or a
continuation line of an example is indented only when the point happens
to be at the front of it."
  (let ((text "doc ///
  Description
    Example
      f(a,
        b + c)
///
")
        (want "doc ///
  Description
    Example
      f(a,
           b + c)
///
"))
    (dolist (column '(0 3 12))
      (should (equal (M2-simple-doc-tests--tab text 4 column) want)))))

(ert-deftest M2-simple-doc-test-tab-leaves-the-point-alone-on-a-tab-indented-line ()
  "Where TAB changes nothing, it must not move the point either.
Whether the point is within the indentation cannot be told by adding
`current-indentation', a column, to `line-beginning-position', a
position: they agree only where the line is indented with spaces, and a
good third of Macaulay2's docstrings are indented with tabs."
  (with-temp-buffer
    (insert "doc ///\n\tKey\n\t\tbarbaz\n///\n")
    (M2-mode)
    (goto-char (point-min))
    (forward-line 2)
    (end-of-line)
    (let ((before (current-column))
          (this-command 'indent-for-tab-command))
      (indent-according-to-mode)
      (should (= (current-column) before)))))

(ert-deftest M2-simple-doc-test-the-commonest-step-ties-towards-the-top ()
  "Where two steps are equally common, the one used first wins.
A docstring is read downwards, so the step its opening sections are
written in is the one to follow."
  ;; The arguments arrive as the parser pushes them, bottom line first.
  (should (= (M2-simple-doc--mode-of '(4 2 4 2) 99) 2))
  (should (= (M2-simple-doc--mode-of '(4 2) 99) 2))
  ;; A clear majority wins whichever end it is at.
  (should (= (M2-simple-doc--mode-of '(4 4 2) 99) 4))
  (should (= (M2-simple-doc--mode-of '() 99) 99)))

(ert-deftest M2-simple-doc-test-tab-still-inserts-one-where-nothing-is-known ()
  "In a body whose indentation is content, an explicit tab is still a tab.
`Pre' is taken verbatim, so the engine has nothing to say about where its
lines go; TAB there does what it does in code, and inserts."
  (should (equal (M2-simple-doc-tests--tab "doc ///
  Description
    Pre
      raw
///
" 3 9)
                 (concat "doc ///\n  Description\n    Pre\n      raw"
                         (make-string M2-indent-level ?\s)
                         "\n///\n"))))

(ert-deftest M2-simple-doc-test-tab-places-a-keyword-by-its-table ()
  "TAB puts a keyword where the table that admits it says, not where it sits.
`Text' is legal only inside a `Description', so TAB moves it into the one
above --- which is what lets the engine correct a docstring rather than
ratify it."
  (should (equal (M2-simple-doc-tests--tab "\
doc ///
  Description
Text
      prose
///
" 2)
                 "\
doc ///
  Description
    Text
      prose
///
")))

(ert-deftest M2-simple-doc-test-bulk-indent-does-not-restructure ()
  "`indent-region' must not turn body text into a section.
The `Example' below sits inside the body of the `Text' above it, so
SimpleDoc reads it as a line of that paragraph, however much it looks
like a section.  Moving it up beside the `Text' would add an example to
the documentation that its author never wrote, so reindenting a whole
file leaves it alone; TAB on the line still promotes it."
  (let ((text "\
doc ///
  Description
    Text
      prose
      Example
      2+2
///
"))
    (should (equal (M2-simple-doc-tests--indent text) text))))

(ert-deftest M2-simple-doc-test-ambiguous-keywords-take-the-inner-table ()
  "`Description' is legal in both a `Node' and a `Synopsis'.
The innermost section that admits it wins, which is the dispatch
SimpleDoc itself performs."
  ;; Inside a Synopsis, it belongs to the Synopsis.
  (should (equal (M2-simple-doc-tests--indent "\
doc ///
Node
    Key
        foo
    Synopsis
        Usage
            foo n
        Description
            Text
                prose
///
")
                 "\
doc ///
Node
    Key
        foo
    Synopsis
        Usage
            foo n
        Description
            Text
                prose
///
"))
  ;; With no Synopsis in the way, it belongs to the Node.
  (should (equal (M2-simple-doc-tests--indent "\
doc ///
Node
    Key
        foo
    Description
        Text
            prose
///
")
                 "\
doc ///
Node
    Key
        foo
    Description
        Text
            prose
///
")))

(M2-simple-doc-tests--deftest M2-simple-doc-test-nodes-do-not-nest
  ;; `Node' is in its own body table, so a node can be made to nest inside
  ;; another; nothing consumes a nested one, and reading the second `Node'
  ;; below as a subsection of the first would swallow it and every node
  ;; after it.  Each is a section of the docstring itself.
  "doc ///
Node
  Key
    foo
  Description
    Text
      prose
Node
  Key
    bar
///
")

(ert-deftest M2-simple-doc-test-word-that-is-not-a-keyword-here ()
  "A word is a keyword only where the table in force admits it.
`Text' alone on a line of a `Key' is a Macaulay2 expression naming the
symbol `Text', not the opening of a section, so it stays where it is."
  (should (equal (M2-simple-doc-tests--indent "\
doc ///
  Key
    Text
    (foo, ZZ)
///
")
                 "\
doc ///
  Key
    Text
    (foo, ZZ)
///
")))

;;; Measuring a line, as splitByIndent measures it.

(ert-deftest M2-simple-doc-test-indentation-is-measured-in-columns ()
  "A tab advances to the next multiple of eight, whatever `tab-width' is.
SimpleDoc says so, and a good third of Macaulay2's own docstrings are
indented with tabs, so a mode that counted characters would misread them."
  (dolist (case '(("\tx" . 8) (" \tx" . 8) ("       \tx" . 8)
                  ("        \tx" . 16) ("  \r x" . 1) ("    x" . 4)))
    (with-temp-buffer
      (insert (car case))
      (let ((tab-width 4))              ; deliberately not eight
        (should (equal (cons (car case) (M2-simple-doc--indentation))
                       case)))))
  ;; A line of nothing but whitespace is blank, which is an infinite
  ;; indentation rather than column zero: that is what lets a blank line
  ;; continue a section instead of ending it.
  (dolist (blank '("" "   " "\t"))
    (with-temp-buffer
      (insert blank)
      (should-not (M2-simple-doc--indentation)))))

(M2-simple-doc-tests--deftest M2-simple-doc-test-tabs-are-left-alone
  "doc ///
\tKey
\t\tfoo
\tHeadline
\t\ta headline
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-comment-does-not-break-a-block
  ;; A line matching "^[[:space:]]*--" is deleted before any indentation is
  ;; measured, so however far left it sits it cannot end a section.
  "doc ///
  Description
    Text
      prose
-- a comment at column zero
      more prose
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-blank-line-does-not-break-a-block
  "doc ///
  Description
    Text
      one paragraph

      and another
///
")

;;; The base and the step are inferred, not imposed.

(M2-simple-doc-tests--deftest M2-simple-doc-test-house-style-two
  "doc ///
  Key
    foo
  Description
    Text
      prose
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-house-style-four
  "doc ///
    Key
        foo
    Description
        Text
            prose
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-house-style-one
  "doc ///
 Key
  foo
 Description
  Text
   prose
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-node-at-column-zero
  "doc ///
Node
    Key
        foo
    Description
        Text
            prose
///
")

;;; Bodies whose indentation is content.

(M2-simple-doc-tests--deftest M2-simple-doc-test-verbatim-bodies-untouched
  ;; Pre subtracts the least indentation in the section, CannedExample and
  ;; Citation that of their first line, and a line shallower than the
  ;; reference is flushed left rather than kept where it was.  Reindenting
  ;; any of them would change what is rendered.
  "doc ///
  Description
    Pre
         deliberately
           ragged
      text
    CannedExample
        i1 : 2+2
        o1 = 4
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-item-descriptions-untouched
  "doc ///
  Inputs
    n:ZZ
      the number of things
    R:Ring
        indented further, and left that way
  Outputs
    :List
      the things
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-menu-nesting-untouched
  "doc ///
  Subnodes
    :A heading
    foo
      bar
        baz
///
")

;;; Example and Code.

(M2-simple-doc-tests--deftest M2-simple-doc-test-examples-stay-separate
  ;; Each line at the base begins an example of its own.  Were SMIE allowed
  ;; to pull the second one in, the two would render as one.
  "doc ///
  Description
    Example
      R = QQ[x];
      I = ideal x
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-example-continues-under-smie
  "doc ///
  Description
    Example
      f = i -> (
          a := i^2;
          a+1)
///
")

(ert-deftest M2-simple-doc-test-example-is-indented-relative-to-its-section ()
  "SMIE indents an example's body from the section's base, not from column 0.
The body of an `Example' is a block of Macaulay2 that the section around
it has already pushed to the right."
  (should (equal (M2-simple-doc-tests--indent "\
doc ///
  Description
    Example
      f = i -> (
      a := i^2;
          a+1)
///
")
                 ;; The line already at the base begins a new example and is
                 ;; left there; the deeper one is placed by SMIE, relative
                 ;; to the base rather than to the left margin.
                 "\
doc ///
  Description
    Example
      f = i -> (
      a := i^2;
          a+1)
///
")))

(M2-simple-doc-tests--deftest M2-simple-doc-test-example-base-is-the-authors
  ;; The first line of an `Example' fixes the base indentation of the whole
  ;; section, and with it the grouping of every line after it.  Pulling it
  ;; back to the usual step, as the body of a prose section would be, would
  ;; leave the lines after it deeper than the base and run two examples
  ;; into one.  Here the body sits far in from its keyword and stays there.
  "doc ///
  Description
    Example
          K = f 4
          J = g K
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-example-floor-only-falls
  ;; An Example body is divided the way a docstring is: a line no deeper
  ;; than the running floor begins a new example and lowers the floor.  So
  ;; the three lines below are three examples even though the first is the
  ;; deepest, and none of them may be moved.  Reading the rule as "at the
  ;; base" rather than "no deeper than the floor" ran them all into one.
  "doc ///
  Description
    Example
       Q = QQ[x,y,z];
      f Q
      g Q
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-code-is-indented-freely
  ;; A Code section is one parenthesized expression with no grouping to
  ;; preserve, so SMIE has a free hand there.
  "doc ///
  Description
    Code
      PARA {
          \"hi\"}
///
")

;;; The clamps.

(ert-deftest M2-simple-doc-test-a-line-is-not-moved-past-its-own-body ()
  "A keyword is left alone rather than moved out over the lines beneath it.
An indentation function moves one line while its neighbours stay put, so
a move that would strand this section's body outside it is refused.  Here
the second `Text' belongs beside the first, at column 4, but its own
prose sits at column 3: moving it there would leave the prose behind, no
longer part of the section it describes."
  (should (equal (M2-simple-doc-tests--indent "\
doc ///
  Description
    Text
      prose
  Text
   more prose
///
")
                 "\
doc ///
  Description
    Text
      prose
  Text
   more prose
///
")))

(M2-simple-doc-tests--deftest M2-simple-doc-test-a-line-is-not-moved-into-another
  ;; The `SeeAlso' below is a section of the `Node': at column 1 nothing
  ;; stands between them.  Its siblings sit at column 4, but it may not
  ;; join them, because the stray line at column 2 opened a block of its
  ;; own that reaches column 4 --- moving it there would make it a line of
  ;; that block rather than a section at all.  A line indented past its
  ;; siblings is not beside them.
  "doc ///
Node
    Key
      foo
    Description
      Text
        prose
  a stray line
 SeeAlso
      bar
///
")

;;; Cycling through the possibilities with TAB.

(defun M2-simple-doc-tests--tab-cycle (text line presses)
  "Press TAB PRESSES times on LINE of TEXT and return the columns reached."
  (with-temp-buffer
    (insert text)
    (M2-mode)
    (goto-char (point-min))
    (forward-line line)
    (let ((last-command nil) (columns nil))
      (dotimes (_ presses)
        (let ((this-command 'indent-for-tab-command))
          (indent-according-to-mode)
          (push (current-indentation) columns)
          (setq last-command this-command)))
      (nreverse columns))))

(ert-deftest M2-simple-doc-test-tab-cycles-through-the-levels ()
  "TAB pressed again steps out to the next level that would make sense.
Under a key, the next line may be another key or a new section of the
node, and only the writer knows which; the first TAB offers the likelier,
and the second the other.  At the end the cycle comes round again, as it
does in `python-mode'."
  (should (equal (M2-simple-doc-tests--tab-cycle "doc ///
  Key
    foo

///
" 3 5)
                 ;; The body of Key, then beside Key itself, then round.
                 '(4 2 4 2 4))))

(ert-deftest M2-simple-doc-test-tab-cycle-offers-each-enclosing-level ()
  "Every level a line could belong to is offered, innermost first."
  (should (equal (M2-simple-doc-tests--tab-cycle "doc ///
  Inputs
    n:ZZ
      what n is

///
" 4 4)
                 ;; Another line of the description, another item, another
                 ;; section of the node, and round again.
                 '(6 4 2 6))))

(ert-deftest M2-simple-doc-test-tab-cycle-leaves-a-line-with-text-alone ()
  "Cycling is for a line still being written, not for reflowing prose."
  (let ((text "doc ///
  Description
    Text
      prose
///
"))
    (should (equal (M2-simple-doc-tests--tab-cycle text 3 3) '(6 6 6)))))

;;; Correcting a line by hand.

(ert-deftest M2-simple-doc-test-tab-lines-up-a-stray-example-line ()
  "TAB on a line SMIE reads as a statement of its own puts it at the floor.
A line one column too deep goes on being part of the example above it,
which is rarely what was meant, so TAB lines it up.  `indent-region'
leaves it alone: moving it makes an example of it, which changes what
`installPackage' runs, and that is not a thing to do to a whole file."
  (let ((text "doc ///
  Description
    Example
      x
       y
///
"))
    (should (equal (M2-simple-doc-tests--tab text 4) "\
doc ///
  Description
    Example
      x
      y
///
"))
    (should (equal (M2-simple-doc-tests--indent text) text))))

(ert-deftest M2-simple-doc-test-tab-brings-in-a-line-typed-at-the-margin ()
  "TAB on a line that has fallen short of its section brings it in.
A line is typed from the left margin, and until it is indented it sits
below everything around it.  Doing nothing there --- on the grounds that
a shallower line begins something new --- leaves TAB dead on the one line
that most needs it.  `indent-region' still does nothing: a line shallower
than its neighbours may have been meant to close the section."
  (dolist (case '(("doc ///\n  Description\n    Example\n      x\ny\n///\n" 4 "      y")
                  ("doc ///\n  Description\n    Text\n      prose\ny\n///\n" 4 "      y")
                  ("doc ///\n  Key\n    foo\nbar\n///\n" 3 "    bar")))
    (let ((text (nth 0 case)) (line (nth 1 case)) (want (nth 2 case)))
      (with-temp-buffer
        (insert (M2-simple-doc-tests--tab text line))
        (goto-char (point-min))
        (forward-line line)
        (should (equal (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position))
                       want)))
      ;; ...but a whole-file reindentation leaves it alone.
      (should (equal (M2-simple-doc-tests--indent text) text)))))

(M2-simple-doc-tests--deftest M2-simple-doc-test-item-description-keeps-its-depth
  ;; The description of an item is deeper than its head, and that is what
  ;; makes it the description.  TAB must not pull it up to the head level.
  "doc ///
  Inputs
    n:ZZ
      what n is
///
")

(M2-simple-doc-tests--deftest M2-simple-doc-test-example-continuation-stays-deep
  ;; A line SMIE reads as continuing an expression --- here an argument of
  ;; a call whose bracket is still open --- belongs deeper than the floor,
  ;; and goes on being part of the same example.  The column is the one
  ;; M2-mode gives such a line anywhere else: the bracket's own, plus
  ;; `M2-indent-level'.
  "doc ///
  Description
    Example
      f(a,
           b)
///
")

;;; Writing one from nothing.

(defun M2-simple-doc-tests--type (keys)
  "Type KEYS into an empty `M2-mode' buffer and return what comes out.
KEYS is a list of strings to insert and of the symbols `ret' and `tab',
which run the commands those keys are bound to.  Each is run as the
command loop would run it, setting `this-command' and `last-command', so
that the rules keyed on them --- the tab that indents rather than
inserts, the second tab that cycles --- are exercised as they are in use."
  (with-temp-buffer
    (M2-mode)
    (electric-indent-local-mode 1)
    (let ((last-command nil))
      (dolist (key keys)
        (let ((this-command (cond ((eq key 'ret) 'newline)
                                  ((eq key 'tab) 'indent-for-tab-command)
                                  (t 'self-insert-command))))
          (cond ((eq key 'ret) (call-interactively #'newline))
                ((eq key 'tab) (call-interactively #'indent-for-tab-command))
                (t (insert key)))
          (setq last-command this-command))))
    (buffer-string)))

(ert-deftest M2-simple-doc-test-a-docstring-can-be-typed ()
  "A whole node comes out indented, typed as one would type it.
The point is where typing leaves it --- at the end of the line --- and
RET is what opens each new line.  Every bug found in this engine by
actually using it lived on that path and not on `indent-region', which is
what the rest of these tests and the corpus check exercise."
  (should (equal (M2-simple-doc-tests--type
                  '("doc ///" ret
                    "Key" ret
                    "(foo, ZZ)" ret
                    "Headline" tab ret
                    "what foo does" ret
                    "Description" tab ret
                    "Text" ret
                    "some prose" ret
                    "Example" tab ret
                    "2+2" ret
                    "3+3" ret
                    "///"))
                 "doc ///
  Key
    (foo, ZZ)
  Headline
    what foo does
  Description
    Text
      some prose
    Example
      2+2
      3+3
      ///")))

(ert-deftest M2-simple-doc-test-typing-a-multi-line-example ()
  "An example spanning several lines indents itself as it is typed.
While a bracket is open the doc string is unbalanced, so
`M2-syntax-propertize' demotes it to punctuation to stop prose displacing
the code after it.  SMIE cannot indent by a bracket it cannot see as one,
and read that way it does not answer at all, which left every such line
at the left margin.  Inside a body that really is Macaulay2 the syntax
table alone is used, so the bracket counts again."
  (should (equal (M2-simple-doc-tests--type
                  '("doc ///" ret "Description" ret "Example" tab ret
                    "f = x -> (" ret "a := x^2;" ret "a+1)" ret "f 3"))
                 "doc ///
  Description
    Example
      f = x -> (
          a := x^2;
          a+1)
      f 3"))
  ;; `f 3' is a statement of its own, so it goes back to the floor and is
  ;; an example of its own, as it would be had it been written that way.
  (should (equal (M2-simple-doc-tests--type
                  '("doc ///" ret "Description" ret "Example" tab ret
                    "f = x -> (" ret))
                 "doc ///\n  Description\n    Example\n      f = x -> (\n          ")))

(ert-deftest M2-simple-doc-test-typing-inside-an-unfinished-string ()
  "Where SMIE will not answer, a line just opened still lands somewhere.
Inside a string it declines, and the floor --- where the example began
--- is the one column that cannot be wrong."
  (should (equal (M2-simple-doc-tests--type
                  '("doc ///" ret "Description" ret "Example" tab ret
                    "s = \"abc" ret))
                 "doc ///\n  Description\n    Example\n      s = \"abc\n      ")))

(ert-deftest M2-simple-doc-test-typing-reaches-every-level-with-tab ()
  "A line typed at the margin is brought in by TAB, at any depth."
  ;; RET after `Text' opens its body; the prose is typed there directly.
  (should (equal (M2-simple-doc-tests--type
                  '("doc ///" ret "Description" ret "Text" ret "prose"))
                 "doc ///\n  Description\n    Text\n      prose"))
  ;; And a keyword typed where RET left it is moved out to its own level.
  (should (equal (M2-simple-doc-tests--type
                  '("doc ///" ret "Key" ret "foo" ret "Headline" tab))
                 "doc ///\n  Key\n    foo\n  Headline")))

;;; Strings still being typed.

(ert-deftest M2-simple-doc-test-unterminated-string-makes-progress ()
  "A docstring with no closing /// yet must still indent, and must not hang."
  (dolist (text '("doc ///\n" "doc ///\nKey\n" "doc ///\n  Description\n    Text\n"))
    (with-temp-buffer
      (insert text)
      (M2-mode)
      (let ((inhibit-message t))
        (with-timeout (10 (ert-fail "indentation did not finish"))
          (indent-region (point-min) (point-max))))))
  ;; At the very end of the buffer there is no character to carry the
  ;; property that marks the string, so the position before it is used.
  (with-temp-buffer
    (insert "doc ///\nKey\n")
    (M2-mode)
    (goto-char (point-max))
    (should (M2-inside-simple-doc-p (point)))))

(ert-deftest M2-simple-doc-test-terminator-line-is-not-simple-doc ()
  "The line holding the closing /// belongs to the Macaulay2 around it."
  (should (equal (M2-simple-doc-tests--indent "\
doc ///
  Key
    foo
///
")
                 "\
doc ///
  Key
    foo
///
")))

;;; Opening a line.

(ert-deftest M2-simple-doc-test-new-line-begins-the-body-of-a-section ()
  "RET after a keyword lands where that section's body belongs."
  (with-temp-buffer
    (insert "doc ///\n  Description\n\n///\n")
    (M2-mode)
    (goto-char (point-min))
    (forward-line 2)
    (indent-according-to-mode)
    ;; A `Description' holds sections, so the next line is a subsection.
    (should (= (current-indentation) (+ 2 M2-simple-doc-indent-level)))))

(ert-deftest M2-simple-doc-test-new-line-continues-a-paragraph ()
  "RET inside a paragraph carries on at the same column."
  (with-temp-buffer
    (insert "doc ///\n  Description\n    Text\n      prose\n\n///\n")
    (M2-mode)
    (goto-char (point-min))
    (forward-line 4)
    (indent-according-to-mode)
    (should (= (current-indentation) 6))))

(provide 'M2-simple-doc-tests)

;;; M2-simple-doc-tests.el ends here
