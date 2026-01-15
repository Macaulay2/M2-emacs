;;; M2-init.el --- Setup M2.el for autoloading (legacy) -*- lexical-binding: t -*-

;; Copyright (C) 1997-2026 The Macaulay2 Authors

;; Version: 1.25.11
;; Keywords: languages
;; URL: https://github.com/Macaulay2/M2-emacs

;;; Commentary:

;; This file is used to set up autoloads for the M2 package.  It is used as a
;; legacy fallback if M2 was not installed using package-install or similar.
;;
;; In particular, users can add the following to their .emacs:
;; (add-to-list 'load-path "/path/to/M2")
;; (load "M2-init")
;; This is done automatically by the Macaulay2 method "setupEmacs()".

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

(autoload 'M2             "M2" "Run Macaulay2 in an emacs buffer" t)
(autoload 'M2-mode        "M2" "Macaulay2 editing mode" t)
(autoload 'M2-comint-mode "M2" "Macaulay2 command interpreter mode" t)
(add-to-list 'auto-mode-alist '("\\.m2\\'" . M2-mode))

(provide 'M2-init)

;;; M2-init.el ends here
