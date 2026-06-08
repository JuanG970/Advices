;;; scripts/emacs-tangle.el --- Hermetic org-babel-tangle runner
;;
;; Loaded by the Makefile via `emacs --batch --load`. Does NOT load
;; the user's init file (--no-init) so it's reproducible across
;; machines and isn't affected by personal config.
;;
;; Usage:
;;   emacs --batch --load scripts/emacs-tangle.el \
;;         --eval "(org-babel-tangle-file \"Implementation.org\")"

;; Suppress the usual interactive noise.
(setq inhibit-startup-screen t)
(setq message-log-max 16384)

;; Org-mode ships with a recent enough org-babel in any modern emacs;
;; `org` is in the load-path by default on emacs >= 27.
(require 'org)
(require 'ob-tangle)

;; Print which file we're tangling and to what. The default
;; org-babel-tangle-file prints nothing on success, which is hostile
;; to CI logs — wrap it.
(defun cass/tangle-with-logging (file)
  (message "[tangle] %s -> %s" file
           (or (org-entry-get (org-find-exact-headline-in-buffer
                               (file-name-nondirectory file)
                               (find-file-noselect file))
                              "tangle" t)
               "<file-level PROPERTY>"))
  (let ((result (org-babel-tangle-file file)))
    (if (or (null result) (string= result ""))
        (message "[tangle] %s: done" file)
      (message "[tangle] %s: %s" file result))))

(provide 'cass-tangle)
;;; emacs-tangle.el ends here
