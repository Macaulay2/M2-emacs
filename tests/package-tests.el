;;; package-tests.el --- Test the installed archive -*- lexical-binding: t -*-
(require 'package)
(require 'ert)
(require 'cl-lib)

(load (expand-file-name "install-package.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)

(ert-deftest M2-package-autoloads ()
  (should (autoloadp (symbol-function 'M2)))
  (should (autoloadp (symbol-function 'M2-register-eglot)))
  (should (autoloadp (symbol-function 'M2-register-lsp)))
  (with-temp-buffer
    (setq buffer-file-name "/tmp/example.m2")
    (set-auto-mode)
    (should (eq major-mode 'M2-mode))))

(ert-deftest M2-package-edit-without-executable ()
  (require 'M2)
  (let ((M2-exe "/nonexistent/M2"))
    (with-temp-buffer
      (M2-mode)
      (insert "groeb")
      (should (M2-completion-at-point)))))

(ert-deftest M2-package-command-configuration ()
  (require 'M2)
  (let ((M2-command nil) (M2-exe "/a path/M2"))
    (should (equal (M2-default-command)
                   (concat (shell-quote-argument M2-exe) " --no-readline")))
    (setq M2-exe "/another/M2")
    (should (string-match-p "/another/M2" (M2-default-command))))
  (let ((M2-command "ssh server M2 --no-readline"))
    (should (equal (M2-default-command) M2-command))))

(ert-deftest M2-package-info-navigation ()
  (require 'M2)
  (require 'info)
  (let* ((directory (make-temp-file "M2-info-test-" t))
         ;; Keep the configured path available after M2-info-help returns.
         (Info-additional-directory-list
          (cons directory Info-additional-directory-list))
         info-buffer)
    (unwind-protect
        (save-window-excursion
          (dolist (manual '(("M2-test-first" . "* Menu:\n* Second manual: (M2-test-second)Top.\n")
                            ("M2-test-second" . "Cross-manual navigation succeeded.\n")))
            (with-temp-file (expand-file-name (concat (car manual) ".info") directory)
              (insert "\x1f\nFile: " (car manual) ".info,  Node: Top,  Up: (dir)\n\n"
                      (cdr manual))))
          (should (equal (M2-info-help "-* infoHelp: (M2-test-first)Top *-\nafter request")
                         "after request"))
          (setq info-buffer (get-buffer "*info*"))
          (with-current-buffer info-buffer
            (should (equal (file-name-base Info-current-file) "M2-test-first"))
            (goto-char (point-min))
            (search-forward "Second manual:")
            (Info-follow-nearest-node)
            (should (equal (file-name-base Info-current-file) "M2-test-second"))
            (should (equal Info-current-node "Top"))
            (should (string-match-p "Cross-manual navigation succeeded" (buffer-string)))))
      (when (buffer-live-p info-buffer) (kill-buffer info-buffer))
      (delete-directory directory t))))

(ert-deftest M2-package-session ()
  (require 'M2)
  (let ((buffer (M2 "cat" "M2-test" t)))
    (unwind-protect
        (with-current-buffer buffer
          (should (eq major-mode 'M2-comint-mode))
          (let ((process (get-buffer-process buffer)))
            (process-send-string process "M2-package-test-output\n")
            (let ((deadline (+ (float-time) 5)))
              (while (and (< (float-time) deadline)
                          (not (string-match-p "M2-package-test-output"
                                               (buffer-string))))
                (accept-process-output process 0.1)))
            (should (string-match-p "M2-package-test-output" (buffer-string)))))
      (when (buffer-live-p buffer)
        (set-process-query-on-exit-flag (get-buffer-process buffer) nil)
        (kill-buffer buffer)))))

(ert-deftest M2-package-real-session ()
  (skip-unless (getenv "M2_TEST_COMMAND"))
  (require 'M2)
  (let ((buffer (M2 (getenv "M2_TEST_COMMAND") "M2-integration-test" t)))
    (unwind-protect
        (with-current-buffer buffer
          (let ((process (get-buffer-process buffer)))
            (process-send-string process
                                 "print(\"EMACS-TEST-\" | toString(2+2))\n")
            (let ((deadline (+ (float-time) 30)))
              (while (and (< (float-time) deadline)
                          (not (string-match-p "EMACS-TEST-4" (buffer-string))))
                (accept-process-output process 0.1)))
            (should (string-match-p "EMACS-TEST-4" (buffer-string)))))
      (when (buffer-live-p buffer)
        (set-process-query-on-exit-flag (get-buffer-process buffer) nil)
        (kill-buffer buffer)))))

(ert-run-tests-batch-and-exit)
;;; package-tests.el ends here
