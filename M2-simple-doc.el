;;; M2-simple-doc.el --- SimpleDoc support for Macaulay2 docstrings -*- lexical-binding: t -*-

;; Copyright (C) 1997-2026 The Macaulay2 Authors

;; Version: 1.26.06
;; Keywords: languages
;; URL: https://github.com/Macaulay2/M2-emacs

;;; Commentary:

;; What is written in a "doc ///.../// " string is not Macaulay2 but
;; SimpleDoc, the language the SimpleDoc package parses.  This file
;; indents it and fontifies its prose.
;;
;; SimpleDoc follows the off-side rule: a section is opened by a line
;; holding a keyword and nothing else, and its body is the following, more
;; deeply indented lines.  Nothing closes a section; it ends at the first
;; line indented no more deeply than its keyword, and one such line may end
;; several sections at once.  Which keywords are legal depends on the
;; enclosing section, and is fixed by one of the four tables below.
;;
;; This is why SMIE is not used here, although the rest of the mode is
;; built on it.  A SMIE lexer returns one token per position and must move
;; over it, and the backward lexer must be its exact inverse; the several
;; zero-width closers that one dedent stands for cannot be spelled that
;; way.  Nor could the tokens be trusted if they could: they would be read
;; off the indentation, which is the very thing being computed, whereas the
;; tokens of Macaulay2 are text and cannot change under reindentation.  And
;; the keyword tables overlap --- `Description' is legal in both a `Node'
;; and a `Synopsis' --- so one token would need different precedence levels
;; in different contexts, which an operator-precedence grammar cannot say.
;;
;; SMIE is used for the one part of a docstring that really is Macaulay2:
;; the body of an `Example' or `Code' section.
;;
;; Two things are inferred from the block rather than imposed on it, since
;; both vary widely across Macaulay2's own packages: the column of its
;; top-level sections, and the size of one indentation step.
;; `M2-simple-doc-indent-level' is only the fallback for a block that
;; offers no evidence yet.  More generally, where a line is the first of
;; its kind in a section --- its first subsection, its first body line ---
;; its column is the author's choice and is left alone; the ones after it
;; are aligned with it.  Only the first of anything has nothing to be
;; measured against, and computing a column for it instead would drag its
;; siblings after it.
;;
;; The one distinction to hold on to while reading the rest is between an
;; indentation the writer asked for by pressing TAB and one taken in the
;; course of reindenting a whole file.  In this language they cannot be
;; the same.  Which section a line belongs to is decided by its
;; indentation and nothing else, so moving a line is not a matter of
;; presentation: it can promote a line of a paragraph into a section, or
;; split one example into two, and change what is rendered and what
;; `installPackage' runs.  So `indent-region' never restructures a
;; docstring --- it aligns what is already there and otherwise keeps its
;; hands off --- while TAB does what it is asked, including the things
;; bulk reindentation must not do.  `M2-simple-doc--explicit-p' is that
;; distinction, and several rules below turn on it.

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

(require 'cl-lib)
(require 'smie)

;; Defined in M2.el, which requires this file rather than the other way
;; round, as M2-symbols.el and M2-operators.el are.
(declare-function M2-inside-simple-doc-p "M2" (&optional pos))
(defvar M2-smie--top-level-column)

(defcustom M2-simple-doc-indent-level 2
  "Fallback indentation increment inside a SimpleDoc string.
The increment is normally inferred from the string itself, since
Macaulay2's own packages are written in steps of anything from one column
to eight.  This is used only where there is nothing to infer it from,
which is to say while the first section of a docstring is being typed."
  :type 'integer
  :group 'M2)

(defcustom M2-simple-doc-string-openers '("doc" "document" "multidoc")
  "Words introducing a ///.../// string written in SimpleDoc.
Such a string is indented as SimpleDoc, and its prose is fontified as
documentation rather than as Macaulay2.  A ///.../// introduced by any
other word is either Macaulay2 code, if the word is in
`M2-code-string-openers', or simply a string."
  :type '(repeat string)
  :group 'M2)

