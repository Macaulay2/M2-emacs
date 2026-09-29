;;; archive-tests.el --- Install M2 through a local package archive -*- lexical-binding: t -*-

(require 'package)
(when (equal (car command-line-args-left) "--")
  (pop command-line-args-left))
(let ((archive (expand-file-name (pop command-line-args-left)))
      (package-user-dir (make-temp-file "M2-archive-test-" t))
      (package-archives nil))
  (add-to-list 'package-archives (cons "macaulay2" archive))
  (package-initialize)
  (package-refresh-contents)
  (let ((candidate (cadr (assq 'M2 package-archive-contents))))
    (unless candidate
      (error "M2 is missing from archive-contents"))
    (package-install candidate)
    (unless (and (package-installed-p 'M2 (package-desc-version candidate))
                 (fboundp 'M2-help))
      (error "The archive did not install and activate M2"))))

;;; archive-tests.el ends here
