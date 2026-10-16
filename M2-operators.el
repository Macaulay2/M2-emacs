;;; M2-operators.el --- Generated Macaulay2 operator table -*- lexical-binding: t -*-

;; Copyright (C) 1997-2026 The Macaulay2 Authors

;; Version: 1.26.06
;; Keywords: languages
;; URL: https://github.com/Macaulay2/M2-emacs

;;; Commentary:

;; This file contains the Macaulay2 operator table, read from the parsing
;; tables of the interpreter itself rather than transcribed by hand, so that
;; it cannot drift as operators are added to the language.
;;
;; It is used to build the grammar in M2.el.  Run "make update-operators" to
;; regenerate it.
;;
;; Auto-generated for Macaulay2-1.26.06. Do not modify this file manually.

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

(defconst M2-operators-version
  "1.26.06"
  "The M2 version used to generate the operator table.")

(defconst M2-operators-binary
  '((left ",")
    (right "%=" "&=" "**=" "*=" "++=" "+=" "-=" "->" "..<=" "..=" "//=" "/=" ":=" "<-" "<<=" "<==>=" "=" "===>=" "==>=" "=>" ">>" ">>=" "??=" "@=" "@@=" "@@?=" "\\=" "\\\\=" "^**=" "^=" "^^=" "_=" "|-=" "|=" "|_=" "||=" "~=" "·=" "⊠=" "⧢=")
    (left "<<")
    (right "|-")
    (right "<===" "===>")
    (right "<==>")
    (right "<==" "==>")
    (right "??" "or")
    (right "xor")
    (right "and")
    (right "!=" "<" "<=" "=!=" "==" "===" ">" ">=" "?" "~")
    (left "||")
    (right ":")
    (left "|")
    (left "^^")
    (left "&")
    (left ".." "..<")
    (left "+" "++" "-")
    (left "·")
    (left "**" "⊠" "⧢")
    (right "\\" "\\\\")
    (left "%" "*" "/" "//")
    (right "@")
    (left "@@" "@@?")
    (left "#" "#?" "." ".?" "^" "^**" "^<" "^<=" "^>" "^>=" "_" "_<" "_<=" "_>" "_>=" "|_"))
  "Macaulay2 binary operators grouped by precedence, loosest level first.
Each element is a row for `smie-precs->prec2'.  Adjacency and the statement
separator are omitted, since `M2-smie-grammar' describes those itself.")

(defconst M2-operators-postfix
  '("!" "^!" "^*" "^~" "_!" "_*" "_~")
  "Macaulay2 postfix operators.
The closing delimiters, which the parsing tables also count as postfix,
are omitted, since `M2-smie-grammar' describes those itself.")

(provide 'M2-operators)

;;; M2-operators.el ends here
