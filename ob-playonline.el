;;; ob-playonline.el --- Online org-babel src block execution -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Gong Qijian <gongqijian@gmail.com>

;; Author: Gong Qijian <gongqijian@gmail.com>
;; Created: 2019/10/30
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.4") (org "9.0.1") (dash "2.14.1"))
;; URL: https://github.com/twlz0ne/ob-playonline
;; Keywords: tool

;; This program is free software; you can redistribute it and/or modify
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

;; This file enables oneline execution of org-babel src blocks
;; throught the ob-playonline-org-babel-execute-src-block function
;; See README.md for more information.

;;; Change Log:

;;  0.1.0  2019/11/01  Initial version.

;;; Code:

(require 'org)
(require 'dash)
(require 'play-code)

;;;###autoload
(defalias 'org-babel-execute-src-block:playonline 'ob-playonline-org-babel-execute-src-block)

;;;###autoload
(defun ob-playonline-org-babel-execute-src-block (&optional orig-fun arg info params)
  "Like `org-babel-execute-src-block', but send code to online playground.
Original docstring for org-babel-execute-src-block:

Execute the current source code block.  Insert the results of
execution into the buffer.  Source code execution and the
collection and formatting of results can be controlled through a
variety of header arguments.

With prefix argument ARG, force re-execution even if an existing
result cached in the buffer would otherwise have been returned.

Optionally supply a value for INFO in the form returned by
`org-babel-get-src-block-info'.

Optionally supply a value for PARAMS which will be merged with
the header arguments specified at the front of the source code
block."
  (interactive "P")
  (cond
    ;; If this function is not called as advice, do nothing
    ((not orig-fun)
     (warn "ob-async-org-babel-execute-src-block is no longer needed in org-ctrl-c-ctrl-c-hook")
     nil)
    ;; If there is no :playonline parameter, call the original function
    ((not (assoc :playonline (nth 2 (or info (org-babel-get-src-block-info)))))
     (funcall orig-fun arg info params))
    ;; Otherwise, perform asynchronous execution
    (t
     (let* ((org-babel-current-src-block-location
              (or org-babel-current-src-block-location
                  (nth 5 info)
                  (org-babel-where-is-src-block-head)))
            (info (if info (copy-tree info) (org-babel-get-src-block-info))))
       ;; Merge PARAMS with INFO before considering source block
       ;; evaluation since both could disagree.
       (cl-callf org-babel-merge-params (nth 2 info) params)
       (when (org-babel-check-evaluate info)
         (cl-callf org-babel-process-params (nth 2 info))
         (let* ((params (nth 2 info))
                (cache (let ((c (cdr (assq :cache params))))
                         (and (not arg) c (string= "yes" c))))
                (new-hash (and cache (org-babel-sha1-hash info)))
                (old-hash (and cache (org-babel-current-result-hash)))
                (current-cache (and new-hash (equal new-hash old-hash))))
           (cond
             (current-cache
              (save-excursion		;Return cached result.
                (goto-char (org-babel-where-is-src-block-result nil info))
                (forward-line)
                (skip-chars-forward " \t")
                (let ((result (org-babel-read-result)))
                  (message (replace-regexp-in-string "%" "%%" (format "%S" result)))
                  result)))
             ((org-babel-confirm-evaluate info)
              (let* ((lang (nth 0 info))
                     (result-params (cdr (assq :result-params params)))
                     ;; Expand noweb references in BODY and remove any
                     ;; coderef.
                     (body
                       (let ((coderef (nth 6 info))
                             (expand
                               (if (org-babel-noweb-p params :eval)
                                   (org-babel-expand-noweb-references info)
                                 (nth 1 info))))
                         (if (not coderef) expand
                           (replace-regexp-in-string
                            (org-src-coderef-regexp coderef) "" expand nil nil 1))))
                     (dir (cdr (assq :dir params)))
                     (default-directory
                       (or (and dir (file-name-as-directory (expand-file-name dir)))
                           default-directory))
                     cmd
                     lang-id
                     wrapper
                     (play-code-output-to-buffer-p nil)
                     result)
                (-setq (lang-id cmd wrapper)
                  (play-code--get-lang-and-function
                   (play-code--get-mode-alias
                    (org-src--get-lang-mode lang))))
                (when wrapper
                  (setq body (funcall wrapper body)))
                (unless (fboundp cmd)
                  (error "No online playground for %s!" lang))
                (message "executing %s code block%s..."
                         (capitalize lang)
                         (let ((name (nth 4 info)))
                           (if name (format " (%s)" name) "")))
                (if (member "none" result-params)
                    (progn (funcall cmd lang-id body)
                           (message "result silenced"))
                  (setq result
                        (let ((r (funcall cmd lang-id body)))
                          (if (and (eq (cdr (assq :result-type params)) 'value)
                                   (or (member "vector" result-params)
                                       (member "table" result-params))
                                   (not (listp r)))
                              (list (list r))
                            r)))
                  (let ((file (cdr (assq :file params))))
                    ;; If non-empty result and :file then write to :file.
                    (when file
                      (when result
                        (with-temp-file file
                          (insert (org-babel-format-result
                                   result (cdr (assq :sep params))))))
                      (setq result file))
                    ;; Possibly perform post process provided its
                    ;; appropriate.  Dynamically bind "*this*" to the
                    ;; actual results of the block.
                    (let ((post (cdr (assq :post params))))
                      (when post
                        (let ((*this* (if (not file) result
                                        (org-babel-result-to-file
                                         file
                                         (let ((desc (assq :file-desc params)))
                                           (and desc (or (cdr desc) result)))))))
                          (setq result (org-babel-ref-resolve post))
                          (when file
                            (setq result-params (remove "file" result-params))))))
                    (org-babel-insert-result
                     result result-params info new-hash lang)))
                (run-hooks 'org-babel-after-execute-hook)
                result)))))))))

(advice-add 'org-babel-execute-src-block :around 'ob-playonline-org-babel-execute-src-block)

(provide 'ob-playonline)

;;; ob-playonline.el ends here
