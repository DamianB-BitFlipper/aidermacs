;;; aidermacs-doom.el --- Description -*- lexical-binding: t; no-byte-compile: t -*-
;; Author: Mingde (Matthew) Zeng <matthewzmd@posteo.net>
;; Version: 0.5.0
;; Package-Requires: ((emacs "26.1") (transient "0.3.0"))
;; Keywords: ai emacs agents llm aider ai-pair-programming, convenience, tools
;; URL: https://github.com/MatthewZMD/aidermacs.el
;; Originally forked from: Kang Tu <tninja@gmail.com> Aider.el
;;
;; This file is not part of GNU Emacs.
;;
;;; Commentary:
;;
;;  Doom integration for aidermacs
;;
;;; Code:

(defun aidermacs-doom-setup-keys ()
  "Setup aidermacs keybindings if the current buffer is in a git repository."
  (when (and (featurep 'doom-keybinds)
             (vc-backend (or (buffer-file-name) default-directory)))
    (map! :leader
          (:prefix ("A" . "aidermacs")
           ;; Core Actions
           :desc "Start/Open Session" "." #'aidermacs-run-in-current-dir
           :desc "Change Model" "o" #'aidermacs-change-model
           :desc "Reset Session" "s" #'aidermacs-reset
           :desc "Exit Session" "x" #'aidermacs-exit

           ;; Quick Actions
           :desc "Add Current File" "f" #'aidermacs-add-current-file
           :desc "Code Change" "c" #'aidermacs-code-change
           :desc "Refactor" "r" #'aidermacs-function-or-region-refactor
           :desc "Code Go Ahead" "g" #'aidermacs-code-go-ahead
           :desc "Undo Change" "u" #'aidermacs-undo-last-change

           ;; File Commands
           (:prefix ("F" . "File Commands")
            :desc "Add Current File" "f" #'aidermacs-add-current-file
            :desc "Add File Interactively" "i" #'aidermacs-add-files-interactively
            :desc "Add Current Read-Only" "r" #'aidermacs-add-current-file-read-only
            :desc "Add Current Window Files" "w" #'aidermacs-add-files-in-current-window
            :desc "Add Current Directory Files" "d" #'aidermacs-add-same-type-files-under-dir
            :desc "Add Dired Marked Files" "m" #'aidermacs-batch-add-dired-marked-files
            :desc "Drop File Interactively" "j" #'aidermacs-drop-file
            :desc "Drop Current File" "k" #'aidermacs-drop-current-file
            :desc "List Files" "l" #'aidermacs-list-added-files)

           ;; Code Commands
           (:prefix ("C" . "Code Commands")
            :desc "Code Change" "c" #'aidermacs-code-change
            :desc "Refactor Code" "r" #'aidermacs-function-or-region-refactor
            :desc "Implement TODO" "i" #'aidermacs-implement-todo
            :desc "Write Tests" "t" #'aidermacs-write-unit-test
            :desc "Fix Test" "T" #'aidermacs-fix-failing-test-under-cursor
            :desc "Debug Exception" "x" #'aidermacs-debug-exception
            :desc "Undo Change" "u" #'aidermacs-undo-last-change)

           ;; Understanding
           :desc "Show Last Commit" "m" #'aidermacs-magit-show-last-commit
           :desc "Ask General Question" "Q" #'aidermacs-ask-question-general
           :desc "Ask Question" "q" #'aidermacs-ask-question
           :desc "Explain This Code" "e" #'aidermacs-function-or-region-explain
           :desc "Explain This Symbol" "p" #'aidermacs-explain-symbol-under-point

           ;; Others
           :desc "Session History" "H" #'aidermacs-show-output-history
           :desc "Copy Last Aidermacs Output" "L" #'aidermacs-get-last-output
           :desc "Clear Model Selection Cache" "O" #'aidermacs-clear-model-cache
           :desc "Clear Buffer" "l" #'aidermacs-clear
           :desc "Aider Help" "h" #'aidermacs-help
           ))))

;; Add the setup function to appropriate hooks
(add-hook 'find-file-hook #'aidermacs-doom-setup-keys)
(add-hook 'dired-mode-hook #'aidermacs-doom-setup-keys)
(add-hook 'after-change-major-mode-hook #'aidermacs-doom-setup-keys)

(provide 'aidermacs-doom)
;;; aidermacs-doom.el ends here
