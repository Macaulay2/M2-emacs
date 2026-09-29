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

(ert-deftest M2-package-documentation ()
  (require 'M2)
  (save-window-excursion
    (M2-help)
    (should buffer-read-only)
    (should (string-match-p "Running Macaulay2" (buffer-string)))
    (kill-buffer))
  (let ((M2-info-directory "/test/info") seen)
    (cl-letf (((symbol-function 'info-other-window)
               (lambda (node)
                 (setq seen (list node (car Info-additional-directory-list))))))
      (M2-info-help "-* infoHelp: (Macaulay2)Top *-\n"))
    (should (equal seen '("(Macaulay2)Top" "/test/info")))))

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
