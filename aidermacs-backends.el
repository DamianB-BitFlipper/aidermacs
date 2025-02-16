;;; aidermacs-backends.el --- Backend implementations for aidermacs.el -*- lexical-binding: t; -*-
;; Author: Mingde (Matthew) Zeng <matthewzmd@posteo.net>
;; Version: 0.5.0
;; Package-Requires: ((emacs "26.1") (transient "0.3.0"))
;; Keywords: ai emacs agents llm aider ai-pair-programming, convenience, tools
;; URL: https://github.com/MatthewZMD/aidermacs.el
;; Originally forked from: Kang Tu <tninja@gmail.com> Aider.el

;;; Commentary:
;; Backend dispatcher for aidermacs.el

;;; Code:

(require 'aidermacs-backend-comint)
(when (require 'vterm nil 'noerror)
  (require 'aidermacs-backend-vterm))

(defgroup aidermacs-backends nil
  "Backend customization for aidermacs."
  :group 'aidermacs)

(defcustom aidermacs-backend 'comint
  "Backend to use for the aidermacs process.
Options are 'comint (the default) or 'vterm. When set to 'vterm, aidermacs will
launch a fully functional vterm buffer (with bracketed paste support) instead
of using a comint process."
  :type '(choice (const :tag "Comint" comint)
          (const :tag "VTerm" vterm))
  :group 'aidermacs-backends)

;; Core output management functionality
(defgroup aidermacs-output nil
  "Output handling for aidermacs."
  :group 'aidermacs)

(defcustom aidermacs-output-limit 10
  "Maximum number of output entries to keep in history."
  :type 'integer
  :group 'aidermacs-output)

(defvar aidermacs--output-history nil
  "List to store aidermacs output history.
Each entry is a cons cell (timestamp . output-text).")

(defvar aidermacs--last-command nil
  "Store the last command sent to aidermacs.")

(defvar aidermacs--current-output ""
  "Accumulator for current output being captured as a string.")

(defun aidermacs-get-output-history (&optional limit)
  "Get the output history, optionally limited to LIMIT entries.
Returns a list of (timestamp . output-text) pairs, most recent first."
  (let ((history aidermacs--output-history))
    (if limit
        (seq-take history limit)
      history)))

(defun aidermacs-clear-output-history ()
  "Clear the output history."
  (interactive)
  (setq aidermacs--output-history nil))

(defvar aidermacs--current-callback nil
  "Store the callback function for the current command.")

(defvar aidermacs--in-callback nil
  "Flag to prevent recursive callbacks.")

(defun aidermacs--store-output (output)
  "Store OUTPUT string in the history with timestamp.
If there's a callback function, call it with the output."
  (setq aidermacs--current-output (substring-no-properties output))
  (push (cons (current-time) (substring-no-properties output)) aidermacs--output-history)
  (when (> (length aidermacs--output-history) aidermacs-output-limit)
    (setq aidermacs--output-history
          (seq-take aidermacs--output-history aidermacs-output-limit)))
  (unless aidermacs--in-callback
    (when aidermacs--current-callback
      (let ((aidermacs--in-callback t))
        (funcall aidermacs--current-callback output)
        (setq aidermacs--current-callback nil)))))

;; Backend dispatcher functions
(defun aidermacs-run-backend (program args buffer-name)
  "Run aidermacs using the selected backend.
PROGRAM is the aidermacs executable path, ARGS are command line arguments,
and BUFFER-NAME is the name for the aidermacs buffer."
  (cond
   ((eq aidermacs-backend 'vterm)
    (aidermacs-run-vterm program args buffer-name))
   (t
    (aidermacs-run-comint program args buffer-name))))

(defvar-local aidermacs--command-in-progress nil
  "Track whether a command is being accumulated but not yet submitted.")

(defun aidermacs--process-command-delimiters (command command-start submit)
  "Process COMMAND adding delimiters based on COMMAND-START and SUBMIT flags.
Add full delimiters if:
- COMMAND-START, SUBMIT and command contains newlines are all true
Add start delimiter if COMMAND-START is true and SUBMIT is nil
Add end delimiter if COMMAND-START is nil and SUBMIT is true
Return the processed command string."
  (cond
   ;; Full delimiters if all three conditions are true
   ((and command-start 
         submit
         (string-match-p "\n" command))
    (concat "{aidermacs\n" command "\naidermacs}"))
   ;; Just start delimiter - when starting but not submitting
   ((and command-start (not submit))
    (concat "{aidermacs\n" command))
   ;; Just end delimiter - when submitting but not starting
   ((and (not command-start) submit)
    (concat command "\naidermacs}"))
   ;; No delimiters
   (t command)))

(defun aidermacs--send-command-backend (buffer command submit)
  "Send COMMAND to BUFFER using the appropriate backend."
  (with-current-buffer buffer
    (let ((command-start (not aidermacs--command-in-progress)))
      (setq aidermacs--last-command command
            aidermacs--current-output nil)
      (setq-local aidermacs--command-in-progress (not submit))
      (let ((processed-command (aidermacs--process-command-delimiters 
                               command command-start submit)))
        (if (eq aidermacs-backend 'vterm)
            (aidermacs--send-command-vterm buffer processed-command submit)
          (aidermacs--send-command-comint buffer processed-command submit))))))

(defun aidermacs--send-command-redirect-backend (buffer command &optional callback)
  "Send COMMAND to BUFFER using the appropriate backend.
CALLBACK if provided will be called with the command output when available."
  (with-current-buffer buffer
    (setq aidermacs--last-command command
          aidermacs--current-output nil
          aidermacs--current-callback callback)
    (if (eq aidermacs-backend 'vterm)
        (aidermacs--send-command-vterm buffer command)
      (aidermacs--send-command-redirect-comint buffer command))))

(defun aidermacs--send-cancel-backend (buffer)
  "Send cancel signal (Ctrl-C) to BUFFER using the appropriate backend."
  (with-current-buffer buffer
    (if (eq aidermacs-backend 'vterm)
        (aidermacs--send-cancel-vterm buffer)
      (aidermacs--send-cancel-comint buffer))))

(provide 'aidermacs-backends)

;;; aidermacs-backends.el ends here
