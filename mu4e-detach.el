;;; mu4e-detach.el --- Detach email attachments in mu4e, save and remove them

;; This file is not part of Emacs

;; Copyright (C) 2017 Gambhiro Bhikkhu

;; Author           : Gambhiro Bhikkhu <gambhiro.bhikkhu.85@gmail.com>
;; Package-Requires : ((s "1.10.0"))
;; URL              : https://github.com/gambhiro/mu4e-detach
;; Version          : 0.1.0.20170905
;; Keywords         : email, mu4e

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
;; Detach email attachments in mu4e by saving them to a folder and (optionally)
;; removing the attachment from the message. A short text is appended to the
;; message with a list of the removed attachments.
;;
;; This package adds actions to headers-view and message-view.
;;
;; By default, it only saves the attachments and does not remove them.
;;
;; The 'altermime' tool is used to change the messages. Install with your
;; distribution's package manager. On Ubuntu:
;;
;; sudo apt-get install altermime

;;; Code:

(require 's)

(defgroup mu4e-detach nil
  "Detach email attachments in mu4e, save and remove them"
  :link '(url-link "https://github.com/gambhiro/mu4e-detach")
  :prefix "mu4e-detach-"
  :group 'external)

(defcustom mu4e-detach-save-all-attachments-folder-base "~/Downloads/attachments"
  "Base folder for saving. For each message, a new folder is
  created for saving attachments."
  :group 'mu4e-detach
  :type 'string)

(defcustom mu4e-detach-save t
  "Controls if attachments should be saved."
  :group 'mu4e-detach
  :type 'boolean)

(defcustom mu4e-detach-remove nil
  "Controls if attachments should be removed."
  :group 'mu4e-detach
  :type 'boolean)

(defcustom mu4e-detach-append-removed-filenames t
  "Controls if the list of removed file names should be appended
  to the message."
  :group 'mu4e-detach
  :type 'boolean)

(defvar mu4e-detach/callback-counter 0)
(defvar mu4e-detach/found-altermime nil)
(defvar mu4e-detach/debug nil)

(defun end-with-slash (dirpath)
  (if (s-ends-with? "/" dirpath) dirpath (concat dirpath "/")))

(defun has-altermime? ()
  "Checks if altermime is available."
  (if mu4e-detach/found-altermime t
    (setq mu4e-detach/found-altermime
          (if (= 0 (shell-command "which altermime")) t nil))))

(defun mu4e-detach/attachment-save-folder-path (attachment-dir msg)
  "Returns a full path to a folder, where the last folder is in
the pattern of '2017-07-15T20-02-19 Fwd: forest in Norway (1)/'.
This folder can be used to save the attachments. It doesn't
create the folder, but checks that it doesn't already exists."
  (let* ((msgsubject (mu4e-msg-field msg :subject))
         (msgdate (mu4e-msg-field msg :date))
         ;; Date time format: "2017-07-15T20-02-19"
         (msgdateiso (format-time-string "%Y-%m-%dT%H-%M-%S" msgdate))
         (save-folder (concat
                       (end-with-slash attachment-dir)
                       ;; No trailing slash here
                       (format "%s %s" msgdateiso (s-replace "/" "-" msgsubject))))
         (save-folder-w-suffix save-folder)
         ;; Exists try counter
         (n 0))
    (while (file-exists-p save-folder-w-suffix)
      (setq n (+ 1 n))
      (setq save-folder-w-suffix (format "%s (%s)" save-folder n)))
    (end-with-slash save-folder-w-suffix)))

(defun mu4e-detach/post-detach-callback ()
  "Restore the view handler if this message was the last in the queue."
  (when mu4e-detach/debug
    (message "mu4e-detach/post-detach-callback"))

  (setq mu4e-detach/callback-counter (+ -1 mu4e-detach/callback-counter))

  (when mu4e-detach/debug
      (message (format "mu4e-detach/callback-counter: %d" mu4e-detach/callback-counter)))

  (when (<= mu4e-detach/callback-counter 0)
    (progn (setq mu4e-detach/callback-counter 0)
           (when mu4e-detach-remove
             (mu4e-update-index))
           (message "[mu4e-detach] restoring view handler")
           (setq mu4e-view-func 'mu4e~headers-view-handler))))

(defun mu4e-detach/detach-callback (msg)
  "Detach the attachments."
  (let* ((x (when mu4e-detach/debug (message "mu4e-detach/detach-callback")))
         (x (mu4e~view-construct-attachments-header msg));; Populate attachment map
         (count (hash-table-count mu4e~view-attach-map));; Count the attachments
         (attachnums (mu4e-split-ranges-to-numbers "a" count));; A list of numbers for all attachments
         ;; Use separate folders for the email's attachments
         (attachdir (mu4e-detach/attachment-save-folder-path
                     mu4e-detach-save-all-attachments-folder-base
                     msg)))

    ;; Create the save folder, with parents if needed
    (mkdir attachdir t)

    (let ((msgpath (mu4e-msg-field msg :path))
          (fnamelist '()))

      ;; Save all attachments
     (dolist (num attachnums)
       (let* ((att (mu4e~view-get-attach msg num))
              (fname  (plist-get att :name))
              (index (plist-get att :index))
              ;; No need to check for overwrites because we are writing to a new folder
              (fpath (expand-file-name (concat attachdir fname))))
         ;; Keep track of file names
         (add-to-list 'fnamelist fname)
         ;; Save the attachment
         (when mu4e-detach-save
           (message (format "Saving attachment: %s" fpath))
           (mu4e~proc-extract
            'save (mu4e-message-field msg :docid)
            index mu4e-decryption-policy fpath))))

     ;; Remove all attachments from the message
     (when mu4e-detach-remove
       (if (has-altermime?)
           (if mu4e-detach-append-removed-filenames
               ;; Remove and append
               (let* ((docid (mu4e-message-field msg :docid))
                      ;; Txt and html disclaimers of removed file names
                      (disc-txt (format "Removed attachments:\n- %s\n"
                                        (s-join "\n- " fnamelist)))
                      (disc-html (format "<p>Removed attachments:\n<ul>\n<li>%s</li>\n</ul>\n</p>"
                                         (s-join "</li>\n<li>" fnamelist)))

                      (disc-txt-fpath (format "/tmp/disclaimer-%d.txt" docid))
                      (disc-html-fpath (format "/tmp/disclaimer-%d.html" docid))

                      (cmd (format "altermime --input='%s' --removeall --disclaimer='%s' --disclaimer-html='%s'"
                                   msgpath disc-txt-fpath disc-html-fpath)))

                 ;; Create the disclaimer files
                 (with-temp-file disc-txt-fpath (insert disc-txt))
                 (with-temp-file disc-html-fpath (insert disc-html))

                 (message cmd)

                 (when mu4e-detach/debug
                   (message disc-txt)
                   (message disc-html))

                 ;; Call altermime
                 (unless mu4e-detach/debug
                   (shell-command cmd))

                 ;; Tidy up
                 (unless mu4e-detach/debug
                   (delete-file disc-txt-fpath)
                   (delete-file disc-html-fpath)))

             ;; Just remove
             (let* ((cmd (format "altermime --input='%s' --removeall"
                                 msgpath replace-name with-fpath)))
               (message cmd)
               (unless mu4e-detach/debug
                 (shell-command cmd))))

         (message ("[mu4e-detach] ERROR Can't find altermime. Is it installed?")))))

    ;; Callback restores the view handler after the last message
    (mu4e-detach/post-detach-callback)))

;; headers view mode action
(defun mu4e-detach/headers-detach-all-attachments (msg)
  "Remove all attachments from a single message. Retreive the
full message from mu server. The message will be given to
mu4e-view-func as a callback. This is async, so we use another
callback to do the work, which has to restore mu4e-view-func."
  (let* ((docid (mu4e-message-field (or msg (mu4e-msg-at-point)) :docid)))
    (setq mu4e-detach/callback-counter (+ 1 mu4e-detach/callback-counter))
    (setq mu4e-view-func (lambda (m) (mu4e-detach/detach-callback m)))
    (mu4e~proc-send-command
     "cmd:view docid:%s extract-images:false extract-encrypted:false" docid)))

;; message view mode action
(defun mu4e-detach/view-detach-all-attachments (msg num)
  (mu4e-detach/headers-detach-all-attachments msg))

;;;###autoload
(defun mu4e-detach/load ()
  (add-to-list 'mu4e-view-attachment-actions
               '("Ddetach-all-attachments" . mu4e-detach/view-detach-all-attachments))
  (add-to-list 'mu4e-headers-actions
               '("Ddetach-all-attachments" . mu4e-detach/headers-detach-all-attachments)))

(provide 'mu4e-detach)
;;; mu4e-detach.el ends here
