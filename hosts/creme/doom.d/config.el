;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets. It is optional.
;; (setq user-full-name "John Doe"
;;       user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;;(setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light)
;;      doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/org/")


;; Whenever you reconfigure a package, make sure to wrap your config in an
;; `after!' block, otherwise Doom's defaults may override your settings. E.g.
;;
;;   (after! PACKAGE
;;     (setq x y))
;;
;; The exceptions to this rule:
;;
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Here are some additional functions/macros that will help you configure Doom.
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up a symbol (functions, variables, faces,
;; etc).
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

;; Identity
(setq user-full-name "Kimberly McCarty"
      user-mail-address "kimb@kimb.dev")

;; Use a POSIX shell internally. creme's login shell is fish, which
;; doom doctor flags as non-POSIX — it can break Emacs utilities that
;; spawn child processes (diff-hl TRAMP, term shells, etc.). Keep fish
;; as the interactive shell inside terminal emulators via
;; vterm-shell/explicit-shell-file-name, but use bash for
;; shell-command/compile/call-process.
(setq shell-file-name (executable-find "bash")
      vterm-shell "/run/current-system/sw/bin/fish"
      explicit-shell-file-name "/run/current-system/sw/bin/fish")

;; GPG/pinentry - use Qt dialog, passphrase cached by gpg-agent
(setq epa-file-select-keys nil)     ; Don't prompt for key selection
(setq epa-pinentry-mode 'ask)       ; Use system pinentry (Qt dialog)

;; Ensure spawned processes (mu4e/mbsync) can reach gpg-agent
(setenv "GNUPGHOME" (expand-file-name "~/.gnupg"))
(when (display-graphic-p)
  (setenv "DISPLAY" (or (getenv "DISPLAY") ":0")))

;; Ement (Matrix client)
(after! ement
  ;; Cache session tokens so we don't re-auth every restart
  (setq ement-sessions-file "~/.cache/ement-sessions.el"
        ;; Suppress non-fatal errors (Tuwunel is stricter than Synapse)
        ement-notify-on-error nil
        ;; Disable desktop notifications (using browser notifications instead)
        ement-notify-notification-predicates nil
        ement-notify-sound nil)

  ;; Leader keybinds under SPC e
  (map! :leader
        (:prefix ("e" . "ement")
         :desc "Connect"      "c" #'ement-connect
         :desc "Room list"    "l" #'ement-room-list
         :desc "View room"    "r" #'ement-view-room
         :desc "Disconnect"   "q" #'ement-disconnect))

  ;; Fix: handle nil unread counts from bridged rooms (mautrix-discord)
  (defadvice! +ement-room-list-column-format-unread-safe (fn item depth)
    :around #'ement-room-list-column-format-unread
    (condition-case nil
        (funcall fn item depth)
      (wrong-type-argument ""))))

;; agent-shell: LLM agents in Emacs via ACP
(after! agent-shell
  (require 'acp)
  (require 'agent-shell)
  ;; Use nix to run claude-code-acp (no global install needed)
  (setq agent-shell-anthropic-claude-command
        '("nix" "run" "nixpkgs#nodejs_latest" "--" "npx" "@zed-industries/claude-code-acp"))
  ;; Use login auth (reuses existing claude login)
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t))
  ;; Keybinds under SPC a
  (map! :leader
        (:prefix ("a" . "agent")
         :desc "Claude Code"  "c" #'agent-shell-anthropic-start-claude-code
         :desc "Gemini"       "g" #'agent-shell-google-start-gemini)))

;; mu4e
(after! mu4e
  (setq mu4e-get-mail-command "mbsync -a"
        mu4e-update-interval 300
        mu4e-maildir "~/Mail"
        mu4e-context-policy 'pick-first
        mu4e-compose-context-policy 'ask-if-none
        send-mail-function 'smtpmail-send-it
        mu4e-contexts
        (list
         (make-mu4e-context
          :name "Gmail"
          :match-func (lambda (msg)
                        (when msg
                          (or (mu4e-message-contact-field-matches msg :to "mccarty.tim@gmail.com")
                              (string-prefix-p "/gmail" (mu4e-message-field msg :maildir)))))
          :vars '((user-mail-address     . "mccarty.tim@gmail.com")
                  (user-full-name        . "Kimberly McCarty")
                  (mu4e-sent-folder      . "/gmail/[Gmail]/Sent Mail")
                  (mu4e-drafts-folder    . "/gmail/[Gmail]/Drafts")
                  (mu4e-trash-folder     . "/gmail/[Gmail]/Trash")
                  (mu4e-refile-folder    . "/gmail/[Gmail]/Trash")
                  (smtpmail-smtp-server  . "smtp.gmail.com")
                  (smtpmail-smtp-service . 587)
                  (smtpmail-stream-type  . starttls)))
         (make-mu4e-context
          :name "Zoho"
          :match-func (lambda (msg)
                        (when msg
                          (or (mu4e-message-contact-field-matches msg :to "mccartykim@zoho.com")
                              (string-prefix-p "/zoho" (mu4e-message-field msg :maildir)))))
          :vars '((user-mail-address     . "mccartykim@zoho.com")
                  (user-full-name        . "Kimberly McCarty")
                  (mu4e-sent-folder      . "/zoho/Sent")
                  (mu4e-drafts-folder    . "/zoho/Drafts")
                  (mu4e-trash-folder     . "/zoho/Trash")
                  (mu4e-refile-folder    . "/zoho/Trash")
                  (smtpmail-smtp-server  . "smtp.zoho.com")
                  (smtpmail-smtp-service . 465)
                  (smtpmail-stream-type  . ssl)))
         (make-mu4e-context
          :name "Fastmail"
          :match-func (lambda (msg)
                        (when msg
                          (or (mu4e-message-contact-field-matches msg :to "kimb@kimb.dev")
                              (string-prefix-p "/fastmail" (mu4e-message-field msg :maildir)))))
          :vars '((user-mail-address     . "kimb@kimb.dev")
                  (user-full-name        . "Kimberly McCarty")
                  (mu4e-sent-folder      . "/fastmail/Sent")
                  (mu4e-drafts-folder    . "/fastmail/Drafts")
                  (mu4e-trash-folder     . "/fastmail/Trash")
                  (mu4e-refile-folder    . "/fastmail/Trash")
                  (smtpmail-smtp-server  . "smtp.fastmail.com")
                  (smtpmail-smtp-service . 587)
                  (smtpmail-stream-type  . starttls)))))

  ;; Open links in eww by default within mu4e
  (setq browse-url-handlers
        '(("." . eww-browse-url)))

  ;; Extract actual link URL at point (shr stores it as a text property)
  (defun +mu4e/browse-url-at-point-external ()
    "Open the URL at point in an external browser."
    (interactive)
    (if-let ((url (or (get-text-property (point) 'shr-url)
                      (thing-at-point 'url))))
        (browse-url-xdg-open url)
      (message "No URL at point")))

  ;; gx → open link in external browser
  (map! :map mu4e-view-mode-map
        :n "gx" #'+mu4e/browse-url-at-point-external
        :map eww-mode-map
        :n "gx" #'eww-browse-with-external-browser))
