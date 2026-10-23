;;; lsp-tests.el --- LSP configuration and integration tests -*- lexical-binding: t -*-
(require 'ert)
(require 'cl-lib)
(load (expand-file-name "install-package.el"
                        (file-name-directory (or load-file-name buffer-file-name)))
      nil t)
(require 'M2)

(ert-deftest M2-lsp-server-discovery ()
  (let* ((directory (make-temp-file "M2-lsp-prefix-" t))
         (M2-exe (expand-file-name "M2" directory))
         (server (expand-file-name "M2-language-server" directory))
         (M2-language-server-command nil)
         (exec-path nil))
    (unwind-protect
        (progn
          (with-temp-file server (insert "#!/bin/sh\nexit 0\n"))
          (set-file-modes server #o755)
          (should (equal (M2--language-server-command) (list server)))
          (delete-file server)
          (should (equal (M2--language-server-command) '("M2-language-server")))
          (setq M2-language-server-command '("ssh" "host" "M2-language-server"))
          (should (equal (M2--language-server-command) M2-language-server-command)))
      (delete-directory directory t))))

(ert-deftest M2-lsp-eglot-registration ()
  (skip-unless (require 'eglot nil t))
  (M2-register-eglot)
  (M2-register-eglot)
  (let ((M2-language-server-command '("test-server" "--test")))
    (should (equal (funcall (cdr (assq 'M2-mode eglot-server-programs)) nil)
                   M2-language-server-command))))

(ert-deftest M2-lsp-lsp-mode-registration ()
  (skip-unless (require 'lsp-mode nil t))
  (M2-register-lsp)
  (M2-register-lsp)
  (should (gethash 'M2 lsp-clients))
  (should (equal (cdr (assq 'M2-mode lsp-language-id-configuration)) "M2")))

(defun M2-test--server-command ()
  "Read the optional integration-test command as a Lisp list."
  (read (getenv "M2_LSP_TEST_COMMAND")))

(ert-deftest M2-lsp-eglot-integration ()
  (skip-unless (getenv "M2_LSP_TEST_COMMAND"))
  (require 'eglot)
  (M2-register-eglot)
  (let* ((directory (make-temp-file "M2-eglot-" t))
         (file (expand-file-name "example.m2" directory))
         (M2-language-server-command (M2-test--server-command))
         (eglot-sync-connect 10)
         (eglot-connect-timeout 20)
         buffer server)
    (unwind-protect
        (progn
          (with-temp-file file (insert "ring\n"))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (call-interactively #'eglot)
            (let ((deadline (+ (float-time) 25)))
              (while (and (< (float-time) deadline)
                          (not (eglot-current-server)))
                (accept-process-output nil 0.1)))
            (setq server (eglot-current-server))
            (should server)
            (let ((reply (jsonrpc-request
                          server :textDocument/completion
                          (list :textDocument (list :uri (concat "file://" file))
                                :position '(:line 0 :character 2)))))
              (should (> (length reply) 0))
              (should (string-prefix-p "ring" (plist-get (elt reply 0) :label))))))
      (when server (eglot-shutdown server))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (delete-directory directory t))))

(ert-deftest M2-lsp-lsp-mode-integration ()
  (skip-unless (getenv "M2_LSP_TEST_COMMAND"))
  (require 'lsp-mode)
  (M2-register-lsp)
  (let* ((directory (make-temp-file "M2-lsp-mode-" t))
         (file (expand-file-name "example.m2" directory))
         (M2-language-server-command (M2-test--server-command))
         (lsp-session-file (expand-file-name "session" directory))
         (lsp-enable-file-watchers nil)
         (lsp-enable-snippet nil)
         (lsp-auto-guess-root t)
         buffer)
    (unwind-protect
        (progn
          (with-temp-file file (insert "ring\n"))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (lsp)
            (let ((deadline (+ (float-time) 25)))
              (while (and (< (float-time) deadline) (not (cl-some (lambda (workspace)
                                          (eq (lsp--workspace-status workspace) 'initialized))
                                        (lsp-workspaces))))
                (accept-process-output nil 0.1)))
            (should (cl-some (lambda (workspace)
                               (eq (lsp--workspace-status workspace) 'initialized))
                             (lsp-workspaces)))
            (let ((reply (lsp-request
                          "textDocument/completion"
                          (list :textDocument (list :uri (concat "file://" file))
                                :position '(:line 0 :character 2)))))
              (should (> (length reply) 0))
              (should (string-prefix-p "ring" (gethash "label" (elt reply 0)))))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (mapc #'lsp-workspace-shutdown (lsp-workspaces)))
        (kill-buffer buffer))
      (delete-directory directory t))))

(ert-run-tests-batch-and-exit)
;;; lsp-tests.el ends here