(defconst M2-simple-doc--whitespace " \t\r\f\v"
  "The characters SimpleDoc passes over at either end of a line.
Not a newline: these are the ones that can stand inside one.")

(defconst M2-simple-doc--tab-width 8
  "The width of a tab in a SimpleDoc string.
SimpleDoc measures indentation in columns, with a tab advancing to the
next multiple of this, whatever `tab-width' may be in the buffer.")

;;; The keyword tables.

;; Four tables, one per context, exactly as in SimpleDoc.m2.  `Synopsis'
;; is deliberately absent from the synopsis table: a synopsis does not
;; nest.

(defconst M2-simple-doc--tables
  '((node         "Node" "Key" "Headline" "Usage" "Inputs" "Outputs"
                  "Consequences" "Description" "Synopsis" "Acknowledgement"
                  "Contributors" "References" "Citation" "Caveat" "SeeAlso"
                  "Subnodes" "SourceCode" "ExampleFiles")
    (synopsis     "Heading" "BaseFunction" "Usage" "Inputs" "Outputs"
                  "Consequences" "Description")
    (description  "Text" "Tree" "Example" "CannedExample" "Pre" "Code")
    (consequences "Item"))
  "The four SimpleDoc keyword tables.
The car of each entry names a context and the cdr lists the keywords
legal there.  The node table is also the one in force at the top level of
a docstring.")

(defconst M2-simple-doc--bodies
  ;; KEYWORD           TABLE IN ITS BODY   SHAPE OF ITS BODY
  '(("Node"            node                sections)
    ("Synopsis"        synopsis            sections)
    ("Description"     description         sections)
    ("Consequences"    consequences        sections)
    ("Key"             nil                 lines)
    ("SeeAlso"         nil                 lines)
    ("SourceCode"      nil                 lines)
    ("Headline"        nil                 lines)
    ("Heading"         nil                 lines)
    ("BaseFunction"    nil                 lines)
    ("Text"            nil                 lines)
    ("Caveat"          nil                 lines)
    ("Acknowledgement" nil                 lines)
    ("Contributors"    nil                 lines)
    ("References"      nil                 lines)
    ("Item"            nil                 lines)
    ("Inputs"          nil                 lines)
    ("Outputs"         nil                 lines)
    ("Subnodes"        nil                 lines)
    ("Tree"            nil                 lines)
    ("Example"         nil                 example)
    ("Code"            nil                 code)
    ("Usage"           nil                 verbatim)
    ("Pre"             nil                 verbatim)
    ("CannedExample"   nil                 verbatim)
    ("Citation"        nil                 verbatim)
    ("ExampleFiles"    nil                 verbatim))
  "For each SimpleDoc keyword, what its body holds.
The second element is the keyword table in force inside it, or nil if it
holds no sections.  The third is the shape of the body:

`sections'  further sections, and nothing else;
`lines'     text, one line at a time --- prose, keys, item lists and
            menus alike.  Every line is stripped before SimpleDoc uses
            it, so the indentation of such a line carries nothing beyond
            the nesting it expresses;
`code'      Macaulay2, indented by SMIE;
`example'   Macaulay2 too, but grouped into separate examples by its
            indentation, so that SMIE may not move a line onto or off the
            base column;
`verbatim'  text whose indentation is part of the content, and which is
            therefore never reindented.")

(defconst M2-simple-doc--keyword-regexp
  (concat (regexp-opt (mapcar #'car M2-simple-doc--bodies) t)
          "[" M2-simple-doc--whitespace "]*$")
  "Regexp matching a line that holds a SimpleDoc keyword and nothing else.
Matching this is much cheaper than taking the text of the line and
looking it up, and all but a few lines of a docstring fail it.  Whether
the keyword is legal where it stands is a separate question, which
`M2-simple-doc--admits-p' answers.")

(defun M2-simple-doc--keyword-on-line ()
  "Return the SimpleDoc keyword on the line at point, or nil.
A keyword line holds a keyword and nothing else --- `Headline' is one,
`Headline blah' is an error --- and only such a line can open a section,
so this is the whole of what the parser needs to read from a line.  It is
one regexp rather than a string taken out of the buffer and looked up,
which matters: this runs for every line of the docstring above whichever
one is being indented or fontified."
  (save-excursion
    (forward-line 0)
    (skip-chars-forward M2-simple-doc--whitespace (line-end-position))
    (and (looking-at M2-simple-doc--keyword-regexp)
         (match-string-no-properties 1))))

(defsubst M2-simple-doc--admits-p (table keyword)
  "Return non-nil if TABLE, a context name, admits KEYWORD."
  (and table keyword
       (member keyword (cdr (assq table M2-simple-doc--tables)))))

(defsubst M2-simple-doc--body-table (keyword)
  "Return the keyword table in force inside KEYWORD's body."
  (nth 1 (assoc keyword M2-simple-doc--bodies)))

(defsubst M2-simple-doc--body-shape (keyword)
  "Return the shape of KEYWORD's body, or nil if there is no such keyword.
The shapes are `sections', `lines', `code', `example' and `verbatim', and
`M2-simple-doc--bodies' describes them."
  (nth 2 (assoc keyword M2-simple-doc--bodies)))

;;; Reading a line.

(defun M2-simple-doc--indentation ()
  "Return the SimpleDoc indent of the line at point, or nil if it is blank.
A space counts one column, a tab advances to the next multiple of
`M2-simple-doc--tab-width', and a carriage return returns to column zero.
A line holding nothing but those is blank, which SimpleDoc treats as an
infinite indentation rather than as column zero --- which is what lets a
blank line continue a section rather than end it."
  (save-excursion
    (forward-line 0)
    (let ((column 0) (eol (line-end-position)) (done nil))
      (while (not done)
        (if (>= (point) eol)
            (setq column nil done t)
          (pcase (char-after)
            (?\s (setq column (1+ column)) (forward-char 1))
            (?\t (setq column (* M2-simple-doc--tab-width
                                 (1+ (/ column M2-simple-doc--tab-width))))
                 (forward-char 1))
            (?\r (setq column 0) (forward-char 1))
            (_ (setq done t)))))
      column)))

(defun M2-simple-doc--comment-line-p ()
  "Return non-nil if the line at point vanishes before it is ever parsed.
Lines matching \"^[[:space:]]*--\" are deleted outright before any
indentation is measured, so such a line can never break a block, end a
paragraph, or separate two examples, however it is indented."
  (save-excursion
    (forward-line 0)
    (looking-at-p (concat "[" M2-simple-doc--whitespace "]*--"))))

;;; The block parser.

;; `splitByIndent' keeps a running indent and starts a new block at every
;; line not more deeply indented than it.  A frame here stands for one such
;; line, and the running indent is the innermost frame's, so the whole
;; discipline is "pop while this line is no deeper than the top frame".
;; That reproduces the floor rule exactly, including its one surprise: the
;; running indent only ever decreases, so a keyword indented less than its
;; siblings silently swallows them rather than standing beside them.
;;
;; A frame is pushed for every line, not just for a keyword line.  A line
;; that is not a keyword admits nothing, which is what makes a keyword
;; typed inside a body climb back out to the section that does admit it.

(cl-defstruct (M2-simple-doc--frame
               (:constructor M2-simple-doc--frame
                             (indent keyword position
                              &aux (table (M2-simple-doc--body-table keyword))))
               (:copier nil))
  "One line of a docstring, and what has been seen inside it so far.
INDENT is the column it stands in and POSITION where it begins.  KEYWORD
is the section it opens, or nil if it opens none, and TABLE the keyword
table then in force in its body.  SECTION-ANCHOR and BODY-ANCHOR record
the column of the first subsection and of the first body line it was
found to have, so that the ones after them can be aligned with them."
  indent keyword table section-anchor body-anchor position)

(defsubst M2-simple-doc--root-frame-p (frame)
  "Return non-nil if FRAME is the one standing for the docstring itself.
Nothing encloses it, so it is the one frame with no line of its own, and
it is given an indent no line can have."
  (< (M2-simple-doc--frame-indent frame) 0))

(defun M2-simple-doc--mode-of (values fallback)
  "Return the most common member of VALUES, or FALLBACK if there is none.
Ties are broken towards the value seen first, which is the one nearest
the top of the docstring."
  ;; VALUES arrives bottom-to-top, having been pushed as the docstring was
  ;; read, and `>=' lets each later one take a tie.  Walking it as it comes
  ;; therefore leaves the topmost winner standing.
  (let ((counts nil) (best nil) (best-count 0))
    (dolist (value values)
      (let ((cell (assq value counts)))
        (if cell (setcdr cell (1+ (cdr cell)))
          (push (setq cell (cons value 1)) counts))
        (when (>= (cdr cell) best-count)
          (setq best value best-count (cdr cell)))))
    (or best fallback)))

