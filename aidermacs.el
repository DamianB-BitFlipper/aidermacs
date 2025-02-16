;;; aidermacs.el --- aidermacs package for interactive conversation with aider -*- lexical-binding: t; -*-a
;; Author: Mingde (Matthew) Zeng <matthewzmd@posteo.net>
;; Version: 0.5.0
;; Package-Requires: ((emacs "26.1") (transient "0.3.0"))
;; Keywords: ai emacs agents llm aider ai-pair-programming, convenience, tools
;; URL: https://github.com/MatthewZMD/aidermacs.el
;; Originally forked from: Kang Tu <tninja@gmail.com> Aider.el

;;; Commentary:
;; This package provides an interactive interface to communicate with https://github.com/paul-gauthier/aidermacs.

;;; Code:

(require 'comint)
(require 'dired)
(require 'transient)
(require 'vc-git)
(require 'which-func)
(require 'ansi-color)


(require 'aidermacs-backends)
(require 'aidermacs-models)
(when (featurep 'doom)
  (require 'aidermacs-doom))

(defgroup aidermacs nil
  "Customization group for the aidermacs package."
  :prefix "aidermacs-"
  :group 'convenience)

(defcustom aidermacs-program "aider"
  "The name or path of the aidermacs program."
  :type 'string
  :group 'aidermacs)

(define-obsolete-variable-alias 'aidermacs-args 'aidermacs-extra-args "0.5.0"
  "Old name for `aidermacs-extra-args', please update your config to use the new name.")

(defcustom aidermacs-extra-args nil
  "Additional arguments to pass to the aidermacs command.
The model argument will be added automatically based on `aidermacs-default-model'."
  :type '(repeat string)
  :group 'aidermacs)

(defcustom aidermacs-subtree-only nil
  "When non-nil, run aider with --subtree-only flag to only consider files in current directory.
This is useful for working in monorepos where you want to limit aider's scope."
  :type 'boolean
  :group 'aidermacs)

(defcustom aidermacs-auto-commits nil
  "When non-nil, enable auto-commits of LLM changes.
When nil, disable auto-commits requiring manual git commits."
  :type 'boolean
  :group 'aidermacs)

(defun aidermacs-project-root ()
  "Get the project root using project.el, VC, or fallback to file directory."
  (or (when (fboundp 'project-current)
        (project-root (project-current)))
      (vc-git-root default-directory)
      (when buffer-file-name
        (file-name-directory buffer-file-name))
      default-directory))


(defcustom aidermacs-language-name-map '(("elisp" . "emacs-lisp")
                                         ("bash" . "sh")
                                         ("objective-c" . "objc")
                                         ("objectivec" . "objc")
                                         ("cpp" . "c++"))
  "Map external language names to Emacs names."
  :type '(alist :key-type (string :tag "Language Name/Alias")
          :value-type (string :tag "Mode Name (without -mode)"))
  :group 'aidermacs)

(defcustom aidermacs-prompt-file-name ".aider.prompt.org"
  "File name that will automatically enable aidermacs-minor-mode when opened.
This is the file name without path."
  :type 'string
  :group 'aidermacs)

(defvar aidermacs-read-string-history nil
  "History list for aidermacs read string inputs.")

(if (bound-and-true-p savehist-loaded)
    (add-to-list 'savehist-additional-variables 'aidermacs-read-string-history)
  (add-hook 'savehist-mode-hook
            (lambda ()
              (add-to-list 'savehist-additional-variables 'aidermacs-read-string-history))))


;;;###autoload
(defun aidermacs-plain-read-string (prompt &optional initial-input)
  "Read a string from the user with PROMPT and optional INITIAL-INPUT.
This function can be customized or redefined by the user."
  (read-string prompt initial-input 'aidermacs-read-string-history))

;;;###autoload
(defun aidermacs-plain-read-string-with-ret (prompt &optional initial-input)
  "Read a string from the user with PROMPT and optional INITIAL-INPUT.
Returns a cons cell (string . submit-flag) where submit-flag is:
- t if RET was pressed
- nil if S-RET was pressed."
  (let* ((map (make-sparse-keymap))
         (return-value nil)
         (submit-flag nil))
    ;; Set up keymap for RET and S-RET
    (set-keymap-parent map minibuffer-local-map)
    (define-key map (kbd "RET") (lambda ()
                                 (setq submit-flag t)
                                 (exit-minibuffer)))
    (define-key map (kbd "S-RET") (lambda ()
                                   (setq submit-flag nil)
                                   (exit-minibuffer)))
    ;; Read the string with our custom keymap
    (let ((str (read-from-minibuffer prompt initial-input map nil
                                    'aidermacs-read-string-history)))
      (cons str submit-flag))))

;;;###autoload
(defalias 'aidermacs-read-string 'aidermacs-plain-read-string)

(eval-and-compile
  ;; Ensure the alias is always available in both compiled and interpreted modes.
  (defalias 'aidermacs-read-string 'aidermacs-plain-read-string))

;; Transient menu for aidermacs commands
;; The instruction in the autoload comment is needed, see
;; https://github.com/magit/transient/issues/280.
;;;###autoload (autoload 'aidermacs-transient-menu "aidermacs" "Transient menu for aidermacs commands." t)
;; Define secondary transient menus
(transient-define-prefix aidermacs-transient-file-commands ()
  "File management commands."
  ["File Actions"
   ["Add Actions"
    ("f" "Add Current File" aidermacs-add-current-file)
    ("i" "Add File Interactively" aidermacs-add-files-interactively)
    ("r" "Add Current Read-Only" aidermacs-add-current-file-read-only)
    ("w" "Add Current Window Files" aidermacs-add-files-in-current-window)
    ("d" "Add Current Directory Files" aidermacs-add-same-type-files-under-dir)
    ("m" "Add Dired Marked Files" aidermacs-batch-add-dired-marked-files)]

   ["Drop Actions"
    ("j" "Drop File Interactively" aidermacs-drop-file)
    ("k" "Drop Current File" aidermacs-drop-current-file)
    ("a" "Drop All Files" aidermacs-drop-all-files)]

   ["Other Actions"
    ("l" "List Files" aidermacs-list-added-files)]])

(transient-define-prefix aidermacs-transient-code-commands ()
  "Code modification commands."
  ["Code Actions"
   ("c" "Code Change" aidermacs-code-change)
   ("r" "Refactor Code" aidermacs-function-or-region-refactor)
   ("i" "Implement TODO" aidermacs-implement-todo)
   ("t" "Write Tests" aidermacs-write-unit-test)
   ("T" "Fix Test" aidermacs-fix-failing-test-under-cursor)
   ("x" "Debug Exception" aidermacs-debug-exception)
   ("u" "Undo Auto Git Commit" aidermacs-undo-last-commit)])

(transient-define-prefix aidermacs-transient-mode-commands ()
  "Code modification commands."
  ["Mode Actions"
   ("a" "Set Architect Mode" aidermacs-set-architect-mode)
   ("?" "Set Ask Mode" aidermacs-set-ask-mode)
   ("c" "Set Code Mode" aidermacs-set-code-mode)])

;; Main transient menu
(transient-define-prefix aidermacs-transient-menu ()
  "AI Pair Programming Interface"
  ["Aidermacs: AI Pair Programming"
   ["Core Actions"
    ("a" "Start/Open Session" aidermacs-run)
    ("-" "Start in Current Dir" aidermacs-run-in-current-dir)
    ("o" "Change Solo Model" aidermacs-change-model)
    ("r" "Reset Session" aidermacs-reset)
    ("X" "Exit Session" aidermacs-exit)
    ("<return>" "Submit in Session" aidermacs-submit)
    ("g" "Code Go Ahead" aidermacs-code-go-ahead)
    ("s" "Commit" aidermacs-commit)
    ("." "Send Line or Region" aidermacs-send-line-or-region)
    (">" "Send Block or Region" aidermacs-send-block-or-region)
    ("SPC" "Send Text" aidermacs-send-text)
    ("y" "Yes" aidermacs-yes)
    ("n" "No" aidermacs-no)
    ("q" "Cancel" aidermacs-cancel)]

   ["Tools"
    ("f" "File Commands" aidermacs-transient-file-commands)
    ("c" "Code Commands" aidermacs-transient-code-commands)
    ("m" "Mode Commands" aidermacs-transient-mode-commands)]

   ["Understanding"
    ("d" "Show Diff" aidermacs-diff-maybe-magit)
    ("Q" "Ask General Question" aidermacs-ask-question-general)
    ("?" "Ask Question with Context" aidermacs-ask-question)
    ("e" "Explain This Code" aidermacs-function-or-region-explain)
    ("p" "Explain This Symbol" aidermacs-explain-symbol-under-point)]

   ["Others"
    ("H" "Session History" aidermacs-show-output-history)
    ("L" "Copy Last Aidermacs Output" aidermacs-get-last-output)
    ("O" "Clear Supported Models List" aidermacs-clear-supported-models)
    ("l" "Clear Buffer" aidermacs-clear)
    ("h" "Aider Help" aidermacs-help)]])

(defun aidermacs-buffer-name ()
  "Generate the aidermacs buffer name based on project root or current directory.
Prefers existing sessions closer to current directory."
  (let* ((root (aidermacs-project-root))
         (current-dir (file-truename default-directory))
         ;; Get all existing aidermacs buffers
         (aidermacs-buffers
          (cl-remove-if-not
           (lambda (buf)
             (string-match-p "^\\*aidermacs:" (buffer-name buf)))
           (buffer-list)))
         ;; Extract directory paths and subtree status from buffer names
         (buffer-dirs
          (mapcar
           (lambda (buf)
             (when (string-match "^\\*aidermacs:\\(.*?\\)\\*$"
                                 (buffer-name buf))
               (cons (match-string 1 (buffer-name buf))
                     (match-string 2 (buffer-name buf)))))
           aidermacs-buffers))
         ;; Find closest parent directory that has an aidermacs session
         (closest-parent
          (car
           (car
            (sort
             (cl-remove-if-not
              (lambda (dir-info)
                (and (car dir-info)
                     (string-prefix-p (car dir-info) current-dir)
                     (file-exists-p (car dir-info))))
              buffer-dirs)
             (lambda (a b)
               ;; Sort by path length (deeper paths first)
               (> (length (car a)) (length (car b))))))))
         (display-root (cond
                        ;; Use current directory for new subtree session
                        (aidermacs-subtree-only current-dir)
                        ;; Use closest parent if it exists
                        (closest-parent closest-parent)
                        ;; Fall back to project root for new non-subtree session
                        (t root))))
    (format "*aidermacs:%s*"
            (file-truename display-root))))

;;;###autoload
(defun aidermacs-run ()
  "Run aidermacs process using the selected backend."
  (interactive)
  (let* ((buffer-name (aidermacs-buffer-name))
         (has-model-arg (seq-position aidermacs-extra-args "--model"))
         (final-args (append
                      (when aidermacs-use-architect-mode
                        (list "--architect"
                              "--model" aidermacs-architect-model
                              "--editor-model" aidermacs-editor-model))
                      (unless aidermacs-use-architect-mode
                        (unless has-model-arg
                          (list "--model" aidermacs-default-model)))
                      (unless aidermacs-auto-commits
                        '("--no-auto-commits"))
                      (when aidermacs-subtree-only
                        '("--subtree-only"))
                      aidermacs-extra-args)))
    ;; Check if a matching buffer exists (handled by aidermacs-buffer-name)
    (if (get-buffer buffer-name)
        (aidermacs-switch-to-buffer)
      ;; Start new session with proper directory and args
      (aidermacs-run-backend aidermacs-program final-args buffer-name)
      (aidermacs-switch-to-buffer))))

;;;###autoload
(defun aidermacs-run-in-current-dir ()
  "Run aidermacs in the current directory with --subtree-only flag.
This is useful for working in monorepos where you want to limit aider's scope."
  (interactive)
  (let ((aidermacs-subtree-only t)
        (default-directory (file-truename default-directory)))
    (aidermacs-run)))

(defun aidermacs--send-command (command submit &optional switch-to-buffer)
  "Send COMMAND to the corresponding aidermacs process.
If SUBMIT is non-nil, submit the command to the backend. Otherwise,
just add it to the context. If SWITCH-TO-BUFFER is non-nil, switch
to the aidermacs buffer."
  (let* ((buffer-name (aidermacs-buffer-name))
         (buffer (or (get-buffer buffer-name)
                     (progn (aidermacs-run)
                            (get-buffer buffer-name))))
         (processed-command command))
    (aidermacs--send-command-backend buffer processed-command submit)
    (when (and switch-to-buffer (not (string= (buffer-name) buffer-name)))
      (aidermacs-switch-to-buffer))))

(defun aidermacs--send-command-redirect (command callback)
  "Send COMMAND to the corresponding aidermacs process in the background.
CALLBACK will be called with the command output when available."
  (let* ((buffer-name (aidermacs-buffer-name))
         (buffer (or (get-buffer buffer-name)
                     (progn (aidermacs-run)
                            (get-buffer buffer-name))))
         (processed-command command))
    (aidermacs--send-command-redirect-backend buffer processed-command callback)))


;; Function to switch to the aidermacs buffer
;;;###autoload
(defun aidermacs-switch-to-buffer ()
  "Switch to the aidermacs buffer.
If the buffer is already visible in a window, switch to that window.
If the current buffer is already the aidermacs buffer, do nothing."
  (interactive)
  (let ((buffer (get-buffer (aidermacs-buffer-name))))
    (cond
     ((string= (buffer-name) (aidermacs-buffer-name)) t)
     ((and buffer (get-buffer-window buffer))
      (select-window (get-buffer-window buffer)))  ;; Switch to existing window
     (buffer
      (pop-to-buffer buffer))
     (t
      (message "Buffer '%s' does not exist." (aidermacs-buffer-name))))))

;; Functions to set the various modes
;;;###autoload
(defun aidermacs-set-architect-mode ()
  "Send the command \"/architect\" to the aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/architect" t))

;;;###autoload
(defun aidermacs-set-ask-mode ()
  "Send the command \"/ask\" to the aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/ask" t))

;;;###autoload
(defun aidermacs-set-code-mode ()
  "Send the command \"/code\" to the aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/code" t))

;;;###autoload
(defun aidermacs-commit ()
  "Send the command \"/commit\" to the aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/commit" t))

;; Function to reset the aidermacs buffer
;;;###autoload
(defun aidermacs-clear ()
  "Send the command \"/clear\" to the aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/clear" t))

;;;###autoload
(defun aidermacs-reset ()
  "Send the command \"/reset\" to the aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/reset" t))

;;;###autoload
(defun aidermacs-exit ()
  "Send the command \"/exit\" to the aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/exit" t))

;;;###autoload
(defun aidermacs-submit ()
  "Trigger execution in the aidermacs buffer."
  (interactive)
  ;; The command is an empty string, but set submit to true to trigger aider execution
  (aidermacs--send-command "" t)
  (message "Submitted"))

;;;###autoload
(defun aidermacs-cancel ()
  "Send Ctrl-C to cancel the current operation in the aidermacs buffer."
  (interactive)
  (let ((buffer (get-buffer (aidermacs-buffer-name))))
    (if buffer
        (aidermacs--send-cancel-backend buffer)
      (message "No active aidermacs buffer found."))))

;;;###autoload
(defun aidermacs-yes ()
  "Send \"Yes\" to the aidermacs buffer and submit."
  (interactive)
  (aidermacs--send-command "Yes" t))

;;;###autoload
(defun aidermacs-no ()
  "Send \"No\" to the aidermacs buffer and submit."
  (interactive)
  (aidermacs--send-command "No" t))

;;;###autoload
(defun aidermacs-act-on-current-file (command-prefix)
  "Send the command \"COMMAND-PREFIX <current buffer file full path>\" to the corresponding aidermacs buffer."
  ;; Ensure the current buffer is associated with a file
  (if (not buffer-file-name)
      (message "Current buffer is not associated with a file.")
    (let* ((file-path (buffer-file-name))
           ;; Use buffer-file-name directly
           (formatted-path (if (string-match-p " " file-path)
                               (format "\"%s\"" file-path)
                             file-path))
           (command (format "%s %s" command-prefix formatted-path)))
      ;; Use the shared helper function to send the command
      (aidermacs--send-command command t))))

;;;###autoload
(defun aidermacs-add-current-file ()
  "Send the command \"/add <current buffer file full path>\" to the corresponding aidermacs buffer."
  (interactive)
  (aidermacs-act-on-current-file "/add"))

;;;###autoload
(defun aidermacs-add-current-file-read-only ()
  "Send the command \"/read-only <current buffer file full path>\" to the corresponding aidermacs buffer."
  (interactive)
  (aidermacs-act-on-current-file "/read-only"))


;;;###autoload
(defun aidermacs-drop-current-file ()
  "Send the command \"/drop <current buffer file full path>\" to the corresponding aider buffer."
  (interactive)
  (aidermacs-act-on-current-file "/drop"))

;;;###autoload
(defun aidermacs-add-files-in-current-window ()
  "Add files in all buffers in the current Emacs window to the aidermacs buffer."
  (interactive)
  (let ((files (mapcar (lambda (buffer)
                         (with-current-buffer buffer
                           (when buffer-file-name
                             (expand-file-name buffer-file-name))))
                       (mapcar 'window-buffer (window-list)))))
    (setq files (delq nil files))
    (if files
        (let ((command (concat "/add " (mapconcat 'identity files " "))))
          (aidermacs--send-command command t))
      (message "No files found in the current window."))))

;; Function to send a custom command to corresponding aidermacs buffer
;;;###autoload
(defun aidermacs-send-text ()
  "Send arbitrary text to the aidermacs buffer.
Prompts for user input and sends the entered text directly to aider.
It can be a /command or any text. The text is added to the input buffer
without being submitted."
  (interactive)
  (let ((text (aidermacs-read-string "Enter text to send: ")))
    (aidermacs--send-command text nil)))

;; New function to get command from user and send it prefixed with "/code "
;;;###autoload
(defun aidermacs-code-change ()
  "Prompt the user for a command and send it to the corresponding aidermacs buffer prefixed with \"/code \"."
  (interactive)
  (when-let ((command (aidermacs--form-prompt "/code" "Code change" t)))
    (aidermacs--send-command command t)))

(defun aidermacs--parse-ls-output (output)
  "Parse the /ls command OUTPUT to extract files in chat.
After the \"Files in chat:\" header, each subsequent line that begins with
whitespace is processed. The first non-whitespace token is taken as the file name.
Relative paths are resolved using the repository root (if available) or
`default-directory`. Only files that exist on disk are included in the result.
Returns a deduplicated list of such file names."
  (when output
    (with-temp-buffer
      (insert output)
      (goto-char (point-min))
      (let ((files '())
            (base (or (vc-git-root default-directory)
                      default-directory)))
        ;; Parse read-only files section
        (when (search-forward "Read-only files:" nil t)
          (forward-line 1)
          (while (and (not (eobp))
                      (string-match-p "^[[:space:]]" (thing-at-point 'line t)))
            (let* ((line (string-trim (thing-at-point 'line t)))
                   (file (car (split-string line))))
              (when (and file (file-exists-p (expand-file-name file base)))
                (push (concat file " (read-only)") files)))
            (forward-line 1)))

        ;; Parse files in chat section
        (when (search-forward "Files in chat:" nil t)
          (forward-line 1)
          (while (and (not (eobp))
                      (string-match-p "^[[:space:]]" (thing-at-point 'line t)))
            (let* ((line (string-trim (thing-at-point 'line t)))
                   (file (car (split-string line))))
              (when (and file (file-exists-p (expand-file-name file base)))
                (push file files)))
            (forward-line 1)))

        ;; Remove duplicates and return
        (delete-dups (nreverse files))))))

;;;###autoload
(defun aidermacs-list-added-files ()
  "List all files currently added to the chat session.
Sends the \"/ls\" command and returns the list of files via callback."
  (interactive)
  (aidermacs--send-command-redirect
   "/ls"
   (lambda (output)
     (let ((files (aidermacs--parse-ls-output output)))
       (message "%s" (prin1-to-string files))
       files))))

;;;###autoload
(defun aidermacs-drop-file ()
  "Drop a file from the chat session by selecting from currently added files."
  (interactive)
  (aidermacs--send-command-redirect
   "/ls"
   (lambda (output)
     (if-let* ((files (aidermacs--parse-ls-output output))
               (file (completing-read "Select file to drop: " files nil t))
               (clean-file (replace-regexp-in-string " (read-only)$" "" file)))
         (aidermacs--send-command (format "/drop ./%s" clean-file) t))
     (message "No files available to drop"))))


;;;###autoload
(defun aidermacs-drop-all-files ()
  "Drop all files from the current chat session."
  (interactive)
  (aidermacs--send-command "/drop" t))


;;;###autoload
(defun aidermacs-show-output-history ()
  "Display the AI output history in a new buffer."
  (interactive)
  (let ((buf (get-buffer-create "*aidermacs-history*"))
        (history aidermacs--output-history))
    (with-current-buffer buf
      (org-mode)
      (setq buffer-read-only nil)
      (erase-buffer)
      (display-line-numbers-mode 1)
      (dolist (entry history)
        (let ((timestamp (format-time-string "%Y-%m-%d %H:%M:%S" (car entry)))
              (output (cdr entry)))
          (insert (format "* %s\n#+BEGIN_SRC\n%s\n#+END_SRC\n" timestamp output))))
      (goto-char (point-min))
      (setq buffer-read-only t)
      (local-set-key (kbd "q") 'kill-this-buffer)
      (switch-to-buffer-other-window buf))))

;;;###autoload
(defun aidermacs-get-last-output ()
  "Get the most recent output from aidermacs."
  (interactive)
  (message aidermacs--current-output)
  (kill-new aidermacs--current-output)
  aidermacs--current-output)


;;;###autoload
(defun aidermacs-ask-question ()
  "Let the user ask a question to aider.
Sends the input to the corresponding aidermacs buffer prefixed with \"/ask \".
If a region is active, append the region text to the question. If cursor is inside
a function, include the function name as context."
  (interactive)
  ;; Dispatch to general question if in aidermacs buffer
  (when (string= (buffer-name) (aidermacs-buffer-name))
    (call-interactively 'aidermacs-ask-question-general)
    (cl-return-from aidermacs-ask-question))
  (aidermacs-add-current-file)
  (when-let ((command (aidermacs--form-prompt "/ask" "Ask")))
    (aidermacs--send-command command t)))

;;;###autoload
(defun aidermacs-ask-question-general ()
  "Prompt the user for a general question and send it to the corresponding aidermacs buffer prefixed with \"/ask \"."
  (interactive)
  (when-let ((command (aidermacs--form-prompt "/ask" "Ask general question" t)))
    (aidermacs--send-command command t)))

;;;###autoload
(defun aidermacs-help ()
  "Prompt the user for a command and send it to the corresponding aidermacs buffer prefixed with \"/help \"."
  (interactive)
  (when-let ((command (aidermacs--form-prompt "/help" nil t)))
    (aidermacs--send-command command t)))

;;;###autoload
(defun aidermacs-architect-code ()
  "Prompt the user for a command and send it to the corresponding aidermacs buffer prefixed with \"/architect\"."
  (interactive)
  (when-let ((command (aidermacs--form-prompt "/architect" "Architect Code")))
    (aidermacs--send-command command t)))

;;;###autoload
(defun aidermacs-debug-exception ()
  "Prompt the user for a command and send it to the corresponding aidermacs buffer prefixed with \"/debug\",
replacing all newline characters except for the one at the end."
  (interactive)
  (when-let ((user-command (aidermacs--form-prompt "/ask" "Enter exception, can be multiple lines")))
    (let ((command (concat "/ask Investigate the following exception, with current added files as context: " user-command)))
      (aidermacs--send-command command t))))

;;;###autoload
(defun aidermacs-code-go-ahead ()
  "Send the command \"go ahead\" to the corresponding aidermacs buffer."
  (interactive)
  (aidermacs--send-command "/code go ahead" t))

;;;###autoload
(defun aidermacs-diff-maybe-magit ()
  "Show the last commit's diff using Magit.
If Magit is not installed, use aiders \"/diff\" command."
  (interactive)
  (if (require 'magit nil 'noerror)
      (magit-show-commit "HEAD")
    (aidermacs--send-command "/diff" t)))

;;;###autoload
(defun aidermacs-undo-last-commit ()
  "Undo the last change made by aidermacs."
  (interactive)
  (aidermacs--send-command "/undo" t))


;;;###autoload
(defun aidermacs--form-prompt (command prompt-prefix &optional ignore-context)
  "Form a prompt based on COMMAND, PROMPT-PREFIX and optional context.
If COMMAND is nil, do not include it in the prompt.
If IGNORE-CONTEXT is non-nil, skip function and region context.
If region is active, use that region's text.
If point is in a function, use function name."
  (let* ((on-function (unless ignore-context (which-function)))
         (region-text (when (and (use-region-p) (not ignore-context))
                        (buffer-substring-no-properties (region-beginning) (region-end))))
         (context (concat (when on-function
                            (format " function `%s`" on-function))
                          (when region-text
                            (format " on the following code block:\n```\n%s\n```\n" region-text))))
         (prompt (concat (when command
                           (concat command " "))
                         prompt-prefix
                         context
                         ": "))
         (user-command (aidermacs-read-string prompt)))
    (concat prompt user-command)))

(defun aidermacs-function-or-region-refactor ()
  "Refactor code at point or region.
If region is active, refactor that region.
If point is in a function, refactor that function."
  (interactive)
  (aidermacs-add-current-file)
  (when-let ((command (aidermacs--form-prompt "/architect" "Refactor")))
    (aidermacs--send-command command t)))

;;;###autoload
(defun aidermacs-function-or-region-explain ()
  "Explain code at point or region.
If region is active, explain that region.
If point is in a function, explain that function."
  (interactive)
  (aidermacs-add-current-file)
  (when-let ((command (aidermacs--form-prompt "/ask" "Explain")))
    (aidermacs--send-command command t)))

;;;###autoload
(defun aidermacs-explain-symbol-under-point ()
  "Ask aidermacs to explain symbol under point, given the code line as background info."
  (interactive)
  (aidermacs-add-current-file)
  (let* ((symbol (thing-at-point 'symbol))
         (line (buffer-substring-no-properties
                (line-beginning-position)
                (line-end-position)))
         (prompt (format "/ask Please explain what '%s' means in the context of this code line: %s"
                         symbol line)))
    (aidermacs--send-command prompt t)))

;;;###autoload
(defun aidermacs-batch-add-dired-marked-files ()
  "Add multiple Dired marked files to the aidermacs buffer with the \"/add\" command."
  (interactive)
  (let ((files (dired-get-marked-files)))
    (if files
        (let ((command (concat "/add " (mapconcat 'expand-file-name files " "))))
          (aidermacs--send-command command t))
      (message "No files marked in Dired."))))

;;;###autoload
(defun aidermacs-add-files-interactively ()
  "Add files to aidermacs by interactively selecting them using `find-file`.
Keep selecting files until C-g is pressed."
  (interactive)
  (while t
    (condition-case nil
        (when-let ((file (expand-file-name (read-file-name "Select file to add (C-g to finish): "))))
          (if (file-exists-p file)
              (aidermacs--send-command (concat "/add " file) t)
            (message "File does not exist: %s" file)))
      (quit (keyboard-quit)))))

;;;###autoload
(defun aidermacs-add-same-type-files-under-dir ()
  "Add all files with same suffix as current file under current directory to aidermacs.
If there are more than 40 files, refuse to add and show warning message."
  (interactive)
  (if (not buffer-file-name)
      (message "Current buffer is not visiting a file")
    (let* ((current-suffix (file-name-extension buffer-file-name))
           (dir (file-name-directory buffer-file-name))
           (max-files 40)
           (files (directory-files dir t
                                   (concat "\\." current-suffix "$")
                                   t))) ; t means don't include . and ..
      (if (> (length files) max-files)
          (message "Too many files (%d, > %d) found with suffix .%s. Aborting."
                   (length files) max-files current-suffix)
        (let ((command (concat "/add " (mapconcat 'identity files " "))))
          (aidermacs--send-command command t))
        (message "Added %d files with suffix .%s"
                 (length files) current-suffix)))))

;;;###autoload
(defun aidermacs-write-unit-test ()
  "Generate unit test code for current buffer.
Do nothing if current buffer is not visiting a file.
If current buffer filename contains 'test':
  - If cursor is inside a test function, implement that test
  - Otherwise show message asking to place cursor inside a test function
Otherwise:
  - If cursor is on a function, generate unit test for that function
  - Otherwise generate unit tests for the entire file"
  (interactive)
  (aidermacs-add-current-file)
  (if (not buffer-file-name)
      (message "Current buffer is not visiting a file.")
    (let ((is-test-file (string-match-p "test" (file-name-nondirectory buffer-file-name)))
          (function-name (which-function)))
      (cond
       ;; Test file case
       (is-test-file
        (if function-name
            (if (string-match-p "test" function-name)
                (let* ((initial-input
                        (format "Please implement test function '%s'. Follow standard unit testing practices and make it a meaningful test. Do not use Mock if possible."
                                function-name))
                       (command (aidermacs--form-prompt "/architect" initial-input)))
                  (aidermacs--send-command command t t))
              (message "Current function '%s' does not appear to be a test function." function-name))
          (message "Please place cursor inside a test function to implement.")))
       ;; Non-test file case
       (t
        (let* ((common-instructions "Keep existing tests if there are. Follow standard unit testing practices. Do not use Mock if possible.")
               (initial-input
                (if function-name
                    (format "Please write unit test code for function '%s'. %s"
                            function-name common-instructions)
                  (format "Please write unit test code for file '%s'. For each function %s"
                          (file-name-nondirectory buffer-file-name) common-instructions))))
          (command (aidermacs--form-prompt "/architect" initial-input)))
        (aidermacs--send-command command t t))))))

;;;###autoload
(defun aidermacs-fix-failing-test-under-cursor ()
  "Report the current test failure to aidermacs and ask it to fix the code.
This function assumes the cursor is on or inside a test function."
  (interactive)
  (aidermacs-add-current-file)
  (if-let ((test-function-name (which-function)))
      (let* ((initial-input (format "The test '%s' is failing. Please analyze and fix the code to make the test pass. Don't break any other test"
                                    test-function-name))
             (command (aidermacs--form-prompt "/architect" initial-input)))
        (aidermacs--send-command command t t))
    (message "No test function found at cursor position.")))

(defun aidermacs--is-comment-line (line)
  "Check if LINE is a comment line based on current buffer's comment syntax.
Returns non-nil if LINE starts with one or more comment characters,
ignoring leading whitespace."
  (when comment-start
    (let ((comment-str (string-trim-right comment-start)))
      (string-match-p (concat "^[ \t]*"
                              (regexp-quote comment-str)
                              "+")
                      (string-trim-left line)))))

;;;###autoload
(defun aidermacs-implement-todo ()
  "Implement TODO comments in current context.
If region is active, implement that specific region.
If cursor is on a comment line, implement that specific comment.
If point is in a function, implement TODOs for that function.
Otherwise implement TODOs for the entire current file."
  (interactive)
  (if (not buffer-file-name)
      (message "Current buffer is not visiting a file.")
    (let* ((current-line (string-trim (thing-at-point 'line t)))
           (is-comment (aidermacs--is-comment-line current-line)))
      (aidermacs-add-current-file)
      (when-let ((command (aidermacs--form-prompt
                           "/architect"
                           (concat "Please implement the TODO items."
                                   (when is-comment
                                     (format " on this comment: `%s`." current-line))
                                   " Keep existing code structure"))))
        (aidermacs--send-command command t t)))))

;;;###autoload
(defun aidermacs-send-line-or-region ()
  "Send text to the aidermacs buffer.
If region is active, send the selected region.
Otherwise, send the line under cursor."
  (interactive)
  (let ((text (if (use-region-p)
                  (prog1
                      (buffer-substring-no-properties (region-beginning) (region-end))
                    (deactivate-mark))
                (string-trim (thing-at-point 'line t)))))
    (when text
      (aidermacs--send-command (concat text "\n") nil))))

;;;###autoload
(defun aidermacs-send-block-or-region ()
  "Send the current active region text or current paragraph content.
When sending paragraph content, preserve cursor position."
  (interactive)
  (let ((text (if (use-region-p)
                  (prog1
                      (buffer-substring-no-properties (region-beginning) (region-end))
                    (deactivate-mark))
                (save-excursion
                  (mark-paragraph)
                  (prog1
                      (buffer-substring-no-properties (region-beginning) (region-end))
                    (deactivate-mark))))))
    (when text
      (aidermacs--send-command (concat text "\n") nil))))

;;;###autoload
(defun aidermacs-send-region-line-by-line ()
  "Get the text of the current selected region, split into lines,
and send each non-empty line to aidermacs session."
  (interactive)
  (if (use-region-p)
      (let* ((text (buffer-substring-no-properties (region-beginning) (region-end)))
             (lines (split-string text "\n" t)))
        (mapc (lambda (line)
                (let ((trimmed (string-trim line)))
                  (when (not (string-empty-p trimmed))
                    (aidermacs--send-command trimmed t))))
              lines))
    (message "No region selected.")))

;;;###autoload
(defun aidermacs-open-prompt-file ()
  "Open aidermacs prompt file under git repo root.
If file doesn't exist, create it with command binding help and sample prompt."
  (interactive)
  (let* ((git-root (vc-git-root default-directory))
         (prompt-file (when git-root
                        (expand-file-name aidermacs-prompt-file-name git-root))))
    (if prompt-file
        (progn
          (find-file-other-window prompt-file)
          (unless (file-exists-p prompt-file)
            ;; Insert initial content for new file
            (insert "# aidermacs Prompt File - Command Reference:\n")
            (insert "# C-c C-n or C-<return>: Send current line or selected region line by line\n")
            (insert "# C-c C-c: Send current block or selected region as a whole\n")
            (insert "# C-c C-z: Switch to aidermacs buffer\n\n")
            (insert "* Sample task:\n\n")
            (insert "/ask what this repo is about?\n")
            (save-buffer)))
      (message "Not in a git repository"))))

;;;###autoload
(defvar aidermacs-minor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-n") 'aidermacs-send-line-or-region)
    (define-key map (kbd "C-<return>") 'aidermacs-send-line-or-region)
    (define-key map (kbd "C-c C-c") 'aidermacs-send-block-or-region)
    (define-key map (kbd "C-c C-z") 'aidermacs-switch-to-buffer)
    map)
  "Keymap for `aidermacs-minor-mode'.")

;;;###autoload
(define-minor-mode aidermacs-minor-mode
  "Minor mode for interacting with aidermacs AI pair programming tool.

Provides these keybindings:
\\{aidermacs-minor-mode-map}"
  :lighter " aidermacs"
  :keymap aidermacs-minor-mode-map
  :override t
  :group 'aidermacs)

;; Auto-enable aidermacs-minor-mode for specific files
(defcustom aidermacs-auto-mode-files
  (list
   aidermacs-prompt-file-name    ; Default prompt file
   ".aider.chat.md"
   ".aider.chat.history.md"
   ".aider.input.history")
  "List of filenames that should automatically enable `aidermacs-minor-mode'.
These are exact filename matches (including the dot prefix)."
  :type '(repeat string)
  :group 'aidermacs)

(defun aidermacs--should-enable-minor-mode-p (filename)
  "Determine if aidermacs-minor-mode should be enabled for FILENAME.
Returns t if the file matches any of the patterns in `aidermacs-auto-mode-files'."
  (when filename
    (let ((base-name (file-name-nondirectory filename)))
      (member base-name aidermacs-auto-mode-files))))

(add-hook 'find-file-hook
          (lambda ()
            (when (and buffer-file-name
                       (aidermacs--should-enable-minor-mode-p buffer-file-name))
              (aidermacs-minor-mode 1))))

(provide 'aidermacs)
;;; aidermacs.el ends here
