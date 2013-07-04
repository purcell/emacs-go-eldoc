;;; go-eldoc.el --- eldoc for go-mode

;; Copyright (C) 2013 by Syohei YOSHIDA

;; Author: Syohei YOSHIDA <syohex@gmail.com>
;; URL: https://github.com/syohex/emacs-go-eldoc
;; Version: 0.01
;; Package-Requires: ((go-mode) (go-autocomplete))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; To use this package, add these lines to your .emacs file:
;;
;;     (require 'go-eldoc)
;;     (add-hook go-mode-hook 'go-eldoc-setup)
;;

;;; Code:

(eval-when-compile
  (require 'cl))

(require 'eldoc)
(require 'go-mode)
(require 'go-autocomplete)
(require 'thingatpt)

(defgroup go-eldoc nil
  "Eldoc for golang"
  :group 'go
  :prefix "go-eldoc-")

(defun go-eldoc--current-arg-index (curpoint)
  (save-excursion
    (let ((count 1))
      (while (search-forward "," curpoint t)
        (setq count (1+ count)))
      count)))

(defun go-eldoc--count-string (str from to)
  (save-excursion
    (goto-char from)
    (loop while (search-forward str to t)
          counting 1)))

(defun go-eldoc--inside-funcall-p (from to)
  (save-excursion
    (goto-char (point))
    (let ((left-paren (go-eldoc--count-string "(" from to))
          (right-paren (go-eldoc--count-string ")" from to)))
      (> left-paren right-paren))))

(defun go-eldoc--validate-funcinfo (funcinfo)
  (and funcinfo (stringp funcinfo)
       (string-match ",,func" funcinfo)))

(defun go-eldoc--match-candidates (funcinfo cur-symbol)
  (when (go-eldoc--validate-funcinfo funcinfo)
    (let ((regexp (format "^\\(%s,,.+\\)$" cur-symbol)))
      (when (string-match regexp funcinfo)
        (match-string-no-properties 1 funcinfo)))))

(defun go-eldoc--get-funcinfo ()
  (let ((curpoint (point)))
    (save-excursion
      (when (go-in-string-or-comment-p)
        (go-goto-beginning-of-string-or-comment))
      (and (re-search-backward "\\([a-zA-Z0-9_]+\\)\\s-*(" nil t)
           (goto-char (match-end 0)))
      (when (char-equal (string-to-char "(") (preceding-char))
        (backward-char)
        (when (go-eldoc--inside-funcall-p (1- (point)) curpoint)
          (let ((matched (go-eldoc--match-candidates
                          (ac-go-invoke-autocomplete) (thing-at-point 'symbol))))
            (when (string-match "\\`\\(.+?\\),,\\(.+\\)$" matched)
              (list :name (match-string-no-properties 1 matched)
                    :signature (match-string-no-properties 2 matched)
                    :index (go-eldoc--current-arg-index curpoint)))))))))

(defun go-eldoc--no-argument-p (arg-type)
  (string-match "\\`\\s-+\\'" arg-type))

(defun go-eldoc--highlight-argument (signature index)
  (let* ((arg-type (plist-get signature :arg-type))
         (ret-type (plist-get signature :ret-type))
         (types (split-string arg-type ", ")))
    (if (go-eldoc--no-argument-p arg-type)
        (concat "() " ret-type)
      (loop with highlight-done = nil
            with arg-len = (length types)
            for i from 0 to arg-len
            for type in types
            if (and (not highlight-done)
                    (or (= i (1- index))
                        (and (= i (1- arg-len))
                             (string-match "\\.\\{3\\}" type))))
            collect
            (progn
              (setq highlight-done t)
              (propertize type 'face 'eldoc-highlight-function-argument)) into args

            else
            collect type into args
            finally
            return (concat "(" (mapconcat 'identity args ", ") ") " ret-type)))))

(defun go-eldoc--analyze-signature (signature)
  (when (string-match "\\`func(\\([^)]*\\))\\(?: \\(.+\\)\\)?$" signature)
    (list :arg-type (match-string-no-properties 1 signature)
          :ret-type (or (match-string-no-properties 2 signature) ""))))

(defun go-eldoc--format-signature (funcinfo)
  (let ((funcname (plist-get funcinfo :name))
        (signature (go-eldoc--analyze-signature (plist-get funcinfo :signature)))
        (index (plist-get funcinfo :index)))
    (format "%s: %s"
            (propertize funcname 'face 'font-lock-function-name-face)
            (go-eldoc--highlight-argument signature index))))

(defun go-eldoc--documentation-function ()
  (let ((funcinfo (go-eldoc--get-funcinfo)))
    (when funcinfo
      (go-eldoc--format-signature funcinfo))))

;;;###autoload
(defun go-eldoc-setup ()
  (interactive)
  (set (make-local-variable 'eldoc-documentation-function)
       'go-eldoc--documentation-function)
  (turn-on-eldoc-mode))

(provide 'go-eldoc)

;;; go-eldoc.el ends here