(defun M2-simple-doc--terminated-p (end)
  "Return non-nil if a closing /// stands at END.
A docstring still being typed has none, and END is then the end of the
buffer rather than a delimiter."
  (save-excursion (goto-char end) (looking-at-p "///")))

(defun M2-simple-doc--text-end (end)
  "Return the end of the SimpleDoc text of a string closing at END.
That is the beginning of the line holding the closing ///, when the
string is closed and nothing but whitespace precedes the /// there, and
END itself otherwise."
  (save-excursion
    (goto-char end)
    (let ((bol (line-beginning-position)))
      (if (and (M2-simple-doc--terminated-p end)
               (save-excursion
                 (skip-chars-backward M2-simple-doc--whitespace bol)
                 (= (point) bol)))
          bol
        end))))

(defun M2-simple-doc--terminator-line-p (end)
  "Return non-nil if the /// closing at END stands on the line at point.
That line is not SimpleDoc but the tail of the Macaulay2 expression the
string belongs to."
  (and (M2-simple-doc--terminated-p end)
       (<= (line-beginning-position) end)
       (<= end (line-end-position))))

(defun M2-simple-doc--walk (start end function)
  "Call FUNCTION for each SimpleDoc line between START and END.
It is called with the line's indent, the keyword it opens or nil, and the
stack of frames enclosing it.  Blank lines and comment lines are passed over, as
SimpleDoc passes over them.  The value is the stack of frames left open
at END, innermost first, always ending in the frame standing for the
docstring itself.

This runs once per line of the docstring for every line indented or
fontified in it, so it does as little per line as it can: a line is
measured, tested against one regexp, and otherwise left untouched."
  (let* ((root (M2-simple-doc--frame -1 nil start))
         (stack (list root)))
    ;; The docstring itself holds node keywords, and nothing encloses it.
    (setf (M2-simple-doc--frame-table root) 'node)
    (save-excursion
      ;; The opening /// leaves the rest of its line behind it, and the
      ;; closing one usually has a line to itself.  Neither is SimpleDoc,
      ;; and reading either as a line of it would be no idle mistake: the
      ;; "doc ///" line sits at the far left, so a frame for it would
      ;; swallow the whole docstring.
      (goto-char start)
      (unless (bolp) (forward-line 1))
      (setq end (max (point) (M2-simple-doc--text-end end)))
      (while (< (point) end)
        (let ((indent (M2-simple-doc--indentation)))
          (unless (or (null indent) (M2-simple-doc--comment-line-p))
            (while (and (cdr stack)
                        (<= indent (M2-simple-doc--frame-indent (car stack))))
              (pop stack))
            (let* ((bol (point))
                   (candidate (M2-simple-doc--keyword-on-line))
                   (keyword (and (M2-simple-doc--admits-p
                                  (M2-simple-doc--frame-table (car stack))
                                  candidate)
                                 candidate)))
              (funcall function indent keyword stack)
              (push (M2-simple-doc--frame indent keyword bol) stack))))
        (forward-line 1)))
    stack))

(defun M2-simple-doc--steps (start end)
  "Return the pair of indentation increments used between START and END.
The value is a cons of the increment between a section and its
subsections and the increment between a section and its body.  Each is
the commonest such increment in the docstring, so that a block written in
some other measure than `M2-simple-doc-indent-level' --- Macaulay2's own
packages use everything from one column to eight --- is indented in the
measure it is written in.

Both are read from the whole docstring rather than from the part above
the line being indented, since the step is a property of the block: were
it read from above, the first subsection of every section would be
computed from the fallback and the rest aligned to that mistake."
  (let ((section nil) (body nil))
    (M2-simple-doc--walk
     start end
     (lambda (indent keyword stack)
       (let* ((parent (car stack))
              (above (M2-simple-doc--frame-indent parent)))
         (unless (M2-simple-doc--root-frame-p parent)
           (cond
            (keyword (push (- indent above) section))
            ;; Only the first line of a section's body measures a step of
            ;; SimpleDoc.  Deeper lines are the structure of something
            ;; else --- a continuation inside an example, the description
            ;; of an item, a nested menu --- and counting them would make
            ;; the block look more steeply stepped than it is written.
            ((eq (M2-simple-doc--body-shape
                  (M2-simple-doc--frame-keyword parent))
                 'lines)
             (push (- indent above) body)))))))
    (cons (M2-simple-doc--mode-of section M2-simple-doc-indent-level)
          (M2-simple-doc--mode-of body M2-simple-doc-indent-level))))

(defvar-local M2-simple-doc--steps-cache nil
  "Memo for `M2-simple-doc--steps'.
A cons of a key describing one docstring and the increments read from it.
Answering means walking the whole block, and the question is asked once
per line; the answer changes only when the block does.")

(defun M2-simple-doc--cached-steps (bounds)
  "Return the indentation increments of the docstring spanning BOUNDS."
  (let ((key (list (car bounds) (cdr bounds) (buffer-chars-modified-tick))))
    (unless (equal (car M2-simple-doc--steps-cache) key)
      (setq M2-simple-doc--steps-cache
            (cons key (M2-simple-doc--steps (car bounds) (cdr bounds)))))
    (cdr M2-simple-doc--steps-cache)))

(defun M2-simple-doc--stack (start limit)
  "Return the stack of frames enclosing LIMIT, from a docstring at START.
Each frame records where the first of its children of each kind sits, so
that the later ones can be aligned with it rather than recomputed ---
which is what keeps a block that is irregular but self-consistent from
being rewritten.

The stack is built from the lines strictly before LIMIT.  The line at
LIMIT never pops a frame, which is what lets a misindented keyword be
moved to where it belongs instead of being taken at its word."
  (M2-simple-doc--walk
   start limit
   (lambda (indent keyword stack)
     (let ((parent (car stack)))
       (if keyword
           (unless (M2-simple-doc--frame-section-anchor parent)
             (setf (M2-simple-doc--frame-section-anchor parent) indent))
         (unless (M2-simple-doc--frame-body-anchor parent)
           (setf (M2-simple-doc--frame-body-anchor parent) indent)))))))

(defun M2-simple-doc--enclosing-section (stack)
  "Return the innermost frame of STACK that opened a section."
  (cl-find-if #'M2-simple-doc--frame-keyword stack))

;;; Indentation.

(defun M2-simple-doc--subtree-limit ()
  "Return the smallest indent of the lines belonging to the line at point.
That is, of the following lines more deeply indented than this one, which
would be stranded outside it were it moved to their level or beyond.
Return nil when it has no such lines."
  (save-excursion
    (let ((own (M2-simple-doc--indentation))
          (limit nil)
          (done nil))
      (when own
        (while (not done)
          (if (/= 0 (forward-line 1))
              (setq done t)
            (let ((indent (M2-simple-doc--indentation)))
              (cond
               ((M2-simple-doc--comment-line-p))
               ((null indent))                  ; blank: still inside
               ((<= indent own) (setq done t))
               (t (setq limit (if limit (min limit indent) indent)))))))
        limit))))

(defun M2-simple-doc--frame-at (stack indent)
  "Return the frame of STACK that a line at INDENT would hang from."
  (cl-find-if (lambda (frame) (> indent (M2-simple-doc--frame-indent frame)))
              stack))

(defun M2-simple-doc--clamp (target parent stack)
  "Return TARGET if the line at point may be moved there, else nil.
PARENT is the frame the line is to hang from and STACK the frames
enclosing it.  Moving a line changes which section it belongs to and
which lines belong to it, and an indentation function moves one line
while its neighbours stay put.  So refuse the move rather than
approximate it when TARGET would

  - carry the line out of PARENT altogether;
  - put it level with the lines that have to stay inside it, which would
    strand them outside;
  - or leave it deep enough for some frame between it and PARENT to adopt
    it.  A line indented past its siblings is not beside them: it is
    inside whatever the one above it opened."
  (let ((subtree (M2-simple-doc--subtree-limit)))
    (and (> target (M2-simple-doc--frame-indent parent))
         (or (null subtree) (< target subtree))
         (eq parent (M2-simple-doc--frame-at stack target))
         target)))

(defun M2-simple-doc--align (anchor parent step stack)
  "Return the column for a line belonging directly inside PARENT.
ANCHOR is where PARENT's first child of this kind already sits, or nil if
it has none, and STEP the increment to fall back on.  STACK is the frames
enclosing the line.

Align with the first child where there is one.  Where there is none this
line *is* the first, and its column is the author's choice of how deeply
this part of the block is stepped: SimpleDoc asks only that it be deeper
than its parent, there is nothing to check it against, and recomputing it
from the block's commonest step would drag its siblings after it or
strand the ones that would not follow.  So leave it, unless the
indentation was asked for by hand."
  (cond
   (anchor (M2-simple-doc--clamp anchor parent stack))
   ((and (M2-simple-doc--explicit-p)
         (not (M2-simple-doc--root-frame-p parent)))
    (M2-simple-doc--clamp (+ (M2-simple-doc--frame-indent parent) step)
                          parent stack))))

(defun M2-simple-doc--body-bounds (section limit)
  "Return the bounds of the body of SECTION, which cannot reach past LIMIT.
The value is a cons of the position after SECTION's keyword line and the
position where its body ends, that being the first line indented no more
deeply than the keyword."
  (save-excursion
    (goto-char (M2-simple-doc--frame-position section))
    (forward-line 1)
    (let ((start (point))
          (indent (M2-simple-doc--frame-indent section))
          (end nil))
      (while (and (null end) (< (point) limit))
        (let ((this (M2-simple-doc--indentation)))
          (if (and this
                   (<= this indent)
                   (not (M2-simple-doc--comment-line-p)))
              (setq end (point))
            (forward-line 1))))
      (cons start (or end (min (point) limit))))))

(defun M2-simple-doc--smie-column (base bounds)
  "Return the column SMIE gives the line at point, with BASE as the outermost.
BOUNDS is the extent of the section body, which is narrowed to before
SMIE is asked.  It must be the body alone and not the whole docstring:
the prose of the sections above is not Macaulay2, and SMIE's lexer, given
sight of it, reads it as a string of identifiers and indents the code
under it as their arguments.

SMIE's notion of the outermost level is moved from column zero out to
BASE, since the code is a block the section has already pushed to the
right.  Return nil where SMIE declines to answer, as it does inside a
string or a comment --- an example may well contain either."
  (unwind-protect
      (save-restriction
        (narrow-to-region (car bounds) (cdr bounds))
        ;; `smie-indent-calculate' indents for the point, not for the line
        ;; the point is on --- `smie-indent-line' moves to the indentation
        ;; before calling it, and so must this.  Reached from
        ;; `indent-line-function', the point is wherever the writer is
        ;; typing, which is usually the end of the line.
        (save-excursion
          (forward-line 0)
          ;; The same two characters `smie-indent-line' skips, since the
          ;; point has to reach where SMIE would have put it.
          (skip-chars-forward " \t")
          (let* ((M2-smie--top-level-column base)
                 ;; `M2-syntax-propertize' demotes to punctuation every
                 ;; delimiter a doc string leaves unbalanced, so that prose
                 ;; cannot displace the code after it.  In here the text is
                 ;; Macaulay2 and a bracket is unbalanced only until it is
                 ;; closed --- which is to say for as long as it is being
                 ;; typed, exactly when indentation is wanted.  So read
                 ;; this much with the syntax table alone.
                 (parse-sexp-lookup-properties nil)
                 (column (condition-case nil (smie-indent-calculate)
                           (error nil))))
            (and (numberp column) column))))
    ;; `syntax-ppss' caches what it parses, and what it parsed just now took
    ;; no notice of those properties.  Do not leave that behind for the rest
    ;; of the buffer to read --- and flush it widened, which is the state
    ;; the rest of the buffer will ask in.
    (syntax-ppss-flush-cache (car bounds))))

(defsubst M2-simple-doc--nothing-on-line-p ()
  "Return non-nil if there is nothing on the line at point to be placed.
That is any line of whitespace, not merely an empty one: after the first
TAB on an empty line it holds the indentation that TAB gave it, and the
next TAB must still see it as a line with nothing on it."
  (null (M2-simple-doc--indentation)))

(defun M2-simple-doc--example-floor (section)
  "Return the indent floor in force for the line at point in SECTION's body.
An `Example' body is divided into separate examples the same way a
docstring is divided into sections: a line no deeper than the running
floor begins a new example and lowers the floor to its own column, and
the more deeply indented lines after it continue that example.

Return nil when nothing above the line has set a floor, which is to say
the line is the first of the body."
  (let ((limit (line-beginning-position))
        (floor nil))
    (save-excursion
      (goto-char (M2-simple-doc--frame-position section))
      (forward-line 1)
      (while (< (point) limit)
        (let ((indent (M2-simple-doc--indentation)))
          (unless (or (null indent) (M2-simple-doc--comment-line-p))
            (when (or (null floor) (<= indent floor))
              (setq floor indent))))
        (forward-line 1)))
    floor))

(defun M2-simple-doc--example-target (section body step)
  "Return the column for a line of the `Example' body of SECTION.
BODY is the extent of that body, and STEP the block's body
increment.  A line that begins an example of its own is left exactly
where it is: its column is what fixes the floor for the lines after it,
so moving it would run two examples together or split one in two,
changing what `installPackage' runs and what the transcript shows.  Only
a line that continues an example is passed to SMIE."
  (let ((floor (M2-simple-doc--example-floor section))
        (current (M2-simple-doc--indentation)))
    (cond
     ;; The first line of the body.  There is nothing to preserve on a
     ;; line just opened with RET, so the usual step is the best guess.
     ((null floor)
      (and (M2-simple-doc--nothing-on-line-p)
           (+ (M2-simple-doc--frame-indent section) step)))
     ;; This line begins an example of its own, and the column it begins
     ;; at is the writer's to choose --- but a line just typed may have no
     ;; indentation at all, and pressing TAB on it asks for it to be lined
     ;; up with the examples above rather than left where it fell.
     ((and current (<= current floor))
      (and (M2-simple-doc--explicit-p) floor))
     (t
      (let ((column (M2-simple-doc--smie-column floor body)))
        (cond
         ;; SMIE would not say --- the point is in a string, or the line
         ;; above is half-written.  A line with something on it stays
         ;; where it is, but one just opened has to go somewhere, and the
         ;; floor is where the example it belongs to began.
         ((null column) (and (M2-simple-doc--nothing-on-line-p) floor))
         ;; SMIE reads the line as the continuation of an expression: a
         ;; bracket is still open, or the line before it ended in an
         ;; operator.  Deeper than the floor is where it belongs, and it
         ;; goes on being part of the same example.
         ((> column floor) column)
         ;; SMIE reads it as a statement of its own, and one of those
         ;; belongs at the floor.  Moving a line that has something on it
         ;; there makes a separate example of it and changes what
         ;; `installPackage' runs, so that waits to be asked for; but a
         ;; line with nothing on it has nothing to move, and is being
         ;; opened for whatever comes next.
         ((or (M2-simple-doc--nothing-on-line-p)
              (M2-simple-doc--explicit-p))
          floor)
         (t nil)))))))

(defun M2-simple-doc--target (bounds)
  "Return the column the line at point belongs at, or nil to leave it alone.
BOUNDS is the extent of the docstring, as `M2-inside-simple-doc-p'
returns it."
  (let ((indent (M2-simple-doc--indentation)))
    (cond
     ((M2-simple-doc--terminator-line-p (cdr bounds)) nil)
     ;; A comment vanishes before SimpleDoc sees it, so nothing can be said
     ;; about where it goes.
     ((M2-simple-doc--comment-line-p) nil)
     ;; A line that is blank but not empty keeps its whitespace, which may
     ;; well be part of a `Pre' or an example --- unless the writer has
     ;; pressed TAB on it, which is a request to move it and which is also
     ;; what every TAB after the first sees, the first having filled the
     ;; line with the whitespace this clause is about.
     ((and (null indent)
           (/= (line-beginning-position) (line-end-position))
           (not (M2-simple-doc--explicit-p)))
      nil)
     (t
      (let* ((steps (M2-simple-doc--cached-steps bounds))
             (stack (M2-simple-doc--stack (car bounds)
                                          (line-beginning-position)))
             (keyword (M2-simple-doc--keyword-on-line))
             (frame (and keyword (M2-simple-doc--keyword-frame stack keyword))))
        (cond
         ;; It names a section, and either it already heads a block where
         ;; it sits or the writer has asked for it to be put in one.
         ((and frame
               (or (M2-simple-doc--explicit-p)
                   (M2-simple-doc--section-here-p stack indent keyword)))
          (M2-simple-doc--align (M2-simple-doc--frame-section-anchor frame)
                                frame (car steps) stack))
         ;; It names a section but heads no block where it sits, so to
         ;; SimpleDoc it is body text that merely reads like a keyword.  It
         ;; cannot be indented as body text either: any move might be the
         ;; one that lands it beside its siblings and makes it the section
         ;; it only looks like.  Leave it exactly where it is.
         (frame nil)
         (t (M2-simple-doc--body-target stack steps bounds))))))))

