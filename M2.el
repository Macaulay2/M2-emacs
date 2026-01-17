;;; M2.el --- Legacy support for running (require 'M2) -*- lexical-binding: t -*-

;; Copyright (C) 1997-2026 The Macaulay2 Authors

;; Version: 1.25.11
;; Keywords: languages
;; URL: https://github.com/Macaulay2/M2-emacs

;;; Commentary:
;; This file exists so that (require 'M2) will still load the Macaulay2 package
;; despite the M2 -> macaulay2 renaming.

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

(warn "`M2' is obsolete (as of 1.26.05); use `macaulay2' instead.")

(unless (fboundp 'macaulay2)
  (load "macaulay2"))

;;; Code:

(provide 'M2)

;;; M2.el ends here
