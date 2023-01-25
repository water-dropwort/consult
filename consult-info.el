;;; consult-info.el --- Search through the info manuals -*- lexical-binding: t -*-

;; Copyright (C) 2021-2023 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Provides the command `consult-info'.  This is an extra package,
;; to allow lazy loading of info.el.  The `consult-info' command
;; is autoloaded.

;;; Code:

(require 'consult)
(require 'info)

(defvar consult-info--history nil)

(defun consult-info--candidates (manuals input)
  "Dynamically find lines in MANUALS matching INPUT."
  (let (candidates)
    (pcase-dolist (`(,manual . ,buffer) manuals)
      (with-current-buffer buffer
        (widen)
        (goto-char (point-min))
        (pcase-let ((`(,regexps . ,hl)
                     (funcall consult--regexp-compiler input 'emacs t)))
          ;; TODO subfile support?!
          (while (ignore-errors (re-search-forward (car regexps) nil t))
            (let ((bol (pos-bol))
                  (eol (pos-eol))
                  (current-node nil))
              (when
                  (save-excursion
                    (goto-char bol)
                    (and
                     (>= (- (point) 2) (point-min))
                     ;; Information separator character
                     (not (eq (char-after (- (point) 2)) ?\^_))
                     ;; Only printable characters on the line, [:cntrl:] does
                     ;; not work?!
                     (not (re-search-forward "[^[:print:]]" eol t))
                     ;; Matches all regexps
                     (seq-every-p
                      (lambda (r)
                        (goto-char bol)
                        (ignore-errors (re-search-forward r eol t)))
                      (cdr regexps))
                     ;; Find node beginning
                     (progn
                       (goto-char bol)
                       (if (search-backward "\n\^_" nil 'move)
                           (forward-line 2)
                         (when (looking-at "\^_")
                           (forward-line 1))))
                     ;; Node name
                     (re-search-forward "Node:[ \t]*" nil t)
                     (setq current-node
                           (buffer-substring-no-properties
                            (point)
                            (progn
                              (skip-chars-forward "^,\t\n")
                              (point))))))
                (let* ((node (format "(%s)%s" manual current-node))
                       (cand (concat
                              node ":"
                              (funcall hl (buffer-substring-no-properties bol eol)))))
                  (add-text-properties 0 (length node)
                                       (list 'consult--info-position (cons buffer bol)
                                             'face 'consult-file
                                             'consult--prefix-group node)
                                       cand)
                  (push cand candidates))))))))
    (nreverse candidates)))

(defun consult-info--position (cand)
  "Return position information for CAND."
  (when-let ((pos (and cand (get-text-property 0 'consult--info-position cand)))
             (node (get-text-property 0 'consult--prefix-group cand))
             (matches (consult--point-placement cand (1+ (length node))))
             (dest (+ (cdr pos) (car matches))))
    (list node dest (cons
                     (set-marker (make-marker) dest (car pos))
                     (cdr matches)))))

(defun consult-info--action (cand)
  "Jump to info CAND."
  (when-let ((pos (consult-info--position cand)))
    (info (car pos))
    (widen)
    (goto-char (cadr pos))
    (Info-select-node)
    (run-hooks 'consult-after-jump-hook)))

(defun consult-info--state ()
  "Info manual preview state."
  (let ((preview (consult--jump-preview)))
    (lambda (action cand)
      (pcase action
        ('preview
         (setq cand (caddr (consult-info--position cand)))
         (funcall preview 'preview cand)
         (let (Info-history Info-history-list Info-history-forward)
           (when cand (ignore-errors (Info-select-node)))))
        ('return
         (consult-info--action cand))))))

;;;###autoload
(defun consult-info (&rest manuals)
  "Full text search through info MANUALS."
  (interactive
   (progn
     (info-initialize)
     (completing-read-multiple
      "Info Manuals: "
      (info--manual-names current-prefix-arg)
      nil t)))
  (let (buffers)
    (unwind-protect
        (progn
          (dolist (manual manuals)
            (with-current-buffer (generate-new-buffer (format "*info-preview: %s*" manual))
              (let (Info-history Info-history-list Info-history-forward)
                (Info-mode)
                (Info-find-node manual "Top"))
              (push (cons manual (current-buffer)) buffers)))
          (consult--read
           (consult--dynamic-collection
            (apply-partially #'consult-info--candidates (reverse buffers)))
           :state (consult-info--state)
           :prompt (format "Info (%s): " (string-join manuals ", "))
           :require-match t
           :sort nil
           :category 'consult-info
           :history '(:input consult-info--history)
           :group #'consult--prefix-group
           :initial (consult--async-split-initial "")
           :lookup #'consult--lookup-member))
      (dolist (buf buffers)
        (kill-buffer (cdr buf))))))

(provide 'consult-info)
;;; consult-info.el ends here