(defun M2-simple-doc--keyword-frame (stack keyword)
  "Return the frame of STACK whose body admits KEYWORD.
The innermost such frame wins, which is what settles the keywords listed
in two tables at once: a `Description' inside a `Synopsis' belongs to the
synopsis, and one inside a `Node' to the node.  Return nil when nothing on
the stack admits KEYWORD, in which case the line is body text that merely
reads like a keyword."
  (if (equal keyword "Node")
      ;; A `Node' names a documentation node, and a docstring is a sequence
      ;; of them.  It appears in its own body table, so one can be made to
      ;; nest inside another, but nothing ever consumes a nested node ---
      ;; the grammar calls that an accident of the table rather than a
      ;; feature.  Reading it as the innermost match would let the node
      ;; above swallow this one and every node after it, so bind it to the
      ;; docstring itself.
      (car (last stack))
    (cl-find-if (lambda (frame)
                  (M2-simple-doc--admits-p (M2-simple-doc--frame-table frame)
                                           keyword))
                stack)))

(defun M2-simple-doc--section-here-p (stack indent keyword)
  "Return non-nil if a line holding KEYWORD at INDENT already opens a section.
STACK is the list of frames enclosing it.  SimpleDoc reads a word as a
keyword only where the line's own indentation puts it directly inside a
section whose table admits it; anywhere else the same word is just a word
in the body of something."
  (let ((frame (M2-simple-doc--frame-at stack indent)))
    (and frame
         (M2-simple-doc--admits-p (M2-simple-doc--frame-table frame) keyword))))

