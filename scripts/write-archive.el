;;; write-archive.el --- Write the Macaulay2 package archive index -*- lexical-binding: t -*-

(when (equal (car command-line-args-left) "--")
  (pop command-line-args-left))

(let* ((version (pop command-line-args-left))
       (directory (pop command-line-args-left))
       (tarball (expand-file-name (format "M2-%s.tar" version) directory))
       (index (expand-file-name "archive-contents" directory)))
  (unless (and version directory (file-exists-p tarball))
    (error "Expected version and directory containing %s" tarball))
  (with-temp-file index
    (prin1 (list 1
                 (cons 'M2
                       (vector (version-to-list version)
                               '((emacs (24 4)))
                               "Macaulay2 editing and interactive sessions"
                               'tar)))
           (current-buffer))
    (insert "\n")))

;;; write-archive.el ends here