(defun M2-simple-doc--explicit-p ()
  "Return non-nil if this line's indentation was asked for by hand.
A keyword line that is not yet a section head is moved into place only
then.  Doing it under `indent-region' would let reindenting a file
silently rewrite its documentation: a line reading `Example' inside a
paragraph is prose to SimpleDoc, however much it looks like a section,
and promoting it would add an example that was never there."
  (memq this-command (bound-and-true-p M2-insert-tab-commands)))

(defun M2-simple-doc--fresh-line-target (stack steps)
  "Return the column for a line with nothing on it yet, given STACK.
STEPS is the block's pair of inferred indentation increments.  Such a
line has just been opened with RET, and since it is blank it popped no
frame: the innermost is the line above.  Continue that line, or begin its
body if it opened a section --- so that RET after `Description' lands
where a `Text' belongs."
  (let* ((frame (car stack))
         (keyword (M2-simple-doc--frame-keyword frame))
         (indent (M2-simple-doc--frame-indent frame)))
    (cond
     ;; Nothing above at all: the docstring is still empty.
     ((M2-simple-doc--root-frame-p frame) M2-simple-doc-indent-level)
     (keyword
      (+ indent (if (eq (M2-simple-doc--body-shape keyword) 'sections)
                    (car steps)
                  (cdr steps))))
     (t indent))))

(defun M2-simple-doc--body-target (stack steps bounds)
  "Return the column for a body line, given the enclosing STACK.
STEPS is the block's pair of inferred indentation increments and BOUNDS
the extent of the docstring."
  (let* ((section (M2-simple-doc--enclosing-section stack))
         (keyword (and section (M2-simple-doc--frame-keyword section)))
         (shape (M2-simple-doc--body-shape keyword))
         (anchor (and section (M2-simple-doc--frame-body-anchor section)))
         (step (cdr steps)))
    (cond
     ;; The two bodies that hold Macaulay2 rather than text.  Both are
     ;; handed to SMIE, over the section body alone; they differ in that an
     ;; `Example' is divided into separate examples by its own
     ;; indentation, which SMIE must therefore not disturb, while a `Code'
     ;; is one parenthesized expression with no such structure to keep.
     ((memq shape '(example code))
      (let ((body (M2-simple-doc--body-bounds
                   section (M2-simple-doc--text-end (cdr bounds)))))
        (if (eq shape 'example)
            (M2-simple-doc--example-target section body step)
          (cond
           (anchor (let ((column (M2-simple-doc--smie-column anchor body)))
                     (and column (max anchor column))))
           ;; The first line of the body fixes the dedent applied to the
           ;; whole section, so it is the author's --- but a line just
           ;; opened has nothing to preserve.
           ((M2-simple-doc--nothing-on-line-p)
            (+ (M2-simple-doc--frame-indent section) step))))))
     ;; A line with nothing on it yet: it has no text to place, and RET
     ;; should always land somewhere.
     ((M2-simple-doc--nothing-on-line-p)
      (M2-simple-doc--fresh-line-target stack steps))
     ;; Outside any section, or inside one that holds only sections and so
     ;; has no business holding this line: say nothing.
     ((null section) nil)
     ((memq shape '(nil sections verbatim)) nil)
     ;; A line one level inside the section is one of its own: an item
     ;; head, a key, a line of a paragraph.
     ((eq section (car stack))
      (M2-simple-doc--align anchor section step stack))
     ;; A line shallower than the section's other body lines has fallen
     ;; short of them --- typed at the left margin, most likely, since that
     ;; is where a line starts.  Where exactly it fell is no information,
     ;; so TAB brings it in to join them.  Bulk reindentation still leaves
     ;; it: a line shallower than the section it appears to be in may have
     ;; been meant to end that section.
     ((and (M2-simple-doc--explicit-p)
           anchor
           (< (or (M2-simple-doc--indentation) 0) anchor))
      (M2-simple-doc--clamp anchor section stack))
     ;; Anything deeper hangs off one of those, and its depth is what says
     ;; so: the description of an item, a nested menu, a continuation.
     ;; Leave it be.
     (t nil))))

(defun M2-simple-doc--candidate-columns (bounds target)
  "Return the columns the line at point could sensibly be given.
BOUNDS is the extent of the docstring and TARGET the column computed for
the line.  The value is sorted, largest first, and always holds TARGET.

The candidates are the columns of the children a section already has: one
level per enclosing section, which is what a line at that depth would be
a part of.  In

  Key
    foo

a line under `foo' can be another key, at the column `foo' stands in, or
a new section of the node, at the column `Key' stands in --- and those
are just the body column of the `Key' frame and the section column of the
docstring's own."
  (let ((columns (list target)))
    (dolist (frame (M2-simple-doc--stack (car bounds) (line-beginning-position)))
      (dolist (column (list (M2-simple-doc--frame-section-anchor frame)
                            (M2-simple-doc--frame-body-anchor frame)))
        (when (and column (>= column 0)) (push column columns))))
    (sort (delete-dups columns) #'>)))

(defun M2-simple-doc--cycling-p ()
  "Return non-nil if this is a second or later TAB on an unwritten line.
Repeating an indentation command is how one asks for the next
possibility, as in `python-mode'.

Unlike `python-mode' this offers the possibilities only for a line with
nothing on it yet, where the writer is choosing what to write next and
any level might be meant.  Once there is text on the line, what it is
settles where it goes: a keyword belongs where its table puts it, and
prose belongs in the section it is part of.  Cycling such a line would
not reindent it but move it from one section to another."
  (and (M2-simple-doc--explicit-p)
       (eq last-command this-command)
       (M2-simple-doc--nothing-on-line-p)))

(defun M2-simple-doc--previous-column (columns indentation)
  "Return the largest of COLUMNS below INDENTATION, or the largest of all.
COLUMNS is sorted largest first, so the first one below INDENTATION is
the one wanted.  Cycling runs leftwards --- the computed column is the
likeliest and the shallower ones are the alternatives --- and comes round
to the deepest again once there is nothing shallower left."
  (or (cl-find-if (lambda (column) (< column indentation)) columns)
      (car columns)))

(defun M2-simple-doc-indent-line (bounds)
  "Indent the current line of the SimpleDoc string spanning BOUNDS.
Return `noindent' where SimpleDoc's own reading of the line makes its
indentation something other than this function's to choose, so that
`indent-region' and `electric-indent-mode' leave such a line alone, and t
where the line was indented.  Never nil, which `M2-electric-tab' reads as
meaning the line was not SimpleDoc at all.

TAB pressed again on a line already indented steps it out to the next
level that would make sense there, and around to the deepest again once
there is nowhere further to go.  Which section a line belongs to is what
its indentation says, and only the writer knows which was meant."
  (let ((target (M2-simple-doc--target bounds)))
    (when (and target (M2-simple-doc--cycling-p))
      (setq target (M2-simple-doc--previous-column
                    (M2-simple-doc--candidate-columns bounds target)
                    (current-indentation))))
    (if (null target)
        'noindent
      ;; SimpleDoc reckons a tab as eight columns whatever the buffer
      ;; thinks, and `M2-mode' indents with spaces.  `indent-line-to' does
      ;; nothing at all when the column already matches, so the lines this
      ;; function leaves where they are keep whatever whitespace they have
      ;; --- which matters, since a good third of Macaulay2's own
      ;; docstrings are indented with tabs.
      (let ((within (<= (point) (save-excursion (back-to-indentation) (point))))
            (tab-width M2-simple-doc--tab-width)
            (indent-tabs-mode nil))
        ;; `indent-line-to' goes to the indentation before changing it, so
        ;; the point has to be put back: after TAB on a line just typed it
        ;; belongs after the text, ready for the next word.
        (save-excursion (indent-line-to target))
        (when within (back-to-indentation)))
      t)))

;;; Fontification.

;; Every one of the 27 SimpleDoc keywords is also a Macaulay2 symbol, so
;; the tables in `M2-mode-font-lock-keywords' mark up a docstring's prose
;; as though it were code: a headline reading "a Key for the Example in
;; the Text" comes out with three constants and two keywords in it, and a
;; -- written in a sentence comments out the rest of the line.  The remedy
;; is not to add colour but to withhold it, so this paints the prose over
;; again as documentation, and is appended to those tables so that it has
;; the last word.
;;
;; What it must not paint over is an @...@ block, whose contents really
;; are Macaulay2 and have just been marked up correctly.

(defconst M2-simple-doc--prose-sections
  '("Text" "Caveat" "Acknowledgement" "Contributors" "References" "Item"
    "Headline" "Heading" "Usage" "Pre" "CannedExample" "Citation"
    "ExampleFiles")
  "Sections whose body is prose, or text taken raw.
`Key', `SeeAlso', `SourceCode', `BaseFunction', `Code' and `Example' are
absent because their bodies are evaluated or run as Macaulay2, and the
menu sections because their entries are mostly documentation keys.")

(defconst M2-simple-doc--item-sections '("Inputs" "Outputs")
  "Sections whose body is a list of items.
The head of an item names a type, which is Macaulay2 and is left as such;
the more deeply indented lines describing it are prose.")

(defun M2-simple-doc--prose-line-p (stack)
  "Return non-nil if the line whose enclosing frames are STACK is prose."
  (let* ((section (M2-simple-doc--enclosing-section stack))
         (keyword (and section (M2-simple-doc--frame-keyword section))))
    (and keyword
         (or (member keyword M2-simple-doc--prose-sections)
             ;; An item's description, but not its head.
             (and (member keyword M2-simple-doc--item-sections)
                  (not (eq section (car stack))))))))

(defun M2-simple-doc--line-spans ()
  "Return the stretches of the line at point outside any @...@ block.
The value is a list of conses, in order.  A backslash escapes the
character after it, so a \\=\\@ is a literal at sign and opens nothing.
An unmatched @ is an error in SimpleDoc; here it simply takes the rest of
the line, so that one cannot swallow the buffer."
  (save-excursion
    (forward-line 0)
    (let ((eol (line-end-position)) (spans nil) (start nil))
      (skip-chars-forward M2-simple-doc--whitespace eol)
      (setq start (point))
      (while (< (point) eol)
        (cond
         ((eq (char-after) ?\\) (forward-char (min 2 (- eol (point)))))
         ((eq (char-after) ?@)
          (when (> (point) start) (push (cons start (point)) spans))
          (forward-char 1)
          (let ((done nil))
            (while (and (not done) (< (point) eol))
              (cond
               ((eq (char-after) ?\\) (forward-char (min 2 (- eol (point)))))
               ((eq (char-after) ?@) (forward-char 1) (setq done t))
               (t (forward-char 1)))))
          (setq start (point)))
         (t (forward-char 1))))
      (when (> eol start) (push (cons start eol) spans))
      (nreverse spans))))

(defun M2-simple-doc--prose-spans (bounds from to)
  "Return the stretches of prose between FROM and TO.
BOUNDS is the extent of the SimpleDoc string they lie in.

Which lines are prose can only be told from the sections above them, so
the string is read from its beginning however small the region; but the
stretches themselves are worked out for the region alone, and the reading
stops at its end.  Doing it for the whole string instead cost a thousand
lines of needless work on every keystroke in a long docstring."
  (let ((spans nil)
        (limit (min to (M2-simple-doc--text-end (cdr bounds)))))
    (M2-simple-doc--walk
     (car bounds) limit
     (lambda (_indent keyword stack)
       ;; A keyword line names a section; it is already marked up as the
       ;; Macaulay2 symbol it also is, which reads well enough.
       (unless keyword
         (when (and (>= (line-end-position) from)
                    (M2-simple-doc--prose-line-p stack))
           (push (M2-simple-doc--line-spans) spans)))))
    (apply #'nconc (nreverse spans))))

(defvar-local M2-simple-doc--spans-cache nil
  "Memo for `M2-simple-doc--prose-spans'.
A cons of a key describing one region of one docstring and the stretches
of prose in it.  Font lock asks for these repeatedly as it works through
a region, and answering means reading the docstring down to it.")

(defun M2-simple-doc--cached-prose-spans (bounds from to)
  "Return the stretches of prose between FROM and TO in the string BOUNDS.
The key deliberately leaves FROM out.  Font lock works through a region
by calling the matcher again and again with the point further along and
the same limit, so keying on the point would miss every time and read the
docstring afresh at every call; the stretches found for the first call
cover the whole of that region, and serve for the rest of them."
  (let ((key (list (car bounds) (cdr bounds) to (buffer-chars-modified-tick))))
    (unless (equal (car M2-simple-doc--spans-cache) key)
      (setq M2-simple-doc--spans-cache
            (cons key (M2-simple-doc--prose-spans bounds from to))))
    (cdr M2-simple-doc--spans-cache)))

(defun M2-simple-doc--opener-regexp ()
  "Return a regexp matching the /// that opens a SimpleDoc string."
  (concat "\\_<" (regexp-opt M2-simple-doc-string-openers) "[ \t]*///"))

(defun M2-simple-doc-fontify-prose (limit)
  "Font-lock matcher for the prose of a SimpleDoc string.
Set the match data to the next stretch of prose between point and LIMIT
and move over it, or return nil when there is none.  A stretch stops at
the end of its line and at either end of an @...@ block, so that the
Macaulay2 expression in one keeps the markup the rest of
`M2-mode-font-lock-keywords' gave it."
  (let ((found nil)
        (start (point))
        (opener (M2-simple-doc--opener-regexp)))
    (while (and (not found) (< (point) limit))
      (let ((bounds (M2-inside-simple-doc-p (point))))
        (if (null bounds)
            (unless (re-search-forward opener limit t)
              (goto-char limit))
          (let* ((spans (M2-simple-doc--cached-prose-spans bounds start limit))
                 (span (cl-find-if (lambda (s) (> (cdr s) (point))) spans)))
            (if (and span (< (car span) limit))
                (let ((beg (max (car span) (point)))
                      (end (min (cdr span) limit)))
                  (set-match-data (list beg end))
                  (goto-char (max end (1+ (point))))
                  (setq found t))
              ;; Nothing more in this string: step past it.
              (goto-char (max (1+ (point)) (min limit (cdr bounds)))))))))
    found))

(provide 'M2-simple-doc)

;;; M2-simple-doc.el ends here